; stat.asm — print file metadata.
;
;   stat PATH...
;
; v1 prints a fixed key:value-per-line layout. This isn't byte-for-byte
; with coreutils' multi-line block format (which is wider than 80 cols and
; embeds calendar dates we don't yet format) — that lands once core/time
; arrives in phase 3c. The fields shipped here are sufficient for scripts
; that grep specific keys.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"

extern format_uint
extern format_octal
extern format_date
extern uid_to_name
extern gid_to_name
extern write_all
extern write_cstr
extern putc
extern perror_path

global applet_stat_main

section .bss
align 16
stat_buf: resb STATBUF_SIZE

section .rodata
err_missing:     db "stat: missing operand", 10
err_missing_len: equ $ - err_missing
prefix_stat:     db "stat", 0

lbl_file:  db "  File: ", 0
lbl_size:  db "  Size: ", 0
lbl_type:  db "  Type: ", 0
lbl_mode:  db "  Mode: 0", 0
lbl_uid:   db "  Uid:  ", 0
lbl_gid:   db "  Gid:  ", 0
lbl_mtime: db "  Mtime: ", 0

type_reg:    db "regular file", 0
type_dir:    db "directory", 0
type_lnk:    db "symbolic link", 0
type_chr:    db "character special", 0
type_blk:    db "block special", 0
type_fifo:   db "fifo", 0
type_sock:   db "socket", 0
type_other:  db "unknown", 0

section .text

; int applet_stat_main(int argc /edi/, char **argv /rsi/)
applet_stat_main:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     ebx, edi
    mov     rbp, rsi
    xor     r14d, r14d

    cmp     ebx, 2
    jl      .missing

    mov     r12d, 1
.loop:
    cmp     r12d, ebx
    jge     .out

    mov     eax, SYS_stat
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel stat_buf]
    syscall
    test    rax, rax
    js      .err

    ; File:
    lea     rsi, [rel lbl_file]
    call    emit_label
    mov     edi, STDOUT_FILENO
    mov     rsi, [rbp + r12*8]
    call    write_cstr
    call    emit_newline

    ; Size:
    lea     rsi, [rel lbl_size]
    call    emit_label
    mov     rdi, [rel stat_buf + ST_SIZE]
    call    emit_uint
    call    emit_newline

    ; Type:
    lea     rsi, [rel lbl_type]
    call    emit_label
    call    emit_type
    call    emit_newline

    ; Mode:
    lea     rsi, [rel lbl_mode]
    call    emit_label
    mov     edi, [rel stat_buf + ST_MODE]
    and     edi, 0o7777
    call    emit_octal
    call    emit_newline

    ; Uid: prefer username, fall back to numeric.
    lea     rsi, [rel lbl_uid]
    call    emit_label
    mov     edi, [rel stat_buf + ST_UID]
    call    emit_owner
    call    emit_newline

    ; Gid: prefer groupname, fall back to numeric.
    lea     rsi, [rel lbl_gid]
    call    emit_label
    mov     edi, [rel stat_buf + ST_GID]
    call    emit_group
    call    emit_newline

    ; Mtime: calendar date "Mon DD HH:MM" (UTC for now).
    lea     rsi, [rel lbl_mtime]
    call    emit_label
    mov     rdi, [rel stat_buf + ST_MTIME]
    call    emit_date
    call    emit_newline

    inc     r12d
    jmp     .loop

.err:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_stat]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    inc     r12d
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
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; Helpers (local, file-private). Each respects ABI alignment for nested
; calls — sub rsp, 24 on entry brings rsp back to 0 mod 16 from the
; 8-mod-16 state every callee inherits.

; emit_label(rsi /msg/) -> writes msg to stdout. Tail calls write_cstr.
emit_label:
    mov     edi, STDOUT_FILENO
    jmp     write_cstr

; emit_newline()
emit_newline:
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    jmp     putc

; emit_owner(edi /uid/) — prints username if /etc/passwd resolves it,
; otherwise the numeric uid.
emit_owner:
    sub     rsp, 40                 ; 32-byte scratch + 8 align
    mov     rsi, rsp
    mov     edx, 32
    push    rdi
    sub     rsp, 8
    call    uid_to_name
    add     rsp, 8
    pop     rdi
    test    rax, rax
    jnz     .have

    mov     rsi, rsp
    call    format_uint

.have:
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 40
    ret

emit_group:
    sub     rsp, 40
    mov     rsi, rsp
    mov     edx, 32
    push    rdi
    sub     rsp, 8
    call    gid_to_name
    add     rsp, 8
    pop     rdi
    test    rax, rax
    jnz     .have

    mov     rsi, rsp
    call    format_uint

.have:
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 40
    ret

emit_date:
    sub     rsp, 24                 ; 12-byte date + 12 alignment
    mov     rsi, rsp
    call    format_date
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    mov     edx, 12
    call    write_all
    add     rsp, 24
    ret

; emit_uint(rdi /val/)
emit_uint:
    sub     rsp, 24
    mov     rsi, rsp
    call    format_uint
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 24
    ret

; emit_octal(rdi /val/)
emit_octal:
    sub     rsp, 24
    mov     rsi, rsp
    call    format_octal
    mov     rdx, rax
    mov     edi, STDOUT_FILENO
    mov     rsi, rsp
    call    write_all
    add     rsp, 24
    ret

; emit_type — reads stat_buf, writes the file-type word to stdout.
emit_type:
    mov     ecx, [rel stat_buf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFREG
    je      .reg
    cmp     ecx, S_IFDIR
    je      .dir
    cmp     ecx, S_IFLNK
    je      .lnk
    cmp     ecx, S_IFCHR
    je      .chr
    cmp     ecx, S_IFBLK
    je      .blk
    cmp     ecx, S_IFIFO
    je      .fifo
    cmp     ecx, S_IFSOCK
    je      .sock
    lea     rsi, [rel type_other]
    jmp     .write
.reg:  lea rsi, [rel type_reg]
       jmp .write
.dir:  lea rsi, [rel type_dir]
       jmp .write
.lnk:  lea rsi, [rel type_lnk]
       jmp .write
.chr:  lea rsi, [rel type_chr]
       jmp .write
.blk:  lea rsi, [rel type_blk]
       jmp .write
.fifo: lea rsi, [rel type_fifo]
       jmp .write
.sock: lea rsi, [rel type_sock]
.write:
    mov     edi, STDOUT_FILENO
    jmp     write_cstr
