; head.asm — print the first N lines (or bytes) of each input.
;
;   head [-n N] [-c N] [FILE...]
;
; Default 10 lines. -nN / -cN concatenated forms also accepted.
; Multiple files prefix sections with "==> NAME <==" plus a blank line
; between sections. Negative counts (skip-from-tail) deferred.

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

global applet_head_main

%define BUF_BYTES 65536
%define MODE_LINES 0
%define MODE_BYTES 1

section .bss
align 16
head_iobuf:      resb BUF_BYTES
head_first_done: resb 1

section .rodata
opt_n:        db "-n", 0
opt_c:        db "-c", 0
prefix_head:  db "head", 0
hdr_open:     db "==> ", 0
hdr_close:    db " <==", 10, 0

section .text

; int applet_head_main(int argc /edi/, char **argv /rsi/)
applet_head_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; count
    push    r13                     ; mode
    push    r14                     ; rc
    push    r15                     ; arg cursor

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d
    mov     r12d, 10
    xor     r13d, r13d
    mov     byte [rel head_first_done], 0

    mov     r15d, 1
.flag_loop:
    cmp     r15d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r15*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    lea     rsi, [rel opt_n]
    call    streq
    test    eax, eax
    jnz     .have_n_sep
    mov     rdi, [rbp + r15*8]
    lea     rsi, [rel opt_c]
    call    streq
    test    eax, eax
    jnz     .have_c_sep

    mov     rdi, [rbp + r15*8]
    cmp     byte [rdi + 1], 'n'
    je      .have_n_inline
    cmp     byte [rdi + 1], 'c'
    je      .have_c_inline
    jmp     .flags_done

.have_n_sep:
    inc     r15d
    cmp     r15d, ebx
    jge     .flags_done
    mov     r13d, MODE_LINES
    mov     rdi, [rbp + r15*8]
    call    parse_count
    inc     r15d
    jmp     .flag_loop

.have_c_sep:
    inc     r15d
    cmp     r15d, ebx
    jge     .flags_done
    mov     r13d, MODE_BYTES
    mov     rdi, [rbp + r15*8]
    call    parse_count
    inc     r15d
    jmp     .flag_loop

.have_n_inline:
    mov     r13d, MODE_LINES
    lea     rdi, [rdi + 2]
    call    parse_count
    inc     r15d
    jmp     .flag_loop

.have_c_inline:
    mov     r13d, MODE_BYTES
    lea     rdi, [rdi + 2]
    call    parse_count
    inc     r15d
    jmp     .flag_loop

.flags_done:
    cmp     r15d, ebx
    jl      .files

    ; No files: stdin, no header.
    mov     edi, STDIN_FILENO
    xor     rsi, rsi
    mov     rdx, r12
    mov     ecx, r13d
    xor     r8d, r8d
    call    head_stream
    jmp     .out

.files:
    mov     ecx, ebx
    sub     ecx, r15d
    cmp     ecx, 1
    setg    cl
    movzx   ecx, cl                 ; 1 if multi-file else 0

.file_loop:
    cmp     r15d, ebx
    jge     .out

    mov     eax, SYS_open
    mov     rdi, [rbp + r15*8]
    mov     esi, O_RDONLY
    xor     edx, edx
    push    rcx
    sub     rsp, 8
    syscall
    add     rsp, 8
    pop     rcx
    test    rax, rax
    js      .file_open_err

    mov     edi, eax
    mov     rsi, [rbp + r15*8]
    mov     rdx, r12
    mov     r8, rcx
    mov     ecx, r13d
    push    r8
    sub     rsp, 8
    call    head_stream
    add     rsp, 8
    pop     rcx
    inc     r15d
    jmp     .file_loop

.file_open_err:
    push    rcx
    sub     rsp, 8
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_head]
    mov     rsi, [rbp + r15*8]
    call    perror_path
    add     rsp, 8
    pop     rcx
    mov     r14d, 1
    inc     r15d
    jmp     .file_loop

.out:
    mov     eax, r14d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_count(s /rdi/) -> sets r12 to the parsed value; sets r14d=1 on
; failure (rdi is not preserved).
parse_count:
    sub     rsp, 24                 ; 8-byte slot + 16-byte alignment pad
    mov     rsi, rsp
    call    parse_uint
    test    eax, eax
    jnz     .err
    mov     r12, [rsp]
    add     rsp, 24
    ret
.err:
    add     rsp, 24
    mov     r14d, 1
    ret

; ---------------------------------------------------------------------------
; head_stream(fd /edi/, name /rsi/, count /rdx/, mode /ecx/, want_header /r8d/)
;
;   Emits up to `count` lines or bytes from fd. Closes fd (unless stdin).
head_stream:
    push    rbx                     ; fd
    push    rbp                     ; remaining count
    push    r12                     ; mode
    push    r13                     ; saved name
    push    r14                     ; want_header

    mov     ebx, edi
    mov     rbp, rdx
    mov     r12d, ecx
    mov     r13, rsi
    mov     r14d, r8d

    test    r14d, r14d
    jz      .start
    test    r13, r13
    jz      .start

    cmp     byte [rel head_first_done], 0
    je      .skip_blank
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
.skip_blank:
    mov     byte [rel head_first_done], 1

    mov     edi, STDOUT_FILENO
    lea     rsi, [rel hdr_open]
    call    write_cstr
    mov     edi, STDOUT_FILENO
    mov     rsi, r13
    call    write_cstr
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel hdr_close]
    call    write_cstr

.start:
.read:
    test    rbp, rbp
    jz      .done
    mov     edi, ebx
    lea     rsi, [rel head_iobuf]
    mov     edx, BUF_BYTES
    call    read_buf
    test    rax, rax
    jz      .done
    js      .done

    test    r12d, r12d
    jnz     .bytes_mode

    ; Lines mode.
    mov     rcx, rax
    mov     r9, rcx
    lea     r8, [rel head_iobuf]
    mov     r10, r8
.lscan:
    test    rcx, rcx
    jz      .lflush
    mov     al, [r8]
    inc     r8
    dec     rcx
    cmp     al, 10
    jne     .lscan
    dec     rbp
    jnz     .lscan
    mov     edi, STDOUT_FILENO
    mov     rsi, r10
    mov     rdx, r8
    sub     rdx, r10
    call    write_all
    jmp     .done
.lflush:
    mov     edi, STDOUT_FILENO
    mov     rsi, r10
    mov     rdx, r9
    call    write_all
    jmp     .read

.bytes_mode:
    cmp     rax, rbp
    jle     .write_chunk
    mov     rax, rbp
.write_chunk:
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel head_iobuf]
    mov     rdx, rax
    sub     rbp, rax
    call    write_all
    jmp     .read

.done:
    cmp     ebx, STDIN_FILENO
    je      .ret
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
