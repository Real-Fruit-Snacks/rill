; uname.asm — print system identification.
;
;   uname [-asnrvm]
;
; Default prints the sysname (kernel name, "Linux"). -a prints all
; columns; individual flags select sysname / nodename / release /
; version / machine. -o (operating system) and -p (processor) deferred.
;
; Combined short flags (-snr) are supported.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern strlen
extern write_all
extern putc

global applet_uname_main

%define UTS_LEN 65

section .bss
align 16
uname_buf: resb UTS_LEN * 6         ; sysname, nodename, release, version, machine, domainname

section .rodata
err_uname: db "uname: kernel call failed", 10
err_uname_len: equ $ - err_uname

section .text

%define FLAG_S 1
%define FLAG_N 2
%define FLAG_R 4
%define FLAG_V 8
%define FLAG_M 16
%define FLAG_ALL (FLAG_S | FLAG_N | FLAG_R | FLAG_V | FLAG_M)

applet_uname_main:
    push    rbx
    push    rbp

    mov     ebx, edi
    mov     rbp, rsi

    mov     r8d, 1
    xor     r9d, r9d                ; flags
.flag_loop:
    cmp     r8d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r8*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done
    inc     rdi
.fchar:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .fnext
    cmp     al, 'a'
    je      .fa
    cmp     al, 's'
    je      .fs
    cmp     al, 'n'
    je      .fn
    cmp     al, 'r'
    je      .fr
    cmp     al, 'v'
    je      .fv
    cmp     al, 'm'
    je      .fm
    jmp     .flags_done
.fa: or r9d, FLAG_ALL
     inc rdi
     jmp .fchar
.fs: or r9d, FLAG_S
     inc rdi
     jmp .fchar
.fn: or r9d, FLAG_N
     inc rdi
     jmp .fchar
.fr: or r9d, FLAG_R
     inc rdi
     jmp .fchar
.fv: or r9d, FLAG_V
     inc rdi
     jmp .fchar
.fm: or r9d, FLAG_M
     inc rdi
     jmp .fchar
.fnext:
    inc     r8d
    jmp     .flag_loop

.flags_done:
    test    r9d, r9d
    jnz     .have_flags
    mov     r9d, FLAG_S             ; default → sysname only
.have_flags:

    ; uname syscall.
    mov     eax, SYS_uname
    lea     rdi, [rel uname_buf]
    syscall
    test    rax, rax
    js      .err

    ; Emit each requested field, space-separated.
    xor     ecx, ecx                ; "have emitted any" tracker

    test    r9d, FLAG_S
    jz      .skip_s
    test    ecx, ecx
    jnz     .pre_space_s
    jmp     .emit_s
.pre_space_s:
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.emit_s:
    lea     rdi, [rel uname_buf + 0*UTS_LEN]
    call    emit_field
    mov     ecx, 1
.skip_s:

    test    r9d, FLAG_N
    jz      .skip_n
    test    ecx, ecx
    jnz     .pre_space_n
    jmp     .emit_n
.pre_space_n:
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.emit_n:
    lea     rdi, [rel uname_buf + 1*UTS_LEN]
    call    emit_field
    mov     ecx, 1
.skip_n:

    test    r9d, FLAG_R
    jz      .skip_r
    test    ecx, ecx
    jnz     .pre_space_r
    jmp     .emit_r
.pre_space_r:
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.emit_r:
    lea     rdi, [rel uname_buf + 2*UTS_LEN]
    call    emit_field
    mov     ecx, 1
.skip_r:

    test    r9d, FLAG_V
    jz      .skip_v
    test    ecx, ecx
    jnz     .pre_space_v
    jmp     .emit_v
.pre_space_v:
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.emit_v:
    lea     rdi, [rel uname_buf + 3*UTS_LEN]
    call    emit_field
    mov     ecx, 1
.skip_v:

    test    r9d, FLAG_M
    jz      .skip_m
    test    ecx, ecx
    jnz     .pre_space_m
    jmp     .emit_m
.pre_space_m:
    mov     edi, STDOUT_FILENO
    mov     esi, ' '
    call    putc
.emit_m:
    lea     rdi, [rel uname_buf + 4*UTS_LEN]
    call    emit_field
.skip_m:

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    xor     eax, eax
    jmp     .ret

.err:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_uname]
    mov     edx, err_uname_len
    syscall
    mov     eax, 1

.ret:
    pop     rbp
    pop     rbx
    ret

; emit_field(rdi /buf/) — writes the NUL-terminated string at buf to stdout.
emit_field:
    push    rbx
    mov     rbx, rdi
    call    strlen
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rbx
    call    write_all
    pop     rbx
    ret
