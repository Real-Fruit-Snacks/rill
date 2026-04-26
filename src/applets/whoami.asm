; whoami.asm — print the effective user's name (or numeric uid as fallback).

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern uid_to_name
extern format_uint
extern write_all
extern putc

global applet_whoami_main

section .bss
align 16
whoami_buf: resb 64

section .text

applet_whoami_main:
    mov     eax, SYS_geteuid
    syscall

    mov     edi, eax
    lea     rsi, [rel whoami_buf]
    mov     edx, 64
    call    uid_to_name
    test    rax, rax
    jnz     .have

    ; Fallback: numeric.
    mov     eax, SYS_geteuid
    syscall
    mov     edi, eax
    lea     rsi, [rel whoami_buf]
    call    format_uint

.have:
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel whoami_buf]
    call    write_all
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    xor     eax, eax
    ret
