#!/usr/bin/env bats
load helper

setup() { require_built env; }

@test "env with no args lists env entries" {
    out=$(env -i A=1 B=2 "$BUILD/env" | sort)
    expected=$(printf 'A=1\nB=2')
    [ "$out" = "$expected" ]
}

@test "env errors on arguments (exec not yet supported)" {
    run applet env -i
    [ "$status" -eq 125 ]
    [[ "$output" == *"not yet supported"* ]]
}

@test "env errors on VAR=VAL form too" {
    run applet env FOO=bar
    [ "$status" -eq 125 ]
}
