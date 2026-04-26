; cut.asm — extract sections from each line of input.
;
;   cut -c LIST [FILE...]
;   cut -b LIST [FILE...]            (synonym for -c on ASCII; no multibyte)
;   cut -d DELIM -f LIST [FILE...]
;
; LIST is a comma-separated list of N | N-M | N- | -M items. Field
; ranges are 1-based; an open `N-` runs to end of line and `-M` runs
; from position 1.
;
; -d defaults to TAB. v1 doesn't support -s (suppress lines without the
; delimiter), --output-delimiter, --complement, or multi-byte chars.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern read_buf
extern write_all
extern perror_path

global applet_cut_main

%define BUF_BYTES 65536
%define MAX_RANGES 256
%define OUT_BUF_BYTES 4096

%define MODE_NONE   0
%define MODE_CHARS  1
%define MODE_FIELDS 2

section .bss
align 16
cut_iobuf:    resb BUF_BYTES
cut_outbuf:   resb OUT_BUF_BYTES
cut_ranges:   resq MAX_RANGES * 2
cut_n_ranges: resq 1
cut_outpos:   resq 1
cut_mode:     resb 1
cut_delim:    resb 1

section .rodata
opt_c:        db "-c", 0
opt_b:        db "-b", 0
opt_f:        db "-f", 0
opt_d:        db "-d", 0
prefix_cut:   db "cut", 0
err_no_list:  db "cut: list (-c or -f) is required", 10
err_no_list_len: equ $ - err_no_list
err_bad_list: db "cut: invalid list", 10
err_bad_list_len: equ $ - err_bad_list
err_bad_delim: db "cut: delimiter must be a single character", 10
err_bad_delim_len: equ $ - err_bad_delim

section .text

; int applet_cut_main(int argc /edi/, char **argv /rsi/)
applet_cut_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d
    mov     byte [rel cut_mode], MODE_NONE
    mov     byte [rel cut_delim], 9
    mov     qword [rel cut_n_ranges], 0
    mov     qword [rel cut_outpos], 0

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    movzx   eax, byte [rdi + 1]
    test    eax, eax
    jz      .flags_done

    ; Single-letter flags. Both separate (-c LIST) and inline (-cLIST) forms.
    cmp     al, 'c'
    je      .opt_list
    cmp     al, 'b'
    je      .opt_list
    cmp     al, 'f'
    je      .opt_fields
    cmp     al, 'd'
    je      .opt_delim
    jmp     .flags_done

.opt_list:
    mov     byte [rel cut_mode], MODE_CHARS
    cmp     byte [rdi + 2], 0
    jne     .list_inline
    inc     r12d
    cmp     r12d, ebx
    jge     .no_list
    mov     rdi, [rbp + r12*8]
    jmp     .list_call
.list_inline:
    add     rdi, 2
.list_call:
    call    parse_list
    test    eax, eax
    jnz     .bad_list
    inc     r12d
    jmp     .flag_loop

.opt_fields:
    mov     byte [rel cut_mode], MODE_FIELDS
    cmp     byte [rdi + 2], 0
    jne     .fields_inline
    inc     r12d
    cmp     r12d, ebx
    jge     .no_list
    mov     rdi, [rbp + r12*8]
    jmp     .fields_call
.fields_inline:
    add     rdi, 2
.fields_call:
    call    parse_list
    test    eax, eax
    jnz     .bad_list
    inc     r12d
    jmp     .flag_loop

.opt_delim:
    cmp     byte [rdi + 2], 0
    jne     .delim_inline
    inc     r12d
    cmp     r12d, ebx
    jge     .bad_delim
    mov     rdi, [rbp + r12*8]
    jmp     .delim_check
.delim_inline:
    add     rdi, 2
.delim_check:
    cmp     byte [rdi], 0
    je      .bad_delim
    cmp     byte [rdi + 1], 0
    jne     .bad_delim
    mov     al, [rdi]
    mov     [rel cut_delim], al
    inc     r12d
    jmp     .flag_loop

.flags_done:
    cmp     byte [rel cut_mode], MODE_NONE
    je      .no_list

    cmp     r12d, ebx
    jl      .files

    mov     edi, STDIN_FILENO
    call    cut_stream
    test    eax, eax
    jz      .out
    mov     r14d, 1
    jmp     .out

.files:
.file_loop:
    cmp     r12d, ebx
    jge     .out
    mov     eax, SYS_open
    mov     rdi, [rbp + r12*8]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_err
    mov     edi, eax
    call    cut_stream
    test    eax, eax
    jz      .next
    mov     r14d, 1
.next:
    inc     r12d
    jmp     .file_loop

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_cut]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    inc     r12d
    jmp     .file_loop

.no_list:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_no_list]
    mov     edx, err_no_list_len
    syscall
    mov     r14d, 1
    jmp     .out

.bad_list:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_list]
    mov     edx, err_bad_list_len
    syscall
    mov     r14d, 1
    jmp     .out

.bad_delim:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_delim]
    mov     edx, err_bad_delim_len
    syscall
    mov     r14d, 1

.out:
    call    flush_out
    mov     eax, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; parse_list(s /rdi/) -> rax = 0 ok, 1 bad
;
;   Populates cut_ranges and cut_n_ranges from a comma-separated list.
;   Each entry is one of: N, N-M, N-, -M.
parse_list:
    push    rbx                     ; cursor
    push    r12                     ; range count
    push    r13                     ; (alignment)

    mov     rbx, rdi
    xor     r12d, r12d

.next_item:
    movzx   ecx, byte [rbx]
    test    ecx, ecx
    jz      .err                    ; empty item
    cmp     ecx, ','
    je      .err

    cmp     ecx, '-'
    je      .open_start

    cmp     ecx, '0'
    jb      .err
    cmp     ecx, '9'
    ja      .err

    xor     r8, r8                  ; start
.parse_start:
    movzx   ecx, byte [rbx]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .have_start
    imul    r8, r8, 10
    add     r8, rcx
    inc     rbx
    jmp     .parse_start

.open_start:
    mov     r8, 1                   ; default start when "-N"

.have_start:
    movzx   ecx, byte [rbx]
    cmp     ecx, '-'
    jne     .single

    inc     rbx
    movzx   ecx, byte [rbx]
    test    ecx, ecx
    jz      .open_end
    cmp     ecx, ','
    je      .open_end
    cmp     ecx, '0'
    jb      .err
    cmp     ecx, '9'
    ja      .err

    xor     r9, r9
.parse_end:
    movzx   ecx, byte [rbx]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .have_end
    imul    r9, r9, 10
    add     r9, rcx
    inc     rbx
    jmp     .parse_end

.open_end:
    xor     r9, r9
    jmp     .have_end

.single:
    mov     r9, r8

.have_end:
    cmp     r12d, MAX_RANGES
    jge     .err

    lea     rdx, [rel cut_ranges]
    mov     rcx, r12
    shl     rcx, 4
    add     rdx, rcx
    mov     [rdx], r8
    mov     [rdx + 8], r9
    inc     r12d

    movzx   ecx, byte [rbx]
    test    ecx, ecx
    jz      .ok
    cmp     ecx, ','
    jne     .err
    inc     rbx
    jmp     .next_item

.ok:
    mov     [rel cut_n_ranges], r12
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

.err:
    mov     eax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; pos_selected(pos /edi/) -> rax (1 if covered by any range, 0 else)
pos_selected:
    mov     rcx, [rel cut_n_ranges]
    test    rcx, rcx
    jz      .no
    lea     r8, [rel cut_ranges]
.loop:
    mov     rax, [r8]
    cmp     rdi, rax
    jl      .next
    mov     rax, [r8 + 8]
    test    rax, rax
    jz      .yes                    ; open-ended: in range
    cmp     rdi, rax
    jle     .yes
.next:
    add     r8, 16
    dec     rcx
    jnz     .loop
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; emit_byte(al) — buffer a byte, flushing when full.
;
; Alignment: function entry rsp = 8 mod 16. `push rax` brings to 0 mod 16,
; so any inner call at that point is ABI-aligned.
emit_byte:
    push    rax
    mov     rcx, [rel cut_outpos]
    cmp     rcx, OUT_BUF_BYTES
    jl      .room
    call    flush_out
    mov     rcx, [rel cut_outpos]
.room:
    pop     rax
    lea     r8, [rel cut_outbuf]
    mov     [r8 + rcx], al
    inc     rcx
    mov     [rel cut_outpos], rcx
    ret

; flush_out — write pending output, reset cut_outpos.
flush_out:
    mov     rcx, [rel cut_outpos]
    test    rcx, rcx
    jz      .done
    sub     rsp, 8                  ; align: entry 8 mod 16 -> 0 mod 16
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel cut_outbuf]
    mov     rdx, rcx
    call    write_all
    add     rsp, 8
    mov     qword [rel cut_outpos], 0
.done:
    ret

; ---------------------------------------------------------------------------
; cut_stream(fd /edi/) -> rax (0 ok, 1 err)
;
; Streams the input through the selection logic; closes fd unless stdin.
;
; Register usage:
;   rbx  fd
;   r12  pos (1-based)
;   r13  in_selected (current field is selected)
;   r14  emitted_any (have we emitted any field this line?)
cut_stream:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

    mov     ebx, edi

.line_reset:
    mov     r12d, 1
    mov     edi, r12d
    call    pos_selected
    mov     r13d, eax
    xor     r14d, r14d

.read:
    mov     edi, ebx
    lea     rsi, [rel cut_iobuf]
    mov     edx, BUF_BYTES
    call    read_buf
    test    rax, rax
    jz      .eof
    js      .eof

    mov     rcx, rax
    lea     r15, [rel cut_iobuf]

.scan:
    test    rcx, rcx
    jz      .read
    mov     al, [r15]
    inc     r15
    dec     rcx

    cmp     al, 10
    je      .nl

    cmp     byte [rel cut_mode], MODE_CHARS
    je      .chars_byte

    ; Fields mode.
    cmp     al, [rel cut_delim]
    je      .field_delim

    ; Content byte of current field.
    test    r13d, r13d
    jz      .scan
    push    rcx
    push    r15
    call    emit_byte
    pop     r15
    pop     rcx
    jmp     .scan

.field_delim:
    ; Closing one field, opening the next. emitted_any flags whether
    ; we've ever finished a selected field this line.
    test    r13d, r13d
    jz      .delim_no_finish
    mov     r14d, 1
.delim_no_finish:
    inc     r12d

    push    rcx
    push    r15
    mov     edi, r12d
    call    pos_selected
    mov     r13d, eax
    pop     r15
    pop     rcx

    test    r13d, r13d
    jz      .scan
    test    r14d, r14d
    jz      .scan
    mov     al, [rel cut_delim]
    push    rcx
    push    r15
    call    emit_byte
    pop     r15
    pop     rcx
    jmp     .scan

.chars_byte:
    test    r13d, r13d
    jz      .chars_advance
    push    rcx
    push    r15
    call    emit_byte
    pop     r15
    pop     rcx
.chars_advance:
    inc     r12d
    push    rcx
    push    r15
    mov     edi, r12d
    call    pos_selected
    mov     r13d, eax
    pop     r15
    pop     rcx
    jmp     .scan

.nl:
    mov     al, 10
    push    rcx
    push    r15
    call    emit_byte
    pop     r15
    pop     rcx
    jmp     .line_reset_in_chunk

.line_reset_in_chunk:
    mov     r12d, 1
    push    rcx
    push    r15
    mov     edi, r12d
    call    pos_selected
    mov     r13d, eax
    pop     r15
    pop     rcx
    xor     r14d, r14d
    jmp     .scan

.eof:
    cmp     ebx, STDIN_FILENO
    je      .ret
    mov     eax, SYS_close
    mov     edi, ebx
    syscall

.ret:
    xor     eax, eax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
