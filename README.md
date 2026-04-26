<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Real-Fruit-Snacks/rill/main/docs/assets/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Real-Fruit-Snacks/rill/main/docs/assets/logo-light.svg">
  <img alt="rill" src="https://raw.githubusercontent.com/Real-Fruit-Snacks/rill/main/docs/assets/logo-dark.svg" width="420">
</picture>

![Assembly](https://img.shields.io/badge/language-Assembly-6E4C13.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Tests](https://img.shields.io/badge/tests-329%20passing-brightgreen.svg)

A BusyBox-style multi-call binary in pure x86_64 NASM assembly — **41 Unix utilities**, one ~108 KB static ELF, direct syscalls, no libc, no runtime. The assembly cousin to [jib](https://github.com/Real-Fruit-Snacks/jib) (Rust), [topsail](https://github.com/Real-Fruit-Snacks/topsail) (Go), and [mainsail](https://github.com/Real-Fruit-Snacks/mainsail) (Python).

[Download Latest](https://github.com/Real-Fruit-Snacks/rill/releases/latest)
&nbsp;·&nbsp;
[GitHub Pages](https://real-fruit-snacks.github.io/rill/)
&nbsp;·&nbsp;
[Architecture](#architecture)
&nbsp;·&nbsp;
[Applets](#supported-applets)

</div>

---

## Quick Start

**From a release** — no toolchain required (Linux x86_64):

```bash
curl -LO https://github.com/Real-Fruit-Snacks/rill/releases/latest/download/rill-linux-x64
chmod +x rill-linux-x64
mv rill-linux-x64 rill                  # the dispatcher matches argv[0] == "rill"
./rill date
ln -s rill ls && ./ls -la               # multi-call via symlink
```

**From source** — Linux with NASM, GNU ld, GNU make, and bats (or WSL on Windows):

```bash
git clone https://github.com/Real-Fruit-Snacks/rill.git
cd rill
make             # builds build/rill
make symlinks    # creates build/<applet> symlinks for multi-call dispatch
make test        # runs the bats integration suite (329 cases)
make size        # prints the linked binary's size
```

**Verify:**

```bash
file build/rill
# ELF 64-bit LSB executable, x86-64, statically linked

./build/rill true && echo ok        # subcommand dispatch
./build/ls -la                      # multi-call: argv[0] basename
echo hi | ./build/grep -i 'H.'      # full pipeline
```

---

## Features

### One binary, forty-one utilities

Every common POSIX tool you'd reach for in a shell pipeline — file ops, text processing, system info, process inspection, and a recursive tree walker. Dispatch via `rill <applet>` or call any symlink directly.

```bash
rill ls -la /etc                        # auto-sized columns, localtime mtime
rill find . -name '*.asm' -type f       # tree walk + glob + type filter
rill cat src/start.asm | rill wc -l     # full pipeline through the dispatcher
rill sort -k 2 -n -t , data.csv         # field-aware numeric sort
rill grep -i '^[a-z]+pple' fruits.txt   # BRE regex with case-fold
```

### Real applets, not stubs

Each applet implements the common POSIX flags and edge cases.

- `ls` — `-a`, `-l` with auto-sized columns, localtime mtime via `/etc/localtime` (TZif v2/v3), `total <N>` header, owner/group resolved against `/etc/passwd` and `/etc/group`
- `find` — recursive walk with `-name PATTERN` (full glob: `*`, `?`, `[...]`, `[!...]`, `\X`), `-type fdlcbps`, `-maxdepth N`, `-mindepth N`, `-empty`, `-print` / `-print0`
- `grep` — basic regex (`. * ^ $ [...] [^...] \X`), `-F` for fixed strings, `-i`, `-v`, `-n`, `-c`, multi-file `FILE:` prefixes
- `sort` — `-r`, `-n`, `-u`, `-f`; `-k F[,G]` field selection; `-t SEP` custom delimiter; in-memory quicksort (16 MB / 256 K-line cap)
- `chown` — numeric or named `USER[:GROUP]` / `:GROUP`, `-R` recursive (lchown — no symlink follow), `-h` for top-level lchown vs chown
- `cp` — `-r`/`-R` recursive (preserves symlinks), preserves source mode bits
- `chmod` — octal and symbolic modes (`u/g/o/a` × `+/-/=` × `r/w/x`)
- `tail` — `-n N`, `-nN`; 4 MB sliding window so streams larger than memory still work

### Pure assembly, direct syscalls

No libc, no startup runtime, no global allocator. Every operation is a `syscall` to the kernel. Buffers live in `.bss` (lazy-paged) or on the function's stack frame. The whole binary is a static ELF with two `PT_LOAD` segments — text r-x, data rw-.

```bash
$ ldd build/rill
        not a dynamic executable

$ readelf -l build/rill | grep PT_LOAD
  LOAD           0x000000 0x0000000000400000 0x0000000000400000 0x010600 0x010600 R E 0x1000
  LOAD           0x011000 0x0000000000411000 0x0000000000411000 0x000260 0x4082b8 RW  0x1000
```

### 329-case bats harness

Every applet has integration tests that diff our output against `/usr/bin/<applet>` byte-for-byte where the comparison is deterministic, and check exit codes everywhere else. `make test` runs the lot in WSL or any Linux box with NASM, ld, and bats installed. CI runs the same harness on Ubuntu against every push.

---

## Supported applets

| Category | Applets |
|----------|---------|
| **File ops**       | `ls` `cp` `mv` `rm` `mkdir` `rmdir` `touch` `ln` `readlink` `chmod` `chown` `stat` `find` |
| **Text**           | `cat` `wc` `head` `tail` `cut` `tr` `sort` `uniq` `grep` `tee` |
| **Paths & info**   | `pwd` `basename` `dirname` `which` |
| **System**         | `whoami` `id` `uname` `hostname` `date` `kill` `ps` `env` `printenv` |
| **Control & misc** | `true` `false` `echo` `yes` `sleep` |

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
| `rm`       | `-r`/`-R` recursive (in-place path-buffer walk); `-f` ignores missing |
| `touch`    | creates missing, bumps mtime via `utimensat`; no `-a/-m/-t/-d` |
| `ln`       | hard and `-s` symlink; `-f` overwrites; two-operand form only |
| `readlink` | basic; no `-f/-e/-m` canonicalization yet |
| `chmod`    | octal and symbolic (`u/g/o/a` × `+/-/=` × `r/w/x`); no `s/t` perms or `-R` yet |
| `ls`       | sorted names; `-a`, `-l` (auto-sized columns, localtime mtime, `total <N>` header, uid/gid name resolution); no `-R/-F/-h` |
| `cp`       | `-r`/`-R` recursive (preserves symlinks); preserves source mode bits; no `-p/-i` |
| `mv`       | same-filesystem rename only; cross-device move surfaces a clear error |
| `stat`     | key:value summary; resolves uid/gid names; mtime as `Mon DD HH:MM` (localtime) |
| `chown`    | numeric or named `USER[:GROUP]` / `:GROUP`; `-R` recursive; `-h` no-dereference |
| `tee`      | `-a` appends; named-file failures don't abort other outputs; stdout failure aborts |
| `wc`       | `-l` / `-w` / `-c` columns; multi-file `total` row; bytes-not-chars (no `-m` yet) |
| `head`     | `-n N` / `-nN` / `-c N` / `-cN`; `==> NAME <==` headers between files |
| `tail`     | `-n N` / `-nN`; 4 MB sliding window for streams larger than memory |
| `cut`      | `-c LIST` / `-b LIST` / `-d DELIM -f LIST`; ranges (`N-M`, `N-`, `-M`); inline forms (`-cLIST`, `-d,`) |
| `tr`       | translate / `-d` delete / `-s` squeeze; literal + ranges + escapes (`\n` `\t` `\r` `\f` `\v` `\a` `\b` `\\` `\NNN`) |
| `uniq`     | `-c` count, `-d` dups only, `-u` uniques only; lines truncated at 8 KB |
| `sort`     | `-r`/`-n`/`-u`/`-f`; `-k F[,G]`; `-t SEP`; in-memory quicksort (16 MB / 256 K-line cap) |
| `grep`     | BRE regex (`. * ^ $ [...] [^...] \X`); `-F` for fixed-string; `-i`/`-v`/`-n`/`-c`; multi-file `FILE:` prefixes |
| `find`     | recursive walk; `-name PAT` (glob), `-type fdlcbps`, `-maxdepth N`, `-mindepth N`, `-empty`; actions `-print` (default), `-print0`; no `-exec`/operators yet |
| `whoami`   | uid → name via `/etc/passwd` (numeric fallback) |
| `id`       | full form, `-u`/`-g`/`-un`/`-gn` |
| `uname`    | `-a`/`-s`/`-n`/`-r`/`-v`/`-m`; combined short flags |
| `hostname` | `utsname.nodename`; setter form deferred |
| `date`     | `Sun Apr 26 15:37:54 UTC 2026`; UTC only, no `+FORMAT` yet |
| `kill`     | `-NUM`/`-NAME`/`-SIGNAME`; `-l` lists; default TERM |
| `which`    | walks `$PATH`; falls back to a hardcoded default if `$PATH` unset |
| `ps`       | reads `/proc`; PID + comm-name; no flags yet |

---

## Architecture

```
rill/
├── Makefile                  # NASM probe, build, symlinks, size, test
├── linker.ld                 # two PT_LOAD segments at 0x400000
├── include/                  # NASM include files
│   ├── syscalls.inc          #   SYS_* numbers
│   ├── macros.inc            #   STDIN/OUT/ERR_FILENO, EXIT_USAGE
│   ├── fcntl.inc             #   O_RDONLY, O_DIRECTORY, AT_FDCWD, …
│   └── stat.inc              #   struct stat offsets, S_IF* bits
├── src/
│   ├── start.asm             # _start, applet dispatcher, applet table
│   ├── core/                 # shared runtime
│   │   ├── string.asm        #   strlen, streq, isort_strs, basename
│   │   ├── io.asm            #   write_all (EINTR + short-write loop)
│   │   ├── fmt.asm           #   parse_uint, format_uint, format_uint_pad
│   │   ├── err.asm           #   errno → message + perror_path
│   │   ├── path.asm          #   stat_path, is_directory, path_join
│   │   ├── mode.asm          #   format_mode (10-byte "drwxr-xr-x")
│   │   ├── time.asm          #   Hinnant unix → calendar, format_date
│   │   ├── tz.asm            #   /etc/localtime (TZif v2/v3) parser
│   │   ├── passwd.asm        #   uid/gid ↔ name via /etc/passwd, /etc/group
│   │   └── regex.asm         #   minimal BRE matcher for grep
│   └── applets/              # one .asm per applet (41 files)
└── tests/integration/        # bats: per-applet diffs vs coreutils
```

**Three-layer flow:**

1. **Entry** — `_start` reads `argc` / `argv` from the kernel-prepared stack and tail-calls `dispatch`. The exit code goes to `SYS_exit_group`.
2. **Dispatch** — `dispatch` picks an applet by `basename(argv[0])` against the applet table. If `argv[0]` is `rill` itself, it shifts `argv` by one and retries — so `rill ls` and a `ls` symlink dispatch identically.
3. **Applets** — each receives `argc` in `edi` and `argv` in `rsi` (System V AMD64 ABI), returns its exit code in `rax`. Reads via `SYS_read`, writes via `SYS_write` through `core/io.asm`'s `write_all` (handles `EINTR` and short writes).

Adding an applet is mechanical: drop `src/applets/<name>.asm` exposing `applet_<name>_main`, wire it into `src/start.asm`'s extern list and dispatch table, add a bats file under `tests/integration/`. The Makefile auto-globs `src/applets/*.asm`.

---

## ABI notes

- **Calling convention**: System V AMD64. Args in `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`; return in `rax`. Callee-saved: `rbx`, `rbp`, `r12`–`r15`. Caller-saved scratch: `rax`, `rcx`, `rdx`, `r8`–`r11`.
- **Stack alignment**: at function entry `rsp = 8 mod 16`. Inner `call` sites need `rsp = 0 mod 16`. Common shape: 6 callee-saved pushes + `sub rsp, 8` brings inner-call alignment back to 0 mod 16.
- **Syscall ABI**: `rax = SYS_*`, args in `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`; return in `rax` (negative values are `-errno`).
- **Buffers**: large transient buffers live in `.bss` (lazy-paged by the kernel — no startup cost); per-frame scratch (small enough to fit) lives on the stack with explicit `sub rsp, N`.

---

## Why "rill"?

A rill is a small, fast-running stream — narrow, sharp, cuts through stone over time. Felt fitting for the assembly cousin in the multi-call family: a slimmer, lower-level companion to the Rust [jib](https://github.com/Real-Fruit-Snacks/jib), Go [topsail](https://github.com/Real-Fruit-Snacks/topsail), and Python [mainsail](https://github.com/Real-Fruit-Snacks/mainsail) — same shape, different substrate.

## License

MIT. See [LICENSE](LICENSE).
