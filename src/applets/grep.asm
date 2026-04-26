; grep.asm — search for a literal pattern in input.
;
;   grep [-i] [-v] [-n] [-c] [-F] PATTERN [FILE...]
;
; v1 supports:
;   -F  fixed string (the default in this build — see below)
;   -i  case-insensitive (ASCII)
;   -v  invert match
;   -n  prefix matching lines with their line number
;   -c  print match count instead of lines
;
; This grep does NOT yet support regular expressions — the PATTERN is
; always a literal string (as if -F were always on). Adding a BRE/ERE
; engine is its own change. -F is accepted as a no-op for compatibility.
;
; Multi-file invocation prefixes each match line with "FILE:". Single-file
; or stdin invocation does not. Exit code follows coreutils: 0 if any
; line matched anywhere, 1 if no match, 2 if an input file failed to open.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern streq
extern format_uint
extern read_buf
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_grep_main

%define LINE_BYTES 65536
%define IO_BYTES   65536
%define OUT_BYTES  4096

section .bss
align 16
grep_iobuf:    resb IO_BYTES
grep_outbuf:   resb OUT_BYTES
grep_line:     resb LINE_BYTES      ; current line content
grep_lower:    resb LINE_BYTES      ; lowercased copy when -i
grep_pattern_lower: resb LINE_BYTES ; lowercased pattern when -i
grep_iopos:    resq 1
grep_iolen:    resq 1
grep_iofd:     resq 1
grep_outpos:   resq 1
grep_line_len: resq 1
grep_pattern:  resq 1               ; pointer to active pattern
grep_pattern_len: resq 1
grep_ioeof:    resb 1
grep_flag_i:   resb 1
grep_flag_v:   resb 1
grep_flag_n:   resb 1
grep_flag_c:   resb 1
grep_print_name: resb 1             ; 1 if multi-file (prefix lines with FILE:)
grep_any_match:  resb 1             ; sticky: any line matched anywhere

section .rodata
opt_i:        db "-i", 0
opt_v:        db "-v", 0
opt_n:        db "-n", 0
opt_c:        db "-c", 0
opt_F:        db "-F", 0
prefix_grep:  db "grep", 0
err_no_pat:   db "grep: missing pattern", 10
err_no_pat_len: equ $ - err_no_pat

section .text

; int applet_grep_main(int argc /edi/, char **argv /rsi/)
;
; Register layout:
;   rbx  argc
;   rbp  argv
;   r12  arg cursor
;   r13  rc (0=match found, 1=no match, 2=error)
;   r14  total match count across all files (for any-match exit code)
;   r15  pattern arg index
applet_grep_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    mov     r13d, 1                 ; default: no match
    mov     byte [rel grep_flag_i], 0
    mov     byte [rel grep_flag_v], 0
    mov     byte [rel grep_flag_n], 0
    mov     byte [rel grep_flag_c], 0
    mov     byte [rel grep_print_name], 0
    mov     byte [rel grep_any_match], 0

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .no_pattern
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .pattern_at
    cmp     byte [rdi + 1], 0
    je      .pattern_at

    inc     rdi                     ; consume '-'
.flag_char:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .next_arg
    cmp     al, 'i'
    je      .set_i
    cmp     al, 'v'
    je      .set_v
    cmp     al, 'n'
    je      .set_n
    cmp     al, 'c'
    je      .set_c
    cmp     al, 'F'
    je      .set_F
    jmp     .pattern_at             ; unknown char → treat full arg as the
                                    ; pattern (lets users grep "-foo").

.set_i: mov byte [rel grep_flag_i], 1
        inc rdi
        jmp .flag_char
.set_v: mov byte [rel grep_flag_v], 1
        inc rdi
        jmp .flag_char
.set_n: mov byte [rel grep_flag_n], 1
        inc rdi
        jmp .flag_char
.set_c: mov byte [rel grep_flag_c], 1
        inc rdi
        jmp .flag_char
.set_F: inc rdi
        jmp .flag_char

.next_arg:
    inc     r12d
    jmp     .flag_loop

.pattern_at:
    cmp     r12d, ebx
    jge     .no_pattern
    mov     r15d, r12d
    inc     r12d

    ; Set up pattern (lowercase if -i).
    mov     rdi, [rbp + r15*8]
    cmp     byte [rel grep_flag_i], 0
    je      .pat_set_direct

    ; Lowercase into grep_pattern_lower.
    lea     rsi, [rel grep_pattern_lower]
    xor     ecx, ecx
.pat_lower:
    movzx   eax, byte [rdi + rcx]
    test    eax, eax
    jz      .pat_lower_done
    cmp     eax, 'A'
    jb      .pat_keep
    cmp     eax, 'Z'
    ja      .pat_keep
    add     eax, 'a' - 'A'
.pat_keep:
    mov     [rsi + rcx], al
    inc     rcx
    cmp     rcx, LINE_BYTES - 1
    jge     .pat_lower_done
    jmp     .pat_lower
.pat_lower_done:
    mov     byte [rsi + rcx], 0
    mov     [rel grep_pattern_len], rcx
    mov     [rel grep_pattern], rsi
    jmp     .pat_done

.pat_set_direct:
    mov     [rel grep_pattern], rdi
    xor     ecx, ecx
.pat_len:
    cmp     byte [rdi + rcx], 0
    je      .pat_len_done
    inc     rcx
    jmp     .pat_len
.pat_len_done:
    mov     [rel grep_pattern_len], rcx

.pat_done:
    ; Determine if multi-file (for FILE: prefixes).
    mov     ecx, ebx
    sub     ecx, r12d
    cmp     ecx, 1
    jle     .single_or_stdin
    mov     byte [rel grep_print_name], 1

.single_or_stdin:
    cmp     r12d, ebx
    jl      .files

    ; stdin
    mov     qword [rel grep_iofd], STDIN_FILENO
    xor     rsi, rsi
    call    grep_stream
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
    mov     [rel grep_iofd], rax
    mov     rsi, [rbp + r12*8]
    call    grep_stream
    inc     r12d
    jmp     .file_loop

.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_grep]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r13d, 2
    inc     r12d
    jmp     .file_loop

.no_pattern:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_no_pat]
    mov     edx, err_no_pat_len
    syscall
    mov     r13d, 2

.out:
    call    flush_out
    cmp     byte [rel grep_any_match], 0
    je      .done
    cmp     r13d, 1
    jne     .done
    xor     r13d, r13d              ; some match → exit 0
.done:
    mov     eax, r13d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; grep_stream(name /rsi/)
;
; Reads lines from grep_iofd, applies the match logic, emits per-line
; output (or just accumulates count for -c). On exit, closes fd unless
; stdin and emits the count line for -c.
;
; rbx  saved name (pointer or NULL)
; rbp  per-stream match count (for -c output)
; r12  line number
grep_stream:
    push    rbx
    push    rbp
    push    r12
    push    r13                     ; saved iopos restore
    push    r14
    sub     rsp, 8

    mov     rbx, rsi
    xor     rbp, rbp
    xor     r12, r12

    mov     qword [rel grep_iopos], 0
    mov     qword [rel grep_iolen], 0
    mov     byte  [rel grep_ioeof], 0

.line_loop:
    call    read_line
    test    rax, rax
    js      .eof

    inc     r12

    ; Decide match.
    call    line_matches
    cmp     byte [rel grep_flag_v], 0
    jz      .no_invert
    xor     eax, 1
.no_invert:
    test    eax, eax
    jz      .line_loop

    inc     rbp
    mov     byte [rel grep_any_match], 1

    cmp     byte [rel grep_flag_c], 0
    jne     .line_loop

    ; Emit "[name:][lineno:]<line>\n"
    cmp     byte [rel grep_print_name], 0
    jz      .no_name
    test    rbx, rbx
    jz      .no_name
    mov     rdi, rbx
    call    emit_cstr
    mov     al, ':'
    call    emit_byte
.no_name:

    cmp     byte [rel grep_flag_n], 0
    jz      .no_lineno
    mov     rdi, r12
    call    emit_uint
    mov     al, ':'
    call    emit_byte
.no_lineno:

    lea     rdi, [rel grep_line]
    call    emit_cstr
    mov     al, 10
    call    emit_byte

    jmp     .line_loop

.eof:
    cmp     qword [rel grep_iofd], STDIN_FILENO
    je      .skip_close
    mov     eax, SYS_close
    mov     rdi, [rel grep_iofd]
    syscall
.skip_close:

    cmp     byte [rel grep_flag_c], 0
    jz      .ret

    cmp     byte [rel grep_print_name], 0
    jz      .no_c_name
    test    rbx, rbx
    jz      .no_c_name
    mov     rdi, rbx
    call    emit_cstr
    mov     al, ':'
    call    emit_byte
.no_c_name:
    mov     rdi, rbp
    call    emit_uint
    mov     al, 10
    call    emit_byte

.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; read_line — fills grep_line + grep_line_len. Returns -1 on EOF.
read_line:
    push    rbx
    push    rbp

    xor     ebx, ebx
    mov     qword [rel grep_line_len], 0

.byte_loop:
    mov     rax, [rel grep_iopos]
    cmp     rax, [rel grep_iolen]
    jl      .have_byte

    cmp     byte [rel grep_ioeof], 0
    jne     .no_more

    mov     edi, [rel grep_iofd]
    lea     rsi, [rel grep_iobuf]
    mov     edx, IO_BYTES
    call    read_buf
    test    rax, rax
    jz      .read_eof
    js      .read_eof
    mov     [rel grep_iolen], rax
    mov     qword [rel grep_iopos], 0
    jmp     .byte_loop

.read_eof:
    mov     byte [rel grep_ioeof], 1
    mov     qword [rel grep_iolen], 0
    mov     qword [rel grep_iopos], 0
    test    ebx, ebx
    jnz     .return_line
.no_more:
    mov     rax, -1
    jmp     .ret

.have_byte:
    mov     rcx, [rel grep_iopos]
    movzx   eax, byte [rel grep_iobuf + rcx]
    inc     qword [rel grep_iopos]

    cmp     al, 10
    je      .return_line

    cmp     ebx, LINE_BYTES - 1
    jge     .byte_loop              ; truncate overlong
    mov     [rel grep_line + rbx], al
    inc     ebx
    jmp     .byte_loop

.return_line:
    mov     byte [rel grep_line + rbx], 0
    mov     [rel grep_line_len], rbx
    xor     eax, eax

.ret:
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; line_matches() -> rax (1 if pattern found in line, 0 otherwise)
line_matches:
    push    rbx
    push    rbp

    mov     rbp, [rel grep_pattern]
    mov     rdi, [rel grep_pattern_len]
    test    rdi, rdi
    jz      .yes                    ; empty pattern matches every line

    cmp     byte [rel grep_flag_i], 0
    jne     .case_insensitive

    ; Naive substring search of grep_line for grep_pattern.
    lea     rbx, [rel grep_line]
    mov     rcx, [rel grep_line_len]
    cmp     rcx, rdi
    jl      .no
    sub     rcx, rdi
    inc     rcx                     ; window count = line_len - pat_len + 1

.scan:
    test    rcx, rcx
    jz      .no
    mov     rdi, rbx
    mov     rsi, rbp
    mov     rdx, [rel grep_pattern_len]
    call    bytes_eq
    test    eax, eax
    jnz     .yes
    inc     rbx
    dec     rcx
    jmp     .scan

.case_insensitive:
    ; Lowercase grep_line into grep_lower, then naive search vs the
    ; pre-lowercased pattern (which lives at grep_pattern).
    lea     rsi, [rel grep_line]
    lea     rdi, [rel grep_lower]
    xor     ecx, ecx
.lower_copy:
    movzx   eax, byte [rsi + rcx]
    test    eax, eax
    jz      .lower_done
    cmp     eax, 'A'
    jb      .lower_keep
    cmp     eax, 'Z'
    ja      .lower_keep
    add     eax, 'a' - 'A'
.lower_keep:
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .lower_copy
.lower_done:
    mov     byte [rdi + rcx], 0

    lea     rbx, [rel grep_lower]
    mov     rcx, [rel grep_line_len]
    mov     rdi, [rel grep_pattern_len]
    cmp     rcx, rdi
    jl      .no
    sub     rcx, rdi
    inc     rcx

.iscan:
    test    rcx, rcx
    jz      .no
    mov     rdi, rbx
    mov     rsi, rbp
    mov     rdx, [rel grep_pattern_len]
    call    bytes_eq
    test    eax, eax
    jnz     .yes
    inc     rbx
    dec     rcx
    jmp     .iscan

.no:
    xor     eax, eax
    jmp     .done
.yes:
    mov     eax, 1
.done:
    pop     rbp
    pop     rbx
    ret

; bytes_eq(a /rdi/, b /rsi/, n /rdx/) -> rax (1 if first n bytes equal)
bytes_eq:
    test    rdx, rdx
    jz      .yes
.loop:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    inc     rdi
    inc     rsi
    dec     rdx
    jnz     .loop
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; emit_uint(v /rdi/) — write v in decimal to grep_outbuf.
emit_uint:
    sub     rsp, 32
    mov     rsi, rsp
    call    format_uint
    mov     rdx, rax
    mov     rcx, 0
.loop:
    cmp     rcx, rdx
    jge     .done
    mov     al, [rsp + rcx]
    push    rcx
    push    rdx
    call    emit_byte
    pop     rdx
    pop     rcx
    inc     rcx
    jmp     .loop
.done:
    add     rsp, 32
    ret

; emit_cstr(s /rdi/)
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
    mov     rcx, [rel grep_outpos]
    cmp     rcx, OUT_BYTES
    jl      .room
    call    flush_out
    mov     rcx, [rel grep_outpos]
.room:
    pop     rax
    lea     r8, [rel grep_outbuf]
    mov     [r8 + rcx], al
    inc     rcx
    mov     [rel grep_outpos], rcx
    ret

flush_out:
    mov     rcx, [rel grep_outpos]
    test    rcx, rcx
    jz      .done
    sub     rsp, 8
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel grep_outbuf]
    mov     rdx, rcx
    call    write_all
    add     rsp, 8
    mov     qword [rel grep_outpos], 0
.done:
    ret
