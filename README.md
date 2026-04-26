# rill

A small, fast, professionally-maintained multi-call binary for x86_64 Linux,
written in pure assembly with direct syscalls and no libc.

## Status

Phase 0 — foundation. Build pipeline, dispatcher, and the `true` applet.

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
