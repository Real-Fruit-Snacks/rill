; yes.asm — print a line forever.
;
; Default line is "y\n". With args, the line is argv[1..] joined by spaces
; with a trailing newline. Lines longer than the line buffer (4096 bytes)
; are silently truncated.
;
; Performance note: a future pass should fill the buffer with N copies of
; the line so each write_all amortizes the syscall over many lines.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern strlen
extern write_all

global applet_yes_main

%define LINE_CAP 4096

section .rodata
default_line:     db "y", 10
default_line_len: equ $ - default_line

section .bss
align 16
line_buf:        resb LINE_CAP

section .text

; int applet_yes_main(int argc /edi/, char **argv /rsi/)
applet_yes_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; cursor into line_buf
    push    r13                     ; argv index
    push    r14                     ; end-of-buffer (line_buf + cap - 1)

    mov     ebx, edi
    mov     rbp, rsi

    cmp     ebx, 2
    jl      .use_default

    lea     r12, [rel line_buf]
    lea     r14, [r12 + LINE_CAP - 1]   ; reserve the last byte for '\n'
    mov     r13d, 1

.join_arg:
    cmp     r13d, ebx
    jge     .terminate
    mov     rdi, [rbp + r13*8]
    call    copy_clamped            ; copies *rdi into [r12..r14), advances r12
    inc     r13d
    cmp     r13d, ebx
    jge     .terminate
    cmp     r12, r14
    jge     .terminate
    mov     byte [r12], ' '
    inc     r12
    jmp     .join_arg

.terminate:
    mov     byte [r12], 10
    inc     r12
    lea     rbp, [rel line_buf]
    mov     rdx, r12
    sub     rdx, rbp                ; rdx = total length
    jmp     .write_loop

.use_default:
    lea     rbp, [rel default_line]
    mov     edx, default_line_len

.write_loop:
    mov     edi, STDOUT_FILENO
    mov     rsi, rbp
    push    rdx
    call    write_all
    pop     rdx
    test    eax, eax
    jz      .write_loop
    ; Any error (typically EPIPE from `yes | head` consumer exit) ends the
    ; loop. yes(1) is documented as exiting 0 only on broken-pipe / EOF.
    xor     eax, eax

    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; copy_clamped(const char *src /rdi/) — copies bytes from src into [r12..r14),
; stopping at NUL or when r12 reaches r14. r12 is updated to point past the
; last byte written. Clobbers rax and rdi only. Preserves r13, r14, rbp, rbx.
copy_clamped:
.loop:
    cmp     r12, r14
    jge     .done
    mov     al, [rdi]
    test    al, al
    jz      .done
    mov     [r12], al
    inc     r12
    inc     rdi
    jmp     .loop
.done:
    ret
