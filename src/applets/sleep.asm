; sleep.asm — sleep for a number of seconds.
;
;   sleep N    where N is a non-negative decimal integer
;
; v1 does not accept fractional seconds or unit suffixes (s/m/h/d). Both
; would require a richer parser; we will revisit when the time arithmetic
; is needed elsewhere (e.g. `date`).
;
; EINTR handling: nanosleep is restarted with the remaining time, so a
; transient signal that doesn't terminate us doesn't truncate the sleep.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern parse_uint

global applet_sleep_main

%define EINTR 4

section .rodata
err_missing: db "sleep: missing operand", 10
err_missing_len: equ $ - err_missing
err_bad:     db "sleep: invalid time interval", 10
err_bad_len: equ $ - err_bad

section .text

; int applet_sleep_main(int argc /edi/, char **argv /rsi/)
;
; Stack layout while running:
;   [rsp + 0  .. +16)   struct timespec req  (tv_sec, tv_nsec)
;   [rsp + 16 .. +32)   struct timespec rem
applet_sleep_main:
    push    rbx
    sub     rsp, 32

    cmp     edi, 2
    jl      .missing

    mov     rbx, [rsi + 8]          ; argv[1]
    mov     rdi, rbx
    lea     rsi, [rsp]              ; out -> req.tv_sec
    call    parse_uint
    test    eax, eax
    jnz     .bad_arg

    mov     qword [rsp + 8], 0      ; tv_nsec = 0

.do_sleep:
    mov     eax, SYS_nanosleep
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    syscall
    test    rax, rax
    jz      .ok
    cmp     rax, -EINTR
    jne     .err

    ; req <- rem; retry.
    mov     rcx, [rsp + 16]
    mov     [rsp], rcx
    mov     rcx, [rsp + 24]
    mov     [rsp + 8], rcx
    jmp     .do_sleep

.ok:
    xor     eax, eax
    jmp     .out

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     eax, 1
    jmp     .out

.bad_arg:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad]
    mov     edx, err_bad_len
    syscall
    mov     eax, 1
    jmp     .out

.err:
    mov     eax, 1

.out:
    add     rsp, 32
    pop     rbx
    ret
