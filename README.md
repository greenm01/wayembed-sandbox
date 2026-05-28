# wayembed-sandbox

`wayembed-sandbox` is a small Nim program for trying `wayembed` from outside C.

It opens Wayland windows, loads tiny plugin fixtures, and checks that embedded
plugin surfaces end up where the host expects them. The point is not to be a
full host. It is a quick place to catch ABI mistakes, adapter-order bugs, and
broken Wayland handoffs while `wayembed` is changing.

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

## Run

Most checks run through the sandbox binary:

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

There is also a VST3 host smoke test:

```sh
make vst3-host-smoke
bin/wayembed-vst3-host-smoke
```

It loads nilamp's VST3 bundle by default. Set `WAYEMBED_VST3_PLUGIN`, or pass a
bundle path as the first argument, to try another plugin.

Before committing Nim changes, run:

```sh
nimble checkSources
```
