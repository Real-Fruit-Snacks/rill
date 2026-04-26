#!/usr/bin/env bats
load helper

setup() {
    require_built uniq
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "uniq collapses adjacent duplicates" {
    out=$(printf 'a\na\nb\nb\nb\nc\n' | applet uniq)
    [ "$out" = "$(printf 'a\nb\nc')" ]
}

@test "uniq does not collapse non-adjacent duplicates" {
    out=$(printf 'a\nb\na\n' | applet uniq)
    [ "$out" = "$(printf 'a\nb\na')" ]
}

@test "uniq -c prefixes the count" {
    out=$(printf 'a\na\nb\n' | applet uniq -c)
    [[ "$out" == *"2"* ]]
    [[ "$out" == *"1"* ]]
}

@test "uniq -d only emits duplicated lines" {
    out=$(printf 'a\na\nb\nc\nc\n' | applet uniq -d)
    [ "$out" = "$(printf 'a\nc')" ]
}

@test "uniq -u only emits unique lines" {
    out=$(printf 'a\na\nb\nc\nc\n' | applet uniq -u)
    [ "$out" = "b" ]
}

@test "uniq reads from a file argument" {
    printf 'x\nx\ny\n' > "$TMPDIR/f"
    out=$(applet uniq "$TMPDIR/f")
    [ "$out" = "$(printf 'x\ny')" ]
}

@test "uniq handles input without trailing newline" {
    out=$(printf 'a\na\nb' | applet uniq)
    [ "$out" = "$(printf 'a\nb')" ]
}

@test "uniq matches coreutils on a typical input" {
    printf 'apple\napple\nbanana\ncherry\ncherry\ncherry\n' > "$TMPDIR/f"
    diff <(applet uniq "$TMPDIR/f") <(/usr/bin/uniq "$TMPDIR/f")
}
