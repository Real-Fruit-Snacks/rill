; cp.asm — copy files.
;
;   cp SRC DST
;   cp SRC... DIRECTORY
;
; v1 supports file-to-file and file-to-directory copy. -r (recursive) and
; -p (preserve perms/times) land in phase 3c. Without -p we still create
; the destination with the source's mode bits, but timestamps reset to
; "now" — that's coreutils' default behavior absent -p.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern is_directory
extern path_join
extern read_buf
extern write_all
extern perror_path

global applet_cp_main

section .bss
align 16
cp_statbuf:  resb STATBUF_SIZE
cp_pathbuf:  resb 4096
cp_iobuf:    resb 65536

section .rodata
err_missing:     db "cp: missing operand", 10
err_missing_len: equ $ - err_missing
err_no_dir:      db "cp: target is not a directory", 10
err_no_dir_len:  equ $ - err_no_dir
prefix_cp:       db "cp", 0

section .text

; int applet_cp_main(int argc /edi/, char **argv /rsi/)
;
; Register layout (all callee-saved):
;   rbx  argc
;   rbp  argv
;   r12  dest index
;   r13  dest_is_dir
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
    xor     r14d, r14d

    cmp     ebx, 3
    jl      .missing

    lea     r12d, [rbx - 1]

    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel cp_statbuf]
    call    is_directory
    test    eax, eax
    js      .dest_missing
    mov     r13d, eax
    jmp     .check_arity

.dest_missing:
    cmp     ebx, 3
    je      .as_simple_pair
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cp]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    jmp     .out

.as_simple_pair:
    xor     r13d, r13d

.check_arity:
    test    r13d, r13d
    jnz     .ops
    cmp     ebx, 4
    jl      .ops
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_no_dir]
    mov     edx, err_no_dir_len
    syscall
    mov     r14d, 1
    jmp     .out

.ops:
    mov     r15d, 1
.loop:
    cmp     r15d, r12d
    jge     .out

    mov     rdi, [rbp + r15*8]      ; SRC

    test    r13d, r13d
    jz      .target_simple

    ; Build dest_dir/basename(SRC) in cp_pathbuf.
    call    basename_of
    mov     rdx, rax
    mov     rsi, [rbp + r12*8]
    lea     rdi, [rel cp_pathbuf]
    call    path_join
    lea     rdi, [rel cp_pathbuf]
    jmp     .have_target

.target_simple:
    mov     rdi, [rbp + r12*8]

.have_target:
    mov     rsi, [rbp + r15*8]      ; SRC
    call    copy_one
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
; copy_one(target /rdi/, source /rsi/) -> rax = 0 on success, 1 on error
;
; Errors are reported in-place via perror_path against the most relevant
; path (source for stat/open/read errors, target for create/write errors).
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
    mov     r14d, eax               ; preserve -errno across close
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

; basename_of(path /rdi/) -> rax = pointer to last component
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
