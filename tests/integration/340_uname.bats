#!/usr/bin/env bats
load helper

setup() { require_built uname; }

@test "uname default prints sysname" {
    [ "$(applet uname)" = "$(/bin/uname -s)" ]
}

@test "uname -s prints sysname" {
    [ "$(applet uname -s)" = "$(/bin/uname -s)" ]
}

@test "uname -n prints nodename" {
    [ "$(applet uname -n)" = "$(/bin/uname -n)" ]
}

@test "uname -r prints release" {
    [ "$(applet uname -r)" = "$(/bin/uname -r)" ]
}

@test "uname -m prints machine" {
    [ "$(applet uname -m)" = "$(/bin/uname -m)" ]
}

@test "uname -a contains all fields" {
    out=$(applet uname -a)
    sysname=$(/bin/uname -s)
    nodename=$(/bin/uname -n)
    release=$(/bin/uname -r)
    machine=$(/bin/uname -m)
    [[ "$out" == *"$sysname"* ]]
    [[ "$out" == *"$nodename"* ]]
    [[ "$out" == *"$release"* ]]
    [[ "$out" == *"$machine"* ]]
}

@test "uname -snr combined flags" {
    out=$(applet uname -snr)
    [[ "$out" == *"$(uname -s)"* ]]
    [[ "$out" == *"$(uname -n)"* ]]
    [[ "$out" == *"$(uname -r)"* ]]
}
