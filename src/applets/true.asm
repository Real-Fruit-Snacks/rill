; true.asm — exit 0, ignoring arguments.
;
; POSIX: utilities/true.html

BITS 64
DEFAULT REL

global applet_true_main

section .text

; int applet_true_main(int argc /rdi/, char **argv /rsi/)
applet_true_main:
    xor     eax, eax
    ret
