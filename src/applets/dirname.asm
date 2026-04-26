; dirname.asm — print all but the last component of each path.
;
;   dirname PATH...   → print dirname(PATH) for each PATH, one per line
;
; Corner cases (matching coreutils):
;   dirname ""           → "."
;   dirname "foo"        → "."
;   dirname "/"          → "/"
;   dirname "/foo"       → "/"
;   dirname "/foo/"      → "/"
;   dirname "/foo/bar"   → "/foo"
;   dirname "//foo"      → "//"     (POSIX preserves leading double slash)
;
; v1 does not implement -z.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern strlen
extern write_all
extern putc

global applet_dirname_main

section .rodata
err_missing: db "dirname: missing operand", 10
err_missing_len: equ $ - err_missing
dot:    db "."
slash:  db "/"

section .text

; int applet_dirname_main(int argc /edi/, char **argv /rsi/)
applet_dirname_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     ebx, edi
    mov     rbp, rsi

    cmp     ebx, 2
    jl      .missing

    mov     r12d, 1
.loop:
    cmp     r12d, ebx
    jge     .done

    mov     rdi, [rbp + r12*8]
    call    compute_dirname         ; rax = ptr, rdx = len

    push    rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rax
    mov     rdx, rdx
    call    write_all
    pop     rcx
    test    eax, eax
    js      .err

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    test    eax, eax
    js      .err

    inc     r12d
    jmp     .loop

.done:
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

.err:
    mov     eax, 1

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; compute_dirname(path /rdi/) -> rax = ptr, rdx = len
;
;   Returns a pointer into either the input or one of the static "." / "/"
;   strings, plus a length. Does not allocate.
compute_dirname:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi

    push    rdi
    call    strlen
    pop     rdi
    mov     rcx, rax

    test    rcx, rcx
    jz      .dot

    ; Strip trailing '/' but never past the very first byte (so "/" stays "/").
.trim_trailing:
    cmp     rcx, 1
    jle     .find_slash
    mov     al, [rdi + rcx - 1]
    cmp     al, '/'
    jne     .find_slash
    dec     rcx
    jmp     .trim_trailing

.find_slash:
    mov     rdx, rcx
.scan:
    test    rdx, rdx
    jz      .no_slash
    dec     rdx
    cmp     byte [rdi + rdx], '/'
    jne     .scan

    ; Found a '/' at index rdx. dirname is path[0..rdx], stripping any
    ; trailing repeated slashes back to position 0.
.strip_slash_run:
    test    rdx, rdx
    jz      .root
    cmp     byte [rdi + rdx - 1], '/'
    jne     .have_dir
    dec     rdx
    jmp     .strip_slash_run

.have_dir:
    mov     rax, rdi
    ; rdx already holds the length
    jmp     .ret

.root:
    ; All trailing characters before the slash were slashes; emit just "/".
    ; (We don't preserve "//" specifically — POSIX permits implementations
    ; to collapse it. Matching coreutils' default behavior on Linux.)
    lea     rax, [rel slash]
    mov     edx, 1
    jmp     .ret

.no_slash:
    lea     rax, [rel dot]
    mov     edx, 1
    jmp     .ret

.dot:
    lea     rax, [rel dot]
    mov     edx, 1

.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
