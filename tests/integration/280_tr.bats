#!/usr/bin/env bats
load helper

setup() { require_built tr; }

@test "tr translates literal char-to-char" {
    out=$(echo "abc" | applet tr abc xyz)
    [ "$out" = "xyz" ]
}

@test "tr translates ranges (lower to upper)" {
    out=$(echo "Hello World" | applet tr a-z A-Z)
    [ "$out" = "HELLO WORLD" ]
}

@test "tr pads SET2 with last char when SET1 longer" {
    out=$(echo "abcde" | applet tr abcde XY)
    [ "$out" = "XYYYY" ]
}

@test "tr -d deletes chars in SET1" {
    out=$(echo "abcdef" | applet tr -d bd)
    [ "$out" = "acef" ]
}

@test "tr -d with range" {
    out=$(echo "abcdef" | applet tr -d a-c)
    [ "$out" = "def" ]
}

@test "tr -s squeezes runs in SET1" {
    out=$(echo "aaabbbccc" | applet tr -s a-c)
    [ "$out" = "abc" ]
}

@test "tr translates and squeezes together" {
    # SET2 is squeezed: any run of the SET2 chars in output collapses.
    out=$(echo "aabb" | applet tr -s ab xy)
    [ "$out" = "xy" ]
}

@test "tr handles \\\\t escape" {
    out=$(printf 'a\tb' | applet tr "\t" " ")
    [ "$out" = "a b" ]
}

@test "tr handles \\\\n escape" {
    out=$(printf 'a\nb' | applet tr "\n" " ")
    [ "$out" = "a b" ]
}

@test "tr matches coreutils on a basic case-conversion" {
    diff <(echo "Mixed Case Text" | applet tr a-z A-Z) <(echo "Mixed Case Text" | /usr/bin/tr a-z A-Z)
}
