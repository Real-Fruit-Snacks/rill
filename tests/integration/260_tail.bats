#!/usr/bin/env bats
load helper

setup() {
    require_built tail
    TMPDIR=$(mktemp -d)
    seq 1 50 > "$TMPDIR/seq50"
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "tail defaults to 10 lines" {
    out=$(applet tail < "$TMPDIR/seq50")
    [ "$(echo "$out" | wc -l)" -eq 10 ]
    [ "$(echo "$out" | head -1)" = "41" ]
    [ "$(echo "$out" | tail -1)" = "50" ]
}

@test "tail -n N selects line count" {
    out=$(applet tail -n 3 < "$TMPDIR/seq50")
    [ "$out" = "$(printf '48\n49\n50')" ]
}

@test "tail -nN concatenated form" {
    out=$(applet tail -n5 < "$TMPDIR/seq50")
    [ "$out" = "$(printf '46\n47\n48\n49\n50')" ]
}

@test "tail more lines than input emits all" {
    out=$(printf 'a\nb\n' | applet tail -n 100)
    [ "$out" = "$(printf 'a\nb')" ]
}

@test "tail reads from file argument" {
    out=$(applet tail -n 2 "$TMPDIR/seq50")
    [ "$out" = "$(printf '49\n50')" ]
}

@test "tail of multiple files prints headers" {
    echo a > "$TMPDIR/f1"
    echo b > "$TMPDIR/f2"
    out=$(applet tail "$TMPDIR/f1" "$TMPDIR/f2")
    [[ "$out" == *"==> $TMPDIR/f1 <=="* ]]
    [[ "$out" == *"==> $TMPDIR/f2 <=="* ]]
}

@test "tail handles file without trailing newline" {
    printf 'a\nb\nc' > "$TMPDIR/no_nl"
    out=$(applet tail -n 2 "$TMPDIR/no_nl")
    [ "$out" = "$(printf 'b\nc')" ]
}

@test "tail matches coreutils for default behavior" {
    diff <(applet tail "$TMPDIR/seq50") <(/usr/bin/tail "$TMPDIR/seq50")
}
