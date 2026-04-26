; tz.asm — read /etc/localtime to discover the local UTC offset.
;
; Strategy: parse /etc/localtime as TZif (RFC 8536) and find the largest
; transition time <= now, then look up the associated tt_gmtoff. We prefer
; the v2/v3 block (int64 transitions, works past 2038) when present and
; fall back to the v1 block otherwise. Result is cached for the process.
;
; Limitations:
;   * 8 KB read cap. Modern zones fit easily; America/New_York is ~3.5 KB.
;   * Leap seconds in the file are accounted for in the offset arithmetic
;     (their byte run is skipped) but their effect on time is ignored.
;   * If /etc/localtime is missing/short/unparseable, the offset stays 0.
;   * /etc/localtime changes mid-process are not detected (cached).

BITS 64
DEFAULT REL

%include "syscalls.inc"
%include "macros.inc"
%include "fcntl.inc"

global localtime_offset_secs

%define TZIF_BUF_BYTES 8192

section .bss
align 16
tz_buf:        resb TZIF_BUF_BYTES
tz_offset:     resq 1
tz_loaded:     resb 1

section .rodata
tz_path:       db "/etc/localtime", 0

section .text

; ---------------------------------------------------------------------------
; int64 localtime_offset_secs() -> rax
;
;   Returns seconds-east-of-UTC for now (e.g. -18000 for EST).
;   Cached after first call. 0 on any error.
;
;   Stack: 6 callee-saved pushes + sub 8 -> rsp = 0 mod 16 at inner calls.
localtime_offset_secs:
    cmp     byte [rel tz_loaded], 0
    je      .compute
    mov     rax, [rel tz_offset]
    ret

.compute:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     byte [rel tz_loaded], 1
    mov     qword [rel tz_offset], 0

    mov     eax, SYS_open
    lea     rdi, [rel tz_path]
    mov     esi, O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .out
    mov     r12d, eax

    mov     eax, SYS_read
    mov     edi, r12d
    lea     rsi, [rel tz_buf]
    mov     edx, TZIF_BUF_BYTES
    syscall
    mov     r13, rax

    mov     eax, SYS_close
    mov     edi, r12d
    syscall

    test    r13, r13
    jle     .out
    cmp     r13, 44
    jl      .out

    ; Magic check: "TZif"
    mov     eax, [rel tz_buf]
    cmp     eax, 0x66695A54
    jne     .out

    ; now = time(NULL)
    mov     eax, SYS_time
    xor     edi, edi
    syscall
    mov     r15, rax

    ; Compute v1 body byte count so we know where the v2 header sits.
    ;
    ; v1 body =   ttisutcnt
    ;           + ttisstdcnt
    ;           + leapcnt    * 8
    ;           + timecnt    * 5    (4-byte time + 1-byte type)
    ;           + typecnt    * 6
    ;           + charcnt
    xor     rcx, rcx
    mov     eax, [rel tz_buf + 20]
    bswap   eax
    add     rcx, rax
    mov     eax, [rel tz_buf + 24]
    bswap   eax
    add     rcx, rax
    mov     eax, [rel tz_buf + 28]
    bswap   eax
    lea     rdx, [rax*8]
    add     rcx, rdx
    mov     eax, [rel tz_buf + 32]
    bswap   eax
    lea     rdx, [rax*4 + rax]
    add     rcx, rdx
    mov     eax, [rel tz_buf + 36]
    bswap   eax
    imul    rdx, rax, 6                 ; typecnt*6 (x86 has no *6 scale)
    add     rcx, rdx
    mov     eax, [rel tz_buf + 40]
    bswap   eax
    add     rcx, rax
    add     rcx, 44                     ; rcx = offset of v2 header (if any)

    movzx   eax, byte [rel tz_buf + 4]
    cmp     al, '2'
    jl      .use_v1

    lea     rdx, [rcx + 44]
    cmp     rdx, r13
    jg      .use_v1

    mov     eax, [rel tz_buf + rcx]
    cmp     eax, 0x66695A54
    jne     .use_v1

    ; v2 timecnt @v2_base+32, typecnt @v2_base+36.
    mov     eax, [rel tz_buf + rcx + 32]
    bswap   eax
    mov     r14d, eax                   ; v2 timecnt
    mov     eax, [rel tz_buf + rcx + 36]
    bswap   eax
    mov     ebx, eax                    ; v2 typecnt

    ; v2 body layout (base = tz_buf + rcx + 44):
    ;   transitions[timecnt] int64 BE
    ;   types[timecnt]       uint8
    ;   ttinfo[typecnt]      6 bytes (int32 BE gmtoff, isdst, abbrind)
    lea     rdi, [rel tz_buf]
    add     rdi, rcx
    add     rdi, 44                     ; transitions
    mov     rax, r14
    shl     rax, 3                      ; timecnt * 8
    lea     rsi, [rdi + rax]            ; types
    lea     rbp, [rsi + r14]            ; ttinfo

    ; Bounds: ttinfo end (rbp + typecnt*6) must be inside [tz_buf, tz_buf+r13).
    imul    rax, rbx, 6
    add     rax, rbp
    lea     rdx, [rel tz_buf]
    add     rdx, r13
    cmp     rax, rdx
    jg      .use_v1

    ; Linear scan transitions for largest <= now.
    xor     r8, r8
    mov     r9, -1
.scan_v2:
    cmp     r8, r14
    jge     .scan_v2_done
    mov     rax, [rdi + r8*8]
    bswap   rax
    cmp     rax, r15
    jg      .scan_v2_done               ; sorted ascending; stop at first >
    mov     r9, r8
    inc     r8
    jmp     .scan_v2
.scan_v2_done:
    test    r9, r9
    jns     .have_idx_v2
    xor     r10d, r10d
    jmp     .read_ttinfo_v2
.have_idx_v2:
    movzx   r10d, byte [rsi + r9]
.read_ttinfo_v2:
    cmp     r10d, ebx
    jae     .out
    imul    rax, r10, 6
    add     rax, rbp
    mov     eax, [rax]
    bswap   eax
    movsxd  rax, eax
    mov     [rel tz_offset], rax
    jmp     .out

.use_v1:
    ; Fall back to v1 (int32 transitions).
    mov     eax, [rel tz_buf + 32]
    bswap   eax
    mov     r14d, eax                   ; v1 timecnt
    mov     eax, [rel tz_buf + 36]
    bswap   eax
    mov     ebx, eax                    ; v1 typecnt

    test    r14, r14
    jnz     .v1_have_transitions

    ; No transitions: ttinfo immediately follows the (empty) types array.
    test    ebx, ebx
    jz      .out
    lea     rax, [rel tz_buf + 44]
    mov     eax, [rax]
    bswap   eax
    movsxd  rax, eax
    mov     [rel tz_offset], rax
    jmp     .out

.v1_have_transitions:
    lea     rdi, [rel tz_buf + 44]      ; transitions
    lea     rsi, [rdi + r14*4]          ; types
    lea     rbp, [rsi + r14]            ; ttinfo

    ; Bounds check.
    imul    rax, rbx, 6
    add     rax, rbp
    lea     rdx, [rel tz_buf]
    add     rdx, r13
    cmp     rax, rdx
    jg      .out

    xor     r8, r8
    mov     r9, -1
.scan_v1:
    cmp     r8, r14
    jge     .scan_v1_done
    mov     eax, [rdi + r8*4]
    bswap   eax
    movsxd  rax, eax
    cmp     rax, r15
    jg      .scan_v1_done
    mov     r9, r8
    inc     r8
    jmp     .scan_v1
.scan_v1_done:
    test    r9, r9
    jns     .have_idx_v1
    xor     r10d, r10d
    jmp     .read_ttinfo_v1
.have_idx_v1:
    movzx   r10d, byte [rsi + r9]
.read_ttinfo_v1:
    cmp     r10d, ebx
    jae     .out
    imul    rax, r10, 6
    add     rax, rbp
    mov     eax, [rax]
    bswap   eax
    movsxd  rax, eax
    mov     [rel tz_offset], rax

.out:
    mov     rax, [rel tz_offset]
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret
