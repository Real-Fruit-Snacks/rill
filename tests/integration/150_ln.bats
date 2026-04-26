#!/usr/bin/env bats
load helper

setup() {
    require_built ln
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "ln creates a hard link" {
    echo data > "$TMPDIR/src"
    applet ln "$TMPDIR/src" "$TMPDIR/hardlink"
    [ -f "$TMPDIR/hardlink" ]
    # Same inode.
    [ "$(stat -c %i "$TMPDIR/src")" = "$(stat -c %i "$TMPDIR/hardlink")" ]
}

@test "ln -s creates a symbolic link" {
    echo data > "$TMPDIR/src"
    applet ln -s "$TMPDIR/src" "$TMPDIR/symlink"
    [ -L "$TMPDIR/symlink" ]
    [ "$(readlink "$TMPDIR/symlink")" = "$TMPDIR/src" ]
}

@test "ln -s preserves the literal target string" {
    applet ln -s "../foo" "$TMPDIR/relsym"
    [ "$(readlink "$TMPDIR/relsym")" = "../foo" ]
}

@test "ln errors when LINK_NAME already exists (no -f)" {
    touch "$TMPDIR/src" "$TMPDIR/existing"
    run applet ln "$TMPDIR/src" "$TMPDIR/existing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"File exists"* ]]
}

@test "ln -sf overwrites existing target" {
    touch "$TMPDIR/src" "$TMPDIR/existing"
    applet ln -sf "$TMPDIR/src" "$TMPDIR/existing"
    [ -L "$TMPDIR/existing" ]
}

@test "ln with one arg errors (TARGET-only form not yet supported)" {
    touch "$TMPDIR/src"
    run applet ln "$TMPDIR/src"
    [ "$status" -eq 1 ]
}

@test "ln with no args errors" {
    run applet ln
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}
