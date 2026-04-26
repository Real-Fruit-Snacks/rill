#!/usr/bin/env bats
load helper

setup() { require_built pwd; }

@test "pwd matches coreutils pwd -P" {
    out=$(cd /tmp && applet pwd)
    expected=$(cd /tmp && /bin/pwd -P)
    [ "$out" = "$expected" ]
}

@test "pwd ends with a newline" {
    OUT=$(mktemp)
    applet pwd > "$OUT"
    [ "$(tail -c 1 "$OUT")" = "$(printf '\n')" ]
    rm -f "$OUT"
}
