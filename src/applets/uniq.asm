; uniq.asm — collapse adjacent duplicate lines.
;
;   uniq [-c] [-d] [-u] [INPUT]
;
; -c   prefix each output line with the count of consecutive matches
; -d   only emit duplicated lines (count > 1)
; -u   only emit unique lines (count == 1)
;
; -d and -u are mutually exclusive in coreutils; we accept any combo and
; behave as the intersection (which can produce empty output by design).
;
; v1 doesn't implement -i (case-insensitive), -f N (skip first N fields),
; -s N (skip first N chars), or the OUTPUT-file second positional arg.
; Lines longer than 8 KB are truncated at the boundary.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern format_uint_pad
extern read_buf
extern write_all
extern perror_path

global applet_uniq_main

%define LINE_BYTES 8192
%define IO_BYTES   65536
%define OUT_BYTES  4096

section .bss
align 16
uniq_iobuf:    resb IO_BYTES
uniq_outbuf:   resb OUT_BYTES
uniq_prev:     resb LINE_BYTES
uniq_cur:      resb LINE_BYTES
uniq_iopos:    resq 1
uniq_iolen:    resq 1
uniq_iofd:     resq 1
uniq_outpos:   resq 1
uniq_prev_len: resq 1
uniq_cur_len:  resq 1
uniq_count:    resq 1
uniq_ioeof:    resb 1
uniq_have_prev: resb 1
uniq_flag_c:   resb 1
uniq_flag_d:   resb 1
uniq_flag_u:   resb 1

section .rodata
opt_c:        db "-c", 0
opt_d:        db "-d", 0
opt_u:        db "-u", 0
prefix_uniq:  db "uniq", 0

section .text

; int applet_uniq_main(int argc /edi/, char **argv /rsi/)
applet_uniq_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d
    mov     byte [rel uniq_flag_c], 0
    mov     byte [rel uniq_flag_d], 0
    mov     byte [rel uniq_flag_u], 0
    mov     byte [rel uniq_have_prev], 0
    mov     byte [rel uniq_ioeof], 0
    mov     qword [rel uniq_iopos], 0
    mov     qword [rel uniq_iolen], 0
    mov     qword [rel uniq_outpos], 0
    mov     qword [rel uniq_count], 0

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    lea     rsi, [rel opt_c]
    call    streq
    test    eax, eax
    jnz     .set_c
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_d]
    call    streq
    test    eax, eax
    jnz     .set_d
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_u]
    call    streq
    test    eax, eax
    jnz     .set_u
    jmp     .flags_done
.set_c: mov byte [rel uniq_flag_c], 1
        inc r12d
        jmp .flag_loop
.set_d: mov byte [rel uniq_flag_d], 1
        inc r12d
        jmp .flag_loop
.set_u: mov byte [rel uniq_flag_u], 1
        inc r12d
        jmp .flag_loop

.flags_done:
    cmp     r12d, ebx
    jl      .with_file

    mov     qword [rel uniq_iofd], STDIN_FILENO
    jmp     .process

.with_file:
    mov     eax, SYS_open
    mov     rdi, [rbp + r12*8]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_err
    mov     [rel uniq_iofd], rax

.process:
.line_loop:
    call    read_line
    test    rax, rax
    js      .eof

    ; Compare uniq_cur with uniq_prev.
    cmp     byte [rel uniq_have_prev], 0
    je      .first

    mov     rdx, [rel uniq_prev_len]
    cmp     rdx, [rel uniq_cur_len]
    jne     .different
    mov     rdi, [rel uniq_prev_len]
    test    rdi, rdi
    jz      .same
    lea     rsi, [rel uniq_prev]
    lea     rdi, [rel uniq_cur]
    mov     rcx, rdx
    repe    cmpsb
    jne     .different

.same:
    inc     qword [rel uniq_count]
    jmp     .line_loop

.different:
    call    emit_run
    jmp     .stash_cur

.first:
    mov     byte [rel uniq_have_prev], 1
.stash_cur:
    mov     rcx, [rel uniq_cur_len]
    mov     [rel uniq_prev_len], rcx
    test    rcx, rcx
    jz      .cur_stashed
    lea     rsi, [rel uniq_cur]
    lea     rdi, [rel uniq_prev]
    rep     movsb
.cur_stashed:
    mov     qword [rel uniq_count], 1
    jmp     .line_loop

.eof:
    cmp     byte [rel uniq_have_prev], 0
    je      .done
    call    emit_run
.done:
    cmp     qword [rel uniq_iofd], STDIN_FILENO
    je      .out
    mov     eax, SYS_close
    mov     rdi, [rel uniq_iofd]
    syscall
    jmp     .out

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_uniq]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1

.out:
    call    flush_out
    mov     eax, r14d
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; emit_run — write the current prev line if -d/-u allow it, optionally
; with leading count for -c. Resets the run counter.
emit_run:
    cmp     byte [rel uniq_flag_d], 0
    jz      .check_u
    mov     rax, [rel uniq_count]
    cmp     rax, 1
    jle     .skip
.check_u:
    cmp     byte [rel uniq_flag_u], 0
    jz      .do_emit
    mov     rax, [rel uniq_count]
    cmp     rax, 1
    jne     .skip

.do_emit:
    cmp     byte [rel uniq_flag_c], 0
    jz      .no_count

    sub     rsp, 24
    mov     rdi, [rel uniq_count]
    mov     rsi, rsp
    mov     rdx, 7
    call    format_uint_pad
    mov     r9, rax                 ; len of count text
    mov     rcx, 0
.copy_count:
    cmp     rcx, r9
    jge     .count_done
    mov     al, [rsp + rcx]
    push    rcx
    push    r9
    call    emit_byte
    pop     r9
    pop     rcx
    inc     rcx
    jmp     .copy_count
.count_done:
    add     rsp, 24
    mov     al, ' '
    call    emit_byte

.no_count:
    mov     rcx, [rel uniq_prev_len]
    test    rcx, rcx
    jz      .nl
    lea     r8, [rel uniq_prev]
    xor     r9, r9
.line_copy:
    cmp     r9, rcx
    jge     .nl
    mov     al, [r8 + r9]
    push    rcx
    push    r8
    push    r9
    call    emit_byte
    pop     r9
    pop     r8
    pop     rcx
    inc     r9
    jmp     .line_copy

.nl:
    mov     al, 10
    call    emit_byte

.skip:
    ret

; ---------------------------------------------------------------------------
; read_line() — fills uniq_cur and uniq_cur_len. Returns -1 on EOF
; (when no more lines), 0 otherwise.
read_line:
    push    rbx                     ; line cursor
    push    rbp                     ; (alignment)

    xor     ebx, ebx
    mov     qword [rel uniq_cur_len], 0

.byte_loop:
    ; Refill if needed.
    mov     rax, [rel uniq_iopos]
    cmp     rax, [rel uniq_iolen]
    jl      .have_byte

    cmp     byte [rel uniq_ioeof], 0
    jne     .at_eof

    mov     edi, [rel uniq_iofd]
    lea     rsi, [rel uniq_iobuf]
    mov     edx, IO_BYTES
    call    read_buf
    test    rax, rax
    jz      .read_eof
    js      .read_eof
    mov     [rel uniq_iolen], rax
    mov     qword [rel uniq_iopos], 0
    jmp     .byte_loop

.read_eof:
    mov     byte [rel uniq_ioeof], 1
    mov     qword [rel uniq_iolen], 0
    mov     qword [rel uniq_iopos], 0
    test    ebx, ebx
    jnz     .return_line            ; partial last line without \n
.at_eof:
    mov     rax, -1
    jmp     .ret

.have_byte:
    mov     rcx, [rel uniq_iopos]
    movzx   eax, byte [rel uniq_iobuf + rcx]
    inc     qword [rel uniq_iopos]

    cmp     al, 10
    je      .return_line

    cmp     ebx, LINE_BYTES
    jge     .byte_loop              ; truncate overlong line silently
    mov     [rel uniq_cur + rbx], al
    inc     ebx
    jmp     .byte_loop

.return_line:
    mov     [rel uniq_cur_len], rbx
    xor     eax, eax

.ret:
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
emit_byte:
    push    rax
    mov     rcx, [rel uniq_outpos]
    cmp     rcx, OUT_BYTES
    jl      .room
    call    flush_out
    mov     rcx, [rel uniq_outpos]
.room:
    pop     rax
    lea     r8, [rel uniq_outbuf]
    mov     [r8 + rcx], al
    inc     rcx
    mov     [rel uniq_outpos], rcx
    ret

flush_out:
    mov     rcx, [rel uniq_outpos]
    test    rcx, rcx
    jz      .done
    sub     rsp, 8
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel uniq_outbuf]
    mov     rdx, rcx
    call    write_all
    add     rsp, 8
    mov     qword [rel uniq_outpos], 0
.done:
    ret
