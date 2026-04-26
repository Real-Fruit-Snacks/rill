; false.asm — exit 1, ignoring arguments.
;
; POSIX: utilities/false.html

BITS 64
DEFAULT REL

global applet_false_main

section .text

; int applet_false_main(int argc /edi/, char **argv /rsi/)
applet_false_main:
    mov     eax, 1
    ret
