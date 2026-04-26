# Shared bats setup. Sourced by every test file.

ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
BUILD="$ROOT/build"
RILL="$BUILD/rill"

# Use the symlinks rather than `rill <applet>` so the multi-call dispatch
# path is the one under test. Tests for `rill <applet>` form live in 000.
applet() {
    local name=$1; shift
    "$BUILD/$name" "$@"
}

require_built() {
    [ -x "$RILL" ] || skip "rill not built (run: make symlinks)"
    [ -L "$BUILD/$1" ] || skip "symlink for $1 missing (run: make symlinks)"
}
