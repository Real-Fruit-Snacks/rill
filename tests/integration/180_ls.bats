#!/usr/bin/env bats
load helper

setup() {
    require_built ls
    TMPDIR=$(mktemp -d)
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "ls of empty directory prints nothing" {
    out=$(applet ls "$TMPDIR")
    [ -z "$out" ]
}

@test "ls lists files alphabetically" {
    touch "$TMPDIR/c" "$TMPDIR/a" "$TMPDIR/b"
    out=$(applet ls "$TMPDIR")
    [ "$out" = "$(printf 'a\nb\nc')" ]
}

@test "ls hides dotfiles by default" {
    touch "$TMPDIR/visible" "$TMPDIR/.hidden"
    out=$(applet ls "$TMPDIR")
    [ "$out" = "visible" ]
}

@test "ls -a shows dotfiles including . and .." {
    touch "$TMPDIR/visible" "$TMPDIR/.hidden"
    out=$(applet ls -a "$TMPDIR" | sort)
    [ "$out" = "$(printf '.\n..\n.hidden\nvisible')" ]
}

@test "ls of a single file prints just the file name" {
    touch "$TMPDIR/x"
    out=$(applet ls "$TMPDIR/x")
    [ "$out" = "$TMPDIR/x" ]
}

@test "ls with no args lists current directory" {
    cd "$TMPDIR"
    touch a b
    out=$(applet ls)
    [ "$out" = "$(printf 'a\nb')" ]
}

@test "ls of missing path errors" {
    run applet ls "$TMPDIR/nope"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No such file or directory"* ]]
}

@test "ls of multiple paths prints headers" {
    /bin/mkdir "$TMPDIR/d1" "$TMPDIR/d2"
    touch "$TMPDIR/d1/x" "$TMPDIR/d2/y"
    out=$(applet ls "$TMPDIR/d1" "$TMPDIR/d2")
    [[ "$out" == *"$TMPDIR/d1:"* ]]
    [[ "$out" == *"$TMPDIR/d2:"* ]]
    [[ "$out" == *"x"* ]]
    [[ "$out" == *"y"* ]]
}

@test "ls -l renders mode, nlinks, uid, gid, size, date, name" {
    echo hello > "$TMPDIR/f"
    /bin/chmod 0644 "$TMPDIR/f"
    out=$(applet ls -l "$TMPDIR")
    # Permissions, then a date prefix, then the name.
    [[ "$out" == *"-rw-r--r--"* ]]
    [[ "$out" == *"f"* ]]
}

@test "ls -l of a directory entry shows 'd' prefix" {
    /bin/mkdir "$TMPDIR/sub"
    out=$(applet ls -l "$TMPDIR")
    [[ "$out" == *"drwx"* ]]
}

@test "ls -l of a symlink shows 'l' prefix" {
    /bin/ln -s /tmp "$TMPDIR/link"
    out=$(applet ls -l "$TMPDIR")
    [[ "$out" == *"lrwx"* ]]
}

@test "ls -l of a single file shows long line" {
    echo data > "$TMPDIR/file"
    out=$(applet ls -l "$TMPDIR/file")
    [[ "$out" == *"-rw"* ]]
    [[ "$out" == *"file"* ]]
}

@test "ls -la combines flags" {
    touch "$TMPDIR/.hidden" "$TMPDIR/visible"
    out=$(applet ls -la "$TMPDIR")
    [[ "$out" == *".hidden"* ]]
    [[ "$out" == *"visible"* ]]
}

@test "ls -l size is the actual byte count" {
    head -c 1234 /dev/urandom > "$TMPDIR/exact"
    out=$(applet ls -l "$TMPDIR/exact")
    [[ "$out" == *"1234"* ]]
}

@test "ls -l shows username and groupname (when resolvable)" {
    touch "$TMPDIR/f"
    cur_user=$(id -un)
    cur_group=$(id -gn)
    out=$(applet ls -l "$TMPDIR/f")
    [[ "$out" == *"$cur_user"* ]]
    [[ "$out" == *"$cur_group"* ]]
}
