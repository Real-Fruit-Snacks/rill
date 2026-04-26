; mv.asm — rename or move files.
;
;   mv SRC DST
;   mv SRC... DIRECTORY
;
; v1 implements the same-filesystem case via a single rename(2). On EXDEV
; (cross-filesystem) we surface a clear error pointing at the limitation.
; Cross-filesystem move is a copy-then-unlink that lands once cp grows -r.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"

extern is_directory
extern path_join
extern perror_path

global applet_mv_main

%define EXDEV     18

section .bss
align 16
mv_statbuf: resb STATBUF_SIZE
mv_pathbuf: resb 4096

section .rodata
err_missing:     db "mv: missing operand", 10
err_missing_len: equ $ - err_missing
err_no_dir:      db "mv: target is not a directory", 10
err_no_dir_len:  equ $ - err_no_dir
err_xdev:        db "mv: cross-device move not yet supported", 10
err_xdev_len:    equ $ - err_xdev
prefix_mv:       db "mv", 0

section .text

; int applet_mv_main(int argc /edi/, char **argv /rsi/)
;
; Register usage (all callee-saved so they survive nested calls cleanly):
;   rbx  argc
;   rbp  argv
;   r12  dest index (= argc - 1)
;   r13  dest_is_dir flag
;   r14  rc accumulator
;   r15  loop counter (SRC index)
;
; 6 pushes + sub rsp,8 brings rsp to 0 mod 16 for nested calls.
applet_mv_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d

    cmp     ebx, 3
    jl      .missing

    lea     r12d, [rbx - 1]

    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel mv_statbuf]
    call    is_directory
    test    eax, eax
    js      .stat_err
    mov     r13d, eax
    jmp     .check_arity

.stat_err:
    cmp     ebx, 3
    je      .as_simple_pair
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_mv]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    jmp     .out

.as_simple_pair:
    xor     r13d, r13d

.check_arity:
    test    r13d, r13d
    jnz     .ops
    cmp     ebx, 4
    jl      .ops
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_no_dir]
    mov     edx, err_no_dir_len
    syscall
    mov     r14d, 1
    jmp     .out

.ops:
    mov     r15d, 1
.loop:
    cmp     r15d, r12d
    jge     .out

    test    r13d, r13d
    jz      .rename_simple

    ; Build "<dest>/<basename(SRC)>" in mv_pathbuf.
    mov     rdi, [rbp + r15*8]
    call    basename_of
    mov     rdx, rax
    mov     rsi, [rbp + r12*8]
    lea     rdi, [rel mv_pathbuf]
    call    path_join

    mov     eax, SYS_rename
    mov     rdi, [rbp + r15*8]
    lea     rsi, [rel mv_pathbuf]
    syscall
    jmp     .check_rename

.rename_simple:
    mov     eax, SYS_rename
    mov     rdi, [rbp + r15*8]
    mov     rsi, [rbp + r12*8]
    syscall

.check_rename:
    test    rax, rax
    jns     .next

    cmp     eax, -EXDEV
    jne     .report
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_xdev]
    mov     edx, err_xdev_len
    syscall
    mov     r14d, 1
    jmp     .next

.report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_mv]
    mov     rsi, [rbp + r15*8]
    call    perror_path
    mov     r14d, 1

.next:
    inc     r15d
    jmp     .loop

.missing:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_missing]
    mov     edx, err_missing_len
    syscall
    mov     r14d, 1

.out:
    mov     eax, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; basename_of(path /rdi/) -> rax = pointer to last component
;   Uses dl as scratch (rdx is caller-saved; we don't need it preserved).
basename_of:
    mov     rax, rdi
.loop:
    mov     dl, [rdi]
    test    dl, dl
    jz      .done
    cmp     dl, '/'
    jne     .next
    lea     rax, [rdi + 1]
.next:
    inc     rdi
    jmp     .loop
.done:
    ret
