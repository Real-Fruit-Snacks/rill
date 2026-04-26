; rmdir.asm — remove empty directories.
;
;   rmdir DIR...
;
; Errors out per directory; non-empty / missing / not-a-directory all fail
; with a printed message and rc=1. We do not yet support -p (remove parent
; chains) — that's a wrapper around the same syscall and lands when needed.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern perror_path

global applet_rmdir_main

section .rodata
err_missing: db "rmdir: missing operand", 10
err_missing_len: equ $ - err_missing
prefix_rmdir: db "rmdir", 0

section .text

; int applet_rmdir_main(int argc /edi/, char **argv /rsi/)
applet_rmdir_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d              ; rc

    cmp     ebx, 2
    jl      .missing

    mov     r12d, 1
.loop:
    cmp     r12d, ebx
    jge     .out

    mov     eax, SYS_rmdir
    mov     rdi, [rbp + r12*8]
    syscall
    test    rax, rax
    jns     .next

    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_rmdir]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1

.next:
    inc     r12d
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
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
