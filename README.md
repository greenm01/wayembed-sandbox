# wayembed-sandbox

A small Nim test platform for `wayembed`.

The first goal is to prove that the public C ABI works from a non-C host. The
next goal is a minimal Wayland host surface that embeds one plugin-created
surface through `wayembed`.

## Layout

- `src/bindings/wayembed.nim` mirrors `wayembed.h`.
- `src/bindings/wayembed_adapters.nim` mirrors `wayembed_adapters.h`.
- `src/wayembed_sandbox.nim` provides the command runner.
- `fixtures/c/` is reserved for tiny C Wayland or CLAP fixtures.

## Build

Build `wayembed` first:

```sh
cd /home/niltempus/dev/wayembed
zig build install
```

Then build the sandbox:

```sh
cd /home/niltempus/dev/wayembed-sandbox
nimble c --hints:off -o:bin/wayembed-sandbox src/wayembed_sandbox.nim
```

## Commands

```sh
bin/wayembed-sandbox abi-smoke
bin/wayembed-sandbox host-surface
bin/wayembed-sandbox embed-smoke
bin/wayembed-sandbox clap-order-smoke
bin/wayembed-sandbox lv2-order-smoke
```

`abi-smoke` checks the C ABI from Nim. `host-surface` opens a live Wayland
parent window. `embed-smoke` creates one plugin surface and embeds it through
wayembed. `clap-order-smoke` and `lv2-order-smoke` validate the experimental
adapter handoff order without loading a real plugin.

Before committing Nim changes, run the semantic check last:

```sh
nimble checkSources
```
