; basename.asm — print the final component of a path.
;
;   basename PATH         → print basename(PATH)
;   basename PATH SUFFIX  → also strip SUFFIX from the end (if not equal)
;
; v1 does not implement -a, -s, or -z. It does match coreutils for the
; primary single- and two-argument forms, including the corner cases:
;
;   basename "/"        → "/"
;   basename "/usr/"    → "usr"
;   basename "//"       → "/"
;   basename ""         → ""        (coreutils prints empty + newline)
;
; The suffix is only stripped if PATH's basename is strictly longer than
; the suffix and ends with it; matching coreutils ensures `basename foo .foo`
; prints "foo" rather than "".

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern strlen
extern write_all
extern putc

global applet_basename_main

section .rodata
err_missing: db "basename: missing operand", 10
err_missing_len: equ $ - err_missing
err_extra:   db "basename: extra operand", 10
err_extra_len: equ $ - err_extra
slash:       db "/"

section .text

; int applet_basename_main(int argc /edi/, char **argv /rsi/)
applet_basename_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     ebx, edi
    mov     rbp, rsi

    cmp     ebx, 2
    jl      .missing
    cmp     ebx, 4
    jge     .extra

    mov     rdi, [rbp + 1*8]        ; PATH
    call    compute_basename        ; rax = pointer, rdx = length

    mov     r12, rax
    mov     r13, rdx

    cmp     ebx, 3
    jl      .emit

    ; Strip suffix if applicable.
    mov     rdi, [rbp + 2*8]
    call    strlen
    mov     r14, rax                ; suffix length

    cmp     r14, r13
    jge     .emit                   ; suffix >= base len → keep base

    ; Compare base[len-suflen ..] with suffix.
    mov     rdi, r12
    add     rdi, r13
    sub     rdi, r14                ; pointer to potential suffix start
    mov     rsi, [rbp + 2*8]
    mov     rcx, r14
    repe    cmpsb
    jne     .emit

    ; Suffix matched; trim it.
    sub     r13, r14

.emit:
    test    r13, r13
    jz      .newline_only
    mov     edi, STDOUT_FILENO
    mov     rsi, r12
    mov     rdx, r13
    call    write_all
    test    eax, eax
    js      .err
.newline_only:
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    test    eax, eax
    js      .err

    xor     eax, eax
    jmp     .out

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     eax, 1
    jmp     .out

.extra:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_extra]
    mov     edx, err_extra_len
    syscall
    mov     eax, 1
    jmp     .out

.err:
    mov     eax, 1

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; compute_basename(path /rdi/) -> rax = pointer, rdx = length
;
;   Returns a pointer/length describing the basename per POSIX semantics.
;   Does not modify the input string. Length may be zero (input empty).
compute_basename:
    push    rbx
    push    r12

    mov     r12, rdi                ; original

    ; Find length.
    push    rdi
    call    strlen
    pop     rdi
    mov     rcx, rax                ; len
    test    rcx, rcx
    jz      .empty

    ; Strip trailing '/' (but stop if path is all slashes; we'll handle
    ; that separately).
.trim:
    mov     al, [rdi + rcx - 1]
    cmp     al, '/'
    jne     .trimmed
    dec     rcx
    jnz     .trim
    ; All slashes → return single '/'.
    lea     rax, [rel slash]
    mov     edx, 1
    jmp     .ret

.trimmed:
    ; rcx = stripped length. Find last '/' within [0, rcx).
    mov     rdx, rcx
.scan:
    test    rdx, rdx
    jz      .no_slash
    dec     rdx
    cmp     byte [rdi + rdx], '/'
    jne     .scan

    ; Found '/' at index rdx. Basename starts at rdx+1.
    inc     rdx
    lea     rax, [rdi + rdx]
    sub     rcx, rdx
    mov     rdx, rcx
    jmp     .ret

.no_slash:
    mov     rax, rdi
    mov     rdx, rcx
    jmp     .ret

.empty:
    mov     rax, r12
    xor     edx, edx

.ret:
    pop     r12
    pop     rbx
    ret
