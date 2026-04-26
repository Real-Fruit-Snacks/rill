#!/usr/bin/env bats
load helper

setup() {
    require_built readlink
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "readlink prints target of a symlink" {
    /bin/ln -s /tmp/somewhere "$TMPDIR/link"
    out=$(applet readlink "$TMPDIR/link")
    [ "$out" = "/tmp/somewhere" ]
}

@test "readlink fails on non-symlink" {
    touch "$TMPDIR/file"
    run applet readlink "$TMPDIR/file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid argument"* ]]
}

@test "readlink fails on missing path" {
    run applet readlink "$TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "readlink with no args errors" {
    run applet readlink
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "readlink output ends with newline" {
    /bin/ln -s a "$TMPDIR/L"
    OUT=$(mktemp)
    applet readlink "$TMPDIR/L" > "$OUT"
    [ "$(tail -c 1 "$OUT")" = "$(printf '\n')" ]
    rm -f "$OUT"
}
