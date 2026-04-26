; printenv.asm — print environment variables.
;
; printenv          → print every "NAME=VALUE\n" entry from envp
; printenv NAME...  → print the value of each NAME (one per line). Exit 1
;                     if any NAME is unset. Continue past missing entries
;                     so the user sees results for the ones that do exist.
;
; envp lives on the process stack at &argv[argc+1]. Our dispatcher does
; not forward envp explicitly, but the relationship envp = argv + argc + 1
; holds even after `rill <applet>` arg-shifting, so we recover it here.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern write_cstr
extern putc

global applet_printenv_main

section .text

; int applet_printenv_main(int argc /edi/, char **argv /rsi/)
applet_printenv_main:
    push    rbx                     ; argc
    push    rbp                     ; envp
    push    r12                     ; cursor / arg index
    push    r13                     ; argv (we still need it for arg lookup)
    push    r14                     ; missing-flag (1 if any NAME unset)

    mov     ebx, edi
    mov     r13, rsi

    ; envp = argv + argc + 1 (in elements, 8 bytes each).
    lea     rbp, [rsi + rdi*8 + 8]

    xor     r14d, r14d              ; nothing missing yet

    cmp     ebx, 2
    jl      .print_all

    ; Per-name lookup mode.
    mov     r12d, 1
.name_loop:
    cmp     r12d, ebx
    jge     .out
    mov     rdi, [r13 + r12*8]      ; name to find
    call    find_and_emit
    test    eax, eax
    jnz     .miss
    inc     r12d
    jmp     .name_loop
.miss:
    mov     r14d, 1
    inc     r12d
    jmp     .name_loop

.print_all:
    mov     r12, rbp
.all_loop:
    mov     rdi, [r12]
    test    rdi, rdi
    jz      .out

    push    r12
    mov     edi, STDOUT_FILENO
    mov     rsi, [r12]
    call    write_cstr
    pop     r12
    test    eax, eax
    js      .out

    push    r12
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    pop     r12
    test    eax, eax
    js      .out

    add     r12, 8
    jmp     .all_loop

.out:
    mov     eax, r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; find_and_emit(name /rdi/) -> rax  (0 if found and printed, 1 if missing)
;
; Scans envp (held in rbp) for an entry "name=value", and writes "value\n"
; to stdout if found.
find_and_emit:
    push    rbx                     ; saved name pointer
    push    r12                     ; envp cursor
    push    r13                     ; (alignment)

    mov     rbx, rdi
    mov     r12, rbp

.scan:
    mov     rsi, [r12]
    test    rsi, rsi
    jz      .miss

    ; Compare name (rbx) with prefix of entry (rsi). Match ends with '='.
    mov     rdi, rbx
    mov     rdx, rsi
.prefix:
    mov     al, [rdi]
    test    al, al
    jz      .name_done
    cmp     al, [rdx]
    jne     .next
    inc     rdi
    inc     rdx
    jmp     .prefix
.name_done:
    cmp     byte [rdx], '='
    jne     .next
    lea     rsi, [rdx + 1]          ; value
    mov     edi, STDOUT_FILENO
    call    write_cstr
    test    eax, eax
    js      .miss
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    test    eax, eax
    js      .miss
    xor     eax, eax
    jmp     .ret

.next:
    add     r12, 8
    jmp     .scan

.miss:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
