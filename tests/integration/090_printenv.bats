#!/usr/bin/env bats
load helper

setup() { require_built printenv; }

@test "printenv with no args lists all env entries" {
    out=$(env -i FOO=bar BAZ=qux "$BUILD/printenv" | sort)
    expected=$(printf 'BAZ=qux\nFOO=bar')
    [ "$out" = "$expected" ]
}

@test "printenv NAME prints value when set" {
    out=$(env -i HELLO=world "$BUILD/printenv" HELLO)
    [ "$out" = "world" ]
}

@test "printenv NAME exits 1 when unset" {
    run env -i "$BUILD/printenv" NONEXISTENT
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "printenv multiple names: missing one still exits 1" {
    run env -i SET_VAR=present "$BUILD/printenv" SET_VAR MISSING_VAR
    [ "$status" -eq 1 ]
    [[ "$output" == *"present"* ]]
}

@test "printenv distinguishes a name= prefix correctly" {
    # PREFIX_LONG is set, but printenv PREFIX should not match it.
    run env -i PREFIX_LONG=v "$BUILD/printenv" PREFIX
    [ "$status" -eq 1 ]
}
