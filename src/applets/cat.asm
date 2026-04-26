; cat.asm — concatenate files to stdout.
;
;   cat [FILE...]
;
; A single hyphen ("-") or no FILE means read from stdin. We don't yet
; support -n, -A, -E, -T, -s, etc.; cat is implemented strictly as a
; concatenator until the text-processing phase.
;
; Behavior on errors:
;   - cannot open      → print "cat: <path>: <errno>\n", set rc=1, continue
;   - read error       → same
;   - write error      → print + exit 1 (the rest is hopeless after that)

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern read_buf
extern write_all
extern perror_path

global applet_cat_main

%define BUF_LEN 65536
%define O_RDONLY 0

section .rodata
prefix_cat: db "cat", 0
hyphen:     db "-", 0
stdin_path: db "<stdin>", 0

section .bss
align 16
io_buf: resb BUF_LEN

section .text

; int applet_cat_main(int argc /edi/, char **argv /rsi/)
applet_cat_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; arg index
    push    r13                     ; current fd
    push    r14                     ; rc accumulator

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d              ; rc = 0

    cmp     ebx, 2
    jl      .stdin_only

    mov     r12d, 1
.arg_loop:
    cmp     r12d, ebx
    jge     .out

    mov     rdi, [rbp + r12*8]
    call    open_arg
    mov     r13d, eax
    test    r13d, r13d
    js      .open_fail

    push    rax
    mov     rdi, [rbp + r12*8]
    mov     esi, r13d
    call    cat_fd
    pop     rcx

    test    eax, eax
    jz      .next
    mov     r14d, 1

.next:
    mov     edi, r13d
    call    close_if_not_stdin
    inc     r12d
    jmp     .arg_loop

.open_fail:
    neg     eax                     ; errno
    mov     edx, eax
    lea     rdi, [rel prefix_cat]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    inc     r12d
    jmp     .arg_loop

.stdin_only:
    lea     rdi, [rel stdin_path]
    mov     esi, STDIN_FILENO
    call    cat_fd
    test    eax, eax
    jz      .out
    mov     r14d, 1

.out:
    mov     eax, r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; open_arg(path /rdi/) -> rax = fd or -errno
;
;   Opens the file. The literal "-" means stdin and is returned without
;   touching the kernel.
open_arg:
    cmp     byte [rdi], '-'
    jne     .open
    cmp     byte [rdi + 1], 0
    jne     .open
    mov     eax, STDIN_FILENO
    ret
.open:
    mov     eax, SYS_open
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    ret

; close_if_not_stdin(fd /edi/)
close_if_not_stdin:
    cmp     edi, STDIN_FILENO
    je      .skip
    mov     eax, SYS_close
    syscall
.skip:
    ret

; ---------------------------------------------------------------------------
; cat_fd(path /rdi/, fd /esi/) -> rax = 0 on success, 1 on error
;
;   Read-write loop. path is used for error messages only.
cat_fd:
    push    rbx                     ; saved path
    push    r12                     ; fd
    push    r13                     ; (alignment)

    mov     rbx, rdi
    mov     r12d, esi

.loop:
    mov     edi, r12d
    lea     rsi, [rel io_buf]
    mov     edx, BUF_LEN
    call    read_buf

    test    rax, rax
    jz      .ok                     ; EOF
    js      .read_err

    mov     edi, STDOUT_FILENO
    lea     rsi, [rel io_buf]
    mov     rdx, rax
    call    write_all
    test    eax, eax
    js      .write_err
    jmp     .loop

.ok:
    xor     eax, eax
    jmp     .ret

.read_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cat]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1
    jmp     .ret

.write_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cat]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
