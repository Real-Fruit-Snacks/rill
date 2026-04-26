#!/usr/bin/env bats
load helper

setup() {
    require_built tee
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "tee writes stdin to stdout and one file" {
    out=$(echo hello | applet tee "$TMPDIR/a")
    [ "$out" = "hello" ]
    [ "$(/bin/cat "$TMPDIR/a")" = "hello" ]
}

@test "tee writes to multiple files" {
    echo data | applet tee "$TMPDIR/a" "$TMPDIR/b" "$TMPDIR/c" > /dev/null
    [ "$(/bin/cat "$TMPDIR/a")" = "data" ]
    [ "$(/bin/cat "$TMPDIR/b")" = "data" ]
    [ "$(/bin/cat "$TMPDIR/c")" = "data" ]
}

@test "tee truncates by default" {
    echo old > "$TMPDIR/f"
    echo new | applet tee "$TMPDIR/f" > /dev/null
    [ "$(/bin/cat "$TMPDIR/f")" = "new" ]
}

@test "tee -a appends" {
    echo first > "$TMPDIR/f"
    echo second | applet tee -a "$TMPDIR/f" > /dev/null
    [ "$(/bin/cat "$TMPDIR/f")" = "$(printf 'first\nsecond')" ]
}

@test "tee continues writing other outputs when one file fails to open" {
    run bash -c "echo data | $BUILD/tee /no/such/dir/file $TMPDIR/good > /dev/null"
    [ "$status" -eq 1 ]
    [ "$(/bin/cat "$TMPDIR/good")" = "data" ]
}

@test "tee with no files just copies stdin to stdout" {
    out=$(printf 'a\nb\n' | applet tee)
    [ "$out" = "$(printf 'a\nb')" ]
}
