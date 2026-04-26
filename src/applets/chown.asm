; chown.asm — change file owner / group.
;
;   chown UID         FILE...
;   chown UID:GID     FILE...
;   chown :GID        FILE...
;
; v1 accepts numeric UID/GID only — name resolution requires reading
; /etc/passwd and /etc/group, which is its own change. -R (recursive) is
; deferred alongside the directory walker that will land with rm -r.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern parse_uint
extern perror_path

global applet_chown_main

%define KEEP_ID 0xFFFFFFFF          ; passing -1 to chown leaves that id alone

section .rodata
err_missing:     db "chown: missing operand", 10
err_missing_len: equ $ - err_missing
err_bad_id:      db "chown: invalid user/group spec", 10
err_bad_id_len:  equ $ - err_bad_id
prefix_chown:    db "chown", 0

section .text

; int applet_chown_main(int argc /edi/, char **argv /rsi/)
applet_chown_main:
    push    rbx
    push    rbp
    push    r12                     ; uid (32-bit, low half live)
    push    r13                     ; gid
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d

    cmp     ebx, 3
    jl      .missing

    sub     rsp, 16                 ; scratch for parse_uint outputs
    mov     rdi, [rbp + 1*8]
    lea     rsi, [rsp]
    call    parse_owner
    test    eax, eax
    jnz     .bad_id
    mov     r12, [rsp]              ; uid
    mov     r13, [rsp + 8]          ; gid
    add     rsp, 16

    mov     ecx, 2
.loop:
    cmp     ecx, ebx
    jge     .out

    push    rcx
    sub     rsp, 8
    mov     eax, SYS_chown
    mov     rdi, [rbp + rcx*8]
    mov     esi, r12d
    mov     edx, r13d
    syscall
    add     rsp, 8
    pop     rcx
    test    rax, rax
    jns     .next

    push    rcx
    sub     rsp, 8
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_chown]
    mov     rsi, [rbp + rcx*8]
    call    perror_path
    add     rsp, 8
    pop     rcx
    mov     r14d, 1
.next:
    inc     ecx
    jmp     .loop

.bad_id:
    add     rsp, 16
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_bad_id]
    mov     edx, err_bad_id_len
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
; parse_owner(s /rdi/, out /rsi/) -> rax
;
;   Parses a "UID[:GID]" or ":GID" specification. Writes uid to *rsi and
;   gid to *(rsi+8). For an unset side, writes 0xFFFFFFFF — the kernel
;   sentinel for "leave this id alone" in chown(2).
;
;   Returns 0 on success, -1 on malformed input.
parse_owner:
    push    rbx
    push    r12
    push    r13                     ; (alignment)

    mov     rbx, rdi                ; pointer to spec
    mov     r12, rsi                ; output

    mov     dword [r12],     KEEP_ID
    mov     dword [r12 + 4], 0
    mov     dword [r12 + 8], KEEP_ID
    mov     dword [r12 + 12], 0

    cmp     byte [rbx], ':'
    je      .group_only

    ; Parse uid up to ':' or NUL.
    mov     rdi, rbx
    mov     rsi, r12
    call    parse_uint_until
    test    eax, eax
    jnz     .bad
    mov     al, [rcx]
    test    al, al
    jz      .ok
    cmp     al, ':'
    jne     .bad
    lea     rbx, [rcx + 1]
    jmp     .parse_gid

.group_only:
    inc     rbx                     ; skip ':'

.parse_gid:
    cmp     byte [rbx], 0
    je      .ok                     ; "uid:" with empty gid → keep gid
    lea     rsi, [r12 + 8]
    mov     rdi, rbx
    call    parse_uint_until
    test    eax, eax
    jnz     .bad
    cmp     byte [rcx], 0
    jne     .bad

.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; parse_uint_until(s /rdi/, *out /rsi/) -> rax (0 ok, -1 if no digits)
;
; Like parse_uint but also returns the stop pointer in rcx so the caller
; can examine the delimiter.
parse_uint_until:
    xor     eax, eax
    xor     ecx, ecx
    mov     r8, rdi
.loop:
    movzx   edx, byte [rdi]
    sub     edx, '0'
    cmp     edx, 9
    ja      .done
    imul    rax, rax, 10
    add     rax, rdx
    inc     rdi
    inc     rcx
    jmp     .loop
.done:
    test    rcx, rcx
    jz      .empty
    mov     [rsi], rax
    mov     rcx, rdi                ; stop pointer
    xor     eax, eax
    ret
.empty:
    mov     eax, -1
    ret
