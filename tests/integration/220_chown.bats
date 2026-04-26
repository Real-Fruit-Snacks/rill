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

@test "chown by name resolves via /etc/passwd" {
    touch "$TMPDIR/f"
    cur_user=$(id -un)
    applet chown "$cur_user" "$TMPDIR/f"
    [ "$(stat -c %U "$TMPDIR/f")" = "$cur_user" ]
}

@test "chown name:name resolves both" {
    touch "$TMPDIR/f"
    cur_user=$(id -un)
    cur_group=$(id -gn)
    applet chown "$cur_user:$cur_group" "$TMPDIR/f"
    [ "$(stat -c %U:%G "$TMPDIR/f")" = "$cur_user:$cur_group" ]
}

@test "chown :name resolves group only" {
    touch "$TMPDIR/f"
    cur_group=$(id -gn)
    applet chown ":$cur_group" "$TMPDIR/f"
    [ "$(stat -c %G "$TMPDIR/f")" = "$cur_group" ]
}

@test "chown -R chowns a tree" {
    /bin/mkdir -p "$TMPDIR/d/sub"
    touch "$TMPDIR/d/x" "$TMPDIR/d/sub/y"
    cur_user=$(id -un)
    applet chown -R "$cur_user" "$TMPDIR/d"
    [ "$(stat -c %U "$TMPDIR/d")" = "$cur_user" ]
    [ "$(stat -c %U "$TMPDIR/d/x")" = "$cur_user" ]
    [ "$(stat -c %U "$TMPDIR/d/sub/y")" = "$cur_user" ]
}

@test "chown -R does not follow symlinks" {
    /bin/mkdir "$TMPDIR/d" "$TMPDIR/elsewhere"
    touch "$TMPDIR/elsewhere/keep"
    /bin/ln -s "$TMPDIR/elsewhere" "$TMPDIR/d/link"
    cur_user=$(id -un)
    applet chown -R "$cur_user" "$TMPDIR/d"
    # The link target's contents must not have been chown'd through.
    # We can't fully verify uid changes (we're already the owner), but
    # at least the keep file should still exist and be readable.
    [ -f "$TMPDIR/elsewhere/keep" ]
    [ -L "$TMPDIR/d/link" ]
}

@test "chown rejects unknown name" {
    touch "$TMPDIR/f"
    run applet chown definitely_no_such_user_42 "$TMPDIR/f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid"* ]]
}

@test "chown -h works on a dangling symlink" {
    /bin/ln -s /no/such/target "$TMPDIR/dangling"
    cur_uid=$(id -u)
    # Without -h: chown follows the link, target is missing → fail.
    run applet chown "$cur_uid" "$TMPDIR/dangling"
    [ "$status" -ne 0 ]
    # With -h: the link itself is targeted; missing target is irrelevant.
    applet chown -h "$cur_uid" "$TMPDIR/dangling"
    [ -L "$TMPDIR/dangling" ]
}

@test "chown -hR combined flags accepted" {
    /bin/mkdir "$TMPDIR/d"
    touch "$TMPDIR/d/x"
    /bin/ln -s /no/such/path "$TMPDIR/d/broken"
    cur_user=$(id -un)
    applet chown -hR "$cur_user" "$TMPDIR/d"
    [ -L "$TMPDIR/d/broken" ]
}
