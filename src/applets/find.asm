; find.asm — walk file trees and apply tests.
;
;   find [PATH...] [TEST...]
;
; PATHs come first; the first arg starting with '-' begins the test list.
; If no PATH is given, '.' is implied. Tests are evaluated as a logical
; AND. Operator forms (-or, -not, -a, parens) are intentionally not
; modeled in v1 — repeating the same test simply lets the last value win.
;
; Tests:
;   -name PATTERN   basename glob (* ? [...] [!...] \X)
;   -type C         f reg, d dir, l link, c chr, b blk, p fifo, s sock
;   -maxdepth N     do not descend deeper than N levels (0 = operand only)
;   -mindepth N     suppress output for entries shallower than N
;   -empty          regular files with size 0, or directories with no
;                   non-dot entries
;
; Actions:
;   -print          (default if no other action given) name + '\n'
;   -print0         name + '\0' (for `xargs -0`)
;
; Recursion uses a shared 4 KB path buffer (find_path_buf), appending at
; each descent and truncating back on return. Each recursion frame
; allocates a 32 KB getdents64 buffer on the stack — Linux's default 8
; MB stack supports several hundred levels of depth.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern streq
extern parse_uint
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_find_main

%define D_RECLEN 16
%define D_NAME   19
%define FIND_GETDENTS_BUF_LEN 32768
%define PATH_MAX 4096

section .bss
align 16
find_path_buf:    resb PATH_MAX           ; current path being walked
find_statbuf:     resb STATBUF_SIZE
find_name_pat:    resq 1                  ; pointer or 0
find_maxdepth:    resq 1                  ; -1 sentinel = unlimited
find_mindepth:    resq 1                  ; default 0
find_type_char:   resb 1                  ; 0 = no -type test
find_print0:      resb 1
find_empty_test:  resb 1                  ; -empty was requested
find_action_set:  resb 1                  ; -print/-print0 was explicit

section .rodata
prefix_find:      db "find", 0
opt_name:         db "-name", 0
opt_type:         db "-type", 0
opt_maxdepth:     db "-maxdepth", 0
opt_mindepth:     db "-mindepth", 0
opt_print:        db "-print", 0
opt_print0:       db "-print0", 0
opt_empty:        db "-empty", 0
err_missing_arg:  db "find: missing argument to test", 10
err_missing_arg_len: equ $ - err_missing_arg
err_bad_type:     db "find: -type expects f/d/l/c/b/p/s", 10
err_bad_type_len: equ $ - err_bad_type
err_unknown:      db "find: unknown predicate", 10
err_unknown_len:  equ $ - err_unknown
dot_path:         db ".", 0

section .text

; ---------------------------------------------------------------------------
; int applet_find_main(int argc /edi/, char **argv /rsi/)
;
; Two-pass: collect PATH operands until the first arg starting with '-',
; then parse the test list from that position. Walk each path with
; walk_one(path, 0).
;
; Stack: 6 callee-saved pushes + sub 8 -> 0 mod 16 at inner call sites.
;   rbx  argc
;   rbp  argv
;   r12  arg cursor (during flag/test parse)
;   r13  rc accumulator
;   r14  first-test arg index (and later, current path arg index)
;   r15  one-past-last-path arg index
applet_find_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d

    mov     qword [rel find_name_pat], 0
    mov     qword [rel find_maxdepth], -1
    mov     qword [rel find_mindepth], 0
    mov     byte  [rel find_type_char], 0
    mov     byte  [rel find_print0], 0
    mov     byte  [rel find_empty_test], 0
    mov     byte  [rel find_action_set], 0

    ; Find the boundary: first arg whose first byte is '-' is the start
    ; of the test list. Everything before it (after argv[0]) is a path.
    mov     r12d, 1
.find_split:
    cmp     r12d, ebx
    jge     .split_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    je      .split_done
    inc     r12d
    jmp     .find_split
.split_done:
    mov     r15d, r12d                  ; one past last path

    ; Parse the test list starting at r12.
    ;
    ; r12 advances arg-by-arg; some predicates consume an extra arg.
.test_loop:
    cmp     r12d, ebx
    jge     .tests_parsed
    mov     rdi, [rbp + r12*8]

    lea     rsi, [rel opt_name]
    call    streq
    test    eax, eax
    jnz     .t_name
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_type]
    call    streq
    test    eax, eax
    jnz     .t_type
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_maxdepth]
    call    streq
    test    eax, eax
    jnz     .t_maxdepth
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_mindepth]
    call    streq
    test    eax, eax
    jnz     .t_mindepth
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_print]
    call    streq
    test    eax, eax
    jnz     .t_print
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_print0]
    call    streq
    test    eax, eax
    jnz     .t_print0
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_empty]
    call    streq
    test    eax, eax
    jnz     .t_empty
    jmp     .err_unknown

.t_name:
    inc     r12d
    cmp     r12d, ebx
    jge     .err_missing
    mov     rax, [rbp + r12*8]
    mov     [rel find_name_pat], rax
    inc     r12d
    jmp     .test_loop

.t_type:
    inc     r12d
    cmp     r12d, ebx
    jge     .err_missing
    mov     rdi, [rbp + r12*8]
    movzx   eax, byte [rdi]
    cmp     byte [rdi + 1], 0
    jne     .err_type
    cmp     al, 'f'
    je      .type_ok
    cmp     al, 'd'
    je      .type_ok
    cmp     al, 'l'
    je      .type_ok
    cmp     al, 'c'
    je      .type_ok
    cmp     al, 'b'
    je      .type_ok
    cmp     al, 'p'
    je      .type_ok
    cmp     al, 's'
    je      .type_ok
    jmp     .err_type
.type_ok:
    mov     [rel find_type_char], al
    inc     r12d
    jmp     .test_loop

.t_maxdepth:
    inc     r12d
    cmp     r12d, ebx
    jge     .err_missing
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel find_maxdepth]
    call    parse_uint
    test    eax, eax
    jnz     .err_unknown
    inc     r12d
    jmp     .test_loop

.t_mindepth:
    inc     r12d
    cmp     r12d, ebx
    jge     .err_missing
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel find_mindepth]
    call    parse_uint
    test    eax, eax
    jnz     .err_unknown
    inc     r12d
    jmp     .test_loop

.t_print:
    mov     byte [rel find_print0], 0
    mov     byte [rel find_action_set], 1
    inc     r12d
    jmp     .test_loop

.t_print0:
    mov     byte [rel find_print0], 1
    mov     byte [rel find_action_set], 1
    inc     r12d
    jmp     .test_loop

.t_empty:
    mov     byte [rel find_empty_test], 1
    inc     r12d
    jmp     .test_loop

.tests_parsed:
    ; If no path was given, use ".".
    cmp     r15d, 1
    jg      .have_paths
    lea     rdi, [rel dot_path]
    xor     esi, esi
    call    walk_one
    or      r13d, eax
    jmp     .out

.have_paths:
    mov     r14d, 1
.path_loop:
    cmp     r14d, r15d
    jge     .out
    mov     rdi, [rbp + r14*8]
    xor     esi, esi
    call    walk_one
    or      r13d, eax
    inc     r14d
    jmp     .path_loop

.err_missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing_arg]
    mov     edx, err_missing_arg_len
    syscall
    mov     r13d, 1
    jmp     .out
.err_type:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_type]
    mov     edx, err_bad_type_len
    syscall
    mov     r13d, 1
    jmp     .out
.err_unknown:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_unknown]
    mov     edx, err_unknown_len
    syscall
    mov     r13d, 1

.out:
    mov     eax, r13d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int walk_one(path /rdi/, depth /esi/) -> rax (0 ok, 1 if any error)
;
; Copies `path` into find_path_buf, then dispatches into walk(len, depth).
walk_one:
    push    rbx
    push    rbp
    push    r12
    push    r13                         ; (alignment)

    mov     rbx, rdi                    ; path
    mov     ebp, esi                    ; depth

    ; Copy path into find_path_buf, capturing its length in r12.
    lea     rdi, [rel find_path_buf]
    mov     rsi, rbx
    xor     r12, r12
.copy:
    cmp     r12, PATH_MAX - 1
    jge     .copy_full
    mov     al, [rsi + r12]
    mov     [rdi + r12], al
    test    al, al
    jz      .copied
    inc     r12
    jmp     .copy
.copy_full:
    mov     byte [rdi + r12], 0
.copied:
    mov     edi, r12d
    mov     esi, ebp
    call    walk

    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int walk(path_len /edi/, depth /esi/) -> rax (0 ok, 1 if error sticky)
;
; Recursive descent. find_path_buf[0..path_len] holds the current entity.
; lstats it; if the tests pass and depth >= mindepth, prints. If it's a
; directory and depth < maxdepth (or maxdepth is -1), reads its entries
; and recurses for each non-dot child.
;
; Stack: 5 callee-saved pushes + sub (FIND_GETDENTS_BUF_LEN + 8). Inner
; calls land at 0 mod 16 because the buffer length is a multiple of 16.
;   rbx  path_len
;   rbp  depth
;   r12  saved_len (for path-truncate after recurse)
;   r13  bytes-from-getdents (current frame total)
;   r14  fd (open dir)
;   r15  sticky child-error flag
walk:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, FIND_GETDENTS_BUF_LEN

    mov     ebx, edi
    mov     ebp, esi
    xor     r15d, r15d

    ; lstat the current path.
    mov     eax, SYS_lstat
    lea     rdi, [rel find_path_buf]
    lea     rsi, [rel find_statbuf]
    syscall
    test    rax, rax
    js      .lstat_err

    ; Decide whether this entry should be emitted.
    mov     edi, ebp
    call    decide_emit
    test    eax, eax
    jz      .skip_emit
    call    emit_path
.skip_emit:

    ; Should we recurse? Only directories, and only when depth limit
    ; allows. (For -mindepth filtering we still walk children even if
    ; we skipped emitting this dir.)
    mov     ecx, [rel find_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFDIR
    jne     .ret_ok

    mov     rax, [rel find_maxdepth]
    cmp     rax, -1
    je      .can_descend
    movsxd  rcx, ebp
    cmp     rcx, rax
    jge     .ret_ok                     ; at maxdepth, do not descend

.can_descend:
    ; Open and read the directory.
    mov     eax, SYS_open
    lea     rdi, [rel find_path_buf]
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_err
    mov     r14d, eax

    xor     r13, r13
.read_loop:
    mov     edx, FIND_GETDENTS_BUF_LEN
    sub     edx, r13d
    test    edx, edx
    jz      .read_full
    mov     eax, SYS_getdents64
    mov     edi, r14d
    mov     rsi, rsp
    add     rsi, r13
    syscall
    test    rax, rax
    js      .read_err
    jz      .read_eof
    add     r13, rax
    jmp     .read_loop

.read_full:
.read_err:
    mov     eax, SYS_close
    mov     edi, r14d
    syscall
    mov     r15d, 1
    jmp     .ret_close

.read_eof:
    mov     eax, SYS_close
    mov     edi, r14d
    syscall

    ; Append a separator '/' to find_path_buf if the path doesn't already
    ; end in one. r12 = saved_len (so we can truncate after recurse).
    mov     r12d, ebx
    test    ebx, ebx
    jz      .add_sep
    movsxd  rax, ebx
    lea     rdi, [rel find_path_buf]
    cmp     byte [rdi + rax - 1], '/'
    je      .no_sep
.add_sep:
    movsxd  rax, ebx
    lea     rdi, [rel find_path_buf]
    mov     byte [rdi + rax], '/'
    inc     ebx
.no_sep:

    ; Iterate dirents.
    xor     r9, r9                      ; cursor
.iter:
    cmp     r9, r13
    jge     .iter_done

    mov     rdi, rsp
    add     rdi, r9
    movzx   ecx, word [rdi + D_RECLEN]
    lea     r10, [rdi + D_NAME]

    ; Skip "." and "..".
    cmp     byte [r10], '.'
    jne     .process
    cmp     byte [r10 + 1], 0
    je      .skip_iter
    cmp     byte [r10 + 1], '.'
    jne     .process
    cmp     byte [r10 + 2], 0
    je      .skip_iter

.process:
    ; Append the entry name into find_path_buf at offset ebx.
    mov     r11, r10
.nlen:
    cmp     byte [r11], 0
    je      .nlen_done
    inc     r11
    jmp     .nlen
.nlen_done:
    sub     r11, r10                    ; r11 = name length

    movsxd  rax, ebx
    lea     rdx, [rax + r11]
    cmp     rdx, PATH_MAX - 1
    jae     .skip_iter                  ; would overflow path buf

    lea     rdi, [rel find_path_buf]
    add     rdi, rax
    mov     rsi, r10
.copy_name:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .copy_name_done
    inc     rdi
    inc     rsi
    jmp     .copy_name
.copy_name_done:

    ; Recurse with new length and depth+1.
    push    rcx
    push    r9
    push    r10
    push    r11
    sub     rsp, 8                      ; align (4 pushes -> 0 mod 16)

    mov     edi, ebx
    add     edi, r11d
    lea     esi, [rbp + 1]
    call    walk

    add     rsp, 8
    pop     r11
    pop     r10
    pop     r9
    pop     rcx

    or      r15d, eax

    ; Truncate path buffer back to "<dir>/" prefix.
    movsxd  rax, ebx
    lea     rdi, [rel find_path_buf]
    mov     byte [rdi + rax], 0

.skip_iter:
    add     r9, rcx
    jmp     .iter

.iter_done:
    ; Restore original path length (drop the trailing '/').
    movsxd  rax, r12d
    lea     rdi, [rel find_path_buf]
    mov     byte [rdi + rax], 0

.ret_close:
    test    r15d, r15d
    jnz     .ret_err
.ret_ok:
    xor     eax, eax
    jmp     .ret
.ret_err:
    mov     eax, 1
    jmp     .ret

.lstat_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_find]
    lea     rsi, [rel find_path_buf]
    call    perror_path
    mov     eax, 1
    jmp     .ret

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_find]
    lea     rsi, [rel find_path_buf]
    call    perror_path
    mov     eax, 1

.ret:
    add     rsp, FIND_GETDENTS_BUF_LEN
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int decide_emit(depth /edi/) -> rax (1 if entry passes all tests, 0 else)
;
; Reads find_statbuf and find_path_buf. Order:
;   * mindepth gate
;   * -name match against basename
;   * -type match against st_mode
;   * -empty match
;
; Stack: 1 push + sub 8 (test arg saving across glob_match call) — rsp at
; call sites is 0 mod 16.
decide_emit:
    push    rbx
    sub     rsp, 8

    mov     ebx, edi                    ; depth

    ; mindepth: skip emit if depth < mindepth.
    movsxd  rax, ebx
    cmp     rax, [rel find_mindepth]
    jl      .no

    ; -name PATTERN
    mov     rax, [rel find_name_pat]
    test    rax, rax
    jz      .name_ok

    ; basename of find_path_buf — last component after the final '/'.
    lea     rdi, [rel find_path_buf]
    mov     rsi, rdi                    ; will be basename ptr
.find_base:
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .base_done
    cmp     ecx, '/'
    jne     .base_step
    lea     rsi, [rdi + 1]
.base_step:
    inc     rdi
    jmp     .find_base
.base_done:
    mov     rdi, [rel find_name_pat]
    call    glob_match
    test    eax, eax
    jz      .no
.name_ok:

    ; -type
    movzx   eax, byte [rel find_type_char]
    test    eax, eax
    jz      .type_ok
    mov     ecx, [rel find_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     al, 'f'
    je      .want_reg
    cmp     al, 'd'
    je      .want_dir
    cmp     al, 'l'
    je      .want_lnk
    cmp     al, 'c'
    je      .want_chr
    cmp     al, 'b'
    je      .want_blk
    cmp     al, 'p'
    je      .want_fifo
    cmp     al, 's'
    je      .want_sock
    jmp     .no
.want_reg:  cmp ecx, S_IFREG ; je .type_ok ; jne .no
            jne .no
            jmp .type_ok
.want_dir:  cmp ecx, S_IFDIR
            jne .no
            jmp .type_ok
.want_lnk:  cmp ecx, S_IFLNK
            jne .no
            jmp .type_ok
.want_chr:  cmp ecx, S_IFCHR
            jne .no
            jmp .type_ok
.want_blk:  cmp ecx, S_IFBLK
            jne .no
            jmp .type_ok
.want_fifo: cmp ecx, S_IFIFO
            jne .no
            jmp .type_ok
.want_sock: cmp ecx, S_IFSOCK
            jne .no
.type_ok:

    ; -empty
    cmp     byte [rel find_empty_test], 0
    je      .all_pass

    mov     ecx, [rel find_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFREG
    je      .empty_reg
    cmp     ecx, S_IFDIR
    je      .empty_dir
    jmp     .no
.empty_reg:
    cmp     qword [rel find_statbuf + ST_SIZE], 0
    jne     .no
    jmp     .all_pass
.empty_dir:
    call    dir_is_empty
    test    eax, eax
    jz      .no

.all_pass:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int dir_is_empty() -> rax (1 if find_path_buf names an empty directory)
;
; Opens find_path_buf, getdents64s a small buffer, counts non-dot
; entries. Returns 1 iff the count is 0 (only "." and ".." present).
;
; Uses a 4 KB on-stack getdents buffer (enough for ~120 entries; we only
; need to find one to declare non-empty so a single read suffices for
; nearly every real directory).
dir_is_empty:
    push    rbx
    sub     rsp, 4096                   ; 4 KB scratch dirent buf

    mov     eax, SYS_open
    lea     rdi, [rel find_path_buf]
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .err
    mov     ebx, eax

    mov     eax, SYS_getdents64
    mov     edi, ebx
    mov     rsi, rsp
    mov     edx, 4096
    syscall
    mov     rcx, rax                    ; bytes (signed)

    ; Close fd before scanning (we don't need it any more).
    push    rcx
    sub     rsp, 8
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
    add     rsp, 8
    pop     rcx

    test    rcx, rcx
    js      .err
    jz      .empty                      ; no dirent bytes -> empty

    xor     r8, r8
.scan:
    cmp     r8, rcx
    jge     .empty                      ; finished without seeing a non-dot

    mov     rdi, rsp
    add     rdi, r8
    movzx   edx, word [rdi + D_RECLEN]
    lea     r9, [rdi + D_NAME]

    cmp     byte [r9], '.'
    jne     .non_empty
    cmp     byte [r9 + 1], 0
    je      .skip
    cmp     byte [r9 + 1], '.'
    jne     .non_empty
    cmp     byte [r9 + 2], 0
    je      .skip

.non_empty:
    xor     eax, eax
    jmp     .out

.skip:
    add     r8, rdx
    jmp     .scan

.empty:
    mov     eax, 1
    jmp     .out

.err:
    xor     eax, eax

.out:
    add     rsp, 4096
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; emit_path — writes find_path_buf (NUL-terminated) followed by '\n' or '\0'.
emit_path:
    sub     rsp, 8
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel find_path_buf]
    call    write_cstr
    mov     edi, STDOUT_FILENO
    movzx   esi, byte [rel find_print0]
    test    esi, esi
    jnz     .nul
    mov     esi, 10
    jmp     .term
.nul:
    xor     esi, esi
.term:
    call    putc
    add     rsp, 8
    ret

; ---------------------------------------------------------------------------
; int glob_match(pat /rdi/, str /rsi/) -> rax (1 if pat matches str, 0 else)
;
; Recursive glob matcher.
;
; Supported metacharacters:
;   *   matches any (possibly empty) byte sequence
;   ?   matches any single byte
;   [abc] [a-z] [!abc]   character class with optional ranges and negation
;   \X   literal X
;
; Path separators in str are NOT specially handled — the caller is
; expected to invoke glob_match on the basename only.
glob_match:
    push    rbx
    push    rbp

    mov     rbx, rdi
    mov     rbp, rsi

.loop:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .pat_done

    cmp     al, '*'
    je      .star

    cmp     al, '?'
    je      .question

    cmp     al, '['
    je      .class

    cmp     al, '\'
    je      .escape

    ; Literal byte
    movzx   ecx, byte [rbp]
    test    ecx, ecx
    jz      .no
    cmp     eax, ecx
    jne     .no
    inc     rbx
    inc     rbp
    jmp     .loop

.escape:
    movzx   eax, byte [rbx + 1]
    test    eax, eax
    jz      .no                         ; trailing '\' — no match
    movzx   ecx, byte [rbp]
    test    ecx, ecx
    jz      .no
    cmp     eax, ecx
    jne     .no
    add     rbx, 2
    inc     rbp
    jmp     .loop

.question:
    cmp     byte [rbp], 0
    je      .no
    inc     rbx
    inc     rbp
    jmp     .loop

.star:
    inc     rbx
    ; Collapse "**" into one (avoid exponential blowup).
.collapse:
    cmp     byte [rbx], '*'
    jne     .collapsed
    inc     rbx
    jmp     .collapse
.collapsed:
    cmp     byte [rbx], 0
    jne     .star_search
    ; Trailing '*': matches anything.
    mov     eax, 1
    jmp     .out

.star_search:
    ; Try to match `pat` (rbx) at each suffix of `str` (rbp).
.star_loop:
    mov     rdi, rbx
    mov     rsi, rbp
    call    glob_match
    test    eax, eax
    jnz     .yes_eax
    cmp     byte [rbp], 0
    je      .no
    inc     rbp
    jmp     .star_loop

.class:
    ; Walk class body deciding match for str[0] in lockstep with skip.
    cmp     byte [rbp], 0
    je      .no

    lea     rdi, [rbx + 1]              ; class cursor
    movzx   esi, byte [rbp]             ; the byte to test
    xor     r8d, r8d                    ; negated flag
    cmp     byte [rdi], '!'
    je      .class_neg
    cmp     byte [rdi], '^'
    jne     .class_no_neg
.class_neg:
    mov     r8d, 1
    inc     rdi
.class_no_neg:
    xor     r9d, r9d                   ; matched flag

    ; Allow a leading ']' to be a literal class member.
    cmp     byte [rdi], ']'
    jne     .class_loop
    cmp     esi, ']'
    jne     .class_step_one
    mov     r9d, 1
.class_step_one:
    inc     rdi

.class_loop:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .class_truncated
    cmp     eax, ']'
    je      .class_close

    ; Range: [rdi+1] == '-' AND [rdi+2] not ']' / 0.
    cmp     byte [rdi + 1], '-'
    jne     .class_single
    movzx   ecx, byte [rdi + 2]
    test    ecx, ecx
    jz      .class_single
    cmp     ecx, ']'
    je      .class_single

    ; Range a-b: match if a <= str[0] <= b.
    cmp     esi, eax
    jl      .class_range_step
    cmp     esi, ecx
    jg      .class_range_step
    mov     r9d, 1
.class_range_step:
    add     rdi, 3
    jmp     .class_loop

.class_single:
    cmp     esi, eax
    jne     .class_single_step
    mov     r9d, 1
.class_single_step:
    inc     rdi
    jmp     .class_loop

.class_truncated:
    ; Unterminated class — treat the rest as no-match.
    jmp     .no

.class_close:
    inc     rdi                         ; past ']'
    ; Result is matched XOR negated; if true, advance both and continue.
    xor     r9d, r8d
    test    r9d, r9d
    jz      .no
    mov     rbx, rdi
    inc     rbp
    jmp     .loop

.pat_done:
    cmp     byte [rbp], 0
    je      .yes
    jmp     .no

.yes:
    mov     eax, 1
    jmp     .out
.yes_eax:
    jmp     .out
.no:
    xor     eax, eax
.out:
    pop     rbp
    pop     rbx
    ret
