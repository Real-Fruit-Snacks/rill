; path.asm — small filesystem helpers shared across file-op applets.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "stat.inc"

extern strlen

global is_directory
global stat_path
global path_join

section .text

; int stat_path(const char *path /rdi/, void *buf /rsi/) -> rax (0 or -errno)
;
;   Thin wrapper around SYS_stat with consistent error semantics.
stat_path:
    mov     eax, SYS_stat
    syscall
    ret

; int is_directory(const char *path /rdi/, void *scratch_buf /rsi/) -> rax
;
;   Returns 1 if path resolves to a directory, 0 if it doesn't, -errno on
;   error. Caller supplies a STATBUF_SIZE scratch area. We don't allocate
;   so this can be called from contexts where stack space is tight.
is_directory:
    mov     eax, SYS_stat
    syscall
    test    rax, rax
    js      .err
    mov     ecx, [rsi + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFDIR
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret
.err:
    ret

; size_t path_join(char *dst /rdi/, const char *prefix /rsi/, const char *suffix /rdx/)
;
;   Writes prefix + (optional '/') + suffix + '\0' into dst. Skips adding
;   '/' when prefix already ends with one. Returns the length of the
;   resulting path (excluding NUL).
path_join:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi                ; dst cursor
    mov     r12, rdi                ; dst start (for length calc)

.copy_prefix:
    mov     al, [rsi]
    test    al, al
    jz      .prefix_done
    mov     [rbx], al
    inc     rbx
    inc     rsi
    jmp     .copy_prefix

.prefix_done:
    cmp     rbx, r12
    je      .copy_suffix            ; prefix was empty: skip the '/'
    cmp     byte [rbx - 1], '/'
    je      .copy_suffix
    mov     byte [rbx], '/'
    inc     rbx

.copy_suffix:
    mov     al, [rdx]
    test    al, al
    jz      .done
    mov     [rbx], al
    inc     rbx
    inc     rdx
    jmp     .copy_suffix

.done:
    mov     byte [rbx], 0
    mov     rax, rbx
    sub     rax, r12

    pop     r13
    pop     r12
    pop     rbx
    ret
