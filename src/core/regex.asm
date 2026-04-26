; regex.asm — minimal BRE matcher for grep.
;
; Supports the most common BRE constructs:
;
;   .              any single character
;   *              zero-or-more of the preceding atom
;   ^   (head)     anchor: pattern must match at the start of text
;   $   (tail)     anchor: pattern must match through end of text
;   [...] [^...]   character class with optional ranges (a-z) and negation
;   \X             literal X (escapes any byte's special meaning)
;
; Not supported (callers should fall back to literal -F mode):
;   alternation, grouping, \+, \?, \{n,m\}, backreferences, \b/\w/\s, etc.
;
; Implementation: classic recursive backtracker (after Kernighan & Pike's
; "Beautiful Code" sketch) extended with character-class atoms. The
; recursion is bounded by the pattern length, so deeply nested patterns
; can blow the stack — for the size of patterns grep typically gets
; that's a non-issue in practice.

BITS 64
DEFAULT REL

global regex_search
global regex_atom_end
global regex_class_end

section .text

; ---------------------------------------------------------------------------
; int regex_search(pat /rdi/, text /rsi/) -> rax (1 if match found, else 0)
;
; Returns 1 iff `text` contains a substring matched by `pat`. ^ anchors
; the start; everywhere else we slide the start position one byte at a
; time and retry.
regex_search:
    push    rbx                     ; saved pat
    push    rbp                     ; saved text cursor

    mov     rbx, rdi
    mov     rbp, rsi

    cmp     byte [rbx], '^'
    jne     .scan_loop

    ; Anchored: try once at the start.
    inc     rbx
    mov     rdi, rbx
    mov     rsi, rbp
    call    match_here
    jmp     .ret

.scan_loop:
    mov     rdi, rbx
    mov     rsi, rbp
    call    match_here
    test    eax, eax
    jnz     .ret
    cmp     byte [rbp], 0
    je      .nomatch
    inc     rbp
    jmp     .scan_loop

.nomatch:
    xor     eax, eax

.ret:
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int match_here(pat /rdi/, text /rsi/) -> rax (1 / 0)
;
; Tries to match the rest of `pat` starting at `text` (no further sliding).
match_here:
    push    rbx                     ; pat
    push    rbp                     ; text
    push    r12                     ; atom_end
    push    r13                     ; (alignment)

    mov     rbx, rdi
    mov     rbp, rsi

    ; Empty pattern always matches.
    cmp     byte [rbx], 0
    je      .yes

    ; "$" at end-of-pattern matches end of text only.
    cmp     byte [rbx], '$'
    jne     .have_atom
    cmp     byte [rbx + 1], 0
    jne     .have_atom
    cmp     byte [rbp], 0
    je      .yes
    jmp     .no

.have_atom:
    mov     rdi, rbx
    call    regex_atom_end          ; rax = pointer past the next atom
    mov     r12, rax

    ; Quantifier?
    cmp     byte [r12], '*'
    jne     .no_star

    ; "atom*" — recurse via match_star.
    mov     rdi, rbx                ; atom start
    mov     rsi, r12                ; atom end (exclusive)
    lea     rdx, [r12 + 1]          ; pattern after '*'
    mov     rcx, rbp                ; text
    call    match_star
    jmp     .ret_eax

.no_star:
    ; No quantifier: match exactly one atom against text[0].
    cmp     byte [rbp], 0
    je      .no                     ; can't match empty text against an atom

    mov     rdi, rbx
    mov     rsi, r12
    movzx   edx, byte [rbp]
    call    atom_matches
    test    eax, eax
    jz      .no

    mov     rdi, r12
    lea     rsi, [rbp + 1]
    call    match_here
    jmp     .ret_eax

.yes:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret_eax:
.ret:
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int match_star(atom_start /rdi/, atom_end /rsi/, after_star /rdx/,
;                text /rcx/) -> rax (1 / 0)
;
; Greedy zero-or-more: count the maximum number of matches starting from
; `text`, then walk back trying `after_star` at each point until we find
; a tail match or exhaust.
;
; Stack: 6 callee-saved pushes. From entry's 8 mod 16 -> 8 mod 16 (6
; pushes = 48, 8-48 = -40 mod 16 = 8); add `sub rsp, 8` for inner-call
; alignment.
match_star:
    push    rbx                     ; atom_start
    push    rbp                     ; atom_end
    push    r12                     ; after_star
    push    r13                     ; original text
    push    r14                     ; current text cursor
    push    r15                     ; max-match count
    sub     rsp, 8

    mov     rbx, rdi
    mov     rbp, rsi
    mov     r12, rdx
    mov     r13, rcx
    mov     r14, rcx
    xor     r15, r15

.greedy:
    cmp     byte [r14], 0
    je      .greedy_done
    mov     rdi, rbx
    mov     rsi, rbp
    movzx   edx, byte [r14]
    call    atom_matches
    test    eax, eax
    jz      .greedy_done
    inc     r14
    inc     r15
    jmp     .greedy

.greedy_done:
    ; Try match_here(after_star, text + n) for n = max..0.
.shrink:
    mov     rdi, r12
    mov     rsi, r13
    add     rsi, r15
    call    match_here
    test    eax, eax
    jnz     .ret_yes
    test    r15, r15
    jz      .ret_no
    dec     r15
    jmp     .shrink

.ret_yes:
    mov     eax, 1
    jmp     .ret
.ret_no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; int atom_matches(atom_start /rdi/, atom_end /rsi/, c /edx/) -> rax (1/0)
;
; Tests whether the single-byte `c` matches the atom in [atom_start, atom_end).
atom_matches:
    movzx   eax, byte [rdi]

    cmp     al, '.'
    je      .always

    cmp     al, '\'
    jne     .check_class

    ; "\X" — literal byte at atom_start[1].
    movzx   eax, byte [rdi + 1]
    cmp     eax, edx
    je      .yes
    jmp     .no

.check_class:
    cmp     al, '['
    jne     .literal

    ; Walk class body [atom_start+1, atom_end-1).
    lea     rcx, [rdi + 1]          ; cursor
    mov     r8, rsi
    sub     r8, 1                   ; end of body (exclusive of ']')
    xor     r9d, r9d                ; negated flag
    xor     r10d, r10d              ; matched flag (must be zeroed before loop)
    cmp     byte [rcx], '^'
    jne     .body_loop
    mov     r9d, 1
    inc     rcx

.body_loop:
    cmp     rcx, r8
    jge     .body_done

    ; Range "X-Y" if rcx+2 < r8 and rcx[1] == '-'.
    lea     rax, [rcx + 2]
    cmp     rax, r8
    jge     .single_char
    cmp     byte [rcx + 1], '-'
    jne     .single_char

    ; Range.
    movzx   eax, byte [rcx]         ; lo
    movzx   r11d, byte [rcx + 2]    ; hi
    cmp     edx, eax
    jl      .range_step
    cmp     edx, r11d
    jg      .range_step
    mov     r10d, 1
.range_step:
    add     rcx, 3
    jmp     .body_loop

.single_char:
    movzx   eax, byte [rcx]
    cmp     eax, edx
    jne     .single_step
    mov     r10d, 1
.single_step:
    inc     rcx
    jmp     .body_loop

.body_done:
    ; result = matched XOR negated
    xor     r10d, r9d
    movzx   eax, r10b
    ret

.literal:
    cmp     eax, edx
    je      .yes
.no:
    xor     eax, eax
    ret
.always:
    mov     eax, 1
    ret
.yes:
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; char *regex_atom_end(p /rdi/) -> rax = pointer just past the next atom
;
; "Atom" is one of:
;   * \X           (2 bytes)
;   * [...]        (variable; may include ^ and ranges)
;   * any other    (1 byte)
;
; A NUL byte terminates the pattern, so we never read past it.
regex_atom_end:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .same                   ; empty pattern → length 0 atom

    cmp     al, '\'
    je      .escape

    cmp     al, '['
    je      .class

    lea     rax, [rdi + 1]
    ret

.escape:
    cmp     byte [rdi + 1], 0
    jne     .escape_two
    lea     rax, [rdi + 1]          ; lone trailing '\' — treat as 1 byte
    ret
.escape_two:
    lea     rax, [rdi + 2]
    ret

.class:
    jmp     regex_class_end

.same:
    mov     rax, rdi
    ret

; ---------------------------------------------------------------------------
; char *regex_class_end(p /rdi/) -> rax = pointer past the matching ']'
;
; p[0] is '['. Walks the class body honoring the rule that a literal ']'
; appearing as the first character (after an optional negating '^') is
; treated as a literal, not the closing bracket.
regex_class_end:
    lea     rax, [rdi + 1]
    cmp     byte [rax], '^'
    jne     .check_first
    inc     rax
.check_first:
    cmp     byte [rax], ']'
    jne     .scan
    inc     rax                     ; first ']' is a literal class member
.scan:
    movzx   ecx, byte [rax]
    test    ecx, ecx
    jz      .truncated
    cmp     ecx, ']'
    je      .closed
    inc     rax
    jmp     .scan
.closed:
    inc     rax                     ; past the closing ']'
    ret
.truncated:
    ret                             ; unterminated; treat current pos as end
