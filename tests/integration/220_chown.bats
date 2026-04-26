#!/usr/bin/env bats
load helper

setup() {
    require_built chown
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "chown to current uid is a no-op success" {
    touch "$TMPDIR/f"
    cur_uid=$(id -u)
    applet chown "$cur_uid" "$TMPDIR/f"
    [ "$(stat -c %u "$TMPDIR/f")" = "$cur_uid" ]
}

@test "chown UID:GID accepts both ids" {
    touch "$TMPDIR/f"
    cur_uid=$(id -u)
    cur_gid=$(id -g)
    applet chown "$cur_uid:$cur_gid" "$TMPDIR/f"
    [ "$(stat -c %u "$TMPDIR/f")" = "$cur_uid" ]
    [ "$(stat -c %g "$TMPDIR/f")" = "$cur_gid" ]
}

@test "chown :GID changes group only" {
    touch "$TMPDIR/f"
    cur_gid=$(id -g)
    applet chown ":$cur_gid" "$TMPDIR/f"
    [ "$(stat -c %g "$TMPDIR/f")" = "$cur_gid" ]
}

@test "chown of unprivileged user fails on owned file" {
    touch "$TMPDIR/f"
    run applet chown 0 "$TMPDIR/f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation not permitted"* ]]
}

@test "chown rejects non-numeric spec" {
    touch "$TMPDIR/f"
    run applet chown bob "$TMPDIR/f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid"* ]]
}

@test "chown rejects malformed UID:GID" {
    touch "$TMPDIR/f"
    run applet chown "1000:abc" "$TMPDIR/f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid"* ]]
}

@test "chown with too few args errors" {
    run applet chown
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
    run applet chown 1000
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}
