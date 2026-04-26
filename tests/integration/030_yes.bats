#!/usr/bin/env bats
load helper

setup() { require_built yes; }

@test "yes default prints 'y' on each line" {
    out=$(applet yes | head -5)
    [ "$out" = "$(printf 'y\ny\ny\ny\ny')" ]
}

@test "yes with arg prints arg on each line" {
    out=$(applet yes hello | head -3)
    [ "$out" = "$(printf 'hello\nhello\nhello')" ]
}

@test "yes with multi args joins with space" {
    out=$(applet yes a b c | head -2)
    [ "$out" = "$(printf 'a b c\na b c')" ]
}

@test "yes exits cleanly on broken pipe" {
    applet yes | head -1 > /dev/null
    # If yes survived the SIGPIPE it would exit 0; we just want a quick exit.
}
