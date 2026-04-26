#!/usr/bin/env bats
load helper

setup() { require_built kill; }

@test "kill -l lists signal names" {
    out=$(applet kill -l)
    [[ "$out" == *"HUP"* ]]
    [[ "$out" == *"KILL"* ]]
    [[ "$out" == *"TERM"* ]]
}

@test "kill -0 on self succeeds" {
    run applet kill -0 $$
    [ "$status" -eq 0 ]
}

@test "kill -0 on nonexistent pid fails" {
    run applet kill -0 99999999
    [ "$status" -eq 1 ]
}

@test "kill rejects unknown signal name" {
    run applet kill -DEFINITELYNOSUCHSIG $$
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid signal"* ]]
}

@test "kill with no args errors" {
    run applet kill
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage"* ]]
}

@test "kill with invalid pid reports error and continues" {
    run applet kill notanumber
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid pid"* ]]
}

@test "kill -SIGHUP also accepts SIG prefix" {
    run applet kill -SIGHUP -1
    # -1 is invalid pid but we just want to verify the signal parsed.
    [[ "$output" != *"invalid signal"* ]]
}
