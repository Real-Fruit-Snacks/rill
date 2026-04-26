; mkdir.asm — create directories.
;
;   mkdir [-p] DIR...
;
; v1 supports -p (create intermediate parents, ignore EEXIST). The -m
; (mode) flag is not yet implemented; created directories use 0777 minus
; the process umask, which is what mkdir(2) does naturally.
;
; -p implementation: walk each path forward, and at every internal '/'
; that follows a non-slash character, NUL-terminate temporarily, mkdir
; the prefix (ignoring EEXIST), then restore the '/'. Finally mkdir the
; full path. argv strings live on the writable initial-stack frame, so
; in-place mutation is safe.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern streq
extern perror_path

global applet_mkdir_main

%define EEXIST 17

section .rodata
opt_p:        db "-p", 0
err_missing:  db "mkdir: missing operand", 10
err_missing_len: equ $ - err_missing
prefix_mkdir: db "mkdir", 0

section .text

; int applet_mkdir_main(int argc /edi/, char **argv /rsi/)
applet_mkdir_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; arg cursor
    push    r13                     ; -p flag
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d
    xor     r14d, r14d

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .ops
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .ops
    cmp     byte [rdi + 1], 0
    je      .ops
    lea     rsi, [rel opt_p]
    call    streq
    test    eax, eax
    jz      .ops
    mov     r13d, 1
    inc     r12d
    jmp     .flag_loop

.ops:
    cmp     r12d, ebx
    jge     .missing

.do_loop:
    cmp     r12d, ebx
    jge     .out

    mov     rdi, [rbp + r12*8]
    test    r13d, r13d
    jnz     .do_p

    mov     eax, SYS_mkdir
    mov     esi, 0o777
    syscall
    test    rax, rax
    jns     .next
    jmp     .report

.do_p:
    call    mkdir_p_inplace
    test    rax, rax
    jns     .next

.report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_mkdir]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1

.next:
    inc     r12d
    jmp     .do_loop

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

; ---------------------------------------------------------------------------
; mkdir_p_inplace(path /rdi/) -> rax = 0 or -errno
;
; Walks path forward, mkdir'ing each prefix at every internal '/' that
; follows a non-slash byte. EEXIST is treated as success at every step,
; including the final mkdir on the whole path.
mkdir_p_inplace:
    push    rbx                     ; original path
    push    r12                     ; cursor
    push    r13                     ; (alignment)

    mov     rbx, rdi
    lea     r12, [rdi + 1]          ; skip index 0 (a leading '/' would
                                    ; map to an empty prefix, which mkdir
                                    ; would reject with ENOENT)

.scan:
    mov     al, [r12]
    test    al, al
    jz      .final

    cmp     al, '/'
    jne     .advance
    cmp     byte [r12 - 1], '/'
    je      .advance                ; collapse runs of /

    mov     byte [r12], 0
    mov     eax, SYS_mkdir
    mov     rdi, rbx
    mov     esi, 0o777
    syscall
    mov     byte [r12], '/'

    test    rax, rax
    jns     .advance
    cmp     eax, -EEXIST
    jne     .ret

.advance:
    inc     r12
    jmp     .scan

.final:
    mov     eax, SYS_mkdir
    mov     rdi, rbx
    mov     esi, 0o777
    syscall
    test    rax, rax
    jns     .ok
    cmp     eax, -EEXIST
    jne     .ret
.ok:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
