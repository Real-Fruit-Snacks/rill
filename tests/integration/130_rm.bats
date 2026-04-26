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

@test "rm -r removes an empty directory" {
    /bin/mkdir "$TMPDIR/empty"
    applet rm -r "$TMPDIR/empty"
    [ ! -d "$TMPDIR/empty" ]
}

@test "rm -r removes a directory tree" {
    /bin/mkdir -p "$TMPDIR/a/b/c"
    touch "$TMPDIR/a/x" "$TMPDIR/a/b/y" "$TMPDIR/a/b/c/z"
    applet rm -r "$TMPDIR/a"
    [ ! -d "$TMPDIR/a" ]
}

@test "rm -r through a symlink doesn't follow into target" {
    /bin/mkdir "$TMPDIR/a"
    /bin/mkdir "$TMPDIR/elsewhere"
    touch "$TMPDIR/elsewhere/keep"
    /bin/ln -s "$TMPDIR/elsewhere" "$TMPDIR/a/link"
    applet rm -r "$TMPDIR/a"
    [ ! -e "$TMPDIR/a" ]
    [ -f "$TMPDIR/elsewhere/keep" ]
}

@test "rm -R is alias for -r" {
    /bin/mkdir "$TMPDIR/d"
    touch "$TMPDIR/d/file"
    applet rm -R "$TMPDIR/d"
    [ ! -d "$TMPDIR/d" ]
}

@test "rm -rf ignores missing path" {
    run applet rm -rf "$TMPDIR/nope"
    [ "$status" -eq 0 ]
}

@test "rm -r reports per-entry errors but continues" {
    /bin/mkdir "$TMPDIR/d"
    touch "$TMPDIR/d/file"
    /bin/chmod 0500 "$TMPDIR/d"
    run applet rm -r "$TMPDIR/d"
    /bin/chmod 0700 "$TMPDIR/d"             # cleanup
    [ "$status" -eq 1 ]
}
