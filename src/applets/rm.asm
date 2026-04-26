; rm.asm — remove files.
;
;   rm [-f] FILE...
;
; v1 does not implement -r/-R (recursive). Without -r, attempting to remove
; a directory fails with "Is a directory", matching coreutils. Recursive
; removal lands with the directory-walking machinery in phase 3b alongside
; ls.
;
; -f silences errors about missing files and exits 0 if every other path
; succeeded. It does not affect protected/permission errors.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern streq
extern perror_path

global applet_rm_main

section .rodata
opt_f:        db "-f", 0
prefix_rm:    db "rm", 0

%define ENOENT 2

section .text

; int applet_rm_main(int argc /edi/, char **argv /rsi/)
applet_rm_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d              ; -f flag
    xor     r14d, r14d              ; rc

    mov     r12d, 1

    ; Parse flags. Stop at first non-flag.
.flag_loop:
    cmp     r12d, ebx
    jge     .done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .ops
    cmp     byte [rdi + 1], 0
    je      .ops                    ; bare "-" is an operand
    lea     rsi, [rel opt_f]
    call    streq
    test    eax, eax
    jz      .ops                    ; unknown flag → treat as filename
    mov     r13d, 1
    inc     r12d
    jmp     .flag_loop

.ops:
.unlink_loop:
    cmp     r12d, ebx
    jge     .done

    mov     eax, SYS_unlink
    mov     rdi, [rbp + r12*8]
    syscall
    test    rax, rax
    jns     .next

    ; If -f and ENOENT, swallow.
    cmp     eax, -ENOENT
    jne     .report
    test    r13d, r13d
    jnz     .next
.report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_rm]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
.next:
    inc     r12d
    jmp     .unlink_loop

.done:
    mov     eax, r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
