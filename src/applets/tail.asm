; tail.asm — print the last N lines of each input.
;
;   tail [-n N] [FILE...]
;
; Default 10 lines. -nN concatenated form accepted. Multiple files emit
; "==> NAME <==" headers between sections (matching head's behavior).
;
; Strategy: read each input into a 4 MB .bss accumulator. If the input
; would exceed that, slide the buffer forward (discarding the oldest
; half and continuing). Then scan from the end for the Nth newline and
; emit forward from there. -f / -c / negative-count semantics deferred.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern parse_uint
extern read_buf
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_tail_main

%define BUF_BYTES 4194304           ; 4 MB
%define HALF       2097152

section .bss
align 16
tail_buf:        resb BUF_BYTES
tail_first_done: resb 1

section .rodata
opt_n:        db "-n", 0
prefix_tail:  db "tail", 0
hdr_open:     db "==> ", 0
hdr_close:    db " <==", 10, 0

section .text

; int applet_tail_main(int argc /edi/, char **argv /rsi/)
applet_tail_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; count
    push    r13                     ; rc
    push    r14                     ; arg cursor
    push    r15                     ; want_header

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d
    mov     r12d, 10
    mov     byte [rel tail_first_done], 0

    mov     r14d, 1
.flag_loop:
    cmp     r14d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r14*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    lea     rsi, [rel opt_n]
    call    streq
    test    eax, eax
    jnz     .have_n_sep

    mov     rdi, [rbp + r14*8]
    cmp     byte [rdi + 1], 'n'
    je      .have_n_inline
    jmp     .flags_done

.have_n_sep:
    inc     r14d
    cmp     r14d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r14*8]
    sub     rsp, 24
    mov     rsi, rsp
    call    parse_uint
    test    eax, eax
    jnz     .bad_count
    mov     r12, [rsp]
    add     rsp, 24
    inc     r14d
    jmp     .flag_loop

.have_n_inline:
    lea     rdi, [rdi + 2]
    sub     rsp, 24
    mov     rsi, rsp
    call    parse_uint
    test    eax, eax
    jnz     .bad_count
    mov     r12, [rsp]
    add     rsp, 24
    inc     r14d
    jmp     .flag_loop

.bad_count:
    add     rsp, 24
    mov     r13d, 1
    jmp     .out

.flags_done:
    cmp     r14d, ebx
    jl      .files

    mov     edi, STDIN_FILENO
    xor     rsi, rsi
    mov     rdx, r12
    xor     ecx, ecx
    call    tail_stream
    jmp     .out

.files:
    mov     ecx, ebx
    sub     ecx, r14d
    cmp     ecx, 1
    setg    cl
    movzx   r15d, cl

.file_loop:
    cmp     r14d, ebx
    jge     .out

    mov     eax, SYS_open
    mov     rdi, [rbp + r14*8]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_err

    mov     edi, eax
    mov     rsi, [rbp + r14*8]
    mov     rdx, r12
    mov     ecx, r15d
    call    tail_stream
    inc     r14d
    jmp     .file_loop

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_tail]
    mov     rsi, [rbp + r14*8]
    call    perror_path
    mov     r13d, 1
    inc     r14d
    jmp     .file_loop

.out:
    mov     eax, r13d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; tail_stream(fd /edi/, name /rsi/, count /rdx/, want_header /ecx/)
tail_stream:
    push    rbx                     ; fd
    push    rbp                     ; cumulative bytes in tail_buf
    push    r12                     ; count
    push    r13                     ; saved name
    push    r14                     ; want_header
    sub     rsp, 8

    mov     ebx, edi
    mov     r13, rsi
    mov     r12, rdx
    mov     r14d, ecx
    xor     ebp, ebp

    ; Header (mirrors head's logic).
    test    r14d, r14d
    jz      .read
    test    r13, r13
    jz      .read

    cmp     byte [rel tail_first_done], 0
    je      .skip_blank
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
.skip_blank:
    mov     byte [rel tail_first_done], 1

    mov     edi, STDOUT_FILENO
    lea     rsi, [rel hdr_open]
    call    write_cstr
    mov     edi, STDOUT_FILENO
    mov     rsi, r13
    call    write_cstr
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel hdr_close]
    call    write_cstr

.read:
    mov     edx, BUF_BYTES
    sub     edx, ebp
    test    edx, edx
    jnz     .do_read

    ; Buffer full: slide forward by HALF bytes.
    lea     rdi, [rel tail_buf]
    lea     rsi, [rel tail_buf + HALF]
    mov     ecx, BUF_BYTES - HALF
    rep     movsb
    sub     rbp, HALF
    mov     edx, BUF_BYTES
    sub     edx, ebp

.do_read:
    mov     eax, SYS_read
    mov     edi, ebx
    lea     rsi, [rel tail_buf]
    add     rsi, rbp
    syscall
    test    rax, rax
    jz      .eof
    js      .eof
    add     rbp, rax
    jmp     .read

.eof:
    cmp     ebx, STDIN_FILENO
    je      .have_data
    mov     eax, SYS_close
    mov     edi, ebx
    syscall

.have_data:
    test    rbp, rbp
    jz      .ret
    test    r12, r12
    jz      .ret

    ; Scan backwards for the count-th newline (after possibly skipping a
    ; trailing newline at the very end).
    lea     rsi, [rel tail_buf]     ; base
    mov     rdi, rbp                ; index = total
    dec     rdi                     ; last byte index
    cmp     byte [rsi + rdi], 10
    jne     .scan
    dec     rdi                     ; skip trailing newline

    test    rdi, rdi
    js      .emit_all

.scan:
    mov     rcx, r12                ; remaining nl_count
.scan_loop:
    test    rdi, rdi
    js      .emit_all
    cmp     byte [rsi + rdi], 10
    jne     .back
    dec     rcx
    jz      .found
.back:
    dec     rdi
    jmp     .scan_loop

.found:
    inc     rdi                     ; first byte of the tail
    mov     r8, rdi                 ; save offset before reusing rdi for fd
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel tail_buf]
    add     rsi, r8
    mov     rdx, rbp
    sub     rdx, r8
    call    write_all
    jmp     .ret

.emit_all:
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel tail_buf]
    mov     rdx, rbp
    call    write_all

.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
