#!/usr/bin/env bats
load helper

setup() {
    require_built mv
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "mv renames a file" {
    echo hi > "$TMPDIR/a"
    applet mv "$TMPDIR/a" "$TMPDIR/b"
    [ ! -e "$TMPDIR/a" ]
    [ -f "$TMPDIR/b" ]
    [ "$(/bin/cat "$TMPDIR/b")" = "hi" ]
}

@test "mv into a directory uses basename" {
    echo data > "$TMPDIR/file"
    /bin/mkdir "$TMPDIR/dir"
    applet mv "$TMPDIR/file" "$TMPDIR/dir"
    [ ! -e "$TMPDIR/file" ]
    [ -f "$TMPDIR/dir/file" ]
}

@test "mv many files to a directory" {
    touch "$TMPDIR/a" "$TMPDIR/b"
    /bin/mkdir "$TMPDIR/dest"
    applet mv "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/dest"
    [ -f "$TMPDIR/dest/a" ]
    [ -f "$TMPDIR/dest/b" ]
    [ ! -e "$TMPDIR/a" ]
    [ ! -e "$TMPDIR/b" ]
}

@test "mv many files but target is not a directory" {
    touch "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/file"
    run applet mv "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a directory"* ]]
}

@test "mv errors on missing source" {
    run applet mv "$TMPDIR/nope" "$TMPDIR/out"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "mv with too few args errors" {
    run applet mv
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
    run applet mv "$TMPDIR/a"
    [ "$status" -eq 1 ]
}

@test "mv overwrites an existing destination file" {
    echo old > "$TMPDIR/dst"
    echo new > "$TMPDIR/src"
    applet mv "$TMPDIR/src" "$TMPDIR/dst"
    [ "$(/bin/cat "$TMPDIR/dst")" = "new" ]
}
