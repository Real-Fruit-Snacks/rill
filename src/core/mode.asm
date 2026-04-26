; mode.asm — render a mode_t into the 10-character "drwxr-xr-x" form.
;
; Layout:
;   [0]   file type letter (d/l/-/c/b/p/s)
;   [1-3] owner perms      (rwx, with s/S for setuid)
;   [4-6] group perms      (rwx, with s/S for setgid)
;   [7-9] other perms      (rwx, with t/T for sticky)
;
; setuid/setgid/sticky bits replace the corresponding x with s/s/t when
; the x bit is also set, or S/S/T when it isn't (matching `ls -l` and stat).

BITS 64
DEFAULT REL

%include "stat.inc"

global format_mode

section .text

; void format_mode(uint32_t mode /edi/, char *out /rsi/)
;
;   Writes exactly 10 ASCII bytes into out. No NUL terminator (caller
;   appends if needed).
format_mode:
    ; --- Type letter ---
    mov     eax, edi
    and     eax, S_IFMT

    cmp     eax, S_IFDIR
    je      .type_d
    cmp     eax, S_IFLNK
    je      .type_l
    cmp     eax, S_IFCHR
    je      .type_c
    cmp     eax, S_IFBLK
    je      .type_b
    cmp     eax, S_IFIFO
    je      .type_p
    cmp     eax, S_IFSOCK
    je      .type_s
    mov     byte [rsi], '-'
    jmp     .perms
.type_d: mov byte [rsi], 'd'
         jmp .perms
.type_l: mov byte [rsi], 'l'
         jmp .perms
.type_c: mov byte [rsi], 'c'
         jmp .perms
.type_b: mov byte [rsi], 'b'
         jmp .perms
.type_p: mov byte [rsi], 'p'
         jmp .perms
.type_s: mov byte [rsi], 's'

.perms:
    ; Owner.
    mov     eax, edi
    test    eax, 0o400
    setnz   cl
    mov     dl, 'r'
    mov     bl, '-'
    test    eax, 0o400
    jnz     .ow_r
    mov     dl, '-'
.ow_r:
    mov     [rsi + 1], dl

    mov     dl, '-'
    test    eax, 0o200
    jz      .ow_w_done
    mov     dl, 'w'
.ow_w_done:
    mov     [rsi + 2], dl

    ; setuid + x interaction.
    test    eax, S_ISUID
    jnz     .ou_setuid
    mov     dl, '-'
    test    eax, 0o100
    jz      .ou_x_done
    mov     dl, 'x'
.ou_x_done:
    jmp     .ou_emit
.ou_setuid:
    mov     dl, 'S'
    test    eax, 0o100
    jz      .ou_emit
    mov     dl, 's'
.ou_emit:
    mov     [rsi + 3], dl

    ; Group.
    mov     dl, '-'
    test    eax, 0o040
    jz      .gr_r_done
    mov     dl, 'r'
.gr_r_done:
    mov     [rsi + 4], dl

    mov     dl, '-'
    test    eax, 0o020
    jz      .gw_done
    mov     dl, 'w'
.gw_done:
    mov     [rsi + 5], dl

    test    eax, S_ISGID
    jnz     .gg_setgid
    mov     dl, '-'
    test    eax, 0o010
    jz      .gx_done
    mov     dl, 'x'
.gx_done:
    jmp     .gg_emit
.gg_setgid:
    mov     dl, 'S'
    test    eax, 0o010
    jz      .gg_emit
    mov     dl, 's'
.gg_emit:
    mov     [rsi + 6], dl

    ; Other.
    mov     dl, '-'
    test    eax, 0o004
    jz      .or_done
    mov     dl, 'r'
.or_done:
    mov     [rsi + 7], dl

    mov     dl, '-'
    test    eax, 0o002
    jz      .ow_done
    mov     dl, 'w'
.ow_done:
    mov     [rsi + 8], dl

    test    eax, S_ISVTX
    jnz     .o_sticky
    mov     dl, '-'
    test    eax, 0o001
    jz      .ox_done
    mov     dl, 'x'
.ox_done:
    jmp     .o_emit
.o_sticky:
    mov     dl, 'T'
    test    eax, 0o001
    jz      .o_emit
    mov     dl, 't'
.o_emit:
    mov     [rsi + 9], dl

    ret
