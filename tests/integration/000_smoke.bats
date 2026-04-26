#!/usr/bin/env bats
#
# Phase 0 smoke tests. Verifies the build pipeline and the dispatcher.

setup() {
    BUILD="$BATS_TEST_DIRNAME/../../build"
    RILL="$BUILD/rill"
    [ -x "$RILL" ] || skip "rill binary not built"
}

@test "rill binary is statically linked" {
    run file "$RILL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"statically linked"* ]]
}

@test "rill with no args prints usage and exits 127" {
    run "$RILL"
    [ "$status" -eq 127 ]
    [[ "$output" == *"applet not found"* ]]
}

@test "rill with unknown applet exits 127" {
    run "$RILL" definitely-not-an-applet
    [ "$status" -eq 127 ]
}

@test "rill true exits 0 with no output" {
    run "$RILL" true
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "rill true ignores extra args" {
    run "$RILL" true a b c
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "true symlink dispatches to true applet" {
    [ -L "$BUILD/true" ] || skip "symlink not created (run: make symlinks)"
    run "$BUILD/true"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
