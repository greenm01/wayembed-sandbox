{.passC: "-D_GNU_SOURCE".}

import std/[strformat]

import wayland/native/client as wlclient
import wayland/native/common as wlcommon
import wayland/protocols/wayland/client as wl
import wayland/protocols/wayland/code as wlcode
import wayland/protocols/stable/xdgshell/client as xdg
import wayland/protocols/stable/xdgshell/code as xdgcode

import ./event_loop

const
  protRead = 1
  protWrite = 2
  mapShared = 1
  mfdCloexec = 0x0001

type
  HostSurfaceObj = object
    width*: int32
    height*: int32
    display*: ptr wlcommon.Display
    registry*: ptr wlcommon.Registry
    compositor*: ptr wlcommon.Compositor
    subcompositor*: ptr wlcommon.Subcompositor
    shm*: ptr wlcommon.Shm
    seat*: ptr wlcommon.Seat
    output*: ptr wlcommon.Output
    xdgWmBase*: ptr xdgcode.XdgWmBase
    surface*: ptr wlcommon.Surface
    xdgSurface*: ptr xdgcode.XdgSurface
    toplevel*: ptr xdgcode.XdgToplevel
    buffer*: ptr wlcommon.Buffer
    shmData*: pointer
    shmSize*: int
    configured*: bool
    closed*: bool

  HostSurface* = ptr HostSurfaceObj

proc memfd_create(name: cstring, flags: cuint): cint {.importc, header: "sys/mman.h".}
proc ftruncate(fd: cint, length: clong): cint {.importc, header: "unistd.h".}
proc mmap(
  address: pointer, length: csize_t, prot: cint, flags: cint, fd: cint, offset: clong
): pointer {.importc, header: "sys/mman.h".}

proc munmap(address: pointer, length: csize_t): cint {.importc, header: "sys/mman.h".}
proc closeFd(fd: cint): cint {.importc: "close", header: "unistd.h".}

proc registryGlobal(
    data: pointer,
    registry: ptr wlcommon.Registry,
    name: uint32,
    iface: cstring,
    version: uint32,
) =
  let host = cast[HostSurface](data)
  let bindVersion = proc(maxVersion: uint32): uint32 =
    min(version, maxVersion)
  case $iface
  of "wl_compositor":
    host.compositor = cast[ptr wlcommon.Compositor](wl.bind(
      registry, name, addr wl.wl_compositor_interface, bindVersion(4)
    ))
  of "wl_subcompositor":
    host.subcompositor = cast[ptr wlcommon.Subcompositor](wl.bind(
      registry, name, addr wl.wl_subcompositor_interface, bindVersion(1)
    ))
  of "wl_shm":
    host.shm = cast[ptr wlcommon.Shm](wl.bind(
      registry, name, addr wl.wl_shm_interface, bindVersion(1)
    ))
  of "wl_seat":
    if host.seat == nil:
      host.seat = cast[ptr wlcommon.Seat](wl.bind(
        registry, name, addr wl.wl_seat_interface, bindVersion(4)
      ))
  of "wl_output":
    if host.output == nil:
      host.output = cast[ptr wlcommon.Output](wl.bind(
        registry, name, addr wl.wl_output_interface, bindVersion(4)
      ))
  of "xdg_wm_base":
    host.xdgWmBase = cast[ptr xdgcode.XdgWmBase](wl.bind(
      registry, name, addr xdg.xdg_wm_base_interface, bindVersion(7)
    ))
  else:
    discard

proc registryGlobalRemove(
    data: pointer, registry: ptr wlcommon.Registry, name: uint32
) =
  discard data
  discard registry
  discard name

proc xdgPing(data: pointer, wmBase: ptr xdgcode.XdgWmBase, serial: uint32) =
  discard data
  xdg.pong(wmBase, serial)

proc drawBuffer(host: HostSurface): ptr wlcommon.Buffer =
  let stride = host.width * 4
  let size = int(stride * host.height)
  let fd = memfd_create("wayembed-sandbox", mfdCloexec)
  if fd < 0:
    return nil
  if ftruncate(fd, clong(size)) != 0:
    discard closeFd(fd)
    return nil

  let data = mmap(nil, csize_t(size), protRead or protWrite, mapShared, fd, 0)
  if data == nil or cast[int](data) == -1:
    discard closeFd(fd)
    return nil

  let pixels = cast[ptr UncheckedArray[uint32]](data)
  for y in 0 ..< host.height:
    for x in 0 ..< host.width:
      let stripe =
        if ((x div 24) + (y div 24)) mod 2 == 0: 0x00263a5cu32 else: 0x0032522du32
      pixels[int(y * host.width + x)] = 0xff000000u32 or stripe

  let pool = wl.createPool(host.shm, fd, int32(size))
  if pool == nil:
    discard munmap(data, csize_t(size))
    discard closeFd(fd)
    return nil
  result = wl.createBuffer(
    pool, 0, host.width, host.height, stride, uint32(wlcode.format_xrgb8888)
  )
  wl.destroy(pool)
  discard closeFd(fd)

  if result == nil:
    discard munmap(data, csize_t(size))
    return nil
  host.shmData = data
  host.shmSize = size

proc xdgSurfaceConfigure(
    data: pointer, xdgSurface: ptr xdgcode.XdgSurface, serial: uint32
) =
  let host = cast[HostSurface](data)
  xdg.ackConfigure(xdgSurface, serial)
  if host.buffer == nil:
    host.buffer = drawBuffer(host)
  if host.buffer != nil:
    wl.attach(host.surface, host.buffer, 0, 0)
    wl.damage(host.surface, 0, 0, host.width, host.height)
  wl.commit(host.surface)
  host.configured = true

proc toplevelConfigure(
    data: pointer,
    toplevel: ptr xdgcode.XdgToplevel,
    width: int32,
    height: int32,
    states: ptr wlcommon.Array,
) =
  discard data
  discard toplevel
  discard width
  discard height
  discard states

proc toplevelClose(data: pointer, toplevel: ptr xdgcode.XdgToplevel) =
  discard toplevel
  cast[HostSurface](data).closed = true

proc toplevelConfigureBounds(
    data: pointer, toplevel: ptr xdgcode.XdgToplevel, width: int32, height: int32
) =
  discard data
  discard toplevel
  discard width
  discard height

proc toplevelWmCapabilities(
    data: pointer, toplevel: ptr xdgcode.XdgToplevel, capabilities: ptr wlcommon.Array
) =
  discard data
  discard toplevel
  discard capabilities

var registryListener =
  wl.RegistryListener(global: registryGlobal, globalRemove: registryGlobalRemove)
var wmBaseListener = xdg.XdgWmBaseListener(ping: xdgPing)
var xdgSurfaceListener = xdg.XdgSurfaceListener(configure: xdgSurfaceConfigure)
var toplevelListener = xdg.XdgToplevelListener(
  configure: toplevelConfigure,
  close: toplevelClose,
  configureBounds: toplevelConfigureBounds,
  wmCapabilities: toplevelWmCapabilities,
)

proc openHostSurface*(width, height: int32): HostSurface =
  result = create(HostSurfaceObj)
  result.width = width
  result.height = height
  result.display = wlclient.connect_display(nil)
  if result.display == nil:
    raise newException(IOError, "could not connect to the Wayland compositor")

  result.registry = wl.getRegistry(result.display)
  discard wl.addListener(result.registry, addr registryListener, cast[pointer](result))
  if wlclient.roundtrip(result.display) < 0:
    raise newException(IOError, "Wayland registry roundtrip failed")
  if result.compositor == nil or result.subcompositor == nil or result.shm == nil or
      result.xdgWmBase == nil:
    raise newException(IOError, "compositor is missing a required Wayland global")

  discard xdg.addListener(result.xdgWmBase, addr wmBaseListener, cast[pointer](result))
  result.surface = wl.createSurface(result.compositor)
  result.xdgSurface = xdg.getXdgSurface(result.xdgWmBase, result.surface)
  result.toplevel = xdg.getToplevel(result.xdgSurface)
  discard
    xdg.addListener(result.xdgSurface, addr xdgSurfaceListener, cast[pointer](result))
  discard xdg.addListener(result.toplevel, addr toplevelListener, cast[pointer](result))
  xdg.setTitle(result.toplevel, "wayembed sandbox")
  xdg.setAppId(result.toplevel, "wayembed-sandbox")
  wl.commit(result.surface)
  discard wlclient.flush(result.display)

proc pumpHostSurface*(host: HostSurface, durationMs: int): bool =
  var remaining = max(durationMs, 0)
  while remaining > 0 and not host.closed:
    discard wlclient.flush(host.display)
    let wait = min(remaining, 20)
    let poll = waitForFd(wlclient.get_fd(host.display), wait)
    if poll.failed:
      return false
    if poll.ready:
      if wlclient.dispatch(host.display) < 0:
        return false
    else:
      discard wlclient.dispatch_pending(host.display)
    remaining -= wait
  true

proc closeHostSurface*(host: HostSurface) =
  if host == nil:
    return
  if host.display != nil:
    discard wlclient.flush(host.display)
  if host.shmData != nil and host.shmSize > 0:
    discard munmap(host.shmData, csize_t(host.shmSize))
  if host.display != nil:
    wlclient.disconnect(host.display)
  dealloc(host)

proc describeHostSurface*(host: HostSurface): string =
  &"host-surface width={host.width} height={host.height} configured={host.configured}"
