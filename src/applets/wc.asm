; wc.asm — count lines, words, bytes.
;
;   wc [-l] [-w] [-c] [FILE...]
;
; Without -l/-w/-c, all three counts are printed. With any subset, only
; those columns. Multiple files print one row per file plus a "total"
; row. No FILE means stdin (and no name printed).
;
; Word boundaries are ASCII-whitespace (space, tab, newline, CR, FF, VT).
; Byte counts are bytes, not characters — multibyte (-m) deferred.
;
; Globals (.bss) hold the in-progress per-stream counts plus a running
; total. count_stream() updates both, then calls emit_row().

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern read_buf
extern format_uint_pad
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_wc_main

%define BUF_BYTES 65536

%define FLAG_LINES  1
%define FLAG_WORDS  2
%define FLAG_BYTES  4

section .bss
align 16
wc_iobuf:    resb BUF_BYTES
wc_lines:    resq 1                 ; per-stream
wc_words:    resq 1
wc_bytes:    resq 1
wc_total_l:  resq 1
wc_total_w:  resq 1
wc_total_b:  resq 1
wc_flags:    resb 1                 ; FLAG_* combination

section .rodata
opt_l:        db "-l", 0
opt_w:        db "-w", 0
opt_c:        db "-c", 0
prefix_wc:    db "wc", 0
total_label:  db "total", 0

section .text

; int applet_wc_main(int argc /edi/, char **argv /rsi/)
applet_wc_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; arg cursor
    push    r13                     ; first-file index
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d
    mov     byte [rel wc_flags], 0
    mov     qword [rel wc_total_l], 0
    mov     qword [rel wc_total_w], 0
    mov     qword [rel wc_total_b], 0

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    lea     rsi, [rel opt_l]
    call    streq
    test    eax, eax
    jnz     .set_l
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_w]
    call    streq
    test    eax, eax
    jnz     .set_w
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_c]
    call    streq
    test    eax, eax
    jnz     .set_c
    jmp     .flags_done

.set_l: or byte [rel wc_flags], FLAG_LINES
        inc r12d
        jmp .flag_loop
.set_w: or byte [rel wc_flags], FLAG_WORDS
        inc r12d
        jmp .flag_loop
.set_c: or byte [rel wc_flags], FLAG_BYTES
        inc r12d
        jmp .flag_loop

.flags_done:
    cmp     byte [rel wc_flags], 0
    jne     .have_flags
    mov     byte [rel wc_flags], FLAG_LINES | FLAG_WORDS | FLAG_BYTES
.have_flags:

    mov     r13d, r12d              ; first-file index

    cmp     r12d, ebx
    jl      .files

    ; No files → stdin only.
    mov     edi, STDIN_FILENO
    xor     rsi, rsi
    call    count_stream
    jmp     .out

.files:
.file_loop:
    cmp     r12d, ebx
    jge     .files_done

    mov     eax, SYS_open
    mov     rdi, [rbp + r12*8]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .file_open_err

    mov     edi, eax
    mov     rsi, [rbp + r12*8]
    call    count_stream
    inc     r12d
    jmp     .file_loop

.file_open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_wc]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    inc     r12d
    jmp     .file_loop

.files_done:
    ; Total row only if we processed >1 file.
    mov     ecx, ebx
    sub     ecx, r13d
    cmp     ecx, 2
    jl      .out

    mov     rdi, [rel wc_total_l]
    mov     rsi, [rel wc_total_w]
    mov     rdx, [rel wc_total_b]
    lea     rcx, [rel total_label]
    call    emit_row

.out:
    mov     eax, r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; count_stream(fd /edi/, name /rsi/)
;
;   Counts the stream's lines/words/bytes, accumulates into wc_total_*,
;   emits a row, and closes the fd (skipping stdin).
count_stream:
    push    rbx                     ; fd
    push    rbp                     ; saved name
    push    r12                     ; lines
    push    r13                     ; words
    push    r14                     ; bytes
    push    r15                     ; in_word state (0/1)
    sub     rsp, 8                  ; align

    mov     ebx, edi
    mov     rbp, rsi
    xor     r12, r12
    xor     r13, r13
    xor     r14, r14
    xor     r15d, r15d

.read:
    mov     edi, ebx
    lea     rsi, [rel wc_iobuf]
    mov     edx, BUF_BYTES
    call    read_buf
    test    rax, rax
    jz      .eof
    js      .eof                    ; treat read errors as EOF for v1

    add     r14, rax                ; bytes
    mov     rcx, rax
    lea     rsi, [rel wc_iobuf]
.scan:
    test    rcx, rcx
    jz      .read
    mov     al, [rsi]
    inc     rsi
    dec     rcx

    cmp     al, 10
    jne     .not_nl
    inc     r12
.not_nl:
    cmp     al, ' '
    je      .ws
    cmp     al, 9
    je      .ws
    cmp     al, 10
    je      .ws
    cmp     al, 11
    je      .ws
    cmp     al, 12
    je      .ws
    cmp     al, 13
    je      .ws

    ; non-ws
    test    r15d, r15d
    jnz     .scan
    mov     r15d, 1
    inc     r13
    jmp     .scan

.ws:
    xor     r15d, r15d
    jmp     .scan

.eof:
    cmp     ebx, STDIN_FILENO
    je      .skip_close
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
.skip_close:

    ; Update totals.
    add     [rel wc_total_l], r12
    add     [rel wc_total_w], r13
    add     [rel wc_total_b], r14

    mov     [rel wc_lines], r12
    mov     [rel wc_words], r13
    mov     [rel wc_bytes], r14

    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    mov     rcx, rbp
    call    emit_row

    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; emit_row(lines /rdi/, words /rsi/, bytes /rdx/, name /rcx/)
;
;   Right-aligned 7-wide columns, only those enabled in wc_flags. Name
;   suppressed when NULL.
emit_row:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    sub     rsp, 8

    mov     rbx, rdi
    mov     rbp, rsi
    mov     r12, rdx
    mov     r13, rcx

    mov     r14b, [rel wc_flags]

    test    r14b, FLAG_LINES
    jz      .skip_l
    mov     rdi, rbx
    call    emit_padded_uint
.skip_l:

    test    r14b, FLAG_WORDS
    jz      .skip_w
    test    r14b, FLAG_LINES
    jz      .no_pre_w
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.no_pre_w:
    mov     rdi, rbp
    call    emit_padded_uint
.skip_w:

    test    r14b, FLAG_BYTES
    jz      .skip_b
    mov     dl, FLAG_LINES | FLAG_WORDS
    test    r14b, dl
    jz      .no_pre_b
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.no_pre_b:
    mov     rdi, r12
    call    emit_padded_uint
.skip_b:

    test    r13, r13
    jz      .nl
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
    mov     edi, STDOUT_FILENO
    mov     rsi, r13
    call    write_cstr

.nl:
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; emit_padded_uint(value /rdi/) — writes value in a 7-wide right-aligned
; field to stdout.
emit_padded_uint:
    sub     rsp, 32
    mov     rsi, rsp
    mov     rdx, 7
    call    format_uint_pad
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 32
    ret
