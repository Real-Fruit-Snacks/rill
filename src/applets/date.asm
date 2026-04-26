; date.asm — print the current UTC date and time.
;
;   date
;
; v1 prints "DDD Mon DD HH:MM:SS UTC YYYY", always in UTC. -u is accepted
; as a no-op (UTC is the only mode). +FORMAT (custom strftime), -d STRING
; (parse and emit), and the setter form (`date MMDDhhmm[.SS]`) are all
; deferred — local-time handling needs /etc/localtime parsing and the
; format-string parser is its own engine.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern format_datetime_long
extern write_all
extern putc

global applet_date_main

section .bss
align 16
date_buf: resb 32

section .text

applet_date_main:
    mov     eax, SYS_time
    xor     edi, edi
    syscall

    mov     rdi, rax
    lea     rsi, [rel date_buf]
    call    format_datetime_long

    mov     edi, STDOUT_FILENO
    lea     rsi, [rel date_buf]
    mov     edx, 28
    call    write_all

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    xor     eax, eax
    ret
