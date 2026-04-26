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

@test "stat shows username and groupname when resolvable" {
    touch "$TMPDIR/f"
    cur_user=$(id -un)
    cur_group=$(id -gn)
    out=$(applet stat "$TMPDIR/f")
    [[ "$out" == *"Uid:  $cur_user"* ]]
    [[ "$out" == *"Gid:  $cur_group"* ]]
}

@test "stat formats Mtime as 'Mon DD HH:MM'" {
    touch "$TMPDIR/f"
    out=$(applet stat "$TMPDIR/f")
    # Three-letter month, two-digit day, HH:MM after a space.
    grep -qE "Mtime: (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+[0-9]{1,2} [0-9]{2}:[0-9]{2}" <<<"$out"
}
