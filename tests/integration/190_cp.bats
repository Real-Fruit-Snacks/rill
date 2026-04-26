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

@test "cp without -r refuses a directory source" {
    /bin/mkdir "$TMPDIR/d"
    run applet cp "$TMPDIR/d" "$TMPDIR/dst"
    [ "$status" -eq 1 ]
    [[ "$output" == *"omitting directory"* ]]
}

@test "cp -r copies a directory tree to a new name" {
    /bin/mkdir -p "$TMPDIR/src/sub"
    echo a > "$TMPDIR/src/x"
    echo b > "$TMPDIR/src/sub/y"
    applet cp -r "$TMPDIR/src" "$TMPDIR/copy"
    [ -d "$TMPDIR/copy" ]
    [ "$(/bin/cat "$TMPDIR/copy/x")" = "a" ]
    [ "$(/bin/cat "$TMPDIR/copy/sub/y")" = "b" ]
}

@test "cp -r preserves symlinks (no follow)" {
    /bin/mkdir "$TMPDIR/src"
    /bin/ln -s /tmp "$TMPDIR/src/link"
    applet cp -r "$TMPDIR/src" "$TMPDIR/copy"
    [ -L "$TMPDIR/copy/link" ]
    [ "$(readlink "$TMPDIR/copy/link")" = "/tmp" ]
}

@test "cp -r into an existing directory copies under it" {
    /bin/mkdir -p "$TMPDIR/src/nested"
    echo content > "$TMPDIR/src/nested/file"
    /bin/mkdir "$TMPDIR/dest"
    applet cp -r "$TMPDIR/src" "$TMPDIR/dest"
    [ "$(/bin/cat "$TMPDIR/dest/src/nested/file")" = "content" ]
}

@test "cp -R is alias for -r" {
    /bin/mkdir "$TMPDIR/src"
    touch "$TMPDIR/src/x"
    applet cp -R "$TMPDIR/src" "$TMPDIR/copy"
    [ -f "$TMPDIR/copy/x" ]
}

@test "cp -r preserves directory mode bits" {
    /bin/mkdir "$TMPDIR/src"
    /bin/chmod 0750 "$TMPDIR/src"
    applet cp -r "$TMPDIR/src" "$TMPDIR/copy"
    [ "$(stat -c %a "$TMPDIR/copy")" = "750" ]
}
