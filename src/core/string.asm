; string.asm — string primitives shared across applets.

BITS 64
DEFAULT REL

global strlen
global streq
global str_lt
global basename
global isort_strs

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

; int str_lt(const char *a /rdi/, const char *b /rsi/)
;   Returns 1 if a < b lexicographically (byte-wise unsigned), else 0.
;   NUL is the smallest byte (so prefixes sort before extensions).
str_lt:
.loop:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     eax, ecx
    jb      .lt
    ja      .ge
    test    eax, eax
    jz      .ge                     ; both at NUL → equal → not less
    inc     rdi
    inc     rsi
    jmp     .loop
.lt:
    mov     eax, 1
    ret
.ge:
    xor     eax, eax
    ret

; void isort_strs(char **ptrs /rdi/, size_t n /rsi/)
;   In-place insertion sort of the pointer array, using str_lt as the
;   comparator. Stable. Fine for the small Ns we hit (typical dir size).
isort_strs:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; ptrs
    mov     r13, rsi                ; n

    mov     rbx, 1
.outer:
    cmp     rbx, r13
    jge     .done

    mov     r14, [r12 + rbx*8]      ; key
    mov     rbp, rbx                ; j = i

.inner:
    test    rbp, rbp
    jz      .insert
    mov     rdi, [r12 + rbp*8 - 8]
    mov     rsi, r14
    call    str_lt                  ; rax = 1 if ptrs[j-1] < key
    test    eax, eax
    jnz     .insert                 ; ptrs[j-1] < key → stop, place key here

    mov     rdi, [r12 + rbp*8 - 8]
    mov     [r12 + rbp*8], rdi
    dec     rbp
    jmp     .inner

.insert:
    mov     [r12 + rbp*8], r14
    inc     rbx
    jmp     .outer

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
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
