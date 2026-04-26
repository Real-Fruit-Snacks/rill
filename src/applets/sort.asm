; sort.asm — sort the lines of input.
;
;   sort [-r] [-n] [-u] [FILE...]
;
; -r   reverse sort
; -n   numeric (compare leading integer; non-numeric prefix counts as 0)
; -u   unique (collapse consecutive equals after sort)
;
; Implementation: read everything into a 16 MB .bss buffer, NUL-terminate
; each line in place, build a pointer array (up to 256 K lines), quicksort
; the pointers, then walk and emit. Inputs larger than the buffer error
; out — coreutils' external-merge fallback isn't here yet.
;
; Deferred: -k FIELD, -t SEP, -f case-fold, -b skip-leading-blanks, stable
; sort, locale collation. Multibyte input is treated as bytes.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern read_buf
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_sort_main

%define BUF_BYTES   16777216        ; 16 MB
%define MAX_LINES   262144          ; 256 K
%define OUT_BYTES   65536

section .bss
align 16
sort_buf:        resb BUF_BYTES
sort_lines:      resq MAX_LINES
sort_outbuf:     resb OUT_BYTES
sort_buf_used:   resq 1
sort_n_lines:    resq 1
sort_outpos:     resq 1
sort_flag_r:     resb 1
sort_flag_n:     resb 1
sort_flag_u:     resb 1

section .rodata
opt_r:        db "-r", 0
opt_n:        db "-n", 0
opt_u:        db "-u", 0
prefix_sort:  db "sort", 0
err_too_big:  db "sort: input exceeds 16 MB buffer", 10
err_too_big_len: equ $ - err_too_big
err_too_many: db "sort: too many lines (limit 262144)", 10
err_too_many_len: equ $ - err_too_many

section .text

; int applet_sort_main(int argc /edi/, char **argv /rsi/)
applet_sort_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; arg cursor
    push    r13                     ; rc
    push    r14                     ; (alignment)

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d
    mov     byte [rel sort_flag_r], 0
    mov     byte [rel sort_flag_n], 0
    mov     byte [rel sort_flag_u], 0
    mov     qword [rel sort_buf_used], 0
    mov     qword [rel sort_n_lines], 0
    mov     qword [rel sort_outpos], 0

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    inc     rdi                     ; consume '-'
.flag_char:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .next_arg
    cmp     al, 'r'
    je      .set_r
    cmp     al, 'n'
    je      .set_n
    cmp     al, 'u'
    je      .set_u
    jmp     .flags_done             ; unknown short flag stops parsing
.set_r: mov byte [rel sort_flag_r], 1
        inc rdi
        jmp .flag_char
.set_n: mov byte [rel sort_flag_n], 1
        inc rdi
        jmp .flag_char
.set_u: mov byte [rel sort_flag_u], 1
        inc rdi
        jmp .flag_char

.next_arg:
    inc     r12d
    jmp     .flag_loop

.flags_done:
    cmp     r12d, ebx
    jl      .files

    mov     edi, STDIN_FILENO
    call    slurp_fd
    test    eax, eax
    jnz     .input_err
    jmp     .process

.files:
.file_loop:
    cmp     r12d, ebx
    jge     .process
    mov     eax, SYS_open
    mov     rdi, [rbp + r12*8]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_err
    mov     edi, eax
    call    slurp_fd
    test    eax, eax
    jnz     .input_err
    inc     r12d
    jmp     .file_loop

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_sort]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r13d, 1
    inc     r12d
    jmp     .file_loop

.input_err:
    mov     r13d, 1
    jmp     .out

.process:
    call    build_line_index
    test    eax, eax
    jnz     .input_err

    mov     rax, [rel sort_n_lines]
    test    rax, rax
    jz      .out

    xor     rdi, rdi
    mov     rsi, rax
    call    qsort_lines

    call    emit_lines

.out:
    call    flush_out
    mov     eax, r13d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; slurp_fd(fd /edi/) -> rax (0 ok, 1 buffer-full / read error)
;
; Appends the content of fd to sort_buf. Closes fd unless stdin.
slurp_fd:
    push    rbx
    push    r12

    mov     ebx, edi
    mov     r12, [rel sort_buf_used]

.read:
    mov     rdx, BUF_BYTES
    sub     rdx, r12
    test    rdx, rdx
    jz      .full

    mov     edi, ebx
    lea     rsi, [rel sort_buf]
    add     rsi, r12
    call    read_buf
    test    rax, rax
    jz      .eof
    js      .eof
    add     r12, rax
    jmp     .read

.full:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_too_big]
    mov     edx, err_too_big_len
    syscall
    mov     eax, 1
    jmp     .ret

.eof:
    mov     [rel sort_buf_used], r12
    cmp     ebx, STDIN_FILENO
    je      .ok
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
.ok:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; build_line_index() -> rax (0 ok, 1 too many)
;
; Walks sort_buf, NUL-terminating each '\n' in place, recording each line
; start in sort_lines.
build_line_index:
    mov     rcx, [rel sort_buf_used]
    test    rcx, rcx
    jz      .ok

    lea     r8, [rel sort_buf]      ; cursor
    lea     r9, [rel sort_buf]      ; line start
    add     rcx, r8                 ; end pointer
    xor     r10, r10                ; line count

.loop:
    cmp     r8, rcx
    jge     .tail
    cmp     byte [r8], 10
    jne     .next
    mov     byte [r8], 0
    cmp     r10, MAX_LINES
    jge     .full
    mov     [rel sort_lines + r10*8], r9
    inc     r10
    lea     r9, [r8 + 1]
.next:
    inc     r8
    jmp     .loop

.tail:
    cmp     r9, r8
    jge     .done
    cmp     r10, MAX_LINES
    jge     .full
    mov     [rel sort_lines + r10*8], r9
    inc     r10
    ; The trailing partial line has no '\n' to NUL out; the buffer's
    ; first byte past sort_buf_used must already be 0 — .bss is zero
    ; initialized, so as long as sort_buf_used < BUF_BYTES the
    ; sentinel exists. Guarantee that here:
    cmp     r8, rcx
    jge     .stamp_zero
.stamp_zero:
    mov     byte [r8], 0

.done:
    mov     [rel sort_n_lines], r10
.ok:
    xor     eax, eax
    ret
.full:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_too_many]
    mov     edx, err_too_many_len
    syscall
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; compare_strs(a /rdi/, b /rsi/) -> rax  (-1, 0, +1)
;
; Branches on the active flags. Always returns -1 / 0 / +1 (not raw
; subtraction) so the negation for -r is well-defined on signed reg.
compare_strs:
    cmp     byte [rel sort_flag_n], 0
    jne     .numeric

.alpha:
    ; Byte-wise compare until both NUL.
.alpha_loop:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     eax, ecx
    jne     .alpha_diff
    test    eax, eax
    jz      .equal
    inc     rdi
    inc     rsi
    jmp     .alpha_loop
.alpha_diff:
    jb      .less
    jmp     .greater

.numeric:
    push    rdi                     ; save A (=a)
    push    rsi                     ; save B (=b)
    sub     rsp, 8                  ; align (2 pushes + sub 8 = 24 bytes;
                                    ; from entry's 8 mod 16 -> 0 mod 16)

    ; rdi still = A; parse it.
    call    parse_leading_int
    mov     r8, rax                 ; va

    mov     rdi, [rsp + 8]          ; B (rsi value; second push)
    call    parse_leading_int
    mov     r9, rax                 ; vb

    add     rsp, 8
    pop     rsi
    pop     rdi

    cmp     r8, r9
    jl      .less_signed
    jg      .greater_signed
    jmp     .alpha                  ; tie → fall back to byte compare

.less_signed:
    mov     rax, -1
    jmp     .reverse
.greater_signed:
    mov     rax, 1
    jmp     .reverse
.less:
    mov     rax, -1
    jmp     .reverse
.greater:
    mov     rax, 1
    jmp     .reverse
.equal:
    xor     eax, eax
.reverse:
    cmp     byte [rel sort_flag_r], 0
    je      .done
    neg     rax
.done:
    ret

; parse_leading_int(s /rdi/) -> rax (signed int64; 0 if no digits)
parse_leading_int:
    xor     eax, eax
    xor     ecx, ecx                ; sign
.skip_ws:
    movzx   edx, byte [rdi]
    cmp     edx, ' '
    je      .ws_inc
    cmp     edx, 9
    je      .ws_inc
    jmp     .check_sign
.ws_inc:
    inc     rdi
    jmp     .skip_ws

.check_sign:
    cmp     edx, '-'
    jne     .check_pos
    mov     ecx, 1
    inc     rdi
    jmp     .digits
.check_pos:
    cmp     edx, '+'
    jne     .digits
    inc     rdi

.digits:
    movzx   edx, byte [rdi]
    sub     edx, '0'
    cmp     edx, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rdi
    jmp     .digits

.done:
    test    ecx, ecx
    jz      .ret
    neg     rax
.ret:
    ret

; ---------------------------------------------------------------------------
; qsort_lines(lo /rdi/, hi /rsi/) — sorts sort_lines[lo..hi).
;
; Lomuto partitioning with a middle-element pivot. Recursive (depth
; bounded by ~log2(N) for the typical case; default Linux 8 MB stack
; supports millions of levels of asm recursion).
qsort_lines:
    push    rbx                     ; lo
    push    rbp                     ; hi
    push    r12                     ; pivot pointer
    push    r13                     ; i
    push    r14                     ; j
    push    r15                     ; (alignment via 6 pushes + sub 8)
    sub     rsp, 8

    mov     rbx, rdi
    mov     rbp, rsi

    mov     rax, rbp
    sub     rax, rbx
    cmp     rax, 1
    jle     .done

    ; pivot = lines[(lo+hi)/2]
    lea     rax, [rbx + rbp]
    shr     rax, 1
    mov     r12, [rel sort_lines + rax*8]

    mov     r13, rbx                ; i = lo
    lea     r14, [rbp - 1]          ; j = hi - 1

.partition:
    cmp     r13, r14
    jg      .partitioned

.find_left:
    mov     rdi, [rel sort_lines + r13*8]
    mov     rsi, r12
    call    compare_strs
    test    rax, rax
    jns     .have_left
    inc     r13
    jmp     .find_left
.have_left:

.find_right:
    mov     rdi, [rel sort_lines + r14*8]
    mov     rsi, r12
    call    compare_strs
    test    rax, rax
    jle     .have_right
    dec     r14
    jmp     .find_right
.have_right:

    cmp     r13, r14
    jg      .partitioned
    mov     rdi, [rel sort_lines + r13*8]
    mov     rsi, [rel sort_lines + r14*8]
    mov     [rel sort_lines + r13*8], rsi
    mov     [rel sort_lines + r14*8], rdi
    inc     r13
    dec     r14
    jmp     .partition

.partitioned:
    mov     rdi, rbx
    lea     rsi, [r14 + 1]
    call    qsort_lines

    mov     rdi, r13
    mov     rsi, rbp
    call    qsort_lines

.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; emit_lines — walks sort_lines, writing each line followed by '\n'.
; Honors -u by skipping any line equal to its predecessor.
emit_lines:
    push    rbx
    push    rbp
    push    r12

    xor     rbx, rbx                ; i
    xor     rbp, rbp                ; prev pointer (NULL initially)

.loop:
    cmp     rbx, [rel sort_n_lines]
    jge     .done
    mov     r12, [rel sort_lines + rbx*8]

    ; -u: skip if equal to prev.
    cmp     byte [rel sort_flag_u], 0
    je      .emit
    test    rbp, rbp
    jz      .emit
    mov     rdi, r12
    mov     rsi, rbp
    call    streq
    test    eax, eax
    jnz     .skip

.emit:
    mov     rdi, r12
    call    emit_cstr
    mov     al, 10
    call    emit_byte
    mov     rbp, r12

.skip:
    inc     rbx
    jmp     .loop

.done:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; emit_cstr(s /rdi/) — copies string content into sort_outbuf.
emit_cstr:
    push    rbx
    mov     rbx, rdi
.loop:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .done
    push    rbx
    sub     rsp, 8
    call    emit_byte
    add     rsp, 8
    pop     rbx
    inc     rbx
    jmp     .loop
.done:
    pop     rbx
    ret

emit_byte:
    push    rax
    mov     rcx, [rel sort_outpos]
    cmp     rcx, OUT_BYTES
    jl      .room
    call    flush_out
    mov     rcx, [rel sort_outpos]
.room:
    pop     rax
    lea     r8, [rel sort_outbuf]
    mov     [r8 + rcx], al
    inc     rcx
    mov     [rel sort_outpos], rcx
    ret

flush_out:
    mov     rcx, [rel sort_outpos]
    test    rcx, rcx
    jz      .done
    sub     rsp, 8
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel sort_outbuf]
    mov     rdx, rcx
    call    write_all
    add     rsp, 8
    mov     qword [rel sort_outpos], 0
.done:
    ret
