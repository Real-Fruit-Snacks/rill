# rill

A small, fast, professionally-maintained multi-call binary for x86_64 Linux,
written in pure assembly with direct syscalls and no libc.

## Status

Phase 2 in progress. Multi-call dispatch, runtime (I/O, fmt, errno), and
the trivial-applet sweep are landed.

| Applet | Notes |
|---|---|
| `true`     | exit 0 |
| `false`    | exit 1 |
| `echo`     | supports `-n`; no `-e` escape interpretation yet |
| `yes`      | default `y` line; joins multi-arg with spaces |
| `cat`      | concatenates files; `-` and no-args read stdin; per-file errno reporting |
| `pwd`      | `getcwd` (physical path; no `-L`) |
| `basename` | one-arg and `PATH SUFFIX` forms |
| `dirname`  | accepts multiple paths |
| `sleep`    | integer seconds only (no fractional / unit suffix) |
| `printenv` | all-env or per-name; missing names → exit 1 |
| `env`      | print-only; no `-i` / VAR=VAL / exec yet (returns 125) |

## Build

Requires NASM, GNU ld, GNU make, and bats on Linux (or WSL on Windows).

```sh
make            # builds build/rill
make symlinks   # creates build/<applet> symlinks
make test       # runs the integration suite
make size       # prints binary size
```

## Use

```sh
./build/rill true       # run the `true` applet via dispatch arg
./build/true            # run via symlink (argv[0] dispatch)
```

## Layout

| Path | Purpose |
|---|---|
| `src/start.asm`   | `_start`, applet dispatcher, applet table |
| `src/core/`       | Shared runtime (string ops, I/O, syscalls) |
| `src/applets/`    | One `.asm` per applet |
| `include/`        | NASM include files (syscall numbers, macros) |
| `tests/integration/` | bats integration tests |
| `linker.ld`       | Linker script |

## License

MIT. See [LICENSE](LICENSE).
