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
