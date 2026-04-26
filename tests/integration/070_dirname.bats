#!/usr/bin/env bats
load helper

setup() { require_built dirname; }

@test "dirname of /usr/bin/foo" {
    [ "$(applet dirname /usr/bin/foo)" = "/usr/bin" ]
}

@test "dirname of bare name is '.'" {
    [ "$(applet dirname foo)" = "." ]
}

@test "dirname of '/' is '/'" {
    [ "$(applet dirname /)" = "/" ]
}

@test "dirname of '/foo' is '/'" {
    [ "$(applet dirname /foo)" = "/" ]
}

@test "dirname of '/foo/' is '/'" {
    [ "$(applet dirname /foo/)" = "/" ]
}

@test "dirname of multiple args prints one per line" {
    out=$(applet dirname /a/b /c/d)
    [ "$out" = "$(printf '/a\n/c')" ]
}

@test "dirname with no args errors" {
    run applet dirname
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "dirname matches coreutils on shared cases" {
    for p in /usr/bin/foo foo /a/b/ /; do
        diff <(applet dirname "$p") <(/usr/bin/dirname "$p")
    done
}
