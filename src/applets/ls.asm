; ls.asm — list directory contents (or a single path) in short or long form.
;
;   ls [-a] [-l] [PATH...]
;
; Flags:
;   -a   include dotfiles
;   -l   long format: <perms> <nlinks> <uid> <gid> <size> <date> <name>
;
; Long format prints uid/gid as numbers (no name resolution), uses fixed
; column widths (3/5/5/8), and always renders mtime as "Mon DD HH:MM"
; regardless of age. Recent-vs-old date split, owner/group name lookup,
; and width auto-sizing land later.
;
; Buffers (.bss):
;   ls_dirent_buf   1 MB — getdents64 accumulator (single contiguous run)
;   ls_name_ptrs    16384 entries (128 KB) — sortable pointers
;   ls_full_path    4096 — building "<dir>/<name>" for lstat
;   ls_line_buf     4160 — assembled long-form line before write
;   ls_statbuf      144  — per-entry lstat scratch

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern streq
extern strlen
extern str_lt
extern isort_strs
extern is_directory
extern format_mode
extern format_uint
extern format_uint_pad
extern format_date
extern uid_to_name
extern gid_to_name
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_ls_main

%define DIRENT_BUF_BYTES 1048576
%define MAX_ENTRIES      16384
%define LINE_BUF_BYTES   4160
%define PATH_BUF_BYTES   4096

%define D_RECLEN 16
%define D_NAME   19

section .bss
align 16
ls_dirent_buf:   resb DIRENT_BUF_BYTES
ls_name_ptrs:    resq MAX_ENTRIES
ls_statbuf:      resb STATBUF_SIZE
ls_full_path:    resb PATH_BUF_BYTES
ls_line_buf:     resb LINE_BUF_BYTES
ls_show_hidden:  resb 1
ls_long_form:    resb 1

section .rodata
opt_a:        db "-a", 0
opt_l:        db "-l", 0
opt_la:       db "-la", 0
opt_al:       db "-al", 0
prefix_ls:    db "ls", 0
dot_path:     db ".", 0
err_overflow: db "ls: directory too large for in-memory buffer", 10
err_overflow_len: equ $ - err_overflow

section .text

; int applet_ls_main(int argc /edi/, char **argv /rsi/)
;
; Register usage (callee-saved across nested calls):
;   rbx  argc
;   rbp  argv
;   r12  first-operand index
;   r13  operand count
;   r14  rc
;   r15  current path index
applet_ls_main:
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
    mov     byte [rel ls_show_hidden], 0
    mov     byte [rel ls_long_form], 0

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
    jnz     .set_a
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_l]
    call    streq
    test    eax, eax
    jnz     .set_l
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_la]
    call    streq
    test    eax, eax
    jnz     .set_al
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_al]
    call    streq
    test    eax, eax
    jnz     .set_al
    jmp     .flags_done

.set_a:
    mov     byte [rel ls_show_hidden], 1
    inc     r12d
    jmp     .flag_loop
.set_l:
    mov     byte [rel ls_long_form], 1
    inc     r12d
    jmp     .flag_loop
.set_al:
    mov     byte [rel ls_show_hidden], 1
    mov     byte [rel ls_long_form], 1
    inc     r12d
    jmp     .flag_loop

.flags_done:
    mov     r13d, ebx
    sub     r13d, r12d

    test    r13d, r13d
    jnz     .with_paths

    lea     rdi, [rel dot_path]
    xor     ecx, ecx
    call    list_one
    mov     r14d, eax
    jmp     .out

.with_paths:
    mov     r15d, r12d
.path_loop:
    cmp     r15d, ebx
    jge     .out

    cmp     r15d, r12d
    je      .no_sep
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
.no_sep:

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
    js      .err
    test    eax, eax
    jz      .as_file

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
    js      .err

    mov     edi, eax
    mov     rsi, rbx
    call    list_dir_fd
    jmp     .ret

.as_file:
    ; In long form, lstat already happened (via is_directory we got mode
    ; only for type test). Re-stat with lstat for full info.
    cmp     byte [rel ls_long_form], 0
    je      .file_short

    mov     eax, SYS_lstat
    mov     rdi, rbx
    lea     rsi, [rel ls_statbuf]
    syscall
    test    rax, rax
    js      .err

    mov     rdi, rbx
    lea     rsi, [rel ls_statbuf]
    lea     rdx, [rel ls_line_buf]
    call    format_long_line        ; rax = bytes written
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel ls_line_buf]
    call    write_all
    xor     eax, eax
    jmp     .ret

.file_short:
    mov     edi, STDOUT_FILENO
    mov     rsi, rbx
    call    write_cstr
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc
    xor     eax, eax
    jmp     .ret

.err:
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
; list_dir_fd(fd /edi/, dir_path /rsi/) -> rax = 0 or 1
list_dir_fd:
    push    rbx                     ; fd
    push    rbp                     ; total bytes from getdents
    push    r12                     ; ptr count
    push    r13                     ; cursor / printer
    push    r14                     ; saved dir_path
    push    r15                     ; path-prefix length (where to append name)
    sub     rsp, 8                  ; align

    mov     ebx, edi
    mov     r14, rsi
    xor     ebp, ebp

    ; Build ls_full_path = "<dir_path>/"  (used to lstat each entry)
    lea     rdi, [rel ls_full_path]
    mov     rsi, r14
.copy_dir:
    mov     al, [rsi]
    test    al, al
    jz      .copy_dir_done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .copy_dir
.copy_dir_done:
    ; Avoid duplicate slash if dir_path already ends with '/'.
    lea     rcx, [rel ls_full_path]
    cmp     rdi, rcx
    je      .add_slash              ; empty path → still need '/'
    cmp     byte [rdi - 1], '/'
    je      .no_slash
.add_slash:
    mov     byte [rdi], '/'
    inc     rdi
.no_slash:
    lea     rcx, [rel ls_full_path]
    mov     r15, rdi
    sub     r15, rcx                ; r15 = path-prefix length

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

    cmp     byte [rel ls_long_form], 0
    je      .print_short

    ; Long: lstat full_path then format_long_line.
    mov     rsi, [rel ls_name_ptrs + r13*8]
    lea     rdi, [rel ls_full_path]
    add     rdi, r15
.append_name:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .stat_now
    inc     rdi
    inc     rsi
    jmp     .append_name
.stat_now:
    mov     eax, SYS_lstat
    lea     rdi, [rel ls_full_path]
    lea     rsi, [rel ls_statbuf]
    syscall
    test    rax, rax
    js      .skip_entry             ; surface as silently-skipped; uncommon

    mov     rdi, [rel ls_name_ptrs + r13*8]
    lea     rsi, [rel ls_statbuf]
    lea     rdx, [rel ls_line_buf]
    call    format_long_line
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel ls_line_buf]
    call    write_all
.skip_entry:
    inc     r13d
    jmp     .print

.print_short:
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
    mov     r13d, eax
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
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; format_long_line(name /rdi/, statbuf /rsi/, out /rdx/) -> rax = bytes
;
;   Layout: "<perms> <nlinks 3> <uid 5> <gid 5> <size 8> <date 12> <name>\n"
;
;   Stack: 4 pushes + sub 8 = 40 bytes = 8 mod 16; from entry 8 + 8 = 0
;   mod 16 at internal call sites.
format_long_line:
    push    rbx                     ; out cursor
    push    rbp                     ; statbuf
    push    r12                     ; saved name
    push    r13                     ; out start
    sub     rsp, 8

    mov     r12, rdi
    mov     rbp, rsi
    mov     rbx, rdx
    mov     r13, rdx

    mov     edi, [rbp + ST_MODE]
    mov     rsi, rbx
    call    format_mode
    add     rbx, 10
    mov     byte [rbx], ' '
    inc     rbx

    mov     rdi, [rbp + ST_NLINK]
    mov     rsi, rbx
    mov     rdx, 3
    call    format_uint_pad
    add     rbx, rax
    mov     byte [rbx], ' '
    inc     rbx

    mov     edi, [rbp + ST_UID]
    mov     rsi, rbx
    mov     rdx, 8
    call    format_owner_field
    add     rbx, rax
    mov     byte [rbx], ' '
    inc     rbx

    mov     edi, [rbp + ST_GID]
    mov     rsi, rbx
    mov     rdx, 8
    call    format_group_field
    add     rbx, rax
    mov     byte [rbx], ' '
    inc     rbx

    mov     rdi, [rbp + ST_SIZE]
    mov     rsi, rbx
    mov     rdx, 8
    call    format_uint_pad
    add     rbx, rax
    mov     byte [rbx], ' '
    inc     rbx

    mov     rdi, [rbp + ST_MTIME]
    mov     rsi, rbx
    call    format_date
    add     rbx, 12
    mov     byte [rbx], ' '
    inc     rbx

.copy_name:
    mov     al, [r12]
    test    al, al
    jz      .terminate
    mov     [rbx], al
    inc     rbx
    inc     r12
    jmp     .copy_name

.terminate:
    mov     byte [rbx], 10
    inc     rbx
    mov     rax, rbx
    sub     rax, r13

    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; format_owner_field / format_group_field — write a username/groupname
; (or numeric fallback) into `buf`, left-aligned and space-padded to
; `width`. Returns total bytes written (max(width, len)).
;
; Stack: 3 pushes + sub 32 = 56 bytes = 8 mod 16; from entry's 8 mod 16,
; rsp at the inner call is 0 mod 16.
format_owner_field:
    push    rbx                     ; id
    push    rbp                     ; out buf
    push    r12                     ; width
    sub     rsp, 32                 ; scratch for name/digits

    mov     ebx, edi
    mov     rbp, rsi
    mov     r12, rdx

    mov     edi, ebx
    mov     rsi, rsp
    mov     edx, 32
    call    uid_to_name
    test    rax, rax
    jnz     .write

    mov     edi, ebx
    mov     rsi, rsp
    call    format_uint

.write:
    mov     r9, rax                 ; val_len
    mov     rdi, rbp
    mov     rsi, rsp
    mov     rcx, rax
    rep     movsb

    cmp     r9, r12
    jge     .done

    mov     rcx, r12
    sub     rcx, r9
    mov     al, ' '
    rep     stosb
    mov     rax, r12
    jmp     .ret
.done:
    mov     rax, r9
.ret:
    add     rsp, 32
    pop     r12
    pop     rbp
    pop     rbx
    ret

format_group_field:
    push    rbx
    push    rbp
    push    r12
    sub     rsp, 32

    mov     ebx, edi
    mov     rbp, rsi
    mov     r12, rdx

    mov     edi, ebx
    mov     rsi, rsp
    mov     edx, 32
    call    gid_to_name
    test    rax, rax
    jnz     .write

    mov     edi, ebx
    mov     rsi, rsp
    call    format_uint

.write:
    mov     r9, rax
    mov     rdi, rbp
    mov     rsi, rsp
    mov     rcx, rax
    rep     movsb

    cmp     r9, r12
    jge     .done

    mov     rcx, r12
    sub     rcx, r9
    mov     al, ' '
    rep     stosb
    mov     rax, r12
    jmp     .ret
.done:
    mov     rax, r9
.ret:
    add     rsp, 32
    pop     r12
    pop     rbp
    pop     rbx
    ret
