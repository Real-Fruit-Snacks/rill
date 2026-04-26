; rm.asm — remove files and (optionally) directory trees.
;
;   rm [-r|-R] [-f] PATH...
;
; -r / -R   recursive (post-order: children, then directory itself)
; -f        ignore-missing
;
; Recursion uses a shared 4 KB path buffer (rm_path_buf), appending at
; each descent and truncating back on return. Each recursion frame
; allocates a 32 KB getdents64 buffer on the stack — Linux's default
; 8 MB stack supports ~250 levels of depth.

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "stat.inc"
%include "fcntl.inc"

extern streq
extern perror_path

global applet_rm_main

%define ENOENT  2
%define D_RECLEN 16
%define D_NAME   19
%define RM_GETDENTS_BUF_LEN 32768
%define PATH_MAX 4096

section .bss
align 16
rm_path_buf: resb PATH_MAX
rm_statbuf:  resb STATBUF_SIZE

section .rodata
opt_r:        db "-r", 0
opt_rcap:     db "-R", 0
opt_f:        db "-f", 0
opt_rf:       db "-rf", 0
opt_fr:       db "-fr", 0
opt_Rf:       db "-Rf", 0
opt_fR:       db "-fR", 0
prefix_rm:    db "rm", 0

section .text

; int applet_rm_main(int argc /edi/, char **argv /rsi/)
applet_rm_main:
    push    rbx                     ; argc
    push    rbp                     ; argv
    push    r12                     ; arg cursor
    push    r13                     ; flags (bit 0 = -r, bit 1 = -f)
    push    r14                     ; rc

    mov     ebx, edi
    mov     rbp, rsi
    xor     r13d, r13d
    xor     r14d, r14d

    mov     r12d, 1
.flag_loop:
    cmp     r12d, ebx
    jge     .flags_done
    mov     rdi, [rbp + r12*8]
    cmp     byte [rdi], '-'
    jne     .flags_done
    cmp     byte [rdi + 1], 0
    je      .flags_done

    lea     rsi, [rel opt_r]
    call    streq
    test    eax, eax
    jnz     .set_r
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_rcap]
    call    streq
    test    eax, eax
    jnz     .set_r
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_f]
    call    streq
    test    eax, eax
    jnz     .set_f
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_rf]
    call    streq
    test    eax, eax
    jnz     .set_rf
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_fr]
    call    streq
    test    eax, eax
    jnz     .set_rf
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_Rf]
    call    streq
    test    eax, eax
    jnz     .set_rf
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel opt_fR]
    call    streq
    test    eax, eax
    jnz     .set_rf
    jmp     .flags_done

.set_r:  or r13d, 1
         inc r12d
         jmp .flag_loop
.set_f:  or r13d, 2
         inc r12d
         jmp .flag_loop
.set_rf: or r13d, 3
         inc r12d
         jmp .flag_loop

.flags_done:
.op_loop:
    cmp     r12d, ebx
    jge     .out

    test    r13d, 1
    jnz     .do_recurse

    ; Plain unlink.
    mov     eax, SYS_unlink
    mov     rdi, [rbp + r12*8]
    syscall
    test    rax, rax
    jns     .next
    cmp     eax, -ENOENT
    jne     .report_simple
    test    r13d, 2
    jnz     .next
.report_simple:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_rm]
    mov     rsi, [rbp + r12*8]
    call    perror_path
    mov     r14d, 1
    jmp     .next

.do_recurse:
    ; Copy argv[i] into rm_path_buf, length in ecx.
    mov     rdi, [rbp + r12*8]
    lea     rsi, [rel rm_path_buf]
    xor     ecx, ecx
.copy_arg:
    mov     al, [rdi + rcx]
    mov     [rsi + rcx], al
    test    al, al
    jz      .copied
    inc     ecx
    cmp     ecx, PATH_MAX - 1
    jge     .arg_too_long
    jmp     .copy_arg

.arg_too_long:
    mov     byte [rsi + PATH_MAX - 1], 0
    mov     r14d, 1
    jmp     .next

.copied:
    mov     rdi, rsi
    movsxd  rsi, ecx
    mov     edx, r13d
    call    rm_recurse
    test    eax, eax
    jz      .next
    mov     r14d, 1

.next:
    inc     r12d
    jmp     .op_loop

.out:
    mov     eax, r14d
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; rm_recurse(path /rdi/, len /rsi/, flags /edx/) -> rax (0 or 1)
;
; Register usage during the body:
;   rbx  path
;   rbp  current path length (mutated; restored before return)
;   r12  saved_len (parent's length, for restoration before rmdir)
;   r13  getdents accumulator base (= rsp after sub)
;   r14  flags + sticky-failure bit (bit 8 set if a child failed)
;
; Stack: 5 callee-saved pushes + sub 32768 keeps the inner-call rsp at
; 0 mod 16 (5 pushes give 8 mod 16 from entry's 8 mod 16 = 0; the sub is
; 0 mod 16 itself).
rm_recurse:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    sub     rsp, RM_GETDENTS_BUF_LEN

    mov     rbx, rdi
    mov     rbp, rsi
    mov     r14d, edx
    mov     r13, rsp

    mov     eax, SYS_lstat
    mov     rdi, rbx
    lea     rsi, [rel rm_statbuf]
    syscall
    test    rax, rax
    js      .err_kernel

    mov     ecx, [rel rm_statbuf + ST_MODE]
    and     ecx, S_IFMT
    cmp     ecx, S_IFDIR
    je      .as_dir

    mov     eax, SYS_unlink
    mov     rdi, rbx
    syscall
    test    rax, rax
    jns     .ok
    jmp     .err_kernel

.as_dir:
    mov     eax, SYS_open
    mov     rdi, rbx
    mov     esi, O_RDONLY | O_DIRECTORY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .err_kernel

    push    rax                     ; save fd at [rsp+8] until close
    sub     rsp, 8                  ; align (1 push + 1 sub = 16 = 0 mod 16)

    xor     r8, r8                  ; cumulative bytes read
.read_loop:
    mov     edx, RM_GETDENTS_BUF_LEN
    sub     edx, r8d
    test    edx, edx
    jz      .read_full
    mov     eax, SYS_getdents64
    mov     edi, [rsp + 8]
    mov     rsi, r13
    add     rsi, r8
    syscall
    test    rax, rax
    js      .read_kernel_err
    jz      .read_eof
    add     r8, rax
    jmp     .read_loop

.read_full:
.read_kernel_err:
    ; Close fd and bail.
    mov     edi, [rsp + 8]
    mov     eax, SYS_close
    syscall
    add     rsp, 8
    add     rsp, 8                  ; pop the saved fd slot
    mov     eax, -22                ; pseudo-EINVAL for overflow / read err
    jmp     .err_kernel

.read_eof:
    mov     edi, [rsp + 8]
    push    r8                      ; preserve total across close
    sub     rsp, 8
    mov     eax, SYS_close
    syscall
    add     rsp, 8
    pop     r8
    add     rsp, 8                  ; drop align
    add     rsp, 8                  ; drop saved fd slot

    ; ensure we don't try to use the alignment slot anymore — fd is gone.

    mov     r12, rbp                ; saved_len for restore
    test    rbp, rbp
    jz      .add_sep
    cmp     byte [rbx + rbp - 1], '/'
    je      .no_sep
.add_sep:
    mov     byte [rbx + rbp], '/'
    inc     rbp
.no_sep:

    xor     r9, r9                  ; cursor
.iter:
    cmp     r9, r8
    jge     .iter_done

    lea     rdi, [r13 + r9]
    movzx   ecx, word [rdi + D_RECLEN]
    lea     r10, [rdi + D_NAME]

    cmp     byte [r10], '.'
    jne     .process
    cmp     byte [r10 + 1], 0
    je      .next
    cmp     byte [r10 + 1], '.'
    jne     .process
    cmp     byte [r10 + 2], 0
    je      .next

.process:
    mov     r11, r10
.nlen:
    cmp     byte [r11], 0
    je      .nlen_done
    inc     r11
    jmp     .nlen
.nlen_done:
    sub     r11, r10                ; namelen

    lea     rax, [rbp + r11]
    cmp     rax, PATH_MAX - 1
    jae     .next                   ; skip path-overflow

    ; Append name to rm_path_buf at offset rbp.
    mov     rdi, rbx
    add     rdi, rbp
    mov     rsi, r10
.copy_name:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .copy_done
    inc     rdi
    inc     rsi
    jmp     .copy_name
.copy_done:

    ; Recurse. Save caller-saved scratch (rcx, r8, r9, r10, r11).
    push    rcx
    push    r8
    push    r9
    push    r10
    push    r11
    sub     rsp, 8                  ; align: 5 pushes + sub 8 = 48 = 0 mod 16

    mov     rdi, rbx
    lea     rsi, [rbp + r11]
    mov     edx, r14d
    call    rm_recurse

    add     rsp, 8
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rcx

    ; Truncate name off the path.
    mov     byte [rbx + rbp], 0

    test    eax, eax
    jz      .next
    or      r14d, 0x100             ; sticky child-failed flag

.next:
    add     r9, rcx
    jmp     .iter

.iter_done:
    mov     rbp, r12
    mov     byte [rbx + rbp], 0

    mov     eax, SYS_rmdir
    mov     rdi, rbx
    syscall
    test    rax, rax
    js      .err_kernel

    test    r14d, 0x100
    jnz     .err_already_reported

.ok:
    xor     eax, eax
    jmp     .ret

.err_already_reported:
    mov     eax, 1
    jmp     .ret

.err_kernel:
    cmp     eax, -ENOENT
    jne     .err_report
    test    r14d, 2
    jnz     .ok
.err_report:
    neg     eax
    mov     edx, eax
    lea     rdi, [rel prefix_rm]
    mov     rsi, rbx
    call    perror_path
    mov     eax, 1

.ret:
    add     rsp, RM_GETDENTS_BUF_LEN
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
