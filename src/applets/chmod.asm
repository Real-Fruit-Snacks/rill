; chmod.asm — change file mode bits.
;
;   chmod MODE FILE...
;
; v1 supports octal MODE only (e.g. 644, 755, 0755). Symbolic modes
; ("u+x", "go-w", "a=r") are common enough that they should land soon, but
; the parser is involved enough to deserve its own change.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern parse_octal
extern perror_path

global applet_chmod_main

section .rodata
err_missing: db "chmod: missing operand", 10
err_missing_len: equ $ - err_missing
err_bad_mode: db "chmod: invalid mode", 10
err_bad_mode_len: equ $ - err_bad_mode
prefix_chmod: db "chmod", 0

section .text

; int applet_chmod_main(int argc /edi/, char **argv /rsi/)
applet_chmod_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; mode
    push    r13                     ; arg cursor
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d

    cmp     ebx, 3
    jl      .missing

    sub     rsp, 16
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rsp]
    call    parse_octal
    test    eax, eax
    jnz     .bad_mode_with_stack
    mov     r12, [rsp]
    add     rsp, 16

    mov     r13d, 2
.loop:
    cmp     r13d, ebx
    jge     .out

    mov     eax, SYS_chmod
    mov     rdi, [rbp + r13*8]
    mov     esi, r12d
    syscall
    test    rax, rax
    jns     .next

    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_chmod]
    mov     rsi, [rbp + r13*8]
    call    perror_path
    mov     r14d, 1
.next:
    inc     r13d
    jmp     .loop

.bad_mode_with_stack:
    add     rsp, 16
    jmp     .bad_mode

.bad_mode:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_mode]
    mov     edx, err_bad_mode_len
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
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
