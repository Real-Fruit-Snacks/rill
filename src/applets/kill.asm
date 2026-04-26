; kill.asm — send a signal to one or more processes.
;
;   kill [-SIGNAL | -SIGNUM] PID...
;   kill -l                     (list signal names)
;
; SIGNAL is a name like KILL, TERM, HUP — with or without the SIG prefix.
; SIGNUM is a decimal number. The default is TERM (15).
;
; v1 doesn't yet implement -s SIG (long-form signal selection) or process-
; group / negative-PID semantics. -0 (sanity-check that the process exists)
; works because our kill always passes the parsed signal number through.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern streq
extern parse_uint
extern format_uint
extern write_all
extern write_cstr
extern putc

global applet_kill_main

section .rodata
sig_HUP:    db "HUP", 0
sig_INT:    db "INT", 0
sig_QUIT:   db "QUIT", 0
sig_ILL:    db "ILL", 0
sig_TRAP:   db "TRAP", 0
sig_ABRT:   db "ABRT", 0
sig_BUS:    db "BUS", 0
sig_FPE:    db "FPE", 0
sig_KILL:   db "KILL", 0
sig_USR1:   db "USR1", 0
sig_SEGV:   db "SEGV", 0
sig_USR2:   db "USR2", 0
sig_PIPE:   db "PIPE", 0
sig_ALRM:   db "ALRM", 0
sig_TERM:   db "TERM", 0
sig_CHLD:   db "CHLD", 0
sig_CONT:   db "CONT", 0
sig_STOP:   db "STOP", 0
sig_TSTP:   db "TSTP", 0
sig_TTIN:   db "TTIN", 0
sig_TTOU:   db "TTOU", 0
sig_URG:    db "URG", 0
sig_WINCH:  db "WINCH", 0

align 8
sig_table:
    dq sig_HUP,   1
    dq sig_INT,   2
    dq sig_QUIT,  3
    dq sig_ILL,   4
    dq sig_TRAP,  5
    dq sig_ABRT,  6
    dq sig_BUS,   7
    dq sig_FPE,   8
    dq sig_KILL,  9
    dq sig_USR1, 10
    dq sig_SEGV, 11
    dq sig_USR2, 12
    dq sig_PIPE, 13
    dq sig_ALRM, 14
    dq sig_TERM, 15
    dq sig_CHLD, 17
    dq sig_CONT, 18
    dq sig_STOP, 19
    dq sig_TSTP, 20
    dq sig_TTIN, 21
    dq sig_TTOU, 22
    dq sig_URG,  23
    dq sig_WINCH, 28
    dq 0, 0

err_missing:    db "kill: usage: kill [-SIG] PID...", 10
err_missing_len: equ $ - err_missing
err_bad_sig:    db "kill: invalid signal", 10
err_bad_sig_len: equ $ - err_bad_sig
err_bad_pid:    db "kill: invalid pid: ", 0

section .text

; int applet_kill_main(int argc /edi/, char **argv /rsi/)
applet_kill_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; signum
    push    r13                     ; arg cursor
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    mov     r12d, 15                ; default TERM
    xor     r14d, r14d

    cmp     ebx, 2
    jl      .missing

    mov     r13d, 1
    mov     rdi, [rbp + r13*8]
    cmp     byte [rdi], '-'
    jne     .ops

    cmp     byte [rdi + 1], 'l'
    jne     .parse_sig
    cmp     byte [rdi + 2], 0
    jne     .parse_sig
    call    list_signals
    jmp     .out

.parse_sig:
    inc     rdi                     ; skip '-'

    ; Numeric form?
    movzx   eax, byte [rdi]
    cmp     eax, '0'
    jb      .name_form
    cmp     eax, '9'
    ja      .name_form

    sub     rsp, 24
    mov     rsi, rsp
    call    parse_uint
    test    eax, eax
    jnz     .bad_sig_pop
    mov     r12, [rsp]
    add     rsp, 24
    inc     r13d
    jmp     .ops

.bad_sig_pop:
    add     rsp, 24
    jmp     .bad_sig

.name_form:
    ; Strip optional SIG prefix.
    cmp     byte [rdi], 'S'
    jne     .lookup
    cmp     byte [rdi + 1], 'I'
    jne     .lookup
    cmp     byte [rdi + 2], 'G'
    jne     .lookup
    add     rdi, 3

.lookup:
    lea     rsi, [rel sig_table]
.scan:
    mov     rax, [rsi]
    test    rax, rax
    jz      .bad_sig
    mov     r8, rdi                 ; saved target
    mov     rdi, rax
    push    rsi
    push    r8
    mov     rsi, r8
    call    streq
    pop     r8
    pop     rsi
    test    eax, eax
    jnz     .matched
    mov     rdi, r8
    add     rsi, 16
    jmp     .scan

.matched:
    mov     r12, [rsi + 8]
    inc     r13d
    jmp     .ops

.ops:
    cmp     r13d, ebx
    jge     .missing

.pid_loop:
    cmp     r13d, ebx
    jge     .out

    mov     rdi, [rbp + r13*8]
    sub     rsp, 24
    mov     rsi, rsp
    call    parse_uint
    test    eax, eax
    jnz     .bad_pid_pop
    mov     rdx, [rsp]
    add     rsp, 24

    mov     eax, SYS_kill
    mov     edi, edx
    mov     esi, r12d
    syscall
    test    rax, rax
    jns     .pid_next
    mov     r14d, 1
    jmp     .pid_next

.bad_pid_pop:
    add     rsp, 24
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_pid]
    mov     edx, 19                 ; "kill: invalid pid: "
    syscall
    mov     edi, STDERR_FILENO
    mov     rsi, [rbp + r13*8]
    call    write_cstr
    mov     edi, STDERR_FILENO
    mov     esi, 10
    call    putc
    mov     r14d, 1

.pid_next:
    inc     r13d
    jmp     .pid_loop

.bad_sig:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_sig]
    mov     edx, err_bad_sig_len
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

; list_signals — emits "1 HUP\n 2 INT\n ..." lines.
list_signals:
    push    rbx
    sub     rsp, 8

    lea     rbx, [rel sig_table]
.line:
    mov     rax, [rbx]
    test    rax, rax
    jz      .done

    sub     rsp, 24
    mov     rdi, [rbx + 8]
    mov     rsi, rsp
    call    format_uint
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 24

    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc

    mov     edi, STDOUT_FILENO
    mov     rsi, [rbx]
    call    write_cstr

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    add     rbx, 16
    jmp     .line

.done:
    add     rsp, 8
    pop     rbx
    ret
