#!/usr/bin/env bats
load helper

setup() {
    require_built cat
    TMPF=$(mktemp)
    printf 'line1\nline2\nline3\n' > "$TMPF"
}

teardown() {
    [ -n "${TMPF:-}" ] && rm -f "$TMPF"
}

@test "cat of single file matches coreutils" {
    diff <(applet cat "$TMPF") <(/bin/cat "$TMPF")
}

@test "cat reads stdin when no args" {
    out=$(printf 'a\nb\n' | applet cat)
    [ "$out" = "$(printf 'a\nb')" ]
}

@test "cat treats - as stdin" {
    out=$(printf 'x\ny\n' | applet cat -)
    [ "$out" = "$(printf 'x\ny')" ]
}

@test "cat concatenates multiple files" {
    TMPF2=$(mktemp)
    printf 'extra\n' > "$TMPF2"
    out=$(applet cat "$TMPF" "$TMPF2")
    expected=$(/bin/cat "$TMPF" "$TMPF2")
    [ "$out" = "$expected" ]
    rm -f "$TMPF2"
}

@test "cat reports missing file with errno text" {
    run applet cat /no/such/path/here
    [ "$status" -eq 1 ]
    [[ "$output" == *"cat: /no/such/path/here: No such file or directory"* ]]
}

@test "cat continues past missing file but exits 1" {
    run applet cat /no/such/path "$TMPF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"line1"* ]]
    [[ "$output" == *"line2"* ]]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "cat is byte-identical to coreutils on a 64KB file" {
    BIG=$(mktemp)
    head -c 65536 /dev/urandom > "$BIG"
    diff <(applet cat "$BIG") <(/bin/cat "$BIG")
    rm -f "$BIG"
}
