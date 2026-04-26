#!/usr/bin/env bats
load helper

setup() {
    require_built sort
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "sort default sorts lexicographically" {
    out=$(printf 'banana\napple\ncherry\n' | applet sort)
    [ "$out" = "$(printf 'apple\nbanana\ncherry')" ]
}

@test "sort -r reverses" {
    out=$(printf 'a\nb\nc\n' | applet sort -r)
    [ "$out" = "$(printf 'c\nb\na')" ]
}

@test "sort -n compares numerically" {
    out=$(printf '10\n2\n100\n3\n' | applet sort -n)
    [ "$out" = "$(printf '2\n3\n10\n100')" ]
}

@test "sort -n handles negative numbers" {
    out=$(printf '%s\n' 5 -3 0 -10 | applet sort -n)
    [ "$out" = "$(printf '%s\n' -10 -3 0 5 | head -c -1)" ]
}

@test "sort -u collapses duplicates" {
    out=$(printf 'a\nb\nb\nc\nc\nc\n' | applet sort -u)
    [ "$out" = "$(printf 'a\nb\nc')" ]
}

@test "sort -rn combined" {
    out=$(printf '5\n10\n1\n100\n' | applet sort -rn)
    [ "$out" = "$(printf '100\n10\n5\n1')" ]
}

@test "sort handles file argument" {
    printf 'b\na\nc\n' > "$TMPDIR/in"
    out=$(applet sort "$TMPDIR/in")
    [ "$out" = "$(printf 'a\nb\nc')" ]
}

@test "sort matches coreutils on a typical input" {
    printf 'red\nblue\ngreen\nred\nyellow\n' > "$TMPDIR/in"
    diff <(applet sort "$TMPDIR/in") <(/usr/bin/sort "$TMPDIR/in")
}

@test "sort -u matches coreutils" {
    printf 'a\nb\na\nc\nb\n' > "$TMPDIR/in"
    diff <(applet sort -u "$TMPDIR/in") <(/usr/bin/sort -u "$TMPDIR/in")
}

@test "sort empty input emits nothing" {
    out=$(printf '' | applet sort)
    [ -z "$out" ]
}

@test "sort handles input without trailing newline" {
    out=$(printf 'b\na' | applet sort)
    [ "$out" = "$(printf 'a\nb')" ]
}

@test "sort -k 2 sorts on the second field" {
    out=$(printf 'banana 2\napple 1\ncherry 3\n' | applet sort -k 2)
    [ "$out" = "$(printf 'apple 1\nbanana 2\ncherry 3')" ]
}

@test "sort -k 2 -n combines field selection and numeric" {
    out=$(printf 'banana 30\napple 100\ncherry 5\n' | applet sort -k 2 -n)
    [ "$out" = "$(printf 'cherry 5\nbanana 30\napple 100')" ]
}

@test "sort -k 1,1 limits comparison to a single field" {
    # First-field tie-break: only field 1 matters; field 2 remains in
    # input order for equal keys (we're not strictly stable but the keys
    # here are all distinct).
    out=$(printf 'b zzz\na yyy\nc xxx\n' | applet sort -k 1,1)
    [ "$out" = "$(printf 'a yyy\nb zzz\nc xxx')" ]
}

@test "sort -t : -k 2 uses ':' as field separator" {
    out=$(printf 'foo:b\nbar:a\nbaz:c\n' | applet sort -t : -k 2)
    [ "$out" = "$(printf 'bar:a\nfoo:b\nbaz:c')" ]
}

@test "sort -t, -k2 inline single-arg form" {
    out=$(printf 'a,3\nb,1\nc,2\n' | applet sort -t, -k2)
    [ "$out" = "$(printf 'b,1\nc,2\na,3')" ]
}

@test "sort -f folds case for comparison" {
    # 'apple' < 'Banana' under -f because 'a' == 'A' < 'B'.
    out=$(printf 'apple\nBanana\nCherry\nbutter\n' | applet sort -f)
    expected=$(printf 'apple\nBanana\nCherry\nbutter\n' | /usr/bin/sort -f)
    [ "$out" = "$expected" ]
}

@test "sort -k matches coreutils on a typical input" {
    printf 'banana 30\napple 100\ncherry 5\nplum 17\n' > "$TMPDIR/in"
    diff <(applet sort -k 2 -n "$TMPDIR/in") <(/usr/bin/sort -k 2 -n "$TMPDIR/in")
}

@test "sort -t with no arg errors" {
    run applet sort -t
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing argument"* ]]
}
