; touch.asm — create file if missing, or update its access/mod times.
;
;   touch FILE...
;
; v1 does not implement -a / -m / -t / -d / -r. The default behavior is
; "touch to current time", and that's what every flag-free invocation does.
;
; Strategy: try utimensat(AT_FDCWD, path, NULL, 0) — if the file exists,
; that's a no-allocation, single-syscall update. If it returns ENOENT,
; create the file via openat(O_CREAT|O_WRONLY) with mode 0666 then close.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern perror_path

global applet_touch_main

%define ENOENT 2

section .rodata
err_missing:    db "touch: missing operand", 10
err_missing_len: equ $ - err_missing
prefix_touch:    db "touch", 0

section .text

; int applet_touch_main(int argc /edi/, char **argv /rsi/)
applet_touch_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d

    cmp     ebx, 2
    jl      .missing

    mov     r12d, 1
.loop:
    cmp     r12d, ebx
    jge     .out

    mov     r13, [rbp + r12*8]      ; current path

    ; Fast path: utimensat(AT_FDCWD, path, NULL, 0)
    mov     eax, SYS_utimensat
    mov     edi, AT_FDCWD
    mov     rsi, r13
    xor     edx, edx
    xor     r10d, r10d
    syscall
    test    rax, rax
    jns     .next
    cmp     eax, -ENOENT
    jne     .report

    ; Slow path: create the file. open(path, O_WRONLY|O_CREAT, 0666)
    mov     eax, SYS_open
    mov     rdi, r13
    mov     esi, O_WRONLY | O_CREAT
    mov     edx, 0o666
    syscall
    test    rax, rax
    js      .report

    mov     edi, eax
    mov     eax, SYS_close
    syscall
    jmp     .next

.report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_touch]
    mov     rsi, r13
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
