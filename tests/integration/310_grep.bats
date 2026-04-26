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

@test "grep . matches any single character" {
    out=$(printf 'apple\nat\nack\n' | applet grep 'a..')
    [ "$out" = "$(printf 'apple\nack')" ]
}

@test "grep ^ anchors to line start" {
    out=$(printf 'foo bar\nbar foo\n' | applet grep '^foo')
    [ "$out" = "foo bar" ]
}

@test "grep \$ anchors to line end" {
    out=$(printf 'foo bar\nbar foo\n' | applet grep 'foo$')
    [ "$out" = "bar foo" ]
}

@test "grep a* matches zero or more" {
    out=$(printf 'x\nax\naax\nbb\n' | applet grep 'a*x')
    [ "$out" = "$(printf 'x\nax\naax')" ]
}

@test "grep [abc] character class" {
    out=$(printf 'apple\nberry\ncherry\ndog\n' | applet grep '^[abc]')
    [ "$out" = "$(printf 'apple\nberry\ncherry')" ]
}

@test "grep [a-c] range" {
    out=$(printf 'apple\nberry\ncherry\ndog\n' | applet grep '^[a-c]')
    [ "$out" = "$(printf 'apple\nberry\ncherry')" ]
}

@test "grep [^a-c] negated range" {
    out=$(printf 'apple\nberry\ndog\nelf\n' | applet grep '^[^a-c]')
    [ "$out" = "$(printf 'dog\nelf')" ]
}

@test "grep [0-9] matches digits" {
    out=$(printf 'abc\nabc123\nxyz\n' | applet grep '[0-9]')
    [ "$out" = "abc123" ]
}

@test "grep escapes a metachar with backslash" {
    out=$(printf 'a.b\nab\nazb\n' | applet grep 'a\.b')
    [ "$out" = "a.b" ]
}

@test "grep -F bypasses regex meta" {
    out=$(echo "1.2.3" | applet grep -F .)
    [ "$out" = "1.2.3" ]
    # Plain regex meta '.' would match 'a.b' AND 'aXb', whereas -F is literal.
    out=$(printf 'a.b\naXb\n' | applet grep -F '.')
    [ "$out" = "a.b" ]
}

@test "grep ^\$ matches empty lines" {
    out=$(printf 'a\n\nb\n\nc\n' | applet grep -c '^$')
    [ "$out" = "2" ]
}

@test "grep -i with regex" {
    out=$(printf 'Apple\nBANANA\ncherry\n' | applet grep -i '^[a-z]pple')
    [ "$out" = "Apple" ]
}
