#!/usr/bin/env bats
load helper

setup() {
    require_built stat
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "stat of a regular file prints expected fields" {
    echo "12345" > "$TMPDIR/f"          # 6 bytes including newline
    /bin/chmod 0644 "$TMPDIR/f"
    out=$(applet stat "$TMPDIR/f")
    [[ "$out" == *"File: $TMPDIR/f"* ]]
    [[ "$out" == *"Size: 6"* ]]
    [[ "$out" == *"Type: regular file"* ]]
    [[ "$out" == *"Mode: 0644"* ]]
    [[ "$out" == *"Mtime:"* ]]
}

@test "stat of a directory reports type directory" {
    out=$(applet stat "$TMPDIR")
    [[ "$out" == *"Type: directory"* ]]
}

@test "stat of multiple paths prints both" {
    touch "$TMPDIR/a" "$TMPDIR/b"
    out=$(applet stat "$TMPDIR/a" "$TMPDIR/b")
    [[ "$out" == *"File: $TMPDIR/a"* ]]
    [[ "$out" == *"File: $TMPDIR/b"* ]]
}

@test "stat reports symbolic link type" {
    /bin/ln -s /tmp "$TMPDIR/link"
    out=$(applet stat "$TMPDIR/link")
    # Without -L we follow symlinks (matches default coreutils stat).
    [[ "$out" == *"Type: directory"* ]]
}

@test "stat errors on missing path" {
    run applet stat "$TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "stat with no args errors" {
    run applet stat
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}
