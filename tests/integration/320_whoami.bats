#!/usr/bin/env bats
load helper

setup() { require_built whoami; }

@test "whoami matches the system whoami" {
    diff <(applet whoami) <(/usr/bin/whoami)
}

@test "whoami matches id -un" {
    [ "$(applet whoami)" = "$(/usr/bin/id -un)" ]
}
