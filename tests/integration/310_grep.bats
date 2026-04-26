#!/usr/bin/env bats
load helper

setup() {
    require_built grep
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "grep matches a literal substring" {
    out=$(printf 'apple\nbanana\ncherry\napricot\n' | applet grep ap)
    [ "$out" = "$(printf 'apple\napricot')" ]
}

@test "grep -i is case-insensitive" {
    out=$(printf 'Apple\nBANANA\ncherry\n' | applet grep -i apple)
    [ "$out" = "Apple" ]
}

@test "grep -v inverts" {
    out=$(printf 'a\nb\nc\n' | applet grep -v b)
    [ "$out" = "$(printf 'a\nc')" ]
}

@test "grep -n prefixes line numbers" {
    out=$(printf 'one\ntwo\nthree\nfour\n' | applet grep -n t)
    [ "$out" = "$(printf '2:two\n3:three')" ]
}

@test "grep -c prints count instead of lines" {
    out=$(printf 'a\nab\nb\nabc\n' | applet grep -c a)
    [ "$out" = "3" ]
}

@test "grep with no match exits 1" {
    run bash -c "echo hello | $BUILD/grep xyz"
    [ "$status" -eq 1 ]
}

@test "grep with match exits 0" {
    run bash -c "echo hello | $BUILD/grep ll"
    [ "$status" -eq 0 ]
}

@test "grep -F treats pattern as literal" {
    out=$(echo "1.2.3" | applet grep -F .)
    [ "$out" = "1.2.3" ]
}

@test "grep multi-file prefixes lines with FILE:" {
    echo alpha > "$TMPDIR/a"
    printf 'beta\nalpha\n' > "$TMPDIR/b"
    out=$(applet grep alpha "$TMPDIR/a" "$TMPDIR/b")
    [[ "$out" == *"$TMPDIR/a:alpha"* ]]
    [[ "$out" == *"$TMPDIR/b:alpha"* ]]
}

@test "grep -c on multiple files prints per-file count" {
    printf 'a\nab\n' > "$TMPDIR/f1"
    printf 'a\n' > "$TMPDIR/f2"
    out=$(applet grep -c a "$TMPDIR/f1" "$TMPDIR/f2")
    [[ "$out" == *"$TMPDIR/f1:2"* ]]
    [[ "$out" == *"$TMPDIR/f2:1"* ]]
}

@test "grep handles empty file" {
    : > "$TMPDIR/empty"
    run applet grep anything "$TMPDIR/empty"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "grep matches pattern at line boundaries" {
    out=$(printf 'foo\nfoobar\nbaz\n' | applet grep foo)
    [ "$out" = "$(printf 'foo\nfoobar')" ]
}

@test "grep -iv combines flags" {
    out=$(printf 'Apple\nBANANA\nCherry\n' | applet grep -iv apple)
    [ "$out" = "$(printf 'BANANA\nCherry')" ]
}
