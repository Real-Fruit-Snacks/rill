#!/usr/bin/env bats
load helper

setup() {
    require_built rmdir
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "rmdir removes empty directory" {
    /bin/mkdir "$TMPDIR/empty"
    applet rmdir "$TMPDIR/empty"
    [ ! -d "$TMPDIR/empty" ]
}

@test "rmdir errors on non-empty directory" {
    /bin/mkdir "$TMPDIR/full"
    touch "$TMPDIR/full/file"
    run applet rmdir "$TMPDIR/full"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Directory not empty"* || "$output" == *"not empty"* ]]
}

@test "rmdir errors on missing directory" {
    run applet rmdir "$TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "rmdir with no args errors" {
    run applet rmdir
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}
