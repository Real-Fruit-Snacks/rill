#!/usr/bin/env bats
load helper

setup() {
    require_built rm
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "rm removes a single file" {
    touch "$TMPDIR/x"
    applet rm "$TMPDIR/x"
    [ ! -e "$TMPDIR/x" ]
}

@test "rm removes multiple files" {
    touch "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/c"
    applet rm "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/c"
    [ ! -e "$TMPDIR/a" ]
    [ ! -e "$TMPDIR/b" ]
    [ ! -e "$TMPDIR/c" ]
}

@test "rm errors on missing file without -f" {
    run applet rm "$TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "rm -f silently ignores missing file" {
    run applet rm -f "$TMPDIR/nope"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "rm refuses to remove a directory" {
    /bin/mkdir "$TMPDIR/dir"
    run applet rm "$TMPDIR/dir"
    [ "$status" -eq 1 ]
    [ -d "$TMPDIR/dir" ]
}

@test "rm -f exits 0 when one file is missing and another removed" {
    touch "$TMPDIR/exists"
    run applet rm -f "$TMPDIR/missing" "$TMPDIR/exists"
    [ "$status" -eq 0 ]
    [ ! -e "$TMPDIR/exists" ]
}
