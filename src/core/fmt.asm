; fmt.asm — number parsing and formatting.

BITS 64
DEFAULT REL

global parse_uint
global format_uint

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
