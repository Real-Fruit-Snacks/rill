#!/usr/bin/env bats
load helper

setup() {
    require_built head
    TMPDIR=$(mktemp -d)
    seq 1 50 > "$TMPDIR/seq50"
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "head defaults to 10 lines" {
    out=$(applet head < "$TMPDIR/seq50")
    [ "$(echo "$out" | wc -l)" -eq 10 ]
    [ "$(echo "$out" | head -1)" = "1" ]
    [ "$(echo "$out" | tail -1)" = "10" ]
}

@test "head -n N selects line count" {
    out=$(applet head -n 3 < "$TMPDIR/seq50")
    [ "$out" = "$(printf '1\n2\n3')" ]
}

@test "head -nN concatenated form" {
    out=$(applet head -n5 < "$TMPDIR/seq50")
    [ "$out" = "$(printf '1\n2\n3\n4\n5')" ]
}

@test "head -c N takes first N bytes" {
    out=$(printf 'abcdefghij' | applet head -c 4)
    [ "$out" = "abcd" ]
}

@test "head reads from file argument" {
    out=$(applet head -n 2 "$TMPDIR/seq50")
    [ "$out" = "$(printf '1\n2')" ]
}

@test "head of multiple files prints headers" {
    echo a > "$TMPDIR/f1"
    echo b > "$TMPDIR/f2"
    out=$(applet head "$TMPDIR/f1" "$TMPDIR/f2")
    [[ "$out" == *"==> $TMPDIR/f1 <=="* ]]
    [[ "$out" == *"==> $TMPDIR/f2 <=="* ]]
}

@test "head matches coreutils for default behavior" {
    diff <(applet head "$TMPDIR/seq50") <(/usr/bin/head "$TMPDIR/seq50")
}

@test "head -n 0 emits nothing" {
    out=$(applet head -n 0 < "$TMPDIR/seq50")
    [ -z "$out" ]
}
