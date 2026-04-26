; chmod.asm — change file mode bits.
;
;   chmod MODE FILE...
;
; MODE is either octal (e.g. 644, 0755) or symbolic. Symbolic syntax:
;
;   mode    := clause [ , clause ]...
;   clause  := [ who... ] op [ perm... ]
;   who     := u | g | o | a
;   op      := + | - | =
;   perm    := r | w | x
;
; Examples:
;   chmod 0755 f
;   chmod u+x,go-w f          (add x for user; clear w for group + other)
;   chmod a=r f               (everyone read, no write/exec)
;   chmod +x f                (equivalent to a+x; we don't apply umask)
;
; Not yet supported:
;   - X (conditional exec), s (setuid/setgid), t (sticky)
;   - perm "from" syntax (u=g, etc.)
;   - umask interaction for the implicit-who form
;   - -R recursion

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"

extern parse_octal
extern perror_path

global applet_chmod_main

section .bss
align 16
chmod_statbuf: resb STATBUF_SIZE

section .rodata
err_missing:      db "chmod: missing operand", 10
err_missing_len:  equ $ - err_missing
err_bad_mode:     db "chmod: invalid mode", 10
err_bad_mode_len: equ $ - err_bad_mode
prefix_chmod:     db "chmod", 0

section .text

; int applet_chmod_main(int argc /edi/, char **argv /rsi/)
applet_chmod_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; mode_or_spec ptr
    push    r13                     ; arg cursor
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d

    cmp     ebx, 3
    jl      .missing

    mov     r12, [rbp + 1*8]        ; mode spec (string)

    mov     r13d, 2
.loop:
    cmp     r13d, ebx
    jge     .out

    ; Decide octal vs symbolic per file (cheap; could hoist if needed).
    ; If first char is a digit, use octal. Else symbolic.
    movzx   eax, byte [r12]
    sub     eax, '0'
    cmp     eax, 9
    ja      .symbolic_path

    sub     rsp, 16
    mov     rdi, r12
    lea     rsi, [rsp]
    call    parse_octal
    test    eax, eax
    jnz     .bad_octal
    mov     rcx, [rsp]
    add     rsp, 16

    mov     eax, SYS_chmod
    mov     rdi, [rbp + r13*8]
    mov     esi, ecx
    syscall
    test    rax, rax
    jns     .next
    jmp     .report

.bad_octal:
    add     rsp, 16
    jmp     .bad_mode

.symbolic_path:
    ; lstat → current mode → apply symbolic spec → chmod with new mode.
    mov     eax, SYS_stat
    mov     rdi, [rbp + r13*8]
    lea     rsi, [rel chmod_statbuf]
    syscall
    test    rax, rax
    js      .report

    mov     edi, [rel chmod_statbuf + ST_MODE]
    and     edi, 0o7777
    mov     rsi, r12
    call    apply_symbolic
    cmp     rax, -1
    je      .bad_mode

    mov     ecx, eax
    mov     eax, SYS_chmod
    mov     rdi, [rbp + r13*8]
    mov     esi, ecx
    syscall
    test    rax, rax
    js      .report

.next:
    inc     r13d
    jmp     .loop

.report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_chmod]
    mov     rsi, [rbp + r13*8]
    call    perror_path
    mov     r14d, 1
    inc     r13d
    jmp     .loop

.bad_mode:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_mode]
    mov     edx, err_bad_mode_len
    syscall
    mov     r14d, 1
    jmp     .out

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     r14d, 1

.out:
    mov     eax, r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; apply_symbolic(current /edi/, spec /rsi/) -> rax
;
;   Applies the symbolic mode spec to `current` and returns the new mode.
;   Returns -1 if the spec is malformed.
;
;   Bits in `current` outside 0o7777 are preserved (callers pass perms only).
apply_symbolic:
    mov     eax, edi                ; running mode

.next_clause:
    xor     edx, edx                ; who_mask
.who_loop:
    movzx   ecx, byte [rsi]
    cmp     ecx, 'u'
    je      .who_u
    cmp     ecx, 'g'
    je      .who_g
    cmp     ecx, 'o'
    je      .who_o
    cmp     ecx, 'a'
    je      .who_a
    jmp     .who_done
.who_u: or edx, 0o700
        inc rsi
        jmp .who_loop
.who_g: or edx, 0o070
        inc rsi
        jmp .who_loop
.who_o: or edx, 0o007
        inc rsi
        jmp .who_loop
.who_a: or edx, 0o777
        inc rsi
        jmp .who_loop
.who_done:
    ; Only r/w/x perms are supported, so the who mask intentionally omits
    ; setuid/setgid/sticky. Those bits are preserved across symbolic ops.
    test    edx, edx
    jnz     .have_who
    mov     edx, 0o777              ; default: 'a' (umask handling deferred)
.have_who:

    movzx   ecx, byte [rsi]
    cmp     ecx, '+'
    je      .op_plus
    cmp     ecx, '-'
    je      .op_minus
    cmp     ecx, '='
    je      .op_eq
    jmp     .err

.op_plus:
    inc     rsi
    call    parse_perm_bits         ; r9d = perm bits
    and     r9d, edx
    or      eax, r9d
    jmp     .clause_end
.op_minus:
    inc     rsi
    call    parse_perm_bits
    and     r9d, edx
    not     r9d
    and     eax, r9d
    jmp     .clause_end
.op_eq:
    inc     rsi
    call    parse_perm_bits
    and     r9d, edx
    mov     ecx, edx
    not     ecx
    and     eax, ecx
    or      eax, r9d

.clause_end:
    movzx   ecx, byte [rsi]
    test    ecx, ecx
    jz      .done
    cmp     ecx, ','
    jne     .err
    inc     rsi
    jmp     .next_clause

.done:
    ret
.err:
    mov     rax, -1
    ret

; parse_perm_bits — reads r/w/x sequence from [rsi], advances rsi past
; the end. Returns combined perm bits in r9d. Used only by apply_symbolic.
;   r=0o444, w=0o222, x=0o111. Empty perm → 0.
parse_perm_bits:
    xor     r9d, r9d
.loop:
    movzx   ecx, byte [rsi]
    cmp     ecx, 'r'
    je      .r
    cmp     ecx, 'w'
    je      .w
    cmp     ecx, 'x'
    je      .x
    ret
.r: or r9d, 0o444
    inc rsi
    jmp .loop
.w: or r9d, 0o222
    inc rsi
    jmp .loop
.x: or r9d, 0o111
    inc rsi
    jmp .loop
