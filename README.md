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
nim c --hints:off -o:bin/wayembed-sandbox src/wayembed_sandbox.nim
```

## Commands

```sh
bin/wayembed-sandbox abi-smoke
bin/wayembed-sandbox host-surface
bin/wayembed-sandbox embed-smoke
bin/wayembed-sandbox clap-order-smoke
```

`abi-smoke` is the first runnable proof. The other commands are placeholders
for the next milestones.
