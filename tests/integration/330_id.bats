#!/usr/bin/env bats
load helper

setup() { require_built id; }

@test "id full form contains uid= and gid=" {
    out=$(applet id)
    [[ "$out" == *"uid="* ]]
    [[ "$out" == *"gid="* ]]
}

@test "id -u prints numeric uid" {
    [ "$(applet id -u)" = "$(/usr/bin/id -u)" ]
}

@test "id -g prints numeric gid" {
    [ "$(applet id -g)" = "$(/usr/bin/id -g)" ]
}

@test "id -un prints user name" {
    [ "$(applet id -un)" = "$(/usr/bin/id -un)" ]
}

@test "id -gn prints group name" {
    [ "$(applet id -gn)" = "$(/usr/bin/id -gn)" ]
}
