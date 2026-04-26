; env.asm — print the environment.
;
; Phase 2 supports only the no-argument form:
;
;     env
;
; The full POSIX behavior (-i, VAR=VAL pairs, exec) requires execve and
; environment manipulation, which lands in the process/system phase. Until
; then, any argument causes us to print a clear error and exit 125, the
; coreutils-defined "env: command not specified or not implemented" code.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern write_cstr
extern write_all
extern putc

global applet_env_main

section .rodata
err_unimpl: db "env: arguments not yet supported in this build", 10
err_unimpl_len: equ $ - err_unimpl

section .text

; int applet_env_main(int argc /edi/, char **argv /rsi/)
applet_env_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    cmp     edi, 2
    jge     .unimpl

    ; envp = argv + argc + 1 in elements.
    lea     rbp, [rsi + rdi*8 + 8]
    mov     r12, rbp

.loop:
    mov     rsi, [r12]
    test    rsi, rsi
    jz      .ok

    push    r12
    mov     edi, STDOUT_FILENO
    call    write_cstr
    pop     r12
    test    eax, eax
    js      .err

    push    r12
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    pop     r12
    test    eax, eax
    js      .err

    add     r12, 8
    jmp     .loop

.ok:
    xor     eax, eax
    jmp     .out

.unimpl:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_unimpl]
    mov     edx, err_unimpl_len
    syscall
    mov     eax, 125
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
