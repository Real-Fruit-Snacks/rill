#!/usr/bin/env bats
load helper

setup() { require_built echo; }

@test "echo with no args prints just a newline" {
    run applet echo
    [ "$status" -eq 0 ]
    [ "$output" = "" ]                  # bats strips the trailing newline
}

@test "echo single word" {
    run applet echo hello
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "echo multiple args separated by single space" {
    run applet echo a b c
    [ "$status" -eq 0 ]
    [ "$output" = "a b c" ]
}

@test "echo -n suppresses trailing newline" {
    out=$(applet echo -n hi)
    [ "$out" = "hi" ]
}

@test "echo -n -n -n still suppresses (multiple flags allowed)" {
    out=$(applet echo -n -n -n word)
    [ "$out" = "word" ]
}

@test "echo matches coreutils on simple input" {
    diff <(applet echo foo bar baz) <(/bin/echo foo bar baz)
}
