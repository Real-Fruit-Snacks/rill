; time.asm — convert a Unix epoch second to broken-down calendar fields.
;
; The Hinnant "days from civil" algorithm: given a count of days since
; 1970-01-01, recover (year, month, day) without any tables. We only
; handle non-negative epoch seconds; pre-1970 timestamps would need
; signed division. ls and stat never need that.
;
; Reference: Howard Hinnant, "chrono-Compatible Low-Level Date Algorithms"
; — public domain, ubiquitous in modern date libraries.

BITS 64
DEFAULT REL

global unix_to_calendar
global format_date
global format_date_local
global format_datetime_long

extern localtime_offset_secs

section .rodata
month_names: db "JanFebMarAprMayJunJulAugSepOctNovDec"
day_names:   db "SunMonTueWedThuFriSat"

section .text

; void unix_to_calendar(int64_t epoch_secs /rdi/, struct rill_tm *out /rsi/)
;
;   *out is six dwords laid out as:
;     +0   year   (e.g. 2026, signed but always positive in our use)
;     +4   month  (1..12)
;     +8   day    (1..31)
;    +12   hour   (0..23)
;    +16   minute (0..59)
;    +20   second (0..59)
unix_to_calendar:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14

    mov     rbx, rsi                ; out
    mov     rax, rdi

    ; days = epoch / 86400; secs_in_day = epoch % 86400 (epoch >= 0)
    mov     rcx, 86400
    xor     rdx, rdx
    div     rcx
    mov     rbp, rax                ; days

    ; H, M, S
    mov     rax, rdx
    mov     rcx, 3600
    xor     rdx, rdx
    div     rcx
    mov     [rbx + 12], eax

    mov     rax, rdx
    mov     rcx, 60
    xor     rdx, rdx
    div     rcx
    mov     [rbx + 16], eax
    mov     [rbx + 20], edx

    ; L = days + 719468  (offset so epoch starts inside era 4)
    add     rbp, 719468

    ; era = L / 146097, doe = L % 146097
    mov     rax, rbp
    mov     rcx, 146097
    xor     rdx, rdx
    div     rcx
    mov     r12, rax                ; era
    mov     r13, rdx                ; doe

    ; yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 1460
    div     rcx
    mov     r14, r13
    sub     r14, rax

    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 36524
    div     rcx
    add     r14, rax

    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 146096
    div     rcx
    sub     r14, rax

    mov     rax, r14
    xor     rdx, rdx
    mov     rcx, 365
    div     rcx
    mov     r14, rax                ; yoe

    ; y = yoe + era * 400
    imul    r12, 400
    add     r12, r14

    ; doy = doe - (365*yoe + yoe/4 - yoe/100)
    mov     rax, r14
    mov     rcx, 365
    mul     rcx
    mov     r8, rax

    mov     rax, r14
    xor     rdx, rdx
    mov     rcx, 4
    div     rcx
    add     r8, rax

    mov     rax, r14
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    sub     r8, rax

    mov     r9, r13
    sub     r9, r8                  ; doy (0..365)

    ; mp = (5*doy + 2) / 153   (Mar=0 .. Feb=11)
    mov     rax, r9
    mov     rcx, 5
    mul     rcx
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 153
    div     rcx
    mov     r10, rax                ; mp

    ; d = doy - (153*mp + 2)/5 + 1
    mov     rax, r10
    mov     rcx, 153
    mul     rcx
    add     rax, 2
    xor     rdx, rdx
    mov     rcx, 5
    div     rcx

    mov     rcx, r9
    sub     rcx, rax
    inc     rcx
    mov     [rbx + 8], ecx

    ; m = (mp < 10) ? mp + 3 : mp - 9
    cmp     r10, 10
    jge     .m_ge
    add     r10, 3
    jmp     .m_set
.m_ge:
    sub     r10, 9
.m_set:
    mov     [rbx + 4], r10d

    ; If month <= 2 we're in the next civil year (the algorithm starts
    ; the year on March 1 for the doy math).
    cmp     r10, 2
    jg      .y_set
    inc     r12
.y_set:
    mov     [rbx + 0], r12d

    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; void format_date(int64_t epoch_secs /rdi/, char *out /rsi/)
;
;   Writes 12 bytes "Mon DD HH:MM" into out. No NUL terminator.
;   - Day is space-padded to 2 chars ("Mar  3 ..." vs "Mar 31 ...")
;   - Hour and minute are zero-padded.
;
;   Stack: 3 pushes + sub 32 = 56 bytes = 8 mod 16, from entry's 8 mod 16
;   gives 0 mod 16 at the internal call to unix_to_calendar.
format_date:
    push    rbx                     ; out
    push    r12                     ; tm_base
    push    r13                     ; (alignment)
    sub     rsp, 32                 ; 24 bytes for tm + 8 alignment

    mov     rbx, rsi
    mov     r12, rsp
    mov     rsi, r12
    call    unix_to_calendar

    ; Month name: 3 bytes from month_names[(month-1)*3]
    mov     eax, [r12 + 4]
    dec     eax
    lea     rcx, [rax + rax*2]      ; *3
    lea     rdx, [rel month_names]
    add     rdx, rcx
    mov     al, [rdx]
    mov     [rbx + 0], al
    mov     al, [rdx + 1]
    mov     [rbx + 1], al
    mov     al, [rdx + 2]
    mov     [rbx + 2], al
    mov     byte [rbx + 3], ' '

    ; Day (space-padded, width 2)
    mov     eax, [r12 + 8]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    test    eax, eax
    jnz     .day_two
    mov     byte [rbx + 4], ' '
    jmp     .day_ones
.day_two:
    add     al, '0'
    mov     [rbx + 4], al
.day_ones:
    add     dl, '0'
    mov     [rbx + 5], dl
    mov     byte [rbx + 6], ' '

    ; Hour (zero-padded, width 2)
    mov     eax, [r12 + 12]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 7], al
    add     dl, '0'
    mov     [rbx + 8], dl
    mov     byte [rbx + 9], ':'

    ; Minute (zero-padded, width 2)
    mov     eax, [r12 + 16]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 10], al
    add     dl, '0'
    mov     [rbx + 11], dl

    add     rsp, 32
    pop     r13
    pop     r12
    pop     rbx
    ret

; void format_date_local(int64_t epoch_secs_utc /rdi/, char *out /rsi/)
;
;   Like format_date, but applies the local UTC offset (from /etc/localtime)
;   so the rendered "Mon DD HH:MM" is local wall time. ls -l and stat use
;   this; `date` keeps the explicit-UTC formatter so the printed string
;   matches its trailing zone label.
format_date_local:
    push    rbx                     ; saved out ptr
    push    rbp                     ; (alignment)
    mov     rbx, rsi
    mov     rbp, rdi                ; saved epoch
    call    localtime_offset_secs   ; rax = signed offset
    add     rax, rbp
    mov     rdi, rax
    mov     rsi, rbx
    call    format_date
    pop     rbp
    pop     rbx
    ret

; void format_datetime_long(int64_t epoch_secs /rdi/, char *out /rsi/)
;
;   Writes exactly 28 bytes: "DDD Mon DD HH:MM:SS UTC YYYY".
;   No NUL terminator.
;
;   Stack: 4 callee-saved pushes + sub 32 keeps inner-call rsp at 0
;   mod 16 (32 bytes for the tm struct, 8 for alignment slack).
format_datetime_long:
    push    rbx                     ; out
    push    r12                     ; tm base
    push    r13                     ; epoch (for dow recompute)
    push    r14                     ; (alignment)
    sub     rsp, 32

    mov     rbx, rsi
    mov     r13, rdi
    mov     r12, rsp

    ; Calendar fields.
    mov     rsi, r12
    call    unix_to_calendar

    ; Day-of-week: (days_since_epoch + 4) % 7 with 0=Sun.
    mov     rax, r13
    mov     rcx, 86400
    xor     rdx, rdx
    div     rcx                     ; rax = days
    add     rax, 4
    mov     rcx, 7
    xor     rdx, rdx
    div     rcx                     ; rdx = dow

    lea     rcx, [rax + rax*2]      ; rcx unused; placeholder
    lea     r8, [rdx + rdx*2]       ; r8 = dow * 3
    lea     rcx, [rel day_names]
    add     rcx, r8
    mov     al, [rcx]
    mov     [rbx + 0], al
    mov     al, [rcx + 1]
    mov     [rbx + 1], al
    mov     al, [rcx + 2]
    mov     [rbx + 2], al
    mov     byte [rbx + 3], ' '

    ; Month name.
    mov     eax, [r12 + 4]
    dec     eax
    lea     r8, [rax + rax*2]
    lea     rcx, [rel month_names]
    add     rcx, r8
    mov     al, [rcx]
    mov     [rbx + 4], al
    mov     al, [rcx + 1]
    mov     [rbx + 5], al
    mov     al, [rcx + 2]
    mov     [rbx + 6], al
    mov     byte [rbx + 7], ' '

    ; Day (space-padded 2).
    mov     eax, [r12 + 8]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    test    eax, eax
    jnz     .day_two
    mov     byte [rbx + 8], ' '
    jmp     .day_ones
.day_two:
    add     al, '0'
    mov     [rbx + 8], al
.day_ones:
    add     dl, '0'
    mov     [rbx + 9], dl
    mov     byte [rbx + 10], ' '

    ; Hour:Minute:Second (zero-padded).
    mov     eax, [r12 + 12]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 11], al
    add     dl, '0'
    mov     [rbx + 12], dl
    mov     byte [rbx + 13], ':'

    mov     eax, [r12 + 16]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 14], al
    add     dl, '0'
    mov     [rbx + 15], dl
    mov     byte [rbx + 16], ':'

    mov     eax, [r12 + 20]
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 17], al
    add     dl, '0'
    mov     [rbx + 18], dl

    mov     byte [rbx + 19], ' '
    mov     byte [rbx + 20], 'U'
    mov     byte [rbx + 21], 'T'
    mov     byte [rbx + 22], 'C'
    mov     byte [rbx + 23], ' '

    ; Year (4 digits, zero-padded).
    mov     eax, [r12 + 0]
    mov     ecx, 1000
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 24], al

    mov     eax, edx
    mov     ecx, 100
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 25], al

    mov     eax, edx
    mov     ecx, 10
    xor     edx, edx
    div     ecx
    add     al, '0'
    mov     [rbx + 26], al

    add     dl, '0'
    mov     [rbx + 27], dl

    add     rsp, 32
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
