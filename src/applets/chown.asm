; chown.asm — change file owner / group.
;
;   chown [-R] [-h] USER         FILE...
;   chown [-R] [-h] USER:GROUP   FILE...
;   chown [-R] [-h] :GROUP       FILE...
;
; USER and GROUP may be numeric or named. Named lookup goes through
; /etc/passwd and /etc/group (see core/passwd.asm).
;
; Without -h, top-level operands that are symlinks are dereferenced —
; ownership of the target changes (chown(2) syscall). With -h, the
; symlink itself is changed (lchown(2)). Recursive walks always use
; lchown to avoid following symlinks during traversal, regardless of -h;
; coreutils' more nuanced -L/-H/-P matrix is intentionally not modeled.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern streq
extern parse_uint
extern name_to_uid
extern name_to_gid
extern perror_path

global applet_chown_main

%define KEEP_ID 0xFFFFFFFF
%define ENOENT  2
%define D_RECLEN 16
%define D_NAME   19
%define CHOWN_GETDENTS_BUF_LEN 32768
%define PATH_MAX 4096

section .bss
align 16
chown_path_buf: resb PATH_MAX
chown_statbuf:  resb STATBUF_SIZE
chown_nofollow: resb 1                  ; -h: top-level lchown instead of chown

section .rodata
opt_R:          db "-R", 0
opt_h:          db "-h", 0
opt_Rh:         db "-Rh", 0
opt_hR:         db "-hR", 0
err_missing:    db "chown: missing operand", 10
err_missing_len: equ $ - err_missing
err_bad_id:     db "chown: invalid user/group spec", 10
err_bad_id_len: equ $ - err_bad_id
prefix_chown:   db "chown", 0

section .text

; int applet_chown_main(int argc /edi/, char **argv /rsi/)
;
; Layout:
;   rbx  argc
;   rbp  argv
;   r12  uid (low 32) | gid (high 32)
;   r13  arg cursor (after flags + spec)
;   r14  rc
;   r15  -R flag
applet_chown_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d
    xor     r15d, r15d
    mov     byte [rel chown_nofollow], 0

    mov     r13d, 1
.flag_loop:
    cmp     r13d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r13*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    inc     rdi                         ; consume '-'
.flag_char:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .next_flag
    cmp     al, 'R'
    je      .set_R
    cmp     al, 'h'
    je      .set_h
    jmp     .flags_done                 ; unknown char stops parsing
.set_R: mov r15d, 1
        inc rdi
        jmp .flag_char
.set_h: mov byte [rel chown_nofollow], 1
        inc rdi
        jmp .flag_char
.next_flag:
    inc     r13d
    jmp     .flag_loop

.flags_done:
    ; Need spec + at least one path.
    mov     ecx, ebx
    sub     ecx, r13d
    cmp     ecx, 2
    jl      .missing

    ; Parse the spec (USER[:GROUP] or :GROUP).
    sub     rsp, 16
    mov     rdi, [rbp + r13*8]
    lea     rsi, [rsp]
    call    parse_owner
    test    eax, eax
    jnz     .bad_id_with_stack
    mov     r12, [rsp]              ; lo32 = uid, hi32 = (don't care)
    mov     rax, [rsp + 8]          ; gid
    add     rsp, 16
    shl     rax, 32
    mov     ecx, r12d
    or      rax, rcx                ; rax = (gid << 32) | uid_lo
    mov     r12, rax

    inc     r13d                    ; first FILE arg

.loop:
    cmp     r13d, ebx
    jge     .out

    test    r15d, r15d
    jnz     .recurse

    ; Non-recursive single file: chown(2) follows symlinks by default;
    ; -h selects lchown(2) so the link itself is changed.
    mov     eax, SYS_chown
    cmp     byte [rel chown_nofollow], 0
    je      .do_chown
    mov     eax, SYS_lchown
.do_chown:
    mov     rdi, [rbp + r13*8]
    mov     esi, r12d               ; uid
    mov     rdx, r12
    shr     rdx, 32                 ; gid
    syscall
    test    rax, rax
    jns     .next

.report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_chown]
    mov     rsi, [rbp + r13*8]
    call    perror_path
    mov     r14d, 1
    jmp     .next

.recurse:
    ; Copy argv[i] to chown_path_buf, get length.
    mov     rdi, [rbp + r13*8]
    lea     rsi, [rel chown_path_buf]
    xor     ecx, ecx
.copy_arg:
    mov     al, [rdi + rcx]
    mov     [rsi + rcx], al
    test    al, al
    jz      .copy_done
    inc     ecx
    cmp     ecx, PATH_MAX - 1
    jge     .copy_done
    jmp     .copy_arg
.copy_done:
    mov     byte [rsi + rcx], 0

    mov     rdi, rsi
    movsxd  rsi, ecx
    mov     edx, r12d
    mov     r8, r12
    shr     r8, 32
    mov     r8d, r8d
    call    chown_recurse
    test    eax, eax
    jz      .next
    mov     r14d, 1

.next:
    inc     r13d
    jmp     .loop

.bad_id_with_stack:
    add     rsp, 16
.bad_id:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_id]
    mov     edx, err_bad_id_len
    syscall
    mov     r14d, 1
    jmp     .out

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     r14d, 1

.out:
    mov     eax, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; chown_recurse(path /rdi/, len /rsi/, uid /edx/, gid /r8d/) -> rax = 0 or 1
;
; Mirrors rm_recurse: per-frame 32 KB getdents64 buffer, shared 4 KB path
; buffer. lchown all entries (no symlink traversal during the walk).
chown_recurse:
    push    rbx                     ; path
    push    rbp                     ; len
    push    r12                     ; saved_len
    push    r13                     ; uid|gid (lo32=uid, hi32=gid)
    push    r14                     ; sticky child failure
    sub     rsp, CHOWN_GETDENTS_BUF_LEN

    mov     rbx, rdi
    mov     rbp, rsi
    mov     ecx, edx                ; uid
    mov     eax, r8d                ; gid
    shl     rax, 32
    or      rax, rcx
    mov     r13, rax
    xor     r14d, r14d

    ; lstat to classify.
    mov     eax, SYS_lstat
    mov     rdi, rbx
    lea     rsi, [rel chown_statbuf]
    syscall
    test    rax, rax
    js      .err

    mov     ecx, [rel chown_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFDIR
    je      .as_dir

    ; File or symlink: just lchown.
    mov     eax, SYS_lchown
    mov     rdi, rbx
    mov     esi, r13d               ; uid
    mov     rdx, r13
    shr     rdx, 32                 ; gid
    syscall
    test    rax, rax
    jns     .ok
    jmp     .err

.as_dir:
    ; Read the dir's contents, close, then recurse.
    mov     eax, SYS_open
    mov     rdi, rbx
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .err

    push    rax
    sub     rsp, 8

    xor     r8, r8
.read_loop:
    mov     edx, CHOWN_GETDENTS_BUF_LEN
    sub     edx, r8d
    test    edx, edx
    jz      .read_full
    mov     eax, SYS_getdents64
    mov     edi, [rsp + 8]
    lea     rsi, [rsp + 16]
    add     rsi, r8
    syscall
    test    rax, rax
    js      .read_err
    jz      .read_eof
    add     r8, rax
    jmp     .read_loop

.read_full:
.read_err:
    mov     edi, [rsp + 8]
    mov     eax, SYS_close
    syscall
    add     rsp, 16
    mov     eax, -22
    jmp     .err

.read_eof:
    mov     edi, [rsp + 8]
    push    r8
    sub     rsp, 8
    mov     eax, SYS_close
    syscall
    add     rsp, 8
    pop     r8
    add     rsp, 16

    mov     r12, rbp
    test    rbp, rbp
    jz      .add_sep
    cmp     byte [rbx + rbp - 1], '/'
    je      .no_sep
.add_sep:
    mov     byte [rbx + rbp], '/'
    inc     rbp
.no_sep:

    xor     r9, r9
.iter:
    cmp     r9, r8
    jge     .iter_done

    mov     rdi, rsp
    add     rdi, r9
    movzx   ecx, word [rdi + D_RECLEN]
    lea     r10, [rdi + D_NAME]

    cmp     byte [r10], '.'
    jne     .process
    cmp     byte [r10 + 1], 0
    je      .next_iter
    cmp     byte [r10 + 1], '.'
    jne     .process
    cmp     byte [r10 + 2], 0
    je      .next_iter

.process:
    mov     r11, r10
.nlen:
    cmp     byte [r11], 0
    je      .nlen_done
    inc     r11
    jmp     .nlen
.nlen_done:
    sub     r11, r10

    lea     rax, [rbp + r11]
    cmp     rax, PATH_MAX - 1
    jae     .next_iter

    ; Append name.
    mov     rdi, rbx
    add     rdi, rbp
    mov     rsi, r10
.copy_name:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .copied
    inc     rdi
    inc     rsi
    jmp     .copy_name
.copied:

    ; Recurse.
    push    rcx
    push    r8
    push    r9
    push    r10
    push    r11
    sub     rsp, 8

    mov     rdi, rbx
    lea     rsi, [rbp + r11]
    mov     edx, r13d
    mov     r8, r13
    shr     r8, 32
    mov     r8d, r8d
    call    chown_recurse

    add     rsp, 8
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rcx

    mov     byte [rbx + rbp], 0

    test    eax, eax
    jz      .next_iter
    or      r14d, 1

.next_iter:
    add     r9, rcx
    jmp     .iter

.iter_done:
    mov     rbp, r12
    mov     byte [rbx + rbp], 0

    mov     eax, SYS_lchown
    mov     rdi, rbx
    mov     esi, r13d
    mov     rdx, r13
    shr     rdx, 32
    syscall
    test    rax, rax
    js      .err

    test    r14d, 1
    jnz     .out_failed
.ok:
    xor     eax, eax
    jmp     .ret

.out_failed:
    mov     eax, 1
    jmp     .ret

.err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_chown]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1

.ret:
    add     rsp, CHOWN_GETDENTS_BUF_LEN
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_owner(spec /rdi/, out /rsi/) -> rax (0 ok, -1 bad)
;
;   *out = uid (8 bytes, low 32 valid; 0xFFFFFFFF for "keep")
;   *(out+8) = gid (8 bytes)
parse_owner:
    push    rbx                     ; spec ptr
    push    r12                     ; out
    push    r13                     ; (alignment)

    mov     rbx, rdi
    mov     r12, rsi

    mov     dword [r12],     KEEP_ID
    mov     dword [r12 + 4], 0
    mov     dword [r12 + 8], KEEP_ID
    mov     dword [r12 + 12], 0

    cmp     byte [rbx], ':'
    je      .group_only

    ; Parse user part up to ':' or NUL.
    mov     rdi, rbx
    lea     rsi, [r12]
    call    parse_id_field          ; rax=0/-1, rcx=stop ptr
    test    eax, eax
    jnz     .bad
    mov     al, [rcx]
    test    al, al
    jz      .ok
    cmp     al, ':'
    jne     .bad
    lea     rbx, [rcx + 1]
    jmp     .parse_gid

.group_only:
    inc     rbx

.parse_gid:
    cmp     byte [rbx], 0
    je      .ok                     ; trailing colon → keep gid
    mov     rdi, rbx
    lea     rsi, [r12 + 8]
    call    parse_id_field
    test    eax, eax
    jnz     .bad
    cmp     byte [rcx], 0
    jne     .bad

.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; parse_id_field(s /rdi/, *out /rsi/) -> rax=0/-1, rcx=stop pointer
;
;   Always tries numeric first; if the value isn't a complete number
;   (no digits, or digits followed by a non-':'/non-NUL byte), retries
;   as a name via name_to_uid then name_to_gid. The slot offset doesn't
;   distinguish user vs group here — both lookups are tried so that a
;   name registered only in /etc/group still resolves when the caller
;   uses it as a user spec (matches coreutils behavior).
;
;   Stop pointer (rcx on success) points at the first byte not
;   consumed: ':' for "user:group" or NUL at end of spec.
;
;   Stack: 5 callee-saved pushes keep r12-r14 available across nested
;   calls (name_to_uid clobbers all caller-saved regs).
parse_id_field:
    push    rbx                     ; spec start
    push    rbp                     ; out
    push    r12                     ; stop pointer (after parse)
    push    r13                     ; saved original byte at stop point
    push    r14                     ; (alignment / unused)

    mov     rbx, rdi
    mov     rbp, rsi

    ; Try numeric.
    xor     eax, eax
    mov     r12, rdi
.num_loop:
    movzx   ecx, byte [r12]
    cmp     ecx, '0'
    jb      .num_done
    cmp     ecx, '9'
    ja      .num_done
    imul    rax, rax, 10
    sub     ecx, '0'
    add     rax, rcx
    inc     r12
    jmp     .num_loop
.num_done:
    cmp     r12, rbx
    je      .try_name

    movzx   ecx, byte [r12]
    test    ecx, ecx
    jz      .num_ok
    cmp     ecx, ':'
    je      .num_ok
    ; Digits followed by non-terminator → fall through to name attempt.

.try_name:
    mov     r12, rbx
.find_term:
    mov     al, [r12]
    test    al, al
    jz      .have_term
    cmp     al, ':'
    je      .have_term
    inc     r12
    jmp     .find_term
.have_term:
    movzx   r13d, byte [r12]        ; remember original byte (callee-saved)
    mov     byte [r12], 0

    mov     rdi, rbx
    call    name_to_uid
    cmp     rax, -1
    jne     .name_hit

    mov     rdi, rbx
    call    name_to_gid
    cmp     rax, -1
    je      .name_fail

.name_hit:
    mov     [rbp], rax
    mov     byte [r12], r13b
    mov     rcx, r12
    xor     eax, eax
    jmp     .ret

.num_ok:
    mov     [rbp], rax
    mov     rcx, r12
    xor     eax, eax
    jmp     .ret

.name_fail:
    mov     byte [r12], r13b
    mov     eax, -1

.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
