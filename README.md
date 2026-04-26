# rill

A small, fast, professionally-maintained multi-call binary for x86_64 Linux,
written in pure assembly with direct syscalls and no libc.

## Status

**Phase 3 complete.** 23 applets, 48016 bytes, 168 tests.

All 12 file-op applets from the original Phase 3 plan are now landed:
`mkdir`, `rmdir`, `rm`, `touch`, `ln`, `readlink`, `chmod`, `ls`, `cp`,
`mv`, `stat`, `chown` — including recursive variants (`rm -r`, `cp -r`,
`chown -R`), `chmod` symbolic modes, and `/etc/passwd` + `/etc/group`
name resolution for `ls -l` / `chown` / `stat`.

Polish items deferred to a later phase: localtime conversion for mtime
display (everything is UTC right now), auto-sized column widths in
`ls -l`, the `total <N>` header line, and `chown -h`.

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
| `chmod`    | octal and symbolic modes (`u/g/o/a` × `+/-/=` × `r/w/x`); no `s/t` perms or `-R` yet |
| `ls`       | sorted names; `-a`, `-l` (resolves uid/gid via `/etc/passwd`, fixed col widths, UTC mtime, no `total` line yet); no `-R/-F/-h` |
| `rm`       | `-r`/`-R` recursive (via in-place path-buffer walk), `-f` ignores missing |
| `cp`       | `-r`/`-R` recursive (preserves symlinks); preserves source mode bits; no `-p/-i` |
| `mv`       | same-filesystem rename only; cross-device move surfaced as a clear error |
| `stat`     | key:value summary; resolves uid/gid names; mtime as `Mon DD HH:MM` (UTC) |
| `chown`    | numeric or named `USER[:GROUP]` / `:GROUP`; `-R` recursive (lchown — no symlink follow) |

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
