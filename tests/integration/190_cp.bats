#!/usr/bin/env bats
load helper

setup() {
    require_built cp
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "cp copies a single file" {
    echo "hello" > "$TMPDIR/src"
    applet cp "$TMPDIR/src" "$TMPDIR/dst"
    [ -f "$TMPDIR/dst" ]
    [ "$(/bin/cat "$TMPDIR/dst")" = "hello" ]
}

@test "cp into a directory uses basename" {
    echo "data" > "$TMPDIR/file"
    /bin/mkdir "$TMPDIR/dir"
    applet cp "$TMPDIR/file" "$TMPDIR/dir"
    [ -f "$TMPDIR/dir/file" ]
    [ "$(/bin/cat "$TMPDIR/dir/file")" = "data" ]
}

@test "cp many files to a directory" {
    echo a > "$TMPDIR/a"
    echo b > "$TMPDIR/b"
    /bin/mkdir "$TMPDIR/dest"
    applet cp "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/dest"
    [ -f "$TMPDIR/dest/a" ]
    [ -f "$TMPDIR/dest/b" ]
}

@test "cp errors on missing source" {
    run applet cp "$TMPDIR/nope" "$TMPDIR/out"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "cp many files but target is not a directory" {
    touch "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/file"
    run applet cp "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"target is not a directory"* ]]
}

@test "cp preserves source mode bits" {
    echo data > "$TMPDIR/src"
    /bin/chmod 0640 "$TMPDIR/src"
    applet cp "$TMPDIR/src" "$TMPDIR/dst"
    [ "$(stat -c %a "$TMPDIR/dst")" = "640" ]
}

@test "cp with no args errors" {
    run applet cp
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "cp 64KB file is byte-identical" {
    head -c 65536 /dev/urandom > "$TMPDIR/big"
    applet cp "$TMPDIR/big" "$TMPDIR/big2"
    diff "$TMPDIR/big" "$TMPDIR/big2"
}
