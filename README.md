# rill

A small, fast, professionally-maintained multi-call binary for x86_64 Linux,
written in pure assembly with direct syscalls and no libc.

## Status

Phase 3b complete. 23 applets, 30496 bytes, 134 tests.

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
| `mkdir`    | supports `-p` (create parents, ignore EEXIST) |
| `rmdir`    | empty-directory removal; no `-p` chain yet |
| `rm`       | `-f` to ignore missing; no `-r` yet (refuses directories) |
| `touch`    | creates missing, bumps mtime via `utimensat`; no `-a/-m/-t/-d` |
| `ln`       | hard and `-s` symlink; `-f` overwrites; two-operand form only |
| `readlink` | basic; no `-f/-e/-m` canonicalization yet |
| `chmod`    | octal modes only; symbolic forms next |
| `ls`       | sorted names (one per line), `-a` for dotfiles; no `-l/-h/-F/-R` yet |
| `cp`       | file-to-file and file-to-directory; preserves source mode bits; no `-r/-p/-i` |
| `mv`       | same-filesystem rename only; cross-device move surfaced as a clear error |
| `stat`     | key:value summary (File/Size/Type/Mode/Uid/Gid/Mtime); not coreutils-format-compatible |
| `chown`    | numeric `UID[:GID]` or `:GID` only; no name resolution, no `-R` |

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
