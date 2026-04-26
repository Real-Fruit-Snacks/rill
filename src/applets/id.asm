; id.asm — print user / group identity.
;
;   id              uid=N(name) gid=N(name)
;   id -u           N
;   id -g           N
;   id -un          name
;   id -gn          name
;
; v1 prints uid + primary gid. groups (-G), real-vs-effective separation,
; and id of OTHER users (id <NAME>) are deferred.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern streq
extern format_uint
extern uid_to_name
extern gid_to_name
extern write_all
extern write_cstr
extern putc

global applet_id_main

%define MODE_FULL  0
%define MODE_UID   1
%define MODE_GID   2

section .bss
align 16
id_namebuf: resb 64
id_numbuf:  resb 32

section .rodata
opt_u:        db "-u", 0
opt_g:        db "-g", 0
opt_n:        db "-n", 0
opt_un:       db "-un", 0
opt_nu:       db "-nu", 0
opt_gn:       db "-gn", 0
opt_ng:       db "-ng", 0
err_unsupported: db "id: only -u, -g, -un, -gn supported in this build", 10
err_unsupported_len: equ $ - err_unsupported
lbl_uid:      db "uid=", 0
lbl_gid:      db " gid=", 0

section .text

applet_id_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     ebx, edi
    mov     rbp, rsi
    mov     r12d, MODE_FULL
    xor     r13d, r13d              ; want_name (only when -un / -gn)

    cmp     ebx, 1
    jle     .dispatch

    mov     rdi, [rbp + 1*8]
    lea     rsi, [rel opt_u]
    call    streq
    test    eax, eax
    jnz     .pick_u
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rel opt_g]
    call    streq
    test    eax, eax
    jnz     .pick_g
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rel opt_un]
    call    streq
    test    eax, eax
    jnz     .pick_un
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rel opt_nu]
    call    streq
    test    eax, eax
    jnz     .pick_un
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rel opt_gn]
    call    streq
    test    eax, eax
    jnz     .pick_gn
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rel opt_ng]
    call    streq
    test    eax, eax
    jnz     .pick_gn
    jmp     .unsupported

.pick_u:  mov r12d, MODE_UID
          jmp .dispatch
.pick_g:  mov r12d, MODE_GID
          jmp .dispatch
.pick_un: mov r12d, MODE_UID
          mov r13d, 1
          jmp .dispatch
.pick_gn: mov r12d, MODE_GID
          mov r13d, 1

.dispatch:
    cmp     r12d, MODE_UID
    je      .one_uid
    cmp     r12d, MODE_GID
    je      .one_gid

    ; Full form: uid=N(name) gid=N(name)
    mov     eax, SYS_getuid
    syscall
    mov     r14d, eax

    mov     edi, STDOUT_FILENO
    lea     rsi, [rel lbl_uid]
    call    write_cstr

    mov     rdi, r14
    call    emit_num

    mov     edi, STDOUT_FILENO
    mov     esi, '('
    call    putc

    mov     edi, r14d
    lea     rsi, [rel id_namebuf]
    mov     edx, 64
    call    uid_to_name
    test    rax, rax
    jnz     .have_uname
    mov     rax, 7                  ; literal "unknown"
    lea     rsi, [rel literal_unknown]
    jmp     .emit_uname
.have_uname:
    lea     rsi, [rel id_namebuf]
.emit_uname:
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    call    write_all

    mov     edi, STDOUT_FILENO
    mov     esi, ')'
    call    putc

    mov     edi, STDOUT_FILENO
    lea     rsi, [rel lbl_gid]
    call    write_cstr

    mov     eax, SYS_getgid
    syscall
    mov     r14d, eax

    mov     rdi, r14
    call    emit_num

    mov     edi, STDOUT_FILENO
    mov     esi, '('
    call    putc

    mov     edi, r14d
    lea     rsi, [rel id_namebuf]
    mov     edx, 64
    call    gid_to_name
    test    rax, rax
    jnz     .have_gname
    mov     rax, 7
    lea     rsi, [rel literal_unknown]
    jmp     .emit_gname
.have_gname:
    lea     rsi, [rel id_namebuf]
.emit_gname:
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    call    write_all

    mov     edi, STDOUT_FILENO
    mov     esi, ')'
    call    putc

    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    xor     eax, eax
    jmp     .out

.one_uid:
    mov     eax, SYS_getuid
    syscall
    test    r13d, r13d
    jnz     .one_uid_named
    mov     edi, eax
    call    emit_num
    jmp     .out_nl

.one_uid_named:
    mov     edi, eax
    lea     rsi, [rel id_namebuf]
    mov     edx, 64
    call    uid_to_name
    test    rax, rax
    jz      .one_uid_fallback
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel id_namebuf]
    call    write_all
    jmp     .out_nl
.one_uid_fallback:
    mov     eax, SYS_getuid
    syscall
    mov     edi, eax
    call    emit_num
    jmp     .out_nl

.one_gid:
    mov     eax, SYS_getgid
    syscall
    test    r13d, r13d
    jnz     .one_gid_named
    mov     edi, eax
    call    emit_num
    jmp     .out_nl

.one_gid_named:
    mov     edi, eax
    lea     rsi, [rel id_namebuf]
    mov     edx, 64
    call    gid_to_name
    test    rax, rax
    jz      .one_gid_fallback
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel id_namebuf]
    call    write_all
    jmp     .out_nl
.one_gid_fallback:
    mov     eax, SYS_getgid
    syscall
    mov     edi, eax
    call    emit_num

.out_nl:
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    xor     eax, eax
    jmp     .out

.unsupported:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_unsupported]
    mov     edx, err_unsupported_len
    syscall
    mov     eax, 1

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; emit_num(rdi /val/) — writes val as decimal to stdout.
emit_num:
    sub     rsp, 32
    mov     rsi, rsp
    call    format_uint
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 32
    ret

section .rodata
literal_unknown: db "unknown"
