; ps.asm — list running processes by reading /proc.
;
;   ps
;
; v1 lists every process as "  PID CMD" — no flags wired up. /proc/[pid]/
; comm provides the command name (kernel-truncated to 15 chars). The full
; argv (-f), tty filtering (default ps without -e), or the BSD `ps aux`
; columns are deferred. Threads (subdirs of /proc/[pid]/task) aren't shown.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern format_uint_pad
extern read_buf
extern write_all
extern write_cstr
extern putc

global applet_ps_main

%define D_RECLEN 16
%define D_NAME   19
%define PS_GETDENTS_BUF_LEN 65536

section .bss
align 16
ps_path: resb 64
ps_comm: resb 256
ps_outbuf: resb 4096
ps_outpos: resq 1

section .rodata
proc_path:    db "/proc", 0
header:       db "  PID CMD", 10
header_len:   equ $ - header
proc_prefix:  db "/proc/", 0
comm_suffix:  db "/comm", 0

section .text

applet_ps_main:
    push    rbx                     ; fd
    push    rbp                     ; (alignment)
    push    r12                     ; (alignment)
    push    r13                     ; (alignment)
    push    r14                     ; (alignment)
    sub     rsp, PS_GETDENTS_BUF_LEN

    mov     qword [rel ps_outpos], 0

    ; Header.
    mov     eax, SYS_write
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel header]
    mov     edx, header_len
    syscall

    ; Open /proc.
    mov     eax, SYS_open
    lea     rdi, [rel proc_path]
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .err
    mov     ebx, eax

.read_loop:
    mov     eax, SYS_getdents64
    mov     edi, ebx
    mov     rsi, rsp
    mov     edx, PS_GETDENTS_BUF_LEN
    syscall
    test    rax, rax
    jz      .close
    js      .read_err

    mov     rcx, rax
    xor     r9, r9
.iter:
    cmp     r9, rcx
    jge     .read_loop

    lea     rdi, [rsp + r9]
    movzx   edx, word [rdi + D_RECLEN]
    lea     rsi, [rdi + D_NAME]

    push    rcx
    push    r9
    push    rdx
    sub     rsp, 8
    call    is_all_digits
    add     rsp, 8
    pop     rdx
    pop     r9
    pop     rcx
    test    eax, eax
    jz      .next

    lea     rdi, [rsp + r9]
    add     rdi, D_NAME             ; d_name pointer
    push    rcx
    push    r9
    push    rdx
    sub     rsp, 8
    call    print_proc
    add     rsp, 8
    pop     rdx
    pop     r9
    pop     rcx

.next:
    add     r9, rdx
    jmp     .iter

.read_err:
.close:
    push    rax
    sub     rsp, 8
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
    add     rsp, 8
    pop     rax

.cleanup:
    call    flush_out
    add     rsp, PS_GETDENTS_BUF_LEN
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    xor     eax, eax
    ret

.err:
    add     rsp, PS_GETDENTS_BUF_LEN
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; is_all_digits(s /rsi/) -> rax (1 if non-empty and all digits, 0 else)
is_all_digits:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .no
.loop:
    cmp     eax, '0'
    jb      .no
    cmp     eax, '9'
    ja      .no
    inc     rsi
    movzx   eax, byte [rsi]
    test    eax, eax
    jnz     .loop
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; print_proc(name /rdi/) — emits "  PID CMD\n" for the given pid string.
print_proc:
    push    rbx                     ; pid string ptr
    push    rbp                     ; pid string length
    push    r12                     ; (alignment)

    mov     rbx, rdi
    xor     rbp, rbp
.measure:
    cmp     byte [rbx + rbp], 0
    je      .have_len
    inc     rbp
    jmp     .measure
.have_len:

    ; PID column: right-aligned in 5 chars. Pad with spaces.
    mov     rcx, 5
    cmp     rbp, rcx
    jge     .no_pad
    sub     rcx, rbp
.pad:
    test    rcx, rcx
    jz      .no_pad
    mov     al, ' '
    push    rcx                     ; emit_byte clobbers rcx (caller-saved)
    call    emit_byte
    pop     rcx
    dec     rcx
    jmp     .pad
.no_pad:

    mov     rdi, rbx
    call    emit_cstr

    mov     al, ' '
    call    emit_byte

    ; Build /proc/<pid>/comm path.
    lea     rdi, [rel ps_path]
    mov     byte [rdi + 0], '/'
    mov     byte [rdi + 1], 'p'
    mov     byte [rdi + 2], 'r'
    mov     byte [rdi + 3], 'o'
    mov     byte [rdi + 4], 'c'
    mov     byte [rdi + 5], '/'
    mov     rsi, rbx
    mov     rcx, 6
.copy_pid:
    mov     al, [rsi]
    test    al, al
    jz      .copy_pid_done
    mov     [rdi + rcx], al
    inc     rcx
    inc     rsi
    jmp     .copy_pid
.copy_pid_done:
    mov     byte [rdi + rcx], '/'
    inc     rcx
    mov     byte [rdi + rcx], 'c'
    inc     rcx
    mov     byte [rdi + rcx], 'o'
    inc     rcx
    mov     byte [rdi + rcx], 'm'
    inc     rcx
    mov     byte [rdi + rcx], 'm'
    inc     rcx
    mov     byte [rdi + rcx], 0

    ; Open + read /proc/<pid>/comm.
    mov     eax, SYS_open
    lea     rdi, [rel ps_path]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .no_comm
    mov     r12d, eax

    mov     edi, r12d
    lea     rsi, [rel ps_comm]
    mov     edx, 256
    call    read_buf

    push    rax
    sub     rsp, 8
    mov     eax, SYS_close
    mov     edi, r12d
    syscall
    add     rsp, 8
    pop     rax

    test    rax, rax
    jle     .no_comm

    ; Strip trailing newline.
    lea     rdx, [rel ps_comm]
    add     rdx, rax
    cmp     byte [rdx - 1], 10
    jne     .have_comm
    dec     rax
.have_comm:
    test    rax, rax
    jz      .no_comm
    push    rax
    sub     rsp, 8
    lea     rdi, [rel ps_comm]
    call    emit_buf
    add     rsp, 8
    pop     rax
    jmp     .nl

.no_comm:
    mov     al, '?'
    call    emit_byte

.nl:
    mov     al, 10
    call    emit_byte

    pop     r12
    pop     rbp
    pop     rbx
    ret

; emit_buf(buf /rdi/, len /rax/) — wrapper passing rax as count.
emit_buf:
    push    rbx
    push    rbp
    mov     rbx, rdi
    mov     rbp, rax
    xor     ecx, ecx
.loop:
    cmp     rcx, rbp
    jge     .done
    mov     al, [rbx + rcx]
    push    rcx
    call    emit_byte
    pop     rcx
    inc     rcx
    jmp     .loop
.done:
    pop     rbp
    pop     rbx
    ret

emit_cstr:
    push    rbx
    mov     rbx, rdi
.loop:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .done
    push    rbx
    sub     rsp, 8
    call    emit_byte
    add     rsp, 8
    pop     rbx
    inc     rbx
    jmp     .loop
.done:
    pop     rbx
    ret

emit_byte:
    push    rax
    mov     rcx, [rel ps_outpos]
    cmp     rcx, 4096
    jl      .room
    call    flush_out
    mov     rcx, [rel ps_outpos]
.room:
    pop     rax
    lea     r8, [rel ps_outbuf]
    mov     [r8 + rcx], al
    inc     rcx
    mov     [rel ps_outpos], rcx
    ret

flush_out:
    mov     rcx, [rel ps_outpos]
    test    rcx, rcx
    jz      .done
    sub     rsp, 8
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel ps_outbuf]
    mov     rdx, rcx
    call    write_all
    add     rsp, 8
    mov     qword [rel ps_outpos], 0
.done:
    ret
