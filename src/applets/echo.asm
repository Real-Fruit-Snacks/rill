; echo.asm — print arguments separated by spaces.
;
; Flags supported:
;   -n   Do not append a trailing newline.
;
; We do not implement -e or -E (escape interpretation). GNU echo's defaults
; align with leaving them off, and POSIX does not require -e at all.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern streq
extern write_cstr
extern putc

global applet_echo_main

section .rodata
opt_n:  db "-n", 0

section .text

; int applet_echo_main(int argc /edi/, char **argv /rsi/)
applet_echo_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; argv index
    push    r13                     ; emit-newline flag
    push    r14                     ; (padding for 16-byte alignment)

    mov     ebx, edi
    mov     rbp, rsi
    mov     r13d, 1                 ; emit newline by default
    mov     r12d, 1                 ; first non-program arg

    ; Strip leading -n flags. GNU echo accepts repeated -n.
.flag_loop:
    cmp     r12d, ebx
    jge     .emit
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_n]
    call    streq
    test    eax, eax
    jz      .emit
    xor     r13d, r13d
    inc     r12d
    jmp     .flag_loop

.emit:
    cmp     r12d, ebx
    jge     .trailer

.arg_loop:
    mov     edi, STDOUT_FILENO
    mov     rsi, [rbp + r12*8]
    call    write_cstr
    test    eax, eax
    js      .err

    inc     r12d
    cmp     r12d, ebx
    jge     .trailer

    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
    test    eax, eax
    js      .err
    jmp     .arg_loop

.trailer:
    test    r13d, r13d
    jz      .ok
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    test    eax, eax
    js      .err

.ok:
    xor     eax, eax
    jmp     .out
.err:
    mov     eax, 1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
