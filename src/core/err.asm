; err.asm — errno → message lookup, plus perror-style helpers.
;
; The table covers errors that file-touching applets actually see in
; practice. Anything not in the table falls back to a generic message;
; that's better than refusing to print at all and matches what coreutils
; does for unknown errno values on a fresh system.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern strlen
extern write_all
extern write_cstr
extern putc

global errstr
global perror_path

section .rodata
msg_eperm:    db "Operation not permitted", 0
msg_enoent:   db "No such file or directory", 0
msg_eintr:    db "Interrupted system call", 0
msg_eio:      db "Input/output error", 0
msg_ebadf:    db "Bad file descriptor", 0
msg_enomem:   db "Out of memory", 0
msg_eacces:   db "Permission denied", 0
msg_efault:   db "Bad address", 0
msg_ebusy:    db "Device or resource busy", 0
msg_eexist:   db "File exists", 0
msg_enotdir:  db "Not a directory", 0
msg_eisdir:   db "Is a directory", 0
msg_einval:   db "Invalid argument", 0
msg_emfile:   db "Too many open files", 0
msg_enospc:   db "No space left on device", 0
msg_erofs:    db "Read-only file system", 0
msg_epipe:    db "Broken pipe", 0
msg_enametl:  db "File name too long", 0
msg_eloop:    db "Too many levels of symbolic links", 0
msg_unknown:  db "Unknown error", 0
msg_colon:    db ": ", 0

align 8
errno_table:
    dq  1,  msg_eperm
    dq  2,  msg_enoent
    dq  4,  msg_eintr
    dq  5,  msg_eio
    dq  9,  msg_ebadf
    dq  12, msg_enomem
    dq  13, msg_eacces
    dq  14, msg_efault
    dq  16, msg_ebusy
    dq  17, msg_eexist
    dq  20, msg_enotdir
    dq  21, msg_eisdir
    dq  22, msg_einval
    dq  24, msg_emfile
    dq  28, msg_enospc
    dq  30, msg_erofs
    dq  32, msg_epipe
    dq  36, msg_enametl
    dq  40, msg_eloop
    dq  0,  0                       ; sentinel

section .text

; const char *errstr(int errno /edi/)
errstr:
    movsxd  rdi, edi
    test    rdi, rdi
    js      .negate
    jmp     .lookup
.negate:
    neg     rdi
.lookup:
    lea     rcx, [rel errno_table]
.loop:
    mov     rdx, [rcx]
    test    rdx, rdx
    jz      .unknown
    cmp     rdx, rdi
    je      .found
    add     rcx, 16
    jmp     .loop
.found:
    mov     rax, [rcx + 8]
    ret
.unknown:
    lea     rax, [rel msg_unknown]
    ret

; void perror_path(const char *prefix /rdi/, const char *path /rsi/,
;                  int errno /edx/)
;
;   Writes "<prefix>: <path>: <errno-message>\n" to stderr. errno may be
;   negative (kernel-style); we normalize. Best effort — write errors
;   while reporting an error are silently ignored.
perror_path:
    push    rbx                     ; prefix
    push    rbp                     ; path
    push    r12                     ; errno
    push    r13                     ; (alignment)
    push    r14

    mov     rbx, rdi
    mov     rbp, rsi
    mov     r12d, edx

    mov     edi, STDERR_FILENO
    mov     rsi, rbx
    call    write_cstr

    mov     edi, STDERR_FILENO
    lea     rsi, [rel msg_colon]
    call    write_cstr

    mov     edi, STDERR_FILENO
    mov     rsi, rbp
    call    write_cstr

    mov     edi, STDERR_FILENO
    lea     rsi, [rel msg_colon]
    call    write_cstr

    mov     edi, r12d
    call    errstr
    mov     edi, STDERR_FILENO
    mov     rsi, rax
    call    write_cstr

    mov     edi, STDERR_FILENO
    mov     esi, 10
    call    putc

    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
