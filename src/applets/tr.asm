; tr.asm — translate or delete characters.
;
;   tr SET1 SET2          translate SET1 chars to SET2 chars
;   tr -d SET1            delete SET1 chars
;   tr -s SET1            squeeze runs of SET1 chars to one
;   tr -d -s SET1 SET2    delete SET1 then squeeze SET2 in remainder
;   tr SET1 SET2 -s SET2  translate then squeeze SET2
;
; SET syntax in v1:
;   literal char        a, X, $
;   range               a-z, 0-9, A-Z
;   octal escape        \NNN  (1-3 digits)
;   named escape        \\, \n, \t, \r, \f, \v, \a, \b, \0
;
; Not yet supported: character classes ([:upper:], [:digit:], ...),
; equivalence classes ([=c=]), repeats ([x*N]), and the -c (complement)
; flag. Multi-byte input is treated as bytes.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern read_buf
extern write_all
extern perror_path

global applet_tr_main

%define BUF_BYTES 65536
%define OUT_BUF_BYTES 4096

section .bss
align 16
tr_iobuf:    resb BUF_BYTES
tr_outbuf:   resb OUT_BUF_BYTES
tr_set1_exp: resb 1024              ; expanded SET1 (each byte its own slot)
tr_set2_exp: resb 1024
tr_table:    resb 256               ; translation map (default: identity)
tr_delete:   resb 256               ; delete[c] = 1 if c should be dropped
tr_squeeze:  resb 256               ; squeeze[c] = 1 if c should be squeezed
tr_outpos:   resq 1
tr_set1_len: resq 1
tr_set2_len: resq 1
tr_flag_d:   resb 1
tr_flag_s:   resb 1
tr_prev:     resw 1                 ; previous output byte for -s, or 0xFFFF

section .rodata
opt_d:        db "-d", 0
opt_s:        db "-s", 0
opt_ds:       db "-ds", 0
opt_sd:       db "-sd", 0
prefix_tr:    db "tr", 0
err_usage:    db "tr: usage: tr [-d] [-s] SET1 [SET2]", 10
err_usage_len: equ $ - err_usage

section .text

; int applet_tr_main(int argc /edi/, char **argv /rsi/)
applet_tr_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    mov     byte [rel tr_flag_d], 0
    mov     byte [rel tr_flag_s], 0
    mov     qword [rel tr_outpos], 0
    mov     word [rel tr_prev], 0xFFFF
    xor     r14d, r14d

    ; Identity map.
    lea     rdi, [rel tr_table]
    xor     ecx, ecx
.init_table:
    mov     [rdi + rcx], cl
    inc     ecx
    cmp     ecx, 256
    jl      .init_table

    ; Zero delete and squeeze maps.
    lea     rdi, [rel tr_delete]
    xor     eax, eax
    mov     ecx, 256
    rep     stosb
    lea     rdi, [rel tr_squeeze]
    xor     eax, eax
    mov     ecx, 256
    rep     stosb

    ; Parse flags.
    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    lea     rsi, [rel opt_d]
    call    streq
    test    eax, eax
    jnz     .set_d
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_s]
    call    streq
    test    eax, eax
    jnz     .set_s
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_ds]
    call    streq
    test    eax, eax
    jnz     .set_ds
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_sd]
    call    streq
    test    eax, eax
    jnz     .set_ds
    jmp     .flags_done
.set_d: mov byte [rel tr_flag_d], 1
        inc r12d
        jmp .flag_loop
.set_s: mov byte [rel tr_flag_s], 1
        inc r12d
        jmp .flag_loop
.set_ds: mov byte [rel tr_flag_d], 1
         mov byte [rel tr_flag_s], 1
         inc r12d
         jmp .flag_loop

.flags_done:
    ; Need at least SET1.
    cmp     r12d, ebx
    jge     .usage

    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel tr_set1_exp]
    mov     rdx, 1024
    call    expand_set
    test    rax, rax
    js      .usage
    mov     [rel tr_set1_len], rax
    inc     r12d

    cmp     r12d, ebx
    jge     .have_set1

    ; SET2 present — if -d, that's actually only allowed with -s.
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel tr_set2_exp]
    mov     rdx, 1024
    call    expand_set
    test    rax, rax
    js      .usage
    mov     [rel tr_set2_len], rax
    inc     r12d

.have_set1:
    ; Build maps based on flags.
    cmp     byte [rel tr_flag_d], 0
    jne     .build_delete

    ; Translate mode (SET1 -> SET2). SET2 must be present.
    cmp     qword [rel tr_set2_len], 0
    je      .usage_or_delete_only

    mov     rcx, [rel tr_set1_len]
    mov     rdx, [rel tr_set2_len]
    lea     r8, [rel tr_set1_exp]
    lea     r9, [rel tr_set2_exp]
    xor     r10, r10
.fill_table:
    cmp     r10, rcx
    jge     .fill_done
    movzx   eax, byte [r8 + r10]    ; SET1[i]
    mov     r11, r10
    cmp     r11, rdx
    jl      .pick
    lea     r11, [rdx - 1]          ; pad with last SET2 char
.pick:
    movzx   r11d, byte [r9 + r11]
    mov     [rel tr_table + rax], r11b
    inc     r10
    jmp     .fill_table
.fill_done:

    ; If -s, squeeze SET2 (after translation).
    cmp     byte [rel tr_flag_s], 0
    je      .ready
    mov     rcx, [rel tr_set2_len]
    lea     r8, [rel tr_set2_exp]
    xor     r10, r10
.fill_sq:
    cmp     r10, rcx
    jge     .ready
    movzx   eax, byte [r8 + r10]
    mov     byte [rel tr_squeeze + rax], 1
    inc     r10
    jmp     .fill_sq

.usage_or_delete_only:
    cmp     byte [rel tr_flag_s], 0
    je      .usage
    ; -s alone with one set: squeeze SET1 in identity-translated stream.
    mov     rcx, [rel tr_set1_len]
    lea     r8, [rel tr_set1_exp]
    xor     r10, r10
.fill_sq2:
    cmp     r10, rcx
    jge     .ready
    movzx   eax, byte [r8 + r10]
    mov     byte [rel tr_squeeze + rax], 1
    inc     r10
    jmp     .fill_sq2

.build_delete:
    mov     rcx, [rel tr_set1_len]
    lea     r8, [rel tr_set1_exp]
    xor     r10, r10
.fill_del:
    cmp     r10, rcx
    jge     .del_done
    movzx   eax, byte [r8 + r10]
    mov     byte [rel tr_delete + rax], 1
    inc     r10
    jmp     .fill_del
.del_done:
    cmp     byte [rel tr_flag_s], 0
    je      .ready
    cmp     qword [rel tr_set2_len], 0
    je      .ready
    ; -d -s: SET2 chars in remainder get squeezed.
    mov     rcx, [rel tr_set2_len]
    lea     r8, [rel tr_set2_exp]
    xor     r10, r10
.fill_ds_sq:
    cmp     r10, rcx
    jge     .ready
    movzx   eax, byte [r8 + r10]
    mov     byte [rel tr_squeeze + rax], 1
    inc     r10
    jmp     .fill_ds_sq

.ready:
    call    tr_stream

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

.usage:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_usage]
    mov     edx, err_usage_len
    syscall
    mov     r14d, 1
    jmp     .out

; ---------------------------------------------------------------------------
; expand_set(set /rdi/, out /rsi/, max /rdx/) -> rax (count, or -1 on overflow)
expand_set:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     rbp, rsi
    mov     r12, rdx                ; cap
    xor     r13, r13                ; count
    xor     r14, r14                ; (unused)

.next:
    movzx   ecx, byte [rbx]
    test    ecx, ecx
    jz      .done

    ; Fetch one logical char (handle escape).
    mov     rdi, rbx
    call    parse_one_char
    mov     rdx, rax                ; rdx = char
    mov     rbx, rcx                ; rcx = new cursor

    ; Range: next char is '-' followed by a non-NUL.
    cmp     byte [rbx], '-'
    jne     .one
    cmp     byte [rbx + 1], 0
    je      .one
    inc     rbx                     ; consume '-'

    mov     rdi, rbx
    call    parse_one_char
    mov     r8, rax                 ; end char
    mov     rbx, rcx                ; advance cursor

    ; Emit [rdx .. r8] inclusive.
    mov     rcx, rdx
    cmp     rcx, r8
    jg      .next                   ; ill-formed range collapses
.range_loop:
    cmp     r13, r12
    jge     .overflow
    mov     [rbp + r13], cl
    inc     r13
    cmp     rcx, r8
    je      .next
    inc     rcx
    jmp     .range_loop

.one:
    cmp     r13, r12
    jge     .overflow
    mov     [rbp + r13], dl
    inc     r13
    jmp     .next

.done:
    mov     rax, r13
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

.overflow:
    mov     rax, -1
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; parse_one_char(s /rdi/) -> rax (char), rcx (advanced cursor)
parse_one_char:
    movzx   eax, byte [rdi]
    cmp     al, '\'
    jne     .literal
    movzx   eax, byte [rdi + 1]
    test    al, al
    jz      .lone_backslash
    cmp     al, 'n'
    je      .nl
    cmp     al, 't'
    je      .tab
    cmp     al, 'r'
    je      .cr
    cmp     al, 'f'
    je      .ff
    cmp     al, 'v'
    je      .vt
    cmp     al, 'a'
    je      .bel
    cmp     al, 'b'
    je      .bs
    cmp     al, '\'
    je      .bsbs
    cmp     al, '0'
    jl      .literal_pair
    cmp     al, '9'
    jg      .literal_pair
    ; Octal escape: \NNN (1-3 digits)
    xor     eax, eax
    mov     rcx, rdi
    inc     rcx                     ; past '\'
    mov     edx, 3
.octal:
    movzx   r8d, byte [rcx]
    sub     r8d, '0'
    cmp     r8d, 7
    ja      .octal_done
    shl     eax, 3
    or      eax, r8d
    inc     rcx
    dec     edx
    jnz     .octal
.octal_done:
    ret

.literal:
    lea     rcx, [rdi + 1]
    ret
.literal_pair:
    movzx   eax, byte [rdi + 1]
    lea     rcx, [rdi + 2]
    ret
.lone_backslash:
    movzx   eax, byte [rdi]
    lea     rcx, [rdi + 1]
    ret
.nl:    mov eax, 10
        lea rcx, [rdi + 2]
        ret
.tab:   mov eax, 9
        lea rcx, [rdi + 2]
        ret
.cr:    mov eax, 13
        lea rcx, [rdi + 2]
        ret
.ff:    mov eax, 12
        lea rcx, [rdi + 2]
        ret
.vt:    mov eax, 11
        lea rcx, [rdi + 2]
        ret
.bel:   mov eax, 7
        lea rcx, [rdi + 2]
        ret
.bs:    mov eax, 8
        lea rcx, [rdi + 2]
        ret
.bsbs:  mov eax, '\'
        lea rcx, [rdi + 2]
        ret

; ---------------------------------------------------------------------------
; tr_stream — read stdin, apply maps, write to stdout.
tr_stream:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

.read:
    mov     edi, STDIN_FILENO
    lea     rsi, [rel tr_iobuf]
    mov     edx, BUF_BYTES
    call    read_buf
    test    rax, rax
    jz      .done
    js      .done

    mov     r12, rax
    lea     r13, [rel tr_iobuf]
    xor     r14, r14
.scan:
    cmp     r14, r12
    jge     .read
    movzx   eax, byte [r13 + r14]
    inc     r14

    ; Delete?
    cmp     byte [rel tr_delete + rax], 0
    jne     .scan

    ; Translate.
    movzx   eax, byte [rel tr_table + rax]

    ; Squeeze?
    cmp     byte [rel tr_squeeze + rax], 0
    je      .emit
    movzx   ecx, word [rel tr_prev]
    cmp     cx, ax
    je      .scan                   ; same as previous → squeeze
.emit:
    mov     [rel tr_prev], ax
    push    rax
    call    emit_byte
    pop     rax
    jmp     .scan

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; emit_byte / flush_out — same buffered-write pattern as cut.asm but
; against tr_outbuf / tr_outpos.
emit_byte:
    push    rax
    mov     rcx, [rel tr_outpos]
    cmp     rcx, OUT_BUF_BYTES
    jl      .room
    call    flush_out
    mov     rcx, [rel tr_outpos]
.room:
    pop     rax
    lea     r8, [rel tr_outbuf]
    mov     [r8 + rcx], al
    inc     rcx
    mov     [rel tr_outpos], rcx
    ret

flush_out:
    mov     rcx, [rel tr_outpos]
    test    rcx, rcx
    jz      .done
    sub     rsp, 8
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel tr_outbuf]
    mov     rdx, rcx
    call    write_all
    add     rsp, 8
    mov     qword [rel tr_outpos], 0
.done:
    ret
