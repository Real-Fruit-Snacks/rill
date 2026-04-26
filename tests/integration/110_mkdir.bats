#!/usr/bin/env bats
load helper

setup() {
    require_built mkdir
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "mkdir creates a single directory" {
    applet mkdir "$TMPDIR/new"
    [ -d "$TMPDIR/new" ]
}

@test "mkdir errors on existing directory without -p" {
    /bin/mkdir "$TMPDIR/exists"
    run applet mkdir "$TMPDIR/exists"
    [ "$status" -eq 1 ]
    [[ "$output" == *"File exists"* ]]
}

@test "mkdir -p tolerates existing directory" {
    /bin/mkdir "$TMPDIR/here"
    run applet mkdir -p "$TMPDIR/here"
    [ "$status" -eq 0 ]
}

@test "mkdir -p creates nested parents" {
    applet mkdir -p "$TMPDIR/a/b/c/d"
    [ -d "$TMPDIR/a/b/c/d" ]
}

@test "mkdir -p collapses repeated slashes" {
    applet mkdir -p "$TMPDIR/x//y//z"
    [ -d "$TMPDIR/x/y/z" ]
}

@test "mkdir without -p fails when parent missing" {
    run applet mkdir "$TMPDIR/nope/child"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "mkdir with no args errors" {
    run applet mkdir
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "mkdir creates multiple directories" {
    applet mkdir "$TMPDIR/d1" "$TMPDIR/d2" "$TMPDIR/d3"
    [ -d "$TMPDIR/d1" ]
    [ -d "$TMPDIR/d2" ]
    [ -d "$TMPDIR/d3" ]
}
