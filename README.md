# wayembed-sandbox

A small Nim test platform for `wayembed`.

It proves the public C ABI from a non-C host, opens a live Wayland parent
surface, and embeds plugin-created surfaces through `wayembed`.

## Layout

- `src/bindings/wayembed.nim` mirrors `wayembed.h`.
- `src/bindings/wayembed_adapters.nim` mirrors `wayembed_adapters.h`.
- `src/wayembed_sandbox.nim` provides the command runner.
- `fixtures/c/` contains tiny C Wayland plugin fixtures.

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
bin/wayembed-sandbox fd-embed-smoke
bin/wayembed-sandbox clap-order-smoke
bin/wayembed-sandbox clap-c-plugin-smoke
bin/wayembed-sandbox lv2-order-smoke
bin/wayembed-sandbox lv2-c-plugin-smoke
bin/wayembed-sandbox vst3-order-smoke
bin/wayembed-sandbox vst3-c-plugin-smoke
bin/wayembed-sandbox adapter-fd-c-plugin-smoke
```

`abi-smoke` checks the C ABI from Nim. `host-surface` opens a live Wayland
parent window. `embed-smoke` creates one plugin surface and embeds it through
wayembed. `fd-embed-smoke` runs the same embedded surface path through a raw
client fd. `clap-order-smoke`, `lv2-order-smoke`, and `vst3-order-smoke`
validate the experimental adapter handoff order without loading a real plugin.
`clap-c-plugin-smoke`, `lv2-c-plugin-smoke`, and `vst3-c-plugin-smoke` pass the
adapter handoff display into a tiny C plugin fixture and embed the
fixture-created surface. `adapter-fd-c-plugin-smoke` repeats that fixture path
through fd-backed CLAP, LV2, and VST3 handoffs.

Before committing Nim changes, run the semantic check last:

```sh
nimble checkSources
```
