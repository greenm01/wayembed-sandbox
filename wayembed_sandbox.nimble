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

task abiSmoke, "Run the Nim C ABI smoke test":
  exec "mkdir -p bin"
  exec "nim c --hints:off -o:bin/wayembed-sandbox src/wayembed_sandbox.nim"
  exec "bin/wayembed-sandbox abi-smoke"
