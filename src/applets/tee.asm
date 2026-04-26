; tee.asm — read stdin, write to stdout AND each named file.
;
;   tee [-a] [FILE...]
;
; -a appends instead of truncating. Failures opening or writing to a
; named file are reported but do not abort the operation — the other
; outputs (including stdout) keep going. Stdout failures (EPIPE etc.)
; do abort, since "tee | head" producing nothing is a worse outcome
; than a fast exit.
;
; v1 doesn't ignore SIGPIPE (no rt_sigaction wiring yet) — a broken
; downstream stdout will still kill us. Land that with the signal
; helpers.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern read_buf
extern write_all
extern perror_path

global applet_tee_main

%define MAX_FILES 64
%define BUF_BYTES 65536

section .bss
align 16
tee_fds:    resq MAX_FILES + 1      ; stdout slot + named files
tee_iobuf:  resb BUF_BYTES

section .rodata
opt_a:        db "-a", 0
prefix_tee:   db "tee", 0

section .text

; int applet_tee_main(int argc /edi/, char **argv /rsi/)
;
; rbx  argc
; rbp  argv
; r12  fd count (initially 1: stdout)
; r13  -a flag
; r14  rc
; r15  arg cursor
applet_tee_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d
    xor     r14d, r14d
    mov     r12d, 1
    mov     qword [rel tee_fds], STDOUT_FILENO

    mov     r15d, 1
.flag_loop:
    cmp     r15d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r15*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done
    lea     rsi, [rel opt_a]
    call    streq
    test    eax, eax
    jz      .flags_done
    mov     r13d, 1
    inc     r15d
    jmp     .flag_loop

.flags_done:
.open_loop:
    cmp     r15d, ebx
    jge     .pipe
    cmp     r12d, MAX_FILES
    jge     .pipe                   ; ignore extras

    mov     eax, SYS_open
    mov     rdi, [rbp + r15*8]
    mov     esi, O_WRONLY | O_CREAT
    test    r13d, r13d
    jz      .trunc
    or      esi, O_APPEND
    jmp     .have_flags
.trunc:
    or      esi, O_TRUNC
.have_flags:
    mov     edx, 0o666
    syscall
    test    rax, rax
    js      .open_err

    mov     [rel tee_fds + r12*8], rax
    inc     r12d
    inc     r15d
    jmp     .open_loop

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_tee]
    mov     rsi, [rbp + r15*8]
    call    perror_path
    mov     r14d, 1
    inc     r15d
    jmp     .open_loop

.pipe:
.read_loop:
    mov     edi, STDIN_FILENO
    lea     rsi, [rel tee_iobuf]
    mov     edx, BUF_BYTES
    call    read_buf
    test    rax, rax
    jz      .done
    js      .read_err
    mov     [rsp], rax              ; preserve bytes_read across writes

    mov     ecx, r12d
    xor     r9d, r9d
.fan_out:
    cmp     r9d, ecx
    jge     .read_loop
    push    rcx
    push    r9
    mov     edi, [rel tee_fds + r9*8]
    lea     rsi, [rel tee_iobuf]
    mov     rdx, [rsp + 16]
    call    write_all
    pop     r9
    pop     rcx
    test    eax, eax
    jns     .fan_next
    test    r9d, r9d
    jz      .done                   ; stdout failure → bail
    mov     r14d, 1                 ; named-file failure → record + continue
.fan_next:
    inc     r9d
    jmp     .fan_out

.read_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_tee]
    lea     rsi, [rel prefix_tee]   ; placeholder name; stdin
    call    perror_path
    mov     r14d, 1

.done:
    ; Close all named-file fds (skip stdout at index 0).
    mov     ecx, 1
.close_loop:
    cmp     ecx, r12d
    jge     .out
    mov     edi, [rel tee_fds + rcx*8]
    push    rcx
    mov     eax, SYS_close
    syscall
    pop     rcx
    inc     ecx
    jmp     .close_loop

.out:
    mov     eax, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
