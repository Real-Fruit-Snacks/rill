; which.asm — find an executable in $PATH.
;
;   which COMMAND...
;
; For each COMMAND, walks each ':'-separated entry of $PATH and prints
; the first match where the file exists and is executable. Exit code:
;   0 if every COMMAND was found
;   1 if any was not found
;
; v1 doesn't honor `-a` (print all matches) or `--skip-tilde` style
; flags, and it doesn't follow shell aliases / functions.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

extern write_all
extern write_cstr
extern putc

global applet_which_main

%define X_OK 1
%define PATH_MAX 4096

section .bss
align 16
which_path: resb PATH_MAX

section .rodata
default_path: db "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 0

section .text

; int applet_which_main(int argc /edi/, char **argv /rsi/)
;
; rbx  argc
; rbp  argv
; r12  envp pointer
; r13  PATH value (or default_path if unset)
; r14  rc
applet_which_main:
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

    ; envp = argv + (argc + 1) * 8
    lea     r12, [rsi + rdi*8 + 8]

    ; Look up PATH.
    call    find_path
    mov     r13, rax

    mov     ecx, 1
.cmd_loop:
    cmp     ecx, ebx
    jge     .out

    mov     rdi, [rbp + rcx*8]
    push    rcx
    sub     rsp, 8
    call    locate_in_path
    add     rsp, 8
    pop     rcx
    test    eax, eax
    jnz     .next_cmd
    mov     r14d, 1
.next_cmd:
    inc     ecx
    jmp     .cmd_loop

.missing:
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
; find_path() -> rax = pointer to PATH value (or default_path)
;
; Reads envp (in r12) and finds the entry starting with "PATH=".
find_path:
    mov     r8, r12
.loop:
    mov     rsi, [r8]
    test    rsi, rsi
    jz      .default

    cmp     byte [rsi + 0], 'P'
    jne     .next
    cmp     byte [rsi + 1], 'A'
    jne     .next
    cmp     byte [rsi + 2], 'T'
    jne     .next
    cmp     byte [rsi + 3], 'H'
    jne     .next
    cmp     byte [rsi + 4], '='
    jne     .next

    lea     rax, [rsi + 5]
    ret
.next:
    add     r8, 8
    jmp     .loop
.default:
    lea     rax, [rel default_path]
    ret

; ---------------------------------------------------------------------------
; locate_in_path(cmd /rdi/) -> rax (1 if found and emitted, 0 otherwise)
;
; Walks r13 (PATH), splitting on ':', and tries access(dir/cmd, X_OK)
; for each.
locate_in_path:
    push    rbx                     ; cmd
    push    rbp                     ; PATH cursor

    mov     rbx, rdi
    mov     rbp, r13

.dir_loop:
    cmp     byte [rbp], 0
    je      .not_found

    ; Build "<dir>/<cmd>" in which_path.
    lea     rdi, [rel which_path]
    xor     ecx, ecx

    ; Copy dir component (until ':' or NUL).
.copy_dir:
    movzx   eax, byte [rbp]
    test    eax, eax
    jz      .dir_end
    cmp     eax, ':'
    je      .dir_end
    cmp     ecx, PATH_MAX - 16
    jge     .skip_long
    mov     [rdi + rcx], al
    inc     ecx
    inc     rbp
    jmp     .copy_dir

.skip_long:
    ; Path-too-long: skip rest of this dir entry.
    cmp     byte [rbp], 0
    je      .not_found
    cmp     byte [rbp], ':'
    je      .next_after_colon
    inc     rbp
    jmp     .skip_long

.dir_end:
    ; Append '/' if dir wasn't empty and doesn't end with '/'.
    test    ecx, ecx
    jz      .add_dot
    cmp     byte [rdi + rcx - 1], '/'
    je      .copy_cmd
    mov     byte [rdi + rcx], '/'
    inc     ecx
    jmp     .copy_cmd

.add_dot:
    ; Empty dir component (PATH like "::") means "."; treat as "./".
    mov     byte [rdi + rcx], '.'
    inc     ecx
    mov     byte [rdi + rcx], '/'
    inc     ecx

.copy_cmd:
    mov     rsi, rbx
.cmd_copy:
    mov     al, [rsi]
    test    al, al
    jz      .cmd_done
    cmp     ecx, PATH_MAX - 1
    jge     .cmd_done
    mov     [rdi + rcx], al
    inc     ecx
    inc     rsi
    jmp     .cmd_copy
.cmd_done:
    mov     byte [rdi + rcx], 0

    ; access(path, X_OK)
    push    rcx
    sub     rsp, 8
    mov     eax, SYS_access
    lea     rdi, [rel which_path]
    mov     esi, X_OK
    syscall
    add     rsp, 8
    pop     rcx
    test    rax, rax
    jnz     .next_after_colon

    ; Print the resolved path + newline.
    mov     edi, STDOUT_FILENO
    lea     rsi, [rel which_path]
    movsxd  rdx, ecx
    call    write_all
    mov     edi, STDOUT_FILENO
    mov     esi, 10
    call    putc

    mov     eax, 1
    jmp     .ret

.next_after_colon:
    cmp     byte [rbp], ':'
    jne     .check_eos
    inc     rbp
.check_eos:
    cmp     byte [rbp], 0
    jne     .dir_loop
    jmp     .not_found

.not_found:
    xor     eax, eax
.ret:
    pop     rbp
    pop     rbx
    ret
