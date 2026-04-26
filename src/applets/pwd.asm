; pwd.asm — print the current working directory.
;
; We do not honor -L / -P. The kernel's getcwd resolves symlinks (the -P
; semantics). $PWD-driven -L behavior is a shell concern; matching it
; would require reading $PWD and stat'ing both ends, which we will revisit
; once stat lands.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern write_all

global applet_pwd_main

%define PATH_BUF_LEN 4096

section .bss
align 16
path_buf: resb PATH_BUF_LEN

section .rodata
err_msg: db "pwd: cannot determine current directory", 10
err_msg_len: equ $ - err_msg

section .text

; int applet_pwd_main(int argc /edi/, char **argv /rsi/)
applet_pwd_main:
    mov     eax, SYS_getcwd
    lea     rdi, [rel path_buf]
    mov     esi, PATH_BUF_LEN
    syscall

    test    rax, rax
    js      .err

    ; rax = length including NUL. Replace the trailing NUL with '\n'.
    lea     rcx, [rel path_buf]
    mov     byte [rcx + rax - 1], 10

    mov     edi, STDOUT_FILENO
    mov     rsi, rcx
    mov     rdx, rax                ; len already includes our '\n' slot
    call    write_all
    test    eax, eax
    js      .err
    xor     eax, eax
    ret

.err:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_msg]
    mov     edx, err_msg_len
    syscall
    mov     eax, 1
    ret
