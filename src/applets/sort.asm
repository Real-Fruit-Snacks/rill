; sort.asm — sort the lines of input.
;
;   sort [-r] [-n] [-u] [-f] [-k FIELD] [-t SEP] [FILE...]
;
; -r          reverse sort
; -n          numeric (compare leading integer; non-numeric prefix = 0)
; -u          unique (collapse consecutive equals after sort)
; -f          fold lower-case to upper-case for the comparison (ASCII)
; -k F[,G]    sort using field F (1-based), optionally through field G;
;             without the comma the key extends to end-of-line
; -t SEP      use SEP (single byte) as the field separator. Without -t,
;             fields are runs of non-blank characters separated by blank
;             runs (POSIX whitespace mode); leading blanks before field 1
;             are skipped.
;
; Implementation: read everything into a 16 MB .bss buffer, NUL-terminate
; each line in place, build a pointer array (up to 256 K lines), quicksort
; the pointers, then walk and emit. Inputs larger than the buffer error
; out — coreutils' external-merge fallback isn't here yet.
;
; Deferred: -b skip-leading-blanks per-key, key-modifier suffixes
; (e.g. `-k 2n`), stable sort, locale collation, multi-key. Multibyte
; input is treated as bytes.

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
sort_buf:           resb BUF_BYTES
sort_lines:         resq MAX_LINES
sort_outbuf:        resb OUT_BYTES
sort_buf_used:      resq 1
sort_n_lines:       resq 1
sort_outpos:        resq 1
sort_field_start:   resq 1              ; 0 = no -k (whole line)
sort_field_end:     resq 1              ; 0 = "to end of line"
sort_flag_r:        resb 1
sort_flag_n:        resb 1
sort_flag_u:        resb 1
sort_flag_f:        resb 1
sort_delim_char:    resb 1              ; 0 = whitespace mode

section .rodata
prefix_sort:  db "sort", 0
err_too_big:  db "sort: input exceeds 16 MB buffer", 10
err_too_big_len: equ $ - err_too_big
err_too_many: db "sort: too many lines (limit 262144)", 10
err_too_many_len: equ $ - err_too_many
err_bad_opt:  db "sort: missing argument for -k or -t", 10
err_bad_opt_len: equ $ - err_bad_opt

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
    mov     byte [rel sort_flag_f], 0
    mov     byte [rel sort_delim_char], 0
    mov     qword [rel sort_field_start], 0
    mov     qword [rel sort_field_end], 0
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
    cmp     al, 'f'
    je      .set_f
    cmp     al, 'k'
    je      .set_k
    cmp     al, 't'
    je      .set_t
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
.set_f: mov byte [rel sort_flag_f], 1
        inc rdi
        jmp .flag_char

    ; -k FIELD or -kFIELD. The value, when in the same arg, is the rest
    ; of the arg after 'k'. When in the next arg, we advance r12d once
    ; here and the .next_arg trailer increments it again.
.set_k:
    inc     rdi
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .k_take_next
    call    parse_field_spec
    jmp     .next_arg
.k_take_next:
    inc     r12d
    cmp     r12d, ebx
    jge     .bad_opt
    mov     rdi, [rbp + r12*8]
    call    parse_field_spec
    jmp     .next_arg

.set_t:
    inc     rdi
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .t_take_next
    mov     [rel sort_delim_char], al
    jmp     .next_arg
.t_take_next:
    inc     r12d
    cmp     r12d, ebx
    jge     .bad_opt
    mov     rdi, [rbp + r12*8]
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .bad_opt
    mov     [rel sort_delim_char], al
    jmp     .next_arg

.bad_opt:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_opt]
    mov     edx, err_bad_opt_len
    syscall
    mov     r13d, 1
    jmp     .out

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
; Extracts the comparison key from each line per the active -k/-t/-f
; settings, then compares byte-wise (or numerically with -n, falling back
; to byte-wise on tie). Always returns a normalized -1 / 0 / +1 so the
; -r negation is well-defined.
;
; Stack: 1 push + sub 48 = 56 bytes; from 8 mod 16 entry -> 0 mod 16 at
; inner call sites. Locals (relative to rsp):
;   [ 0]  sa  start of A's key
;   [ 8]  ea  end of A's key
;   [16]  sb  start of B's key
;   [24]  eb  end of B's key
;   [32]  va  parsed numeric value of A (for -n)
;   [40]  saved B pointer (only across extract_key)
compare_strs:
    push    rbp
    sub     rsp, 48

    mov     [rsp + 40], rsi         ; saved B (rdi will be clobbered)
    lea     rsi, [rsp + 0]
    lea     rdx, [rsp + 8]
    call    extract_key

    mov     rdi, [rsp + 40]
    lea     rsi, [rsp + 16]
    lea     rdx, [rsp + 24]
    call    extract_key

    cmp     byte [rel sort_flag_n], 0
    jne     .numeric

    mov     rdi, [rsp + 0]
    mov     rsi, [rsp + 8]
    mov     rdx, [rsp + 16]
    mov     rcx, [rsp + 24]
    call    compare_bytes_keys
    jmp     .reverse

.numeric:
    mov     rdi, [rsp + 0]
    mov     rsi, [rsp + 8]
    call    parse_int_bounded
    mov     [rsp + 32], rax

    mov     rdi, [rsp + 16]
    mov     rsi, [rsp + 24]
    call    parse_int_bounded
    mov     rcx, rax                ; vb
    mov     rax, [rsp + 32]         ; va

    cmp     rax, rcx
    jl      .num_less
    jg      .num_greater
    ; Tie on numeric → fall back to bytewise (matches coreutils stable-ish
    ; behavior on equal numeric keys).
    mov     rdi, [rsp + 0]
    mov     rsi, [rsp + 8]
    mov     rdx, [rsp + 16]
    mov     rcx, [rsp + 24]
    call    compare_bytes_keys
    jmp     .reverse
.num_less:
    mov     rax, -1
    jmp     .reverse
.num_greater:
    mov     rax, 1

.reverse:
    cmp     byte [rel sort_flag_r], 0
    je      .out
    neg     rax

.out:
    add     rsp, 48
    pop     rbp
    ret

; ---------------------------------------------------------------------------
; extract_key(line /rdi/, *out_start /rsi/, *out_end /rdx/)
;
; Identifies the byte range within `line` that compose the comparison key.
; If sort_field_start is 0 (no -k), the key is the whole line.
;
; In whitespace mode (no -t), the line is split on runs of ' ' or '\t';
; the first field's leading blanks are skipped. With -t, fields are split
; on the chosen delimiter byte exactly (consecutive delims yield empty
; fields).
;
;   Stack: 5 callee-saved pushes -> 0 mod 16 at inner... but extract_key
;   makes no inner calls, so alignment doesn't matter further. Just
;   restoring caller-saved state is the priority.
extract_key:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi                ; cursor through line
    mov     rbp, rsi                ; out_start ptr
    mov     r12, rdx                ; out_end ptr
    movzx   r14d, byte [rel sort_delim_char]

    mov     rax, [rel sort_field_start]
    test    rax, rax
    jnz     .have_field

    ; No -k: key is the whole line. Find NUL.
    mov     [rbp], rbx
    mov     rdi, rbx
.full_line_scan:
    cmp     byte [rdi], 0
    je      .full_line_done
    inc     rdi
    jmp     .full_line_scan
.full_line_done:
    mov     [r12], rdi
    jmp     .out

.have_field:
    mov     r13, 1                  ; current field index

    ; In whitespace mode, leading blanks are part of "before field 1" and
    ; are skipped. With -t, no skipping (consecutive delims at start
    ; produce empty fields).
    test    r14d, r14d
    jnz     .walk_to_start

.skip_lead_ws:
    movzx   eax, byte [rbx]
    cmp     eax, ' '
    je      .skip_lead_inc
    cmp     eax, 9
    je      .skip_lead_inc
    jmp     .walk_to_start
.skip_lead_inc:
    inc     rbx
    jmp     .skip_lead_ws

.walk_to_start:
    cmp     r13, [rel sort_field_start]
    jge     .at_start

    test    r14d, r14d
    jnz     .delim_advance

    ; Whitespace: consume the current field (non-blanks), then a blank run.
.ws_field_consume:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .at_start               ; ran past EOL: empty key
    cmp     eax, ' '
    je      .ws_blank_run
    cmp     eax, 9
    je      .ws_blank_run
    inc     rbx
    jmp     .ws_field_consume
.ws_blank_run:
    movzx   eax, byte [rbx]
    cmp     eax, ' '
    je      .ws_blank_run_inc
    cmp     eax, 9
    je      .ws_blank_run_inc
    jmp     .field_advanced
.ws_blank_run_inc:
    inc     rbx
    jmp     .ws_blank_run

.delim_advance:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .at_start
    cmp     al, r14b
    je      .delim_skip_one
    inc     rbx
    jmp     .delim_advance
.delim_skip_one:
    inc     rbx                     ; consume the delim itself

.field_advanced:
    inc     r13
    jmp     .walk_to_start

.at_start:
    mov     [rbp], rbx

    mov     rax, [rel sort_field_end]
    test    rax, rax
    jnz     .walk_to_end

    ; No end_field: extend key to NUL.
.eol_scan:
    cmp     byte [rbx], 0
    je      .eol_done
    inc     rbx
    jmp     .eol_scan
.eol_done:
    mov     [r12], rbx
    jmp     .out

.walk_to_end:
    cmp     r13, [rel sort_field_end]
    jg      .at_end

    test    r14d, r14d
    jnz     .delim_to_end

    ; Whitespace: consume the current field (non-blanks).
.ws_to_end:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .at_end
    cmp     eax, ' '
    je      .ws_to_end_field_done
    cmp     eax, 9
    je      .ws_to_end_field_done
    inc     rbx
    jmp     .ws_to_end
.ws_to_end_field_done:
    cmp     r13, [rel sort_field_end]
    jge     .at_end
    ; Eat the blank-run separator and continue with the next field.
.ws_to_end_blanks:
    movzx   eax, byte [rbx]
    cmp     eax, ' '
    je      .ws_to_end_blanks_inc
    cmp     eax, 9
    je      .ws_to_end_blanks_inc
    jmp     .field_walk_advanced
.ws_to_end_blanks_inc:
    inc     rbx
    jmp     .ws_to_end_blanks

.delim_to_end:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .at_end
    cmp     al, r14b
    je      .dte_at_delim
    inc     rbx
    jmp     .delim_to_end
.dte_at_delim:
    cmp     r13, [rel sort_field_end]
    jge     .at_end
    inc     rbx                     ; consume delim
.field_walk_advanced:
    inc     r13
    jmp     .walk_to_end

.at_end:
    mov     [r12], rbx

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; compare_bytes_keys(sa /rdi/, ea /rsi/, sb /rdx/, eb /rcx/) -> rax (-1/0/1)
;
; Bytewise compare of [sa, ea) vs [sb, eb), with -f case-fold (ASCII).
compare_bytes_keys:
.loop:
    cmp     rdi, rsi
    jae     .a_done
    cmp     rdx, rcx
    jae     .b_done

    movzx   eax, byte [rdi]
    movzx   r8d, byte [rdx]

    cmp     byte [rel sort_flag_f], 0
    je      .compare_now

    cmp     eax, 'A'
    jb      .a_no_fold
    cmp     eax, 'Z'
    ja      .a_no_fold
    add     eax, 'a' - 'A'
.a_no_fold:
    cmp     r8d, 'A'
    jb      .b_no_fold
    cmp     r8d, 'Z'
    ja      .b_no_fold
    add     r8d, 'a' - 'A'
.b_no_fold:

.compare_now:
    cmp     eax, r8d
    jb      .less
    ja      .greater
    inc     rdi
    inc     rdx
    jmp     .loop

.a_done:
    cmp     rdx, rcx
    jae     .equal
    jmp     .less                   ; A exhausted, B has more → A < B
.b_done:
    jmp     .greater                ; B exhausted, A has more → A > B

.less:
    mov     rax, -1
    ret
.greater:
    mov     rax, 1
    ret
.equal:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; parse_int_bounded(s /rdi/, end /rsi/) -> rax (signed int64; 0 on no digits)
;
; Like the original parse_leading_int, but stops at `end` as well as at any
; non-digit byte. Used so that with -t '<digit>' the key range can end on
; a digit without bleeding into the parse.
parse_int_bounded:
    xor     eax, eax
    xor     ecx, ecx                ; sign

.skip_ws:
    cmp     rdi, rsi
    jae     .check_sign
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
    cmp     rdi, rsi
    jae     .digits
    movzx   edx, byte [rdi]
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
    cmp     rdi, rsi
    jae     .done
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
; parse_field_spec(s /rdi/) — parses N or N,M into sort_field_start /_end.
;
; Trailing modifier characters (e.g. `2n`) and explicit `.C` character
; offsets are accepted by skipping them — this build can't honor them but
; ignoring is safer than rejecting.
parse_field_spec:
    xor     eax, eax
.start_digits:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .start_done
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .start_digits
.start_done:
    test    rax, rax
    jz      .skip_modifiers          ; "0" — leave start at 0 (whole line)
    mov     [rel sort_field_start], rax

.skip_modifiers:
    ; Skip optional `.C` and any modifier letters until ',' or NUL.
.scan_until_sep:
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .ret
    cmp     ecx, ','
    je      .at_comma
    inc     rdi
    jmp     .scan_until_sep

.at_comma:
    inc     rdi
    xor     eax, eax
.end_digits:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .end_done
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .end_digits
.end_done:
    mov     [rel sort_field_end], rax

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
