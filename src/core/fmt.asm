; fmt.asm — number parsing and formatting.

BITS 64
DEFAULT REL

global parse_uint
global parse_octal
global format_uint
global format_uint_pad
global format_octal

section .text

; int parse_uint(const char *s /rdi/, uint64_t *out /rsi/)
;
;   Parses a non-negative decimal integer. Stops at the first non-digit.
;   Returns:
;     0 on success (and *out is set)
;    -1 if the string has no leading digit (empty / non-digit start)
;    -2 on overflow (value would exceed 2^64-1)
parse_uint:
    xor     eax, eax                ; accumulator (uint64)
    xor     ecx, ecx                ; digit count

.loop:
    movzx   edx, byte [rdi]
    sub     edx, '0'
    cmp     edx, 9
    ja      .done

    ; acc = acc * 10 + digit, with overflow check
    mov     r8, rax
    shl     rax, 3                  ; *8
    add     rax, r8                 ; *9
    add     rax, r8                 ; *10
    jc      .overflow
    add     rax, rdx
    jc      .overflow

    inc     rdi
    inc     rcx
    jmp     .loop

.done:
    test    rcx, rcx
    jz      .empty
    mov     [rsi], rax
    xor     eax, eax
    ret

.empty:
    mov     eax, -1
    ret

.overflow:
    mov     eax, -2
    ret

; int parse_octal(const char *s /rdi/, uint64_t *out /rsi/)
;
;   Parses a non-negative octal integer (digits 0-7). Stops at the first
;   non-octal-digit. Mirrors parse_uint's contract:
;     0  on success
;    -1  empty / non-digit start
;    -2  overflow
parse_octal:
    xor     eax, eax
    xor     ecx, ecx

.loop:
    movzx   edx, byte [rdi]
    sub     edx, '0'
    cmp     edx, 7
    ja      .done

    mov     r8, rax
    shr     r8, 61                  ; if any of the top 3 bits are set,
    test    r8, r8                  ; the next shl by 3 would lose them
    jnz     .overflow
    shl     rax, 3
    or      rax, rdx

    inc     rdi
    inc     rcx
    jmp     .loop

.done:
    test    rcx, rcx
    jz      .empty
    mov     [rsi], rax
    xor     eax, eax
    ret

.empty:
    mov     eax, -1
    ret

.overflow:
    mov     eax, -2
    ret

; size_t format_uint(uint64_t v /rdi/, char *buf /rsi/)
;
;   Writes the decimal representation of v into buf (no NUL terminator)
;   and returns the number of bytes written. buf must have room for at
;   least 20 bytes (max uint64 = 18446744073709551615 = 20 digits).
format_uint:
    mov     rax, rdi
    mov     rcx, 10
    lea     r8, [rsi + 20]          ; write digits backwards from the end
    mov     r9, r8

.divloop:
    xor     edx, edx
    div     rcx                     ; rax = rax/10, rdx = rax%10
    add     dl, '0'
    dec     r9
    mov     [r9], dl
    test    rax, rax
    jnz     .divloop

    ; Move digits to the front of buf.
    mov     rax, r8
    sub     rax, r9                 ; rax = number of digits

    push    rax
    mov     rdi, rsi
    mov     rsi, r9
    mov     rcx, rax
    rep     movsb
    pop     rax
    ret

; size_t format_uint_pad(uint64_t v /rdi/, char *buf /rsi/, size_t width /rdx/)
;
;   Writes v in decimal, right-aligned in `width` columns, left-padded
;   with spaces. If the natural width exceeds `width`, the value is
;   written in full (no truncation). Returns the number of bytes written.
;
;   Stack: 3 callee-saved pushes + sub 32 -> 56 bytes -> 8 mod 16 from
;   entry's 8 mod 16 = 0 mod 16 at internal call sites.
format_uint_pad:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 32                 ; 24 bytes scratch + 8 align

    mov     rbx, rsi                ; out buf
    mov     r12, rdx                ; width

    mov     rsi, rsp
    call    format_uint
    mov     r13, rax                ; digit count

    cmp     r13, r12
    jge     .no_pad

    mov     rcx, r12
    sub     rcx, r13
    mov     rdi, rbx
    mov     al, ' '
    rep     stosb

    mov     rsi, rsp
    mov     rcx, r13
    rep     movsb

    mov     rax, r12
    jmp     .ret

.no_pad:
    mov     rdi, rbx
    mov     rsi, rsp
    mov     rcx, r13
    rep     movsb
    mov     rax, r13

.ret:
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rbx
    ret

; size_t format_octal(uint64_t v /rdi/, char *buf /rsi/)
;
;   Writes the octal representation of v into buf (no NUL, no leading 0).
;   Returns digit count. buf must hold at least 24 bytes (max u64 = 22
;   octal digits).
format_octal:
    mov     rax, rdi
    mov     ecx, 8
    lea     r8, [rsi + 24]
    mov     r9, r8

.div_oct:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     r9
    mov     [r9], dl
    test    rax, rax
    jnz     .div_oct

    mov     rax, r8
    sub     rax, r9

    push    rax
    mov     rdi, rsi
    mov     rsi, r9
    mov     rcx, rax
    rep     movsb
    pop     rax
    ret
