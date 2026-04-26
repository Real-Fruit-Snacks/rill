; ls.asm — list directory contents (or a file's name).
;
;   ls [-a] [PATH...]
;
; v1 prints one entry per line, sorted by byte-wise name. -a includes
; dotfiles. Long-form (-l), recursion (-R), human sizes (-h), and
; classification (-F) are all deferred — each needs runtime support
; (date formatting, name resolution, directory walker) we don't yet have.
;
; Buffering:
;   - 1 MB getdents64 accumulator (single contiguous spliced buffer)
;   - 16384-entry pointer array
; Both fit easily in .bss. A directory whose entry data exceeds 1 MB
; produces a clear error rather than silent truncation.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern streq
extern str_lt
extern isort_strs
extern is_directory
extern write_cstr
extern putc
extern perror_path

global applet_ls_main

%define DIRENT_BUF_BYTES 1048576
%define MAX_ENTRIES      16384

%define D_RECLEN 16
%define D_NAME   19

section .bss
align 16
ls_dirent_buf:  resb DIRENT_BUF_BYTES
ls_name_ptrs:   resq MAX_ENTRIES
ls_statbuf:     resb STATBUF_SIZE
ls_show_hidden: resb 1

section .rodata
opt_a:        db "-a", 0
prefix_ls:    db "ls", 0
dot_path:     db ".", 0
err_overflow: db "ls: directory too large for in-memory buffer", 10
err_overflow_len: equ $ - err_overflow

section .text

; int applet_ls_main(int argc /edi/, char **argv /rsi/)
;
; Register usage:
;   rbx  argc
;   rbp  argv
;   r12  first-operand index
;   r13  operand count (argc - first_op_index)
;   r14  rc
;   r15  current path index
applet_ls_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                  ; align to 16 for nested calls

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d
    mov     byte [rel ls_show_hidden], 0

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done
    lea     rsi, [rel opt_a]
    call    streq
    test    eax, eax
    jz      .flags_done
    mov     byte [rel ls_show_hidden], 1
    inc     r12d
    jmp     .flag_loop

.flags_done:
    mov     r13d, ebx
    sub     r13d, r12d

    test    r13d, r13d
    jnz     .with_paths

    ; No operands → "."
    lea     rdi, [rel dot_path]
    xor     ecx, ecx                ; no header
    call    list_one
    mov     r14d, eax
    jmp     .out

.with_paths:
    mov     r15d, r12d
.path_loop:
    cmp     r15d, ebx
    jge     .out

    ; Blank line between sections (skip before the first).
    cmp     r15d, r12d
    je      .no_sep
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
.no_sep:

    ; Header only when more than one operand.
    xor     ecx, ecx
    cmp     r13d, 1
    jle     .call_list
    mov     ecx, 1
.call_list:
    mov     rdi, [rbp + r15*8]
    call    list_one
    test    eax, eax
    jz      .next
    mov     r14d, 1
.next:
    inc     r15d
    jmp     .path_loop

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

; ---------------------------------------------------------------------------
; list_one(path /rdi/, want_header /ecx/) -> rax = 0 or 1
;
; If path is a directory, lists its contents (sorted, one per line). If
; it's a file or anything else, prints just the path. With want_header
; non-zero AND path is a directory, prints "<path>:\n" first.
list_one:
    push    rbx                     ; saved path
    push    rbp                     ; want_header
    push    r12                     ; (alignment)

    mov     rbx, rdi
    mov     ebp, ecx

    mov     rdi, rbx
    lea     rsi, [rel ls_statbuf]
    call    is_directory
    test    eax, eax
    js      .stat_err
    test    eax, eax
    jz      .as_file

    ; Directory: optional header, then open + list.
    test    ebp, ebp
    jz      .open
    mov     edi, STDOUT_FILENO
    mov     rsi, rbx
    call    write_cstr
    mov     edi, STDOUT_FILENO
    mov     esi, ':'
    call    putc
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

.open:
    mov     eax, SYS_open
    mov     rdi, rbx
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .open_err

    mov     edi, eax
    mov     rsi, rbx
    call    list_dir_fd
    jmp     .ret

.as_file:
    mov     edi, STDOUT_FILENO
    mov     rsi, rbx
    call    write_cstr
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    xor     eax, eax
    jmp     .ret

.stat_err:
.open_err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_ls]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1

.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; list_dir_fd(fd /edi/, path /rsi/) -> rax = 0 or 1
;
; Reads all entries via getdents64 into ls_dirent_buf, builds the pointer
; array (filtering dotfiles unless ls_show_hidden), sorts, prints. Closes
; fd before returning. path is used only for error messages.
list_dir_fd:
    push    rbx                     ; fd
    push    rbp                     ; total bytes
    push    r12                     ; ptr count
    push    r13                     ; cursor / printer
    push    r14                     ; saved path

    mov     ebx, edi
    mov     r14, rsi
    xor     ebp, ebp

.read_loop:
    mov     eax, DIRENT_BUF_BYTES
    sub     eax, ebp
    test    eax, eax
    jz      .overflow
    mov     edx, eax
    mov     eax, SYS_getdents64
    mov     edi, ebx
    lea     rsi, [rel ls_dirent_buf]
    add     rsi, rbp
    syscall
    test    rax, rax
    js      .read_err
    jz      .read_done
    add     rbp, rax
    jmp     .read_loop

.read_done:
    mov     eax, SYS_close
    mov     edi, ebx
    syscall

    xor     r12d, r12d
    xor     r13, r13
.walk:
    cmp     r13, rbp
    jge     .walk_done

    lea     rdi, [rel ls_dirent_buf]
    add     rdi, r13
    movzx   ecx, word [rdi + D_RECLEN]
    lea     rsi, [rdi + D_NAME]

    ; Filter dotfiles unless -a.
    cmp     byte [rsi], '.'
    jne     .keep
    mov     al, [rel ls_show_hidden]
    test    al, al
    jnz     .keep
    add     r13, rcx
    jmp     .walk

.keep:
    cmp     r12d, MAX_ENTRIES
    jge     .overflow_after_close
    mov     [rel ls_name_ptrs + r12*8], rsi
    inc     r12d
    add     r13, rcx
    jmp     .walk

.walk_done:
    test    r12d, r12d
    jz      .ok

    lea     rdi, [rel ls_name_ptrs]
    movsxd  rsi, r12d
    call    isort_strs

    xor     r13d, r13d
.print:
    cmp     r13d, r12d
    jge     .ok
    mov     edi, STDOUT_FILENO
    mov     rsi, [rel ls_name_ptrs + r13*8]
    call    write_cstr
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    inc     r13d
    jmp     .print

.ok:
    xor     eax, eax
    jmp     .ret

.overflow:
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
.overflow_after_close:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [rel err_overflow]
    mov     edx, err_overflow_len
    syscall
    mov     eax, 1
    jmp     .ret

.read_err:
    mov     r13d, eax               ; preserve -errno across close
    mov     eax, SYS_close
    mov     edi, ebx
    syscall
    mov     eax, r13d
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_ls]
    mov     rsi, r14
    call    perror_path
    mov     eax, 1

.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
