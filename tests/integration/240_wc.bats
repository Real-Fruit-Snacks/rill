#!/usr/bin/env bats
load helper

setup() {
    require_built wc
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "wc default prints lines, words, bytes" {
    out=$(printf 'one two\nthree four\n' | applet wc)
    # 2 lines, 4 words, 19 bytes ("one two\nthree four\n")
    [[ "$out" == *"2"* ]]
    [[ "$out" == *"4"* ]]
    [[ "$out" == *"19"* ]]
}

@test "wc -l counts lines" {
    out=$(printf 'a\nb\nc\n' | applet wc -l)
    [[ "$out" == *"3"* ]]
}

@test "wc -w counts words" {
    out=$(echo "alpha beta gamma delta" | applet wc -w)
    [[ "$out" == *"4"* ]]
}

@test "wc -c counts bytes" {
    out=$(printf '12345' | applet wc -c)
    [[ "$out" == *"5"* ]]
}

@test "wc on file prints filename" {
    echo hello > "$TMPDIR/f"
    out=$(applet wc "$TMPDIR/f")
    [[ "$out" == *"$TMPDIR/f"* ]]
}

@test "wc on multiple files prints total row" {
    echo a > "$TMPDIR/f1"
    echo b > "$TMPDIR/f2"
    out=$(applet wc "$TMPDIR/f1" "$TMPDIR/f2")
    [[ "$out" == *"total"* ]]
}

@test "wc -lwc combined gives all three columns" {
    out=$(printf 'a b\n' | applet wc -l -w -c)
    [[ "$out" == *"1"* ]]
    [[ "$out" == *"2"* ]]
    [[ "$out" == *"4"* ]]
}

@test "wc handles file without trailing newline" {
    printf 'no newline' > "$TMPDIR/f"
    out=$(applet wc -l "$TMPDIR/f")
    [[ "$out" == *"0"* ]]
}
