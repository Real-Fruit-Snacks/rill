; cp.asm — copy files and (optionally) directory trees.
;
;   cp [-r|-R] SRC DST
;   cp [-r|-R] SRC... DIRECTORY
;
; Flags:
;   -r / -R   recurse into directories
;
; Without -r, copying a directory is an error (matching coreutils). With
; -r:
;   - regular files copied (mode bits preserved at create time)
;   - symlinks recreated as symlinks (link target preserved verbatim)
;   - directories created with the source's mode bits, then recursed
;   - special files (block, char, fifo, socket) silently skipped with a
;     warning
;
; Path management for recursion:
;   - cp_src_path, cp_dst_path are 4 KB buffers in .bss
;   - Each recursion level appends "/<name>" to both buffers and truncates
;     them back on return
;   - Per-level stack: 32 KB for getdents64. Default 8 MB stack supports
;     ~250 recursion levels.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern streq
extern is_directory
extern path_join
extern read_buf
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_cp_main

%define EEXIST  17
%define D_RECLEN 16
%define D_NAME   19
%define CP_GETDENTS_BUF_LEN 32768
%define PATH_MAX 4096

section .bss
align 16
cp_statbuf:    resb STATBUF_SIZE
cp_src_path:   resb PATH_MAX
cp_dst_path:   resb PATH_MAX
cp_iobuf:      resb 65536
cp_link_buf:   resb PATH_MAX

section .rodata
opt_r:           db "-r", 0
opt_rcap:        db "-R", 0
err_missing:     db "cp: missing operand", 10
err_missing_len: equ $ - err_missing
err_no_dir:      db "cp: target is not a directory", 10
err_no_dir_len:  equ $ - err_no_dir
err_isdir:       db "cp: omitting directory (use -r)", 10
err_isdir_len:   equ $ - err_isdir
err_special:     db "cp: skipping special file", 10
err_special_len: equ $ - err_special
prefix_cp:       db "cp", 0

section .text

; int applet_cp_main(int argc /edi/, char **argv /rsi/)
;
; Register layout:
;   rbx  argc
;   rbp  argv
;   r12  dest index (= argc-1)
;   r13  dest_is_dir flag (bit 0) + -r flag (bit 1)
;   r14  rc
;   r15  SRC loop index
applet_cp_main:
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
    xor     r14d, r14d

    ; Parse leading flags.
    mov     r15d, 1
.flag_loop:
    cmp     r15d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r15*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done
    lea     rsi, [rel opt_r]
    call    streq
    test    eax, eax
    jnz     .set_r
    mov     rdi, [rbp + r15*8]
    lea     rsi, [rel opt_rcap]
    call    streq
    test    eax, eax
    jnz     .set_r
    jmp     .flags_done
.set_r:
    or      r13d, 2
    inc     r15d
    jmp     .flag_loop

.flags_done:
    mov     ecx, ebx
    sub     ecx, r15d
    cmp     ecx, 2
    jl      .missing

    lea     r12d, [rbx - 1]

    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel cp_statbuf]
    call    is_directory
    test    eax, eax
    js      .dest_missing
    test    eax, eax
    jz      .have_dest
    or      r13d, 1
    jmp     .have_dest

.dest_missing:
    mov     ecx, ebx
    sub     ecx, r15d
    cmp     ecx, 2
    je      .have_dest              ; 2-operand pair: pretend not-a-dir
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    jmp     .out

.have_dest:
    test    r13d, 1
    jnz     .ops
    mov     ecx, ebx
    sub     ecx, r15d
    cmp     ecx, 3
    jl      .ops
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_no_dir]
    mov     edx, err_no_dir_len
    syscall
    mov     r14d, 1
    jmp     .out

.ops:
.loop:
    cmp     r15d, r12d
    jge     .out

    mov     rdi, [rbp + r15*8]      ; SRC
    lea     rsi, [rel cp_src_path]
    call    copy_str_to_buf         ; rax = src_len

    test    r13d, 1
    jz      .target_simple

    ; dest_is_dir → cp_dst_path = dest + "/" + basename(src)
    mov     rdi, [rbp + r15*8]
    call    basename_of
    mov     rdx, rax
    mov     rsi, [rbp + r12*8]
    lea     rdi, [rel cp_dst_path]
    call    path_join               ; rax = total length
    jmp     .have_target

.target_simple:
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel cp_dst_path]
    call    copy_str_to_buf

.have_target:
    test    r13d, 2
    jnz     .recurse

    ; Non-recursive: classify SRC and either copy or error.
    mov     eax, SYS_lstat
    lea     rdi, [rel cp_src_path]
    lea     rsi, [rel cp_statbuf]
    syscall
    test    rax, rax
    js      .src_lstat_err
    mov     ecx, [rel cp_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFDIR
    je      .src_isdir

    lea     rdi, [rel cp_dst_path]
    lea     rsi, [rel cp_src_path]
    call    copy_one
    test    eax, eax
    jz      .next
    mov     r14d, 1
    jmp     .next

.src_isdir:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_isdir]
    mov     edx, err_isdir_len
    syscall
    mov     r14d, 1
    jmp     .next

.src_lstat_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    lea     rsi, [rel cp_src_path]
    call    perror_path
    mov     r14d, 1
    jmp     .next

.recurse:
    ; Compute current lengths via strlen-style scan. The buffers were
    ; populated by copy_str_to_buf / path_join above.
    lea     rdi, [rel cp_src_path]
    call    buf_strlen
    mov     r8, rax
    lea     rdi, [rel cp_dst_path]
    call    buf_strlen
    mov     r9, rax

    lea     rdi, [rel cp_src_path]
    mov     rsi, r8
    lea     rdx, [rel cp_dst_path]
    mov     rcx, r9
    call    cp_recurse
    test    eax, eax
    jz      .next
    mov     r14d, 1

.next:
    inc     r15d
    jmp     .loop

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
; copy_str_to_buf(src /rdi/, dst /rsi/) -> rax = bytes written (excl NUL)
copy_str_to_buf:
    xor     ecx, ecx
.loop:
    mov     al, [rdi + rcx]
    mov     [rsi + rcx], al
    test    al, al
    jz      .done
    inc     ecx
    jmp     .loop
.done:
    movsxd  rax, ecx
    ret

; buf_strlen — strlen in our local convention (avoids dragging in core's
; strlen in case of caller-saved-clobber surprises).
buf_strlen:
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; basename_of — pointer to last path component (no allocation).
basename_of:
    mov     rax, rdi
.loop:
    mov     dl, [rdi]
    test    dl, dl
    jz      .done
    cmp     dl, '/'
    jne     .next
    lea     rax, [rdi + 1]
.next:
    inc     rdi
    jmp     .loop
.done:
    ret

; ---------------------------------------------------------------------------
; cp_recurse(src_path /rdi/, src_len /rsi/, dst_path /rdx/, dst_len /rcx/)
;   -> rax = 0 or 1
;
; Both buffers are mutated during the descent and restored before return.
cp_recurse:
    push    rbx                     ; src_path
    push    rbp                     ; src_len
    push    r12                     ; dst_path
    push    r13                     ; dst_len
    push    r14                     ; sticky child-failed bit
    sub     rsp, CP_GETDENTS_BUF_LEN

    mov     rbx, rdi
    mov     rbp, rsi
    mov     r12, rdx
    mov     r13, rcx
    xor     r14d, r14d

    ; lstat source.
    mov     eax, SYS_lstat
    mov     rdi, rbx
    lea     rsi, [rel cp_statbuf]
    syscall
    test    rax, rax
    js      .src_err

    mov     ecx, [rel cp_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFREG
    je      .as_file
    cmp     ecx, S_IFLNK
    je      .as_symlink
    cmp     ecx, S_IFDIR
    je      .as_dir

    ; Special file → skip with warning, but don't fail the operation.
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_special]
    mov     edx, err_special_len
    syscall
    xor     eax, eax
    jmp     .ret

.as_file:
    mov     rdi, r12
    mov     rsi, rbx
    call    copy_one
    jmp     .ret

.as_symlink:
    sub     rsp, 8                  ; align (running rsp was 0 mod 16)
    mov     eax, SYS_readlink
    mov     rdi, rbx
    lea     rsi, [rel cp_link_buf]
    mov     edx, PATH_MAX - 1
    syscall
    test    rax, rax
    js      .symlink_err

    ; NUL-terminate.
    mov     rcx, rax
    mov     byte [rel cp_link_buf + rcx], 0

    ; If dst already exists, unlink first (so symlink doesn't fail with
    ; EEXIST). Best-effort.
    mov     eax, SYS_unlink
    mov     rdi, r12
    syscall

    mov     eax, SYS_symlink
    lea     rdi, [rel cp_link_buf]
    mov     rsi, r12
    syscall
    add     rsp, 8
    test    rax, rax
    js      .dst_err
    xor     eax, eax
    jmp     .ret

.symlink_err:
    add     rsp, 8
    jmp     .src_err

.as_dir:
    ; mkdir(dst_path, src.mode & 0o7777). Tolerate EEXIST if already a dir.
    mov     eax, SYS_mkdir
    mov     rdi, r12
    mov     esi, [rel cp_statbuf + ST_MODE]
    and     esi, 0o7777
    syscall
    test    rax, rax
    jns     .dir_open_src
    cmp     eax, -EEXIST
    jne     .dst_err

    ; If the existing dst is itself a directory, that's fine (merging).
    mov     eax, SYS_stat
    mov     rdi, r12
    lea     rsi, [rel cp_statbuf]
    syscall
    test    rax, rax
    js      .dst_err
    mov     ecx, [rel cp_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFDIR
    jne     .dst_err

.dir_open_src:
    mov     eax, SYS_open
    mov     rdi, rbx
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .src_err

    push    rax
    sub     rsp, 8                  ; fd at [rsp+8]; rsp now 0 mod 16

    xor     r8, r8
.read_loop:
    mov     edx, CP_GETDENTS_BUF_LEN
    sub     edx, r8d
    test    edx, edx
    jz      .read_full
    mov     eax, SYS_getdents64
    mov     edi, [rsp + 8]
    lea     rsi, [rsp + 16]         ; getdents buf base; we placed it at
                                    ; rsp+16 since rsp..rsp+8 = align,
                                    ; rsp+8..rsp+16 = saved fd
    add     rsi, r8
    syscall
    test    rax, rax
    js      .read_kernel_err
    jz      .read_eof
    add     r8, rax
    jmp     .read_loop

.read_full:
.read_kernel_err:
    mov     edi, [rsp + 8]
    mov     eax, SYS_close
    syscall
    add     rsp, 16
    jmp     .src_err

.read_eof:
    mov     edi, [rsp + 8]
    push    r8
    sub     rsp, 8
    mov     eax, SYS_close
    syscall
    add     rsp, 8
    pop     r8
    add     rsp, 16

    ; Iterate entries; recurse on each non-./.. entry.
    xor     r9, r9
.iter:
    cmp     r9, r8
    jge     .iter_done

    mov     rdi, rsp                ; getdents buffer base (rsp points to it
                                    ; after we removed the fd/align slots)
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
    ; Append name to both src and dst paths (via per-level helpers).
    mov     r11, r10
.nlen:
    cmp     byte [r11], 0
    je      .nlen_done
    inc     r11
    jmp     .nlen
.nlen_done:
    sub     r11, r10                ; r11 = namelen

    ; Bounds for both buffers.
    lea     rax, [rbp + 1 + r11]
    cmp     rax, PATH_MAX - 1
    jae     .next_iter
    lea     rax, [r13 + 1 + r11]
    cmp     rax, PATH_MAX - 1
    jae     .next_iter

    ; Append "/<name>" to src.
    mov     byte [rbx + rbp], '/'
    mov     rdi, rbx
    add     rdi, rbp
    inc     rdi
    mov     rsi, r10
    push    rcx
    push    r8
    push    r9
    push    r10
    push    r11
    sub     rsp, 8
.copy_src_name:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .copied_src
    inc     rdi
    inc     rsi
    jmp     .copy_src_name
.copied_src:
    add     rsp, 8
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rcx

    ; Append "/<name>" to dst.
    mov     byte [r12 + r13], '/'
    mov     rdi, r12
    add     rdi, r13
    inc     rdi
    mov     rsi, r10
.copy_dst_name:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .copied_dst
    inc     rdi
    inc     rsi
    jmp     .copy_dst_name
.copied_dst:

    ; Recurse. Save caller-saved scratch regs we need after.
    push    rcx
    push    r8
    push    r9
    push    r10
    push    r11
    sub     rsp, 8                  ; align: 5 pushes + sub 8 = 48

    mov     rdi, rbx
    lea     rsi, [rbp + 1 + r11]
    mov     rdx, r12
    lea     rcx, [r13 + 1 + r11]
    call    cp_recurse

    add     rsp, 8
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rcx

    test    eax, eax
    jz      .child_ok
    or      r14d, 1

.child_ok:
    ; Truncate both buffers back to parent's length.
    mov     byte [rbx + rbp], 0
    mov     byte [r12 + r13], 0

.next_iter:
    add     r9, rcx
    jmp     .iter

.iter_done:
    test    r14d, 1
    jnz     .out_failed
    xor     eax, eax
    jmp     .ret

.out_failed:
    mov     eax, 1
    jmp     .ret

.src_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1
    jmp     .ret

.dst_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, r12
    call    perror_path
    mov     eax, 1

.ret:
    add     rsp, CP_GETDENTS_BUF_LEN
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; copy_one(target /rdi/, source /rsi/) -> rax = 0 or 1
;
; Read-write file copy. Reports its own errors via perror_path; returns
; just the success/failure flag. Used for the non-recursive cp pair and
; (from cp_recurse) for each regular-file leaf.
copy_one:
    push    rbx                     ; target
    push    rbp                     ; source
    push    r12                     ; src fd
    push    r13                     ; dst fd
    push    r14                     ; saved mode

    mov     rbx, rdi
    mov     rbp, rsi

    mov     eax, SYS_stat
    mov     rdi, rbp
    lea     rsi, [rel cp_statbuf]
    syscall
    test    rax, rax
    js      .stat_err
    mov     r14d, [rel cp_statbuf + ST_MODE]
    and     r14d, 0o7777

    mov     eax, SYS_open
    mov     rdi, rbp
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_src_err
    mov     r12d, eax

    mov     eax, SYS_open
    mov     rdi, rbx
    mov     esi, O_WRONLY | O_CREAT | O_TRUNC
    mov     edx, r14d
    syscall
    test    rax, rax
    js      .open_dst_err
    mov     r13d, eax

.copy_loop:
    mov     edi, r12d
    lea     rsi, [rel cp_iobuf]
    mov     edx, 65536
    call    read_buf
    test    rax, rax
    jz      .done
    js      .read_err

    mov     edi, r13d
    lea     rsi, [rel cp_iobuf]
    mov     rdx, rax
    call    write_all
    test    eax, eax
    js      .write_err
    jmp     .copy_loop

.done:
    mov     edi, r12d
    mov     eax, SYS_close
    syscall
    mov     edi, r13d
    mov     eax, SYS_close
    syscall
    xor     eax, eax
    jmp     .ret

.stat_err:
.open_src_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, rbp
    call    perror_path
    mov     eax, 1
    jmp     .ret

.open_dst_err:
    mov     r14d, eax
    mov     edi, r12d
    mov     eax, SYS_close
    syscall
    mov     eax, r14d
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1
    jmp     .ret

.read_err:
    mov     r14d, eax
    mov     edi, r12d
    mov     eax, SYS_close
    syscall
    mov     edi, r13d
    mov     eax, SYS_close
    syscall
    mov     eax, r14d
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, rbp
    call    perror_path
    mov     eax, 1
    jmp     .ret

.write_err:
    mov     r14d, eax
    mov     edi, r12d
    mov     eax, SYS_close
    syscall
    mov     edi, r13d
    mov     eax, SYS_close
    syscall
    mov     eax, r14d
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1

.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
