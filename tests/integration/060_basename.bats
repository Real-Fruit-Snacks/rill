#!/usr/bin/env bats
load helper

setup() { require_built basename; }

@test "basename of simple path" {
    [ "$(applet basename /usr/bin/foo)" = "foo" ]
}

@test "basename of bare name" {
    [ "$(applet basename foo)" = "foo" ]
}

@test "basename strips trailing slashes" {
    [ "$(applet basename /usr/bin/foo/)" = "foo" ]
}

@test "basename of '/' prints '/'" {
    [ "$(applet basename /)" = "/" ]
}

@test "basename with suffix removes suffix" {
    [ "$(applet basename /usr/bin/foo.txt .txt)" = "foo" ]
}

@test "basename does not remove suffix when it equals the basename" {
    [ "$(applet basename /usr/bin/foo .foo)" = "foo" ]
}

@test "basename matches coreutils on shared cases" {
    for p in /usr/bin/foo foo /a/b/ /; do
        diff <(applet basename "$p") <(/usr/bin/basename "$p")
    done
}

@test "basename with no args errors" {
    run applet basename
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "basename with too many args errors" {
    run applet basename a b c
    [ "$status" -eq 1 ]
    [[ "$output" == *"extra operand"* ]]
}
