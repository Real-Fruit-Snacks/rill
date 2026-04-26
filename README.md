# rill

A small, fast, professionally-maintained multi-call binary for x86_64 Linux,
written in pure assembly with direct syscalls and no libc.

## Status

**Phase 5 + polish complete; new applets landing.** 41 applets, 108016
bytes, 329 tests. Phases 0–5 all landed: dispatcher + runtime + trivial
+ file ops + text processing + process/system. The originally-deferred
polish items have all landed too — `ls -l` now auto-sizes columns and
emits a `total <N>` header, mtimes render in localtime via
`/etc/localtime` (TZif v2/v3 with v1 fallback), `chown -h` is wired,
`grep` understands basic regex (`. * ^ $ [...] [^...] \X`), and `sort`
accepts `-k F[,G]`, `-t SEP`, and `-f`. Phase 6 adds applets beyond the
original 40 — first up: `find`.

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
| `ls`       | sorted names; `-a`, `-l` (resolves uid/gid via `/etc/passwd`, auto-sized columns, localtime mtime via `/etc/localtime`, `total <N>` header); no `-R/-F/-h` |
| `rm`       | `-r`/`-R` recursive (via in-place path-buffer walk), `-f` ignores missing |
| `cp`       | `-r`/`-R` recursive (preserves symlinks); preserves source mode bits; no `-p/-i` |
| `mv`       | same-filesystem rename only; cross-device move surfaced as a clear error |
| `stat`     | key:value summary; resolves uid/gid names; mtime as `Mon DD HH:MM` (localtime) |
| `chown`    | numeric or named `USER[:GROUP]` / `:GROUP`; `-R` recursive (lchown — no symlink follow); `-h` keeps top-level operand a symlink (lchown vs chown) |
| `tee`      | `-a` appends; named-file failures don't abort other outputs; stdout failure aborts |
| `wc`       | `-l` / `-w` / `-c` columns; multi-file `total` row; bytes-not-chars (no `-m` yet) |
| `head`     | `-n N` / `-nN` / `-c N` / `-cN`; `==> NAME <==` headers between files |
| `tail`     | `-n N` / `-nN`; 4 MB sliding window for streams larger than memory |
| `cut`      | `-c LIST` / `-b LIST` / `-d DELIM -f LIST`; ranges (`N-M`, `N-`, `-M`); inline forms (`-cLIST`, `-d,`) |
| `tr`       | translate / `-d` delete / `-s` squeeze; literal + ranges + escapes (`\n` `\t` `\r` `\f` `\v` `\a` `\b` `\\` `\NNN`) |
| `uniq`     | `-c` count, `-d` dups only, `-u` uniques only; lines truncated at 8 KB |
| `sort`     | `-r`/`-n`/`-u`/`-f`; `-k F[,G]`; `-t SEP`; in-memory quicksort (16 MB input cap, 256 K lines) |
| `grep`     | BRE regex (`. * ^ $ [...] [^...] \X`); `-F` for fixed-string; `-i`/`-v`/`-n`/`-c`; multi-file `FILE:` prefixes |
| `whoami`   | uid → name via `/etc/passwd` (numeric fallback) |
| `id`       | full form, `-u`/`-g`/`-un`/`-gn` |
| `uname`    | `-a`/`-s`/`-n`/`-r`/`-v`/`-m`; combined short flags |
| `hostname` | utsname.nodename; setter form deferred |
| `date`     | `Sun Apr 26 15:37:54 UTC 2026`; UTC only, no `+FORMAT` yet |
| `kill`     | `-NUM`/`-NAME`/`-SIGNAME`; `-l` lists; default TERM |
| `which`    | walks `$PATH`; falls back to a hardcoded default if `$PATH` unset |
| `ps`       | reads `/proc`; PID + comm-name; no flags yet |
| `find`     | recursive walk; tests `-name PAT` (glob), `-type FDLCBPS`, `-maxdepth N`, `-mindepth N`, `-empty`; actions `-print` (default), `-print0`; no `-exec`/operators yet |

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
