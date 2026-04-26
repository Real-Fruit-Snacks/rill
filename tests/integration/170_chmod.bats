#!/usr/bin/env bats
load helper

setup() {
    require_built chmod
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "chmod sets octal mode" {
    touch "$TMPDIR/f"
    applet chmod 644 "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "644" ]
}

@test "chmod accepts leading zero" {
    touch "$TMPDIR/f"
    applet chmod 0755 "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "755" ]
}

@test "chmod operates on multiple files" {
    touch "$TMPDIR/a" "$TMPDIR/b"
    applet chmod 600 "$TMPDIR/a" "$TMPDIR/b"
    [ "$(stat -c %a "$TMPDIR/a")" = "600" ]
    [ "$(stat -c %a "$TMPDIR/b")" = "600" ]
}

@test "chmod errors on missing path" {
    run applet chmod 644 "$TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "chmod errors on invalid octal mode" {
    touch "$TMPDIR/f"
    run applet chmod 9zz "$TMPDIR/f"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid mode"* ]]
}

@test "chmod with no operand errors" {
    run applet chmod
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "chmod with mode but no file errors" {
    run applet chmod 644
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing operand"* ]]
}

@test "chmod u+x adds execute for user" {
    touch "$TMPDIR/f"
    /bin/chmod 0644 "$TMPDIR/f"
    applet chmod u+x "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "744" ]
}

@test "chmod go-w clears write for group and other" {
    touch "$TMPDIR/f"
    /bin/chmod 0666 "$TMPDIR/f"
    applet chmod go-w "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "644" ]
}

@test "chmod a=r sets everyone read-only" {
    touch "$TMPDIR/f"
    /bin/chmod 0755 "$TMPDIR/f"
    applet chmod a=r "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "444" ]
}

@test "chmod multi-clause spec works" {
    touch "$TMPDIR/f"
    /bin/chmod 0600 "$TMPDIR/f"
    applet chmod u+x,go=r "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "744" ]
}

@test "chmod implicit who applies to all" {
    touch "$TMPDIR/f"
    /bin/chmod 0644 "$TMPDIR/f"
    applet chmod +x "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "755" ]
}

@test "chmod = with no perms clears who-bits" {
    touch "$TMPDIR/f"
    /bin/chmod 0755 "$TMPDIR/f"
    applet chmod o= "$TMPDIR/f"
    [ "$(stat -c %a "$TMPDIR/f")" = "750" ]
}

@test "chmod rejects unknown symbolic char" {
    touch "$TMPDIR/f"
    run applet chmod u+z "$TMPDIR/f"
    [ "$status" -eq 1 ]
}
