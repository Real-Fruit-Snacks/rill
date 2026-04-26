; readlink.asm — print the target of a symbolic link.
;
;   readlink LINK
;
; v1 does not implement -f / -e / -m (canonicalization variants); those
; require a userspace canonicalize-path routine that's substantial enough
; to belong to phase 3b alongside `realpath`.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern write_all
extern putc
extern perror_path

global applet_readlink_main

%define BUF_LEN 4096

section .bss
align 16
link_buf: resb BUF_LEN

section .rodata
err_missing:     db "readlink: missing operand", 10
err_missing_len: equ $ - err_missing
prefix_readlink: db "readlink", 0

section .text

; int applet_readlink_main(int argc /edi/, char **argv /rsi/)
applet_readlink_main:
    cmp     edi, 2
    jl      .missing

    mov     eax, SYS_readlink
    mov     rdi, [rsi + 8]
    push    rdi                     ; save path for error reporting; +8 (mis)
    sub     rsp, 8                  ; align (1 push + 1 sub of 8 = even mis)
    lea     rsi, [rel link_buf]
    mov     edx, BUF_LEN
    syscall
    add     rsp, 8
    pop     r8                      ; original path

    test    rax, rax
    js      .err

    mov     edx, eax                ; len of link target
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel link_buf]
    push    r8
    sub     rsp, 8
    call    write_all
    add     rsp, 8
    pop     r8
    test    eax, eax
    js      .write_err

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    test    eax, eax
    js      .write_err

    xor     eax, eax
    ret

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     eax, 1
    ret

.err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_readlink]
    mov     rsi, r8
    call    perror_path
    mov     eax, 1
    ret

.write_err:
    mov     eax, 1
    ret
