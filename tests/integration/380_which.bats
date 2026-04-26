#!/usr/bin/env bats
load helper

setup() { require_built which; }

@test "which finds a known command" {
    out=$(applet which ls)
    [ -x "$out" ]
}

@test "which exits 0 when found" {
    run applet which ls
    [ "$status" -eq 0 ]
}

@test "which exits 1 when not found" {
    run applet which definitely_no_such_cmd_42
    [ "$status" -eq 1 ]
}

@test "which finds multiple commands" {
    run applet which ls cat
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

@test "which with one missing returns 1" {
    run applet which ls definitely_missing
    [ "$status" -eq 1 ]
}
