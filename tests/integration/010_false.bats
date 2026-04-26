#!/usr/bin/env bats
load helper

setup() { require_built false; }

@test "false exits 1" {
    run applet false
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "false ignores args" {
    run applet false a b c
    [ "$status" -eq 1 ]
}
