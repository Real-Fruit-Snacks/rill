#!/usr/bin/env bats
load helper

setup() { require_built hostname; }

@test "hostname matches uname -n" {
    [ "$(applet hostname)" = "$(/bin/uname -n)" ]
}
