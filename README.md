<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Real-Fruit-Snacks/rill/main/docs/assets/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Real-Fruit-Snacks/rill/main/docs/assets/logo-light.svg">
  <img alt="Rill" src="https://raw.githubusercontent.com/Real-Fruit-Snacks/rill/main/docs/assets/logo-dark.svg" width="100%">
</picture>

> [!IMPORTANT]
> **A BusyBox-style multi-call binary in pure x86_64 NASM assembly** — 41 POSIX utilities, one ~108 KB static ELF, direct syscalls, no libc, no startup runtime. The assembly cousin to [jib](https://github.com/Real-Fruit-Snacks/jib) (Rust), [topsail](https://github.com/Real-Fruit-Snacks/topsail) (Go), and [mainsail](https://github.com/Real-Fruit-Snacks/mainsail) (Python).

> *A rill is a small, fast-running stream — narrow, sharp, cuts through stone over time.*

---

## §1 / Premise

The multi-call family already had three flavours: jib in Rust, topsail in Go, mainsail in Python. Rill is the same shape rebuilt at the lowest practical level — every applet hand-written in NASM, every operation a direct `syscall`, no dynamic linker, no libc, no global allocator, no startup glue.

It is **not** trying to be smaller than `busybox`. It is trying to be readable end-to-end: every byte the kernel sees originated in a `.asm` file in this repo, and every applet is small enough to read in a sitting.

---

## §2 / Specs

| KEY      | VALUE                                                                       |
|----------|-----------------------------------------------------------------------------|
| BINARY   | One ~108 KB static ELF · two PT_LOAD segments · `ldd` says "not dynamic"   |
| APPLETS  | **41 POSIX utilities** — file ops, text, paths, system, control            |
| RUNTIME  | No libc · no startup · no global allocator · `.bss` + stack frames only    |
| DISPATCH | Multi-call via `argv[0]` basename or `rill <applet>` subcommand            |
| TESTS    | **329 bats cases** — byte-diff against `/usr/bin/<applet>` where possible  |
| STACK    | NASM 2.x · GNU ld · GNU make · System V AMD64 ABI · Linux x86_64           |

Every applet implements the common POSIX flags. See [`tests/integration/`](tests/integration/) for the contract.

---

## §3 / Quickstart

```bash
# From a release — no toolchain needed (Linux x86_64)
curl -LO https://github.com/Real-Fruit-Snacks/rill/releases/latest/download/rill-linux-x64
chmod +x rill-linux-x64 && mv rill-linux-x64 rill
./rill date
ln -s rill ls && ./ls -la              # multi-call via symlink

# From source — Linux with NASM, ld, make, bats (or WSL on Windows)
git clone https://github.com/Real-Fruit-Snacks/rill.git && cd rill
make             # builds build/rill
make symlinks    # creates build/<applet> symlinks for multi-call dispatch
make test        # runs the bats integration suite (329 cases)
make size        # prints the linked binary's size
```

```bash
# Verify
file build/rill                         # ELF 64-bit LSB executable, statically linked
ldd  build/rill                         # not a dynamic executable
./build/rill true && echo ok            # subcommand dispatch
./build/ls -la                          # multi-call: argv[0] basename
echo hi | ./build/grep -i 'H.'          # full pipeline
```

---

## §4 / Reference

```
APPLETS                                                # 41 total

  FILE OPS    ls cp mv rm mkdir rmdir touch ln readlink chmod chown stat find
  TEXT        cat wc head tail cut tr sort uniq grep tee
  PATHS       pwd basename dirname which
  SYSTEM      whoami id uname hostname date kill ps env printenv
  CONTROL     true false echo yes sleep

DISPATCH

  rill <applet> [args]                   # subcommand form
  ln -s rill <applet>                    # multi-call: argv[0] basename
                                         # rill ls and ./ls dispatch identically

NOTABLE FLAG SUPPORT

  ls           -a · -l (auto-sized cols, localtime mtime, uid/gid name resolution)
  find         -name PATTERN (full glob) · -type fdlcbps · -maxdepth/-mindepth · -empty
  grep         BRE regex · -F fixed · -i · -v · -n · -c · multi-file FILE: prefixes
  sort         -r · -n · -u · -f · -k F[,G] field · -t SEP delim · 16 MB cap
  chown        numeric or named USER[:GROUP] · -R recursive · -h no-deref
  chmod        octal and symbolic (u/g/o/a × +/-/= × r/w/x)
  tail         -n N · 4 MB sliding window for streams larger than memory
  cut          -c LIST · -b LIST · -d DELIM -f LIST · ranges · inline forms
  tr           translate · -d delete · -s squeeze · escapes \n \t \r \f \v \a \b \\ \NNN

BUILD TARGETS                                           # Makefile
  make                  Build build/rill
  make symlinks         Create build/<applet> symlinks
  make test             Run the bats integration suite
  make size             Print the linked binary's size
  make clean            Remove build artifacts

ABI
  Calling conv          System V AMD64 (rdi rsi rdx rcx r8 r9 → rax)
  Syscall conv          rax = SYS_* · rdi rsi rdx r10 r8 r9 → rax (-errno)
  Buffers               .bss (lazy-paged) · stack frames (sub rsp, N)
```

Adding an applet is mechanical: drop `src/applets/<name>.asm` exposing `applet_<name>_main`, wire it into `src/start.asm`'s extern list and dispatch table, add a bats file under `tests/integration/`. The Makefile auto-globs `src/applets/*.asm`.

---

## §5 / Authorization

Rill is a userland Unix utility binary — no privileged operations, no network code, no exploitation surface. It runs the same applets `coreutils` does, just compiled smaller and statically.

The interesting questions are **portability** (Linux x86_64 only — no other archs, no other kernels) and **completeness** (most applets cover the common flags; the README per-applet table is honest about what's missing). Open an issue if you need a flag, or send a PR — the harness tells you whether you got it right.

Vulnerabilities go through [private security advisories](https://github.com/Real-Fruit-Snacks/rill/security/advisories/new), never public issues.

---

[License: MIT](LICENSE) · Part of [Real-Fruit-Snacks](https://github.com/Real-Fruit-Snacks) — building offensive security tools, one wave at a time. Sibling: [jib](https://github.com/Real-Fruit-Snacks/jib) (Rust) · [topsail](https://github.com/Real-Fruit-Snacks/topsail) (Go) · [mainsail](https://github.com/Real-Fruit-Snacks/mainsail) (Python) · [moonraker](https://github.com/Real-Fruit-Snacks/moonraker) (Lua) · [staysail](https://github.com/Real-Fruit-Snacks/staysail) (Zig).
