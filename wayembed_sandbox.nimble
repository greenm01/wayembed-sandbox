import std/strutils

# Package

version = "0.1.0"
author = "Mason Austin Green"
description = "Minimal Nim test platform for wayembed"
license = "MIT"
srcDir = "src"
bin = @["wayembed_sandbox"]

# Dependencies

requires "nim >= 2.2.4"
requires "https://github.com/panno8M/wayland-nim == 0.1.0"

task buildSandbox, "Build the sandbox executable":
  exec "mkdir -p bin"
  exec "nim c --hints:off -o:bin/wayembed-sandbox src/wayembed_sandbox.nim"

task checkSources, "Run Nim semantic checks before committing":
  let waylandPath = gorge("nimble path 'wayland@0.1.0'").splitLines()[0].strip()
  exec "nim check --hints:off --path:" & waylandPath & " src/wayembed_sandbox.nim"

task abiSmoke, "Run the Nim C ABI smoke test":
  exec "mkdir -p bin"
  exec "nim c --hints:off -o:bin/wayembed-sandbox src/wayembed_sandbox.nim"
  exec "bin/wayembed-sandbox abi-smoke"
