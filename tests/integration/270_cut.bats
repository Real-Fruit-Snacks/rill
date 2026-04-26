#!/usr/bin/env bats
load helper

setup() {
    require_built cut
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "cut -c with single positions" {
    out=$(echo "abcdefgh" | applet cut -c 1,3,5)
    [ "$out" = "ace" ]
}

@test "cut -c with closed range" {
    out=$(echo "abcdefgh" | applet cut -c 2-4)
    [ "$out" = "bcd" ]
}

@test "cut -c with open-ended range" {
    out=$(echo "abcdefgh" | applet cut -c 5-)
    [ "$out" = "efgh" ]
}

@test "cut -c with leading-dash range" {
    out=$(echo "abcdefgh" | applet cut -c -3)
    [ "$out" = "abc" ]
}

@test "cut -c inline form" {
    out=$(echo "abcdefgh" | applet cut -c1-3)
    [ "$out" = "abc" ]
}

@test "cut -d -f with single fields" {
    out=$(echo "a,b,c,d" | applet cut -d, -f 1,3)
    [ "$out" = "a,c" ]
}

@test "cut -d -f preserves empty selected fields" {
    out=$(echo "a,,b" | applet cut -d, -f 1,2,3)
    [ "$out" = "a,,b" ]
}

@test "cut -d -f skips unselected empty middle" {
    out=$(echo "a,,b" | applet cut -d, -f 1,3)
    [ "$out" = "a,b" ]
}

@test "cut -d -f open-ended" {
    out=$(echo "a,b,c,d" | applet cut -d, -f 2-)
    [ "$out" = "b,c,d" ]
}

@test "cut -d inline form" {
    out=$(echo "a,b,c" | applet cut -d, -f2)
    [ "$out" = "b" ]
}

@test "cut without -c or -f errors" {
    run applet cut "$TMPDIR/whatever"
    [ "$status" -eq 1 ]
    [[ "$output" == *"required"* ]]
}

@test "cut works on multi-line input" {
    out=$(printf 'a,b,c\n1,2,3\n' | applet cut -d, -f 2)
    [ "$out" = "$(printf 'b\n2')" ]
}
