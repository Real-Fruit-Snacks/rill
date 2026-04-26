; start.asm — _start, applet dispatcher, applet table
;
; The multi-call binary uses argv[0] to pick an applet, BusyBox-style. If
; argv[0] is "rill" itself (or any name that doesn't match an applet), we
; shift argv and treat argv[1] as the applet name, so both of these work:
;
;     /usr/bin/true
;     rill true
;
; Calling convention (internal, applets and runtime):
;   System V AMD64 ABI. Args in rdi, rsi, rdx, rcx, r8, r9. Return in rax.
;   Callee-saved: rbx, rbp, r12-r15.
;
; Applet contract:
;   void applet_main(int argc /rdi/, char **argv /rsi/) -> int /rax/
;   The returned value becomes the process exit code.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"

global _start

; Runtime helpers (src/core/string.asm)
extern streq
extern basename

; Applet entry points — one extern + one applet_table row per applet.
extern applet_true_main

; ---------------------------------------------------------------------------
; .rodata
; ---------------------------------------------------------------------------
section .rodata

name_rill:  db "rill", 0
name_true:  db "true", 0

usage_msg:      db "rill: applet not found", 10
usage_msg_len:  equ $ - usage_msg

; Applet dispatch table. Terminated by a NULL name pointer.
;
; Each entry is: { const char *name; int (*main)(int, char**); }
align 8
applet_table:
    dq name_true, applet_true_main
    dq 0, 0

; ---------------------------------------------------------------------------
; .text
; ---------------------------------------------------------------------------
section .text

; _start — kernel entry. The kernel arranges the stack as:
;
;   [rsp +  0]  argc
;   [rsp +  8]  argv[0]
;   [rsp + 16]  argv[1]
;   ...
;   [rsp + 8 + 8*argc]  NULL
;   then envp[]..NULL, then auxv[]..NULL
;
; rsp is 16-byte aligned at entry (per the SysV ABI process-startup section).
_start:
    mov     rdi, [rsp]              ; rdi = argc
    lea     rsi, [rsp + 8]          ; rsi = argv

    call    dispatch                ; rax = exit code

    ; exit_group(rax)
    mov     edi, eax
    mov     eax, SYS_exit_group
    syscall
    ud2                             ; unreachable

; dispatch(argc /rdi/, argv /rsi/) -> exit_code /rax/
;
; Walks the applet table looking for a name matching basename(argv[0]). If
; the name is "rill" we shift argv and try again, so `rill <applet> ...`
; works alongside symlink invocation.
dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     ebx, edi                ; rbx = argc (32-bit is fine)
    mov     r12, rsi                ; r12 = argv

    mov     rdi, [r12]              ; argv[0]
    call    basename
    mov     r13, rax                ; r13 = applet name candidate

.scan:
    lea     r14, [applet_table]
.scan_loop:
    mov     rdi, [r14]              ; entry->name
    test    rdi, rdi
    jz      .not_in_table
    mov     rsi, r13
    call    streq
    test    eax, eax
    jnz     .matched
    add     r14, 16
    jmp     .scan_loop

.matched:
    mov     edi, ebx                ; argc
    mov     rsi, r12                ; argv
    call    [r14 + 8]               ; entry->main
    jmp     .out

.not_in_table:
    ; If candidate is "rill" and we still have an arg to consume, shift.
    mov     rdi, r13
    lea     rsi, [name_rill]
    call    streq
    test    eax, eax
    jz      .usage
    cmp     ebx, 2
    jl      .usage
    dec     ebx
    add     r12, 8
    mov     rdi, [r12]
    call    basename
    mov     r13, rax
    jmp     .scan

.usage:
    mov     eax, SYS_write
    mov     edi, STDERR_FILENO
    lea     rsi, [usage_msg]
    mov     edx, usage_msg_len
    syscall
    mov     eax, EXIT_USAGE

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
