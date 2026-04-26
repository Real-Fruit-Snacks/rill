; ln.asm — create links.
;
;   ln [-s] [-f] TARGET LINK_NAME
;   ln [-s] [-f] TARGET           (creates basename(TARGET) in cwd)
;
; v1 supports the two-operand form. The N-operand "ln TARGET... DIR" form
; lands once we have stat (phase 3b). Hard links are the default; -s makes
; the link a symbolic link. -f removes any existing LINK_NAME first.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern streq
extern strlen
extern perror_path

global applet_ln_main

section .rodata
opt_s:    db "-s", 0
opt_f:    db "-f", 0
opt_sf:   db "-sf", 0
opt_fs:   db "-fs", 0
prefix_ln: db "ln", 0
err_missing: db "ln: missing operand", 10
err_missing_len: equ $ - err_missing
err_extra:   db "ln: too many operands", 10
err_extra_len: equ $ - err_extra

section .text

; int applet_ln_main(int argc /edi/, char **argv /rsi/)
;
; Strategy: walk argv parsing flags into r13d (bit 0 = -s, bit 1 = -f),
; collect non-flag positions into r12 (target idx) and rbp (link idx).
applet_ln_main:
    push    rbx                     ; argc
    push    rbp                     ; link idx (or 0 if missing)
    push    r12                     ; target idx
    push    r13                     ; flags
    push    r14                     ; argv

    mov     ebx, edi
    mov     r14, rsi
    xor     r13d, r13d
    xor     r12d, r12d
    xor     ebp, ebp

    mov     ecx, 1
.scan:
    cmp     ecx, ebx
    jge     .post_scan
    mov     rdi, [r14 + rcx*8]
    cmp     byte [rdi], '-'
    jne     .operand
    cmp     byte [rdi + 1], 0
    je      .operand                ; "-" alone is an operand

    push    rcx
    push    rdi
    sub     rsp, 8

    lea     rsi, [rel opt_s]
    call    streq
    test    eax, eax
    jz      .check_f

    add     rsp, 8
    pop     rdi
    pop     rcx
    or      r13d, 1
    inc     ecx
    jmp     .scan

.check_f:
    mov     rdi, [rsp + 8]          ; restored arg
    lea     rsi, [rel opt_f]
    call    streq
    test    eax, eax
    jz      .check_combo
    add     rsp, 8
    pop     rdi
    pop     rcx
    or      r13d, 2
    inc     ecx
    jmp     .scan

.check_combo:
    mov     rdi, [rsp + 8]
    lea     rsi, [rel opt_sf]
    call    streq
    test    eax, eax
    jnz     .got_combo

    mov     rdi, [rsp + 8]
    lea     rsi, [rel opt_fs]
    call    streq
    test    eax, eax
    jz      .unknown_flag

.got_combo:
    add     rsp, 8
    pop     rdi
    pop     rcx
    or      r13d, 3
    inc     ecx
    jmp     .scan

.unknown_flag:
    add     rsp, 8
    pop     rdi
    pop     rcx
    ; Fall through to operand handling.

.operand:
    test    r12d, r12d
    jnz     .have_target
    mov     r12d, ecx
    inc     ecx
    jmp     .scan

.have_target:
    test    ebp, ebp
    jnz     .extra
    mov     ebp, ecx
    inc     ecx
    jmp     .scan

.extra:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_extra]
    mov     edx, err_extra_len
    syscall
    mov     eax, 1
    jmp     .out

.post_scan:
    test    r12d, r12d
    jz      .missing

    ; If only target given, derive link name from basename(target). To keep
    ; this short and correct, we error out for now and require both args.
    test    ebp, ebp
    jz      .missing

    ; -f: try to unlink LINK_NAME first; ignore errors (the create call
    ; below will surface a real problem).
    test    r13d, 2
    jz      .do_link
    mov     eax, SYS_unlink
    mov     rdi, [r14 + rbp*8]
    syscall

.do_link:
    test    r13d, 1
    jnz     .symlink

    ; Hard link: link(target, link_name)
    mov     eax, SYS_link
    mov     rdi, [r14 + r12*8]      ; target
    mov     rsi, [r14 + rbp*8]      ; link_name
    syscall
    test    rax, rax
    js      .err
    xor     eax, eax
    jmp     .out

.symlink:
    mov     eax, SYS_symlink
    mov     rdi, [r14 + r12*8]
    mov     rsi, [r14 + rbp*8]
    syscall
    test    rax, rax
    js      .err
    xor     eax, eax
    jmp     .out

.err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_ln]
    mov     rsi, [r14 + rbp*8]
    call    perror_path
    mov     eax, 1
    jmp     .out

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     eax, 1

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
