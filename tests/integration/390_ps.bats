#!/usr/bin/env bats
load helper

setup() { require_built ps; }

@test "ps prints a header and at least one process" {
    out=$(applet ps)
    [[ "$out" == "  PID CMD"* ]]
    [ "$(echo "$out" | wc -l)" -ge 2 ]
}

@test "ps shows pid 1 (init)" {
    out=$(applet ps)
    [[ "$out" =~ \ +1\  ]]
}

@test "ps shows the current shell's pid" {
    out=$(applet ps)
    [[ "$out" == *" $$ "* || "$out" == *"$$ "* ]]
}
