; passwd.asm — /etc/passwd and /etc/group lookups for name <-> id.
;
; The two files share a layout (colon-separated fields, one record per
; line) where:
;
;   /etc/passwd:  name : passwd : uid : gid : ...
;   /etc/group:   name : passwd : gid : members
;
; We read each file into a 256 KB .bss buffer (cached after the first
; load this process), then linear-scan. The buffer size caps how many
; entries we can resolve — typical systems are well under 64 KB so this
; is generous. NSS / sssd / LDAP are not consulted; if your system's
; users live there, the lookup will return "not found" and the caller
; falls back to the numeric form.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

extern format_uint

global uid_to_name
global gid_to_name
global name_to_uid
global name_to_gid

%define PWD_BUF_BYTES 262144

section .bss
align 16
pwd_buf:        resb PWD_BUF_BYTES
grp_buf:        resb PWD_BUF_BYTES
pwd_buf_len:    resq 1              ; bytes in pwd_buf, or 0 if not loaded
grp_buf_len:    resq 1
pwd_loaded:     resb 1              ; 0 or 1
grp_loaded:     resb 1

section .rodata
passwd_path:    db "/etc/passwd", 0
group_path:     db "/etc/group", 0

section .text

; ---------------------------------------------------------------------------
; load_file(path /rdi/, buf /rsi/, max /rdx/) -> rax = bytes read or 0
;
;   Reads up to `max` bytes from `path` into `buf`. Returns 0 if the file
;   can't be opened (the lookup will then report "not found", which is
;   the right behavior for a system that doesn't expose names).
load_file:
    push    rbx                     ; buf
    push    rbp                     ; max
    push    r12                     ; fd
    push    r13                     ; (alignment)
    push    r14                     ; cumulative

    mov     rbx, rsi
    mov     rbp, rdx

    mov     eax, SYS_open
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .fail
    mov     r12d, eax

    xor     r14, r14
.loop:
    mov     rax, rbp
    sub     rax, r14
    test    rax, rax
    jz      .done
    mov     edx, eax
    mov     eax, SYS_read
    mov     edi, r12d
    mov     rsi, rbx
    add     rsi, r14
    syscall
    test    rax, rax
    js      .read_err
    jz      .done
    add     r14, rax
    jmp     .loop

.done:
    mov     eax, SYS_close
    mov     edi, r12d
    syscall
    mov     rax, r14
    jmp     .ret

.read_err:
    mov     eax, SYS_close
    mov     edi, r12d
    syscall
.fail:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; ensure_pwd_loaded() / ensure_grp_loaded() — read once, cache.
ensure_pwd_loaded:
    cmp     byte [rel pwd_loaded], 0
    jne     .done
    mov     byte [rel pwd_loaded], 1
    lea     rdi, [rel passwd_path]
    lea     rsi, [rel pwd_buf]
    mov     edx, PWD_BUF_BYTES
    call    load_file
    mov     [rel pwd_buf_len], rax
.done:
    ret

ensure_grp_loaded:
    cmp     byte [rel grp_loaded], 0
    jne     .done
    mov     byte [rel grp_loaded], 1
    lea     rdi, [rel group_path]
    lea     rsi, [rel grp_buf]
    mov     edx, PWD_BUF_BYTES
    call    load_file
    mov     [rel grp_buf_len], rax
.done:
    ret

; ---------------------------------------------------------------------------
; lookup_name_by_id(buf /rdi/, len /rsi/, target /edx/, out /rcx/, out_max /r8/)
;   -> rax = bytes copied (0 if not found)
;
;   Walks a passwd-style file looking for a record whose third field
;   (numeric id) matches `target`. On match, copies the first field
;   (name) into `out`, NUL-terminating, and returns its length.
lookup_name_by_id:
    push    rbx                     ; end pointer
    push    rbp                     ; cursor
    push    r12                     ; target
    push    r13                     ; out
    push    r14                     ; out_max

    mov     r12d, edx
    mov     r13, rcx
    mov     r14, r8

    mov     rbp, rdi
    mov     rbx, rdi
    add     rbx, rsi                ; end

.line:
    cmp     rbp, rbx
    jge     .miss

    ; Find name end (':').
    mov     r9, rbp
.find1:
    cmp     r9, rbx
    jge     .skip_to_eol
    mov     al, [r9]
    cmp     al, 10
    je      .skip_to_eol
    cmp     al, ':'
    je      .name_end
    inc     r9
    jmp     .find1
.name_end:
    mov     r10, r9                 ; r10 = end of name
    inc     r9                      ; past first ':'

    ; Skip second field (passwd) up to ':'.
.find2:
    cmp     r9, rbx
    jge     .skip_to_eol
    mov     al, [r9]
    cmp     al, 10
    je      .skip_to_eol
    cmp     al, ':'
    je      .at_id
    inc     r9
    jmp     .find2
.at_id:
    inc     r9                      ; past second ':'

    ; Parse id (decimal).
    xor     eax, eax
.parse:
    cmp     r9, rbx
    jge     .id_done
    movzx   ecx, byte [r9]
    cmp     ecx, '0'
    jb      .id_done
    cmp     ecx, '9'
    ja      .id_done
    imul    rax, rax, 10
    sub     ecx, '0'
    add     rax, rcx
    inc     r9
    jmp     .parse
.id_done:
    cmp     eax, r12d
    je      .matched

.skip_to_eol:
.eol:
    cmp     r9, rbx
    jge     .miss_after_eol
    cmp     byte [r9], 10
    je      .past_eol
    inc     r9
    jmp     .eol
.past_eol:
    inc     r9
    mov     rbp, r9
    jmp     .line

.miss_after_eol:
    mov     rbp, r9
    jmp     .miss

.matched:
    mov     rcx, r10
    sub     rcx, rbp                ; namelen
    test    rcx, rcx
    jz      .miss
    cmp     rcx, r14
    jl      .copy
    mov     rcx, r14
    dec     rcx                     ; leave room for NUL
.copy:
    mov     rdi, r13
    mov     rsi, rbp
    mov     r9, rcx
    rep     movsb
    mov     byte [rdi], 0
    mov     rax, r9
    jmp     .ret

.miss:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; lookup_id_by_name(buf /rdi/, len /rsi/, name /rdx/) -> rax (id, or -1)
lookup_id_by_name:
    push    rbx                     ; end
    push    rbp                     ; cursor
    push    r12                     ; name

    mov     rbp, rdi
    mov     rbx, rdi
    add     rbx, rsi
    mov     r12, rdx

.line:
    cmp     rbp, rbx
    jge     .miss

    ; Compare line's first field with target name.
    mov     r9, rbp
    mov     r10, r12
.cmp_loop:
    cmp     r9, rbx
    jge     .skip_to_eol
    mov     al, [r9]
    cmp     al, ':'
    je      .name_consumed
    cmp     al, 10
    je      .skip_to_eol
    cmp     al, [r10]
    jne     .skip_to_eol
    inc     r9
    inc     r10
    jmp     .cmp_loop
.name_consumed:
    cmp     byte [r10], 0
    jne     .skip_to_eol            ; line's name is a prefix of target

    ; Match. r9 points at first ':'.
    inc     r9                      ; past ':'

    ; Skip second field.
.skip_pwfield:
    cmp     r9, rbx
    jge     .skip_to_eol
    mov     al, [r9]
    cmp     al, 10
    je      .skip_to_eol
    cmp     al, ':'
    je      .at_id
    inc     r9
    jmp     .skip_pwfield
.at_id:
    inc     r9

    ; Parse id.
    xor     eax, eax
.parse_id:
    cmp     r9, rbx
    jge     .have_id
    movzx   ecx, byte [r9]
    cmp     ecx, '0'
    jb      .have_id
    cmp     ecx, '9'
    ja      .have_id
    imul    rax, rax, 10
    sub     ecx, '0'
    add     rax, rcx
    inc     r9
    jmp     .parse_id
.have_id:
    jmp     .ret

.skip_to_eol:
.eol:
    cmp     r9, rbx
    jge     .miss
    cmp     byte [r9], 10
    je      .past_eol
    inc     r9
    jmp     .eol
.past_eol:
    inc     r9
    mov     rbp, r9
    jmp     .line

.miss:
    mov     rax, -1
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ===========================================================================
; Public wrappers
; ===========================================================================

; size_t uid_to_name(uint32_t uid /edi/, char *out /rsi/, size_t max /rdx/)
uid_to_name:
    push    rbx                     ; uid
    push    rbp                     ; out
    push    r12                     ; max

    mov     ebx, edi
    mov     rbp, rsi
    mov     r12, rdx

    call    ensure_pwd_loaded

    mov     rax, [rel pwd_buf_len]
    test    rax, rax
    jz      .miss

    lea     rdi, [rel pwd_buf]
    mov     rsi, rax
    mov     edx, ebx
    mov     rcx, rbp
    mov     r8, r12
    call    lookup_name_by_id
    jmp     .ret

.miss:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; size_t gid_to_name(uint32_t gid /edi/, char *out /rsi/, size_t max /rdx/)
gid_to_name:
    push    rbx
    push    rbp
    push    r12

    mov     ebx, edi
    mov     rbp, rsi
    mov     r12, rdx

    call    ensure_grp_loaded

    mov     rax, [rel grp_buf_len]
    test    rax, rax
    jz      .miss

    lea     rdi, [rel grp_buf]
    mov     rsi, rax
    mov     edx, ebx
    mov     rcx, rbp
    mov     r8, r12
    call    lookup_name_by_id
    jmp     .ret

.miss:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; int64_t name_to_uid(const char *name /rdi/) — -1 if not found
name_to_uid:
    push    rbx
    push    rbp
    push    r12

    mov     rbx, rdi

    call    ensure_pwd_loaded

    mov     rax, [rel pwd_buf_len]
    test    rax, rax
    jz      .miss

    lea     rdi, [rel pwd_buf]
    mov     rsi, rax
    mov     rdx, rbx
    call    lookup_id_by_name
    jmp     .ret

.miss:
    mov     rax, -1
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret

; int64_t name_to_gid(const char *name /rdi/)
name_to_gid:
    push    rbx
    push    rbp
    push    r12

    mov     rbx, rdi

    call    ensure_grp_loaded

    mov     rax, [rel grp_buf_len]
    test    rax, rax
    jz      .miss

    lea     rdi, [rel grp_buf]
    mov     rsi, rax
    mov     rdx, rbx
    call    lookup_id_by_name
    jmp     .ret

.miss:
    mov     rax, -1
.ret:
    pop     r12
    pop     rbp
    pop     rbx
    ret
