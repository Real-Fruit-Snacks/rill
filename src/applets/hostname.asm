; hostname.asm — print the system's hostname.
;
; Reads from utsname (the same struct uname uses). v1 supports just the
; no-argument print; the setter form (`hostname NEW`) requires CAP_SYS_-
; ADMIN and lands later.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern strlen
extern write_all
extern putc

global applet_hostname_main

%define UTS_LEN 65

section .bss
align 16
hostname_buf: resb UTS_LEN * 6

section .text

applet_hostname_main:
    mov     eax, SYS_uname
    lea     rdi, [rel hostname_buf]
    syscall
    test    rax, rax
    js      .err

    lea     rdi, [rel hostname_buf + UTS_LEN]   ; nodename
    call    strlen
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel hostname_buf + UTS_LEN]
    call    write_all

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    xor     eax, eax
    ret

.err:
    mov     eax, 1
    ret
