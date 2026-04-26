; io.asm — buffered I/O primitives over the raw read/write syscalls.
;
; All functions return 0 on success and -errno on failure. write_all and
; read_full handle short-write/short-read as well as EINTR transparently.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

global write_all
global write_cstr
global putc
global read_buf

extern strlen

%define EINTR 4

section .text

; int write_all(int fd /edi/, const void *buf /rsi/, size_t len /rdx/)
;
;   Writes the entire buffer or returns -errno. Retries on EINTR and short
;   writes. fd is held in rbx, cursor in r12, remaining in r13.
write_all:
    push    rbx
    push    r12
    push    r13

    mov     ebx, edi
    mov     r12, rsi
    mov     r13, rdx

.loop:
    test    r13, r13
    jz      .ok

    mov     eax, SYS_write
    mov     edi, ebx
    mov     rsi, r12
    mov     rdx, r13
    syscall

    test    rax, rax
    js      .check_intr

    add     r12, rax
    sub     r13, rax
    jmp     .loop

.check_intr:
    cmp     rax, -EINTR
    je      .loop
    jmp     .out

.ok:
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; int write_cstr(int fd /edi/, const char *s /rsi/)
;
;   strlen + write_all. Returns 0 or -errno.
write_cstr:
    push    rdi                     ; save fd
    push    rsi                     ; save s; 2 pushes -> need 8 of pad
    sub     rsp, 8

    mov     rdi, rsi
    call    strlen

    add     rsp, 8
    pop     rsi
    pop     rdi

    mov     rdx, rax
    jmp     write_all                ; tail call

; int putc(int fd /edi/, char c /sil/)
;
;   Writes a single byte. Stack space holds the byte for the syscall buf.
putc:
    sub     rsp, 16                 ; one byte buffer; 16 keeps alignment
    mov     [rsp], sil

    mov     eax, SYS_write
    mov     rsi, rsp
    mov     edx, 1
    ; edi already has fd
    syscall

    add     rsp, 16
    test    rax, rax
    js      .err
    xor     eax, eax
.err:
    ret

; ssize_t read_buf(int fd /edi/, void *buf /rsi/, size_t len /rdx/)
;
;   Single-shot read. Retries only on EINTR. Returns bytes read (>=0) or
;   -errno. A return of 0 means EOF.
read_buf:
.again:
    mov     eax, SYS_read
    syscall
    cmp     rax, -EINTR
    je      .again
    ret
