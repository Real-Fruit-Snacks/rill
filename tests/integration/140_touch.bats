#!/usr/bin/env bats
load helper

setup() {
    require_built touch
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "touch creates a missing file" {
    applet touch "$TMPDIR/new"
    [ -f "$TMPDIR/new" ]
    [ ! -s "$TMPDIR/new" ]
}

@test "touch updates mtime of existing file" {
    echo content > "$TMPDIR/old"
    /bin/touch -d '2000-01-01 00:00:00' "$TMPDIR/old"
    before=$(stat -c %Y "$TMPDIR/old")
    applet touch "$TMPDIR/old"
    after=$(stat -c %Y "$TMPDIR/old")
    [ "$after" -gt "$before" ]
    # And content is preserved.
    [ "$(/bin/cat "$TMPDIR/old")" = "content" ]
}

@test "touch creates multiple files" {
    applet touch "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/c"
    [ -f "$TMPDIR/a" ]
    [ -f "$TMPDIR/b" ]
    [ -f "$TMPDIR/c" ]
}

@test "touch errors on missing parent directory" {
    run applet touch "$TMPDIR/missing/file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "touch with no args errors" {
    run applet touch
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}
