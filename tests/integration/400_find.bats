#!/usr/bin/env bats
load helper

setup() {
    require_built find
    TMPDIR=$(mktemp -d)
    /bin/mkdir -p "$TMPDIR/sub/deep"
    touch "$TMPDIR/a.txt" "$TMPDIR/b.log" "$TMPDIR/sub/c.txt" "$TMPDIR/sub/deep/d.txt"
    /bin/ln -s a.txt "$TMPDIR/link"
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "find with explicit path lists everything recursively" {
    out=$(applet find "$TMPDIR" | sort)
    expected=$(/usr/bin/find "$TMPDIR" | sort)
    [ "$out" = "$expected" ]
}

@test "find with no args defaults to '.'" {
    cd "$TMPDIR"
    out=$(applet find | sort)
    expected=$(/usr/bin/find . | sort)
    [ "$out" = "$expected" ]
}

@test "find -name '*.txt' filters by glob" {
    out=$(applet find "$TMPDIR" -name '*.txt' | sort)
    expected=$(/usr/bin/find "$TMPDIR" -name '*.txt' | sort)
    [ "$out" = "$expected" ]
}

@test "find -name 'a*' anchors at the start of basename" {
    out=$(applet find "$TMPDIR" -name 'a*' | sort)
    [ "$out" = "$TMPDIR/a.txt" ]
}

@test "find -type f shows only regular files" {
    out=$(applet find "$TMPDIR" -type f | sort)
    expected=$(/usr/bin/find "$TMPDIR" -type f | sort)
    [ "$out" = "$expected" ]
}

@test "find -type d shows only directories" {
    out=$(applet find "$TMPDIR" -type d | sort)
    expected=$(/usr/bin/find "$TMPDIR" -type d | sort)
    [ "$out" = "$expected" ]
}

@test "find -type l shows only symlinks" {
    out=$(applet find "$TMPDIR" -type l | sort)
    [ "$out" = "$TMPDIR/link" ]
}

@test "find -maxdepth 0 prints only the operand" {
    out=$(applet find "$TMPDIR" -maxdepth 0)
    [ "$out" = "$TMPDIR" ]
}

@test "find -maxdepth 1 stops descending after the first level" {
    out=$(applet find "$TMPDIR" -maxdepth 1 | sort)
    expected=$(/usr/bin/find "$TMPDIR" -maxdepth 1 | sort)
    [ "$out" = "$expected" ]
}

@test "find -mindepth 1 hides the operand" {
    out=$(applet find "$TMPDIR" -mindepth 1 | sort)
    expected=$(/usr/bin/find "$TMPDIR" -mindepth 1 | sort)
    [ "$out" = "$expected" ]
}

@test "find combines -name and -type as logical AND" {
    out=$(applet find "$TMPDIR" -name '*.txt' -type f | sort)
    expected=$(/usr/bin/find "$TMPDIR" -name '*.txt' -type f | sort)
    [ "$out" = "$expected" ]
}

@test "find -print0 emits NUL-separated names" {
    n=$(applet find "$TMPDIR" -name '*.txt' -print0 | tr -cd '\0' | wc -c)
    [ "$n" -eq 3 ]
}

@test "find -empty matches empty files and empty dirs" {
    e=$(mktemp -d)
    /bin/mkdir "$e/has_file" "$e/empty_dir"
    touch "$e/has_file/x"
    out=$(applet find "$e" -empty | sort)
    expected=$(/usr/bin/find "$e" -empty | sort)
    [ "$out" = "$expected" ]
    rm -rf "$e"
}

@test "find -name with [] character class" {
    out=$(applet find "$TMPDIR" -name '[ab]*' | sort)
    [ "$out" = "$(printf '%s\n' "$TMPDIR/a.txt" "$TMPDIR/b.log")" ]
}

@test "find -name '?.txt' uses ? as single-char wildcard" {
    out=$(applet find "$TMPDIR" -name '?.txt' | sort)
    expected=$(/usr/bin/find "$TMPDIR" -name '?.txt' | sort)
    [ "$out" = "$expected" ]
}

@test "find of a missing path errors" {
    run applet find "$TMPDIR/nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "find with multiple paths walks each" {
    /bin/mkdir "$TMPDIR/extra"
    touch "$TMPDIR/extra/y"
    out=$(applet find "$TMPDIR/sub" "$TMPDIR/extra" | sort)
    expected=$(/usr/bin/find "$TMPDIR/sub" "$TMPDIR/extra" | sort)
    [ "$out" = "$expected" ]
}

@test "find -type rejects unknown letter" {
    run applet find "$TMPDIR" -type q
    [ "$status" -ne 0 ]
    [[ "$output" == *"-type"* ]]
}

@test "find rejects unknown predicate" {
    run applet find "$TMPDIR" -wat
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown"* ]]
}
