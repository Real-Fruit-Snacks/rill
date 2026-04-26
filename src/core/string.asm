; string.asm — string primitives shared across applets.

BITS 64
DEFAULT REL

global strlen
global streq
global basename

section .text

; size_t strlen(const char *s /rdi/)
strlen:
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; int streq(const char *a /rdi/, const char *b /rsi/)
;   returns 1 if equal, 0 otherwise.
streq:
.loop:
    mov     cl, [rdi]
    cmp     cl, [rsi]
    jne     .ne
    test    cl, cl
    je      .eq
    inc     rdi
    inc     rsi
    jmp     .loop
.eq:
    mov     eax, 1
    ret
.ne:
    xor     eax, eax
    ret

; const char *basename(const char *path /rdi/)
;   Returns a pointer into the original string at the start of the final
;   path component. If the path has no '/', returns the path itself. Does
;   not allocate or modify the input.
basename:
    mov     rax, rdi                ; default = whole string
.loop:
    mov     cl, [rdi]
    test    cl, cl
    je      .done
    cmp     cl, '/'
    jne     .next
    lea     rax, [rdi + 1]
.next:
    inc     rdi
    jmp     .loop
.done:
    ret
