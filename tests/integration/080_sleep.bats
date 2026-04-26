#!/usr/bin/env bats
load helper

setup() { require_built sleep; }

@test "sleep 0 returns immediately" {
    run applet sleep 0
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "sleep with no args errors" {
    run applet sleep
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "sleep with non-numeric arg errors" {
    run applet sleep notanumber
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid time interval"* ]]
}

@test "sleep 1 actually sleeps roughly 1 second" {
    start=$(date +%s%N)
    applet sleep 1
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))
    [ "$elapsed_ms" -ge 900 ]
    # Upper bound generous enough to survive a busy WSL host scheduler.
    [ "$elapsed_ms" -lt 3000 ]
}
