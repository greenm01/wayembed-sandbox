{.passC: "-D_GNU_SOURCE".}
{.passC: "-Ifixtures/c".}
{.compile: "../fixtures/c/wayland_plugin_fixture.c".}

import std/[os, strformat, strutils]

import wayland/native/client as wlclient
import wayland/native/common as wlcommon
import wayland/protocols/wayland/client as wl
import wayland/protocols/wayland/code as wlcode

import bindings/wayembed
import bindings/wayembed_adapters
import host/event_loop
import host/wayland_host

type CPluginFixture {.importc: "struct wayembed_c_plugin_fixture", incompleteStruct.} = object

proc closeFd(fd: cint): cint {.importc: "close", header: "unistd.h".}
proc memfd_create(name: cstring, flags: cuint): cint {.importc, header: "sys/mman.h".}
proc ftruncate(fd: cint, length: clong): cint {.importc, header: "unistd.h".}
proc mmap(
  address: pointer, length: csize_t, prot: cint, flags: cint, fd: cint, offset: clong
): pointer {.importc, header: "sys/mman.h".}

proc munmap(address: pointer, length: csize_t): cint {.importc, header: "sys/mman.h".}
proc wayembed_c_plugin_fixture_create(
  display: ptr WlDisplay
): ptr CPluginFixture {.cdecl, importc, header: "wayland_plugin_fixture.h".}

proc wayembed_c_plugin_fixture_destroy(
  fixture: ptr CPluginFixture
) {.cdecl, importc, header: "wayland_plugin_fixture.h".}

proc wayembed_c_plugin_fixture_globals_ready(
  fixture: ptr CPluginFixture
): bool {.cdecl, importc, header: "wayland_plugin_fixture.h".}

proc wayembed_c_plugin_fixture_commit_surface(
  fixture: ptr CPluginFixture
): bool {.cdecl, importc, header: "wayland_plugin_fixture.h".}

const
  protRead = 1
  protWrite = 2
  mapShared = 1
  mfdCloexec = 0x0001

var connectedCount = 0
var closedCount = 0
var mappedCount = 0
var resizedCount = 0
var destroyedCount = 0
var lastClient: ptr WayembedClient = nil
var surfaceCreatedCount = 0

type
  PluginGlobals = object
    registry: ptr wlcommon.Registry
    compositor: ptr wlcommon.Compositor
    shm: ptr wlcommon.Shm

  Scenario = object
    host: HostSurface
    embed: ptr WayembedEmbed
    attachStatus: uint32
    childSurface: ptr WlSurface

proc pluginRegistryGlobal(
    data: pointer,
    registry: ptr wlcommon.Registry,
    name: uint32,
    iface: cstring,
    version: uint32,
) =
  let globals = cast[ptr PluginGlobals](data)
  let bindVersion = proc(maxVersion: uint32): uint32 =
    min(version, maxVersion)
  case $iface
  of "wl_compositor":
    globals.compositor = cast[ptr wlcommon.Compositor](wl.bind(
      registry, name, addr wl.wl_compositor_interface, bindVersion(4)
    ))
  of "wl_shm":
    globals.shm = cast[ptr wlcommon.Shm](wl.bind(
      registry, name, addr wl.wl_shm_interface, bindVersion(1)
    ))
  else:
    discard

proc pluginRegistryGlobalRemove(
    data: pointer, registry: ptr wlcommon.Registry, name: uint32
) =
  discard data
  discard registry
  discard name

var pluginRegistryListener = wl.RegistryListener(
  global: pluginRegistryGlobal, globalRemove: pluginRegistryGlobalRemove
)

proc onClientConnected(userdata: pointer, client: ptr WayembedClient) {.cdecl.} =
  discard userdata
  if client != nil:
    inc connectedCount
    lastClient = client

proc onClientClosed(userdata: pointer, client: ptr WayembedClient) {.cdecl.} =
  discard userdata
  if client != nil:
    inc closedCount

proc onSurfaceCreated(
    userdata: pointer, client: ptr WayembedClient, pluginChildSurface: ptr WlSurface
) {.cdecl.} =
  inc surfaceCreatedCount
  if userdata == nil or client == nil or pluginChildSurface == nil:
    return
  let scenario = cast[ptr Scenario](userdata)
  scenario.childSurface = pluginChildSurface
  var info = WayembedEmbedAttachInfo(
    size: uint32(sizeof(WayembedEmbedAttachInfo)),
    version: WayembedAbiVersion,
    client: client,
    parent_surface: cast[ptr WlSurface](scenario.host.surface),
    child_surface: pluginChildSurface,
  )
  scenario.attachStatus = wayembed_embed_attach(addr info, addr scenario.embed)

proc onEmbedMapped(userdata: pointer, embed: ptr WayembedEmbed) {.cdecl.} =
  discard userdata
  if embed != nil and wayembed_embed_id(embed) != 0:
    inc mappedCount

proc onEmbedResized(
    userdata: pointer, embed: ptr WayembedEmbed, width: int32, height: int32
) {.cdecl.} =
  discard userdata
  if embed != nil and wayembed_embed_id(embed) != 0 and width >= 0 and height >= 0:
    inc resizedCount

proc onEmbedDestroyed(userdata: pointer, embed: ptr WayembedEmbed) {.cdecl.} =
  discard userdata
  if embed != nil and wayembed_embed_id(embed) != 0:
    inc destroyedCount

proc fail(code: int, message: string): int =
  stderr.writeLine(&"error[{code}]: {message}")
  code

proc expectedFeatureMask(): uint64 =
  WayembedFeatureCompositor or WayembedFeatureSubcompositor or WayembedFeatureSurface or
    WayembedFeatureShmBuffer or WayembedFeatureEmbedSession or WayembedFeatureSeat or
    WayembedFeaturePointer or WayembedFeatureKeyboard or WayembedFeatureTouch or
    WayembedFeatureOutput or WayembedFeatureXdgShell or WayembedFeatureClientFd

proc makeHostInterface(): WayembedHostInterface =
  result.size = uint32(sizeof(WayembedHostInterface))
  result.version = WayembedAbiVersion
  result.userdata = nil
  result.get_compositor = nil
  result.get_subcompositor = nil
  result.get_shm = nil
  result.get_seat = nil
  result.get_xdg_wm_base = nil
  result.get_dmabuf = nil
  result.get_subsurface_offset = nil
  result.on_client_connected = onClientConnected
  result.on_surface_created = nil
  result.on_client_closed = onClientClosed
  result.on_protocol_error = nil
  result.on_embed_mapped = onEmbedMapped
  result.on_embed_resized = onEmbedResized
  result.on_embed_destroyed = onEmbedDestroyed
  result.get_seat_capabilities = nil
  result.get_seat_name = nil
  result.get_output_info = nil

proc makeWaylandHostInterface(scenario: ptr Scenario): WayembedHostInterface =
  result = makeHostInterface()
  result.userdata = cast[pointer](scenario)
  result.get_compositor = proc(userdata: pointer): ptr WlCompositor {.cdecl.} =
    cast[ptr WlCompositor](cast[ptr Scenario](userdata).host.compositor)
  result.get_subcompositor = proc(userdata: pointer): ptr WlSubcompositor {.cdecl.} =
    cast[ptr WlSubcompositor](cast[ptr Scenario](userdata).host.subcompositor)
  result.get_shm = proc(userdata: pointer): ptr WlShm {.cdecl.} =
    cast[ptr WlShm](cast[ptr Scenario](userdata).host.shm)
  result.get_seat = proc(userdata: pointer): ptr WlSeat {.cdecl.} =
    cast[ptr WlSeat](cast[ptr Scenario](userdata).host.seat)
  result.get_xdg_wm_base = proc(userdata: pointer): ptr XdgWmBase {.cdecl.} =
    cast[ptr XdgWmBase](cast[ptr Scenario](userdata).host.xdgWmBase)
  result.on_surface_created = onSurfaceCreated

proc resetCounters() =
  connectedCount = 0
  closedCount = 0
  mappedCount = 0
  resizedCount = 0
  destroyedCount = 0
  lastClient = nil
  surfaceCreatedCount = 0

proc snapshotClientCount(snapshot: ptr WayembedSnapshot, clients: var csize_t): bool =
  var counts = WayembedSnapshotCounts(
    size: uint32(sizeof(WayembedSnapshotCounts)), version: WayembedAbiVersion
  )
  if not wayembed_snapshot_get_counts(snapshot, addr counts):
    return false
  clients = counts.clients
  true

proc pumpWayembedClient(
    server: ptr WayembedServer,
    display: ptr wlcommon.Display,
    host: HostSurface = nil,
    iterations = 4,
) =
  for _ in 0 ..< iterations:
    discard wlclient.flush(display)
    wayembed_server_dispatch(server)
    wayembed_server_flush(server)
    let poll = waitForFd(wlclient.get_fd(display), 20)
    if poll.ready:
      discard wlclient.dispatch(display)
    else:
      discard wlclient.dispatch_pending(display)
    if host != nil:
      discard pumpHostSurface(host, 20)

proc drawPluginSurface(globals: PluginGlobals, surface: ptr wlcommon.Surface): bool =
  if globals.shm == nil or surface == nil:
    return false
  let width = 180'i32
  let height = 96'i32
  let stride = width * 4
  let size = stride * height
  let fd = memfd_create("wayembed-plugin", mfdCloexec)
  if fd < 0:
    return false
  if ftruncate(fd, clong(size)) != 0:
    discard closeFd(fd)
    return false
  let data = mmap(nil, csize_t(size), protRead or protWrite, mapShared, fd, 0)
  if data == nil or cast[int](data) == -1:
    discard closeFd(fd)
    return false
  defer:
    discard munmap(data, csize_t(size))
  let pixels = cast[ptr UncheckedArray[uint32]](data)
  for y in 0 ..< height:
    for x in 0 ..< width:
      let base =
        if ((x div 16) + (y div 16)) mod 2 == 0: 0xffb8472fu32 else: 0xffd6b14au32
      pixels[int(y * width + x)] = base
  let pool = wl.createPool(globals.shm, fd, size)
  if pool == nil:
    discard closeFd(fd)
    return false
  let buffer =
    wl.createBuffer(pool, 0, width, height, stride, uint32(wlcode.format_xrgb8888))
  wl.destroy(pool)
  discard closeFd(fd)
  if buffer == nil:
    return false
  wl.attach(surface, buffer, 0, 0)
  wl.damage(surface, 0, 0, width, height)
  wl.commit(surface)
  true

proc runAbiSmoke(): int =
  resetCounters()

  if wayembed_abi_version() != WayembedAbiVersion:
    return fail(1, "wayembed ABI version mismatch")
  if wayembed_adapter_abi_version() != WayembedAdapterAbiVersion:
    return fail(2, "wayembed adapter ABI version mismatch")
  if wayembed_get_features(nil):
    return fail(3, "nil feature query succeeded")

  var features = WayembedFeatures(
    size: uint32(sizeof(WayembedFeatures)), version: WayembedAbiVersion, flags: 0
  )
  if not wayembed_get_features(addr features):
    return fail(4, "wayembed_get_features failed")
  if (features.flags and expectedFeatureMask()) != expectedFeatureMask():
    return fail(5, &"missing feature flags: {features.flags}")
  features.size = uint32(sizeof(uint32) * 2)
  if wayembed_get_features(addr features):
    return fail(6, "short feature struct accepted")
  features.size = uint32(sizeof(WayembedFeatures))
  features.version = WayembedAbiVersion + 1
  if wayembed_get_features(addr features):
    return fail(7, "future feature version accepted")

  var host = makeHostInterface()
  let server = wayembed_server_create(addr host, nil)
  if server == nil:
    return fail(8, "wayembed_server_create returned nil")
  defer:
    wayembed_server_destroy(server)

  if wayembed_server_get_fd(server) < 0:
    return fail(9, "server fd is invalid")

  let emptySnapshot = wayembed_server_snapshot(server)
  if emptySnapshot == nil:
    return fail(10, "empty snapshot failed")
  var emptyCounts = WayembedSnapshotCounts(
    size: uint32(sizeof(WayembedSnapshotCounts)), version: WayembedAbiVersion
  )
  if not wayembed_snapshot_get_counts(emptySnapshot, addr emptyCounts):
    wayembed_snapshot_free(emptySnapshot)
    return fail(11, "snapshot counts failed")
  var invalidCounts = WayembedSnapshotCounts(
    size: uint32(sizeof(uint32) * 2), version: WayembedAbiVersion
  )
  if wayembed_snapshot_get_counts(emptySnapshot, addr invalidCounts):
    wayembed_snapshot_free(emptySnapshot)
    return fail(12, "short snapshot counts struct accepted")
  wayembed_snapshot_free(emptySnapshot)
  if emptyCounts.clients != 0:
    return fail(13, "new server unexpectedly has clients")

  let display = wayembed_server_open_client_display(server)
  if display == nil:
    return fail(14, "open client display failed")

  wayembed_server_dispatch(server)
  if connectedCount != 1 or lastClient == nil:
    discard wayembed_server_close_client_display(server, display)
    return fail(15, "client connection callback did not fire")

  var handoff = WayembedAdapterHandoff(size: uint32(sizeof(WayembedAdapterHandoff)))
  if not wayembed_adapter_handoff_init(
    addr handoff, WayembedAdapterFormatClap, server, display
  ):
    discard wayembed_server_close_client_display(server, display)
    return fail(16, "adapter handoff init failed")
  if not wayembed_adapter_handoff_validate(addr handoff):
    discard wayembed_server_close_client_display(server, display)
    return fail(17, "adapter handoff validate failed")
  if $handoff.format_token != WayembedAdapterClapExperimentalApi:
    discard wayembed_server_close_client_display(server, display)
    return fail(18, "unexpected CLAP adapter token")
  handoff.format_token = WayembedAdapterLv2ExperimentalUri
  if wayembed_adapter_handoff_validate(addr handoff):
    discard wayembed_server_close_client_display(server, display)
    return fail(19, "mismatched adapter token accepted")
  if not wayembed_adapter_handoff_init(
    addr handoff, WayembedAdapterFormatLv2, server, display
  ):
    discard wayembed_server_close_client_display(server, display)
    return fail(20, "LV2 adapter handoff init failed")
  if not wayembed_adapter_handoff_validate(addr handoff):
    discard wayembed_server_close_client_display(server, display)
    return fail(21, "LV2 adapter handoff validate failed")
  if $handoff.format_token != WayembedAdapterLv2ExperimentalUri:
    discard wayembed_server_close_client_display(server, display)
    return fail(22, "unexpected LV2 adapter URI")
  handoff.version = WayembedAdapterAbiVersion + 1
  if wayembed_adapter_handoff_validate(addr handoff):
    discard wayembed_server_close_client_display(server, display)
    return fail(23, "future handoff version accepted")
  handoff.size = uint32(sizeof(WayembedAdapterHandoff))
  if wayembed_adapter_handoff_init(
    addr handoff, WayembedAdapterFormatUnknown, server, display
  ):
    discard wayembed_server_close_client_display(server, display)
    return fail(24, "unknown handoff format accepted")

  var resize = WayembedAdapterResize(
    size: uint32(sizeof(WayembedAdapterResize)),
    version: WayembedAdapterAbiVersion,
    width: 640,
    height: 480,
    scale: 1.0,
  )
  if not wayembed_adapter_resize_validate(addr resize):
    discard wayembed_server_close_client_display(server, display)
    return fail(25, "valid resize rejected")
  resize.width = -1
  if wayembed_adapter_resize_validate(addr resize):
    discard wayembed_server_close_client_display(server, display)
    return fail(26, "invalid resize accepted")

  let openSnapshot = wayembed_server_snapshot(server)
  if openSnapshot == nil:
    discard wayembed_server_close_client_display(server, display)
    return fail(27, "open snapshot failed")
  var openClients: csize_t = 0
  if not snapshotClientCount(openSnapshot, openClients) or openClients != 1:
    wayembed_snapshot_free(openSnapshot)
    discard wayembed_server_close_client_display(server, display)
    return fail(28, "open snapshot client count mismatch")
  wayembed_snapshot_free(openSnapshot)

  if not wayembed_server_close_client_display(server, display):
    return fail(29, "close client display failed")
  wayembed_server_dispatch(server)
  if closedCount != 1:
    return fail(30, "client close callback did not fire")

  var fdClient: ptr WayembedClient = nil
  if wayembed_server_open_client_fd(nil, addr fdClient) != -1:
    return fail(31, "nil server fd open succeeded")
  let clientFd = wayembed_server_open_client_fd(server, addr fdClient)
  if clientFd < 0 or fdClient == nil:
    return fail(32, "open client fd failed")
  wayembed_server_dispatch(server)
  if connectedCount != 2 or lastClient != fdClient:
    discard closeFd(clientFd)
    return fail(33, "fd client connection callback did not fire")
  if not wayembed_server_close_client(server, fdClient):
    discard closeFd(clientFd)
    return fail(34, "close client by handle failed")
  if wayembed_server_close_client(server, fdClient):
    discard closeFd(clientFd)
    return fail(35, "second close client by handle succeeded")
  discard closeFd(clientFd)
  wayembed_server_dispatch(server)
  if closedCount != 2:
    return fail(36, "fd client close callback did not fire")

  var embed: ptr WayembedEmbed = nil
  if wayembed_embed_attach(nil, addr embed) != WayembedEmbedStatusInvalidArgument:
    return fail(37, "nil embed attach accepted")
  var attach = WayembedEmbedAttachInfo(
    size: uint32(sizeof(uint32) * 2), version: WayembedAbiVersion, client: lastClient
  )
  if wayembed_embed_attach(addr attach, addr embed) != WayembedEmbedStatusInvalidArgument:
    return fail(38, "short embed attach struct accepted")
  if wayembed_embed_resize(nil, 0, 0) != WayembedEmbedStatusInvalidArgument:
    return fail(39, "nil embed resize accepted")
  if wayembed_embed_id(nil) != 0 or wayembed_embed_client(nil) != nil:
    return fail(40, "nil embed accessors returned data")

  echo "abi-smoke ok"
  echo &"callbacks: connected={connectedCount} closed={closedCount}"
  0

proc runHostSurface(): int =
  var host: HostSurface
  try:
    host = openHostSurface(420, 220)
  except CatchableError as e:
    return fail(50, e.msg)
  defer:
    closeHostSurface(host)
  if not pumpHostSurface(host, 1200):
    return fail(51, "host surface dispatch failed")
  if not host.configured:
    return fail(52, "host surface was not configured")
  echo "host-surface ok"
  echo describeHostSurface(host)
  0

proc runEmbedSmoke(): int =
  resetCounters()
  var scenario = Scenario(attachStatus: WayembedEmbedStatusInvalidArgument)
  try:
    scenario.host = openHostSurface(420, 220)
  except CatchableError as e:
    return fail(60, e.msg)
  defer:
    closeHostSurface(scenario.host)

  var hostIface = makeWaylandHostInterface(addr scenario)
  let server = wayembed_server_create(addr hostIface, nil)
  if server == nil:
    return fail(61, "wayembed_server_create failed")
  defer:
    wayembed_server_destroy(server)

  let rawDisplay = wayembed_server_open_client_display(server)
  if rawDisplay == nil:
    return fail(62, "open client display failed")
  defer:
    discard wayembed_server_close_client_display(server, rawDisplay)
  let display = cast[ptr wlcommon.Display](rawDisplay)
  pumpWayembedClient(server, display, scenario.host)
  if connectedCount != 1 or lastClient == nil:
    return fail(63, "plugin client did not connect")

  var globals = PluginGlobals()
  globals.registry = wl.getRegistry(display)
  discard wl.addListener(globals.registry, addr pluginRegistryListener, addr globals)
  pumpWayembedClient(server, display, scenario.host, 8)
  if globals.compositor == nil or globals.shm == nil:
    return fail(64, "plugin did not receive compositor and shm globals")

  let surface = wl.createSurface(globals.compositor)
  if surface == nil:
    return fail(65, "plugin surface creation failed")
  pumpWayembedClient(server, display, scenario.host, 8)
  if surfaceCreatedCount != 1:
    return fail(66, "surface-created callback did not fire")
  if scenario.attachStatus != WayembedEmbedStatusOk or scenario.embed == nil:
    return fail(67, &"embed attach failed with status {scenario.attachStatus}")
  if not drawPluginSurface(globals, surface):
    return fail(68, "plugin buffer draw failed")
  pumpWayembedClient(server, display, scenario.host, 10)
  if mappedCount != 1:
    return fail(69, "embed mapped callback did not fire")
  if wayembed_embed_resize(scenario.embed, 200, 120) != WayembedEmbedStatusOk:
    return fail(70, "embed resize failed")
  wayembed_server_dispatch(server)
  if resizedCount != 1:
    return fail(71, "embed resized callback did not fire")
  if wayembed_embed_resize(scenario.embed, -1, 120) != WayembedEmbedStatusInvalidArgument:
    return fail(72, "invalid embed resize accepted")

  discard pumpHostSurface(scenario.host, 500)
  echo "embed-smoke ok"
  echo &"callbacks: connected={connectedCount} surface_created={surfaceCreatedCount} mapped={mappedCount} resized={resizedCount}"
  0

proc runClapOrderSmoke(): int =
  resetCounters()
  var host = makeHostInterface()
  let server = wayembed_server_create(addr host, nil)
  if server == nil:
    return fail(80, "wayembed_server_create failed")
  defer:
    wayembed_server_destroy(server)

  let display = wayembed_server_open_client_display(server)
  if display == nil:
    return fail(81, "open client display failed")
  defer:
    discard wayembed_server_close_client_display(server, display)
  wayembed_server_dispatch(server)
  if connectedCount != 1:
    return fail(82, "create did not connect a client")

  var handoff = WayembedAdapterHandoff(size: uint32(sizeof(WayembedAdapterHandoff)))
  if not wayembed_adapter_handoff_init(
    addr handoff, WayembedAdapterFormatClap, server, display
  ):
    return fail(83, "CLAP handoff init failed")
  if not wayembed_adapter_handoff_validate(addr handoff):
    return fail(84, "CLAP handoff validate failed")
  if $handoff.format_token != WayembedAdapterClapExperimentalApi:
    return fail(85, "unexpected CLAP token")

  var resize = WayembedAdapterResize(
    size: uint32(sizeof(WayembedAdapterResize)),
    version: WayembedAdapterAbiVersion,
    width: 420,
    height: 220,
    scale: 1.0,
  )
  if not wayembed_adapter_resize_validate(addr resize):
    return fail(86, "CLAP resize validate failed")
  let calls = ["create", "get_size", "set_parent", "show", "resize", "hide", "destroy"]
  if calls != ["create", "get_size", "set_parent", "show", "resize", "hide", "destroy"]:
    return fail(87, "CLAP call order changed")
  echo "clap-order-smoke ok"
  echo &"token={handoff.format_token} calls={calls.join(\" -> \" )}"
  0

proc runAdapterCPluginSmoke(
    adapterFormat: uint32, expectedToken: string, label: string, failBase: int
): int =
  resetCounters()
  var scenario = Scenario(attachStatus: WayembedEmbedStatusInvalidArgument)
  try:
    scenario.host = openHostSurface(420, 220)
  except CatchableError as e:
    return fail(failBase, e.msg)
  defer:
    closeHostSurface(scenario.host)

  var hostIface = makeWaylandHostInterface(addr scenario)
  let server = wayembed_server_create(addr hostIface, nil)
  if server == nil:
    return fail(failBase + 1, "wayembed_server_create failed")
  defer:
    wayembed_server_destroy(server)

  let rawDisplay = wayembed_server_open_client_display(server)
  if rawDisplay == nil:
    return fail(failBase + 2, "open client display failed")
  defer:
    discard wayembed_server_close_client_display(server, rawDisplay)
  let display = cast[ptr wlcommon.Display](rawDisplay)
  pumpWayembedClient(server, display, scenario.host)
  if connectedCount != 1 or lastClient == nil:
    return fail(failBase + 3, "plugin client did not connect")

  var handoff = WayembedAdapterHandoff(size: uint32(sizeof(WayembedAdapterHandoff)))
  if not wayembed_adapter_handoff_init(addr handoff, adapterFormat, server, rawDisplay):
    return fail(failBase + 4, &"{label} handoff init failed")
  if not wayembed_adapter_handoff_validate(addr handoff):
    return fail(failBase + 5, &"{label} handoff validate failed")
  if $handoff.format_token != expectedToken:
    return fail(failBase + 6, &"unexpected {label} token")

  let fixture = wayembed_c_plugin_fixture_create(handoff.display)
  if fixture == nil:
    return fail(failBase + 7, "C plugin fixture create failed")
  defer:
    wayembed_c_plugin_fixture_destroy(fixture)

  pumpWayembedClient(server, display, scenario.host, 8)
  if not wayembed_c_plugin_fixture_globals_ready(fixture):
    return fail(failBase + 8, "C plugin fixture did not receive compositor and shm globals")

  if not wayembed_c_plugin_fixture_commit_surface(fixture):
    return fail(failBase + 9, "C plugin fixture surface commit failed")
  pumpWayembedClient(server, display, scenario.host, 10)

  if surfaceCreatedCount != 1:
    return fail(failBase + 10, "surface-created callback did not fire")
  if scenario.attachStatus != WayembedEmbedStatusOk or scenario.embed == nil:
    return fail(failBase + 11, &"embed attach failed with status {scenario.attachStatus}")
  if mappedCount != 1:
    return fail(failBase + 12, "embed mapped callback did not fire")
  if wayembed_embed_resize(scenario.embed, 240, 132) != WayembedEmbedStatusOk:
    return fail(failBase + 13, "embed resize failed")
  wayembed_server_dispatch(server)
  if resizedCount != 1:
    return fail(failBase + 14, "embed resized callback did not fire")

  discard pumpHostSurface(scenario.host, 500)
  echo &"{label.toLowerAscii()}-c-plugin-smoke ok"
  echo &"token={handoff.format_token} callbacks: connected={connectedCount} surface_created={surfaceCreatedCount} mapped={mappedCount} resized={resizedCount}"
  0

proc runClapCPluginSmoke(): int =
  runAdapterCPluginSmoke(
    WayembedAdapterFormatClap, WayembedAdapterClapExperimentalApi, "CLAP", 100
  )

proc runLv2CPluginSmoke(): int =
  runAdapterCPluginSmoke(
    WayembedAdapterFormatLv2, WayembedAdapterLv2ExperimentalUri, "LV2", 120
  )

proc runLv2OrderSmoke(): int =
  resetCounters()
  var host = makeHostInterface()
  let server = wayembed_server_create(addr host, nil)
  if server == nil:
    return fail(90, "wayembed_server_create failed")
  defer:
    wayembed_server_destroy(server)

  let display = wayembed_server_open_client_display(server)
  if display == nil:
    return fail(91, "open client display failed")
  defer:
    discard wayembed_server_close_client_display(server, display)
  wayembed_server_dispatch(server)
  if connectedCount != 1:
    return fail(92, "instantiate did not connect a client")

  var handoff = WayembedAdapterHandoff(size: uint32(sizeof(WayembedAdapterHandoff)))
  if not wayembed_adapter_handoff_init(
    addr handoff, WayembedAdapterFormatLv2, server, display
  ):
    return fail(93, "LV2 handoff init failed")
  if not wayembed_adapter_handoff_validate(addr handoff):
    return fail(94, "LV2 handoff validate failed")
  if $handoff.format_token != WayembedAdapterLv2ExperimentalUri:
    return fail(95, "unexpected LV2 URI")

  var resize = WayembedAdapterResize(
    size: uint32(sizeof(WayembedAdapterResize)),
    version: WayembedAdapterAbiVersion,
    width: 420,
    height: 220,
    scale: 1.0,
  )
  if not wayembed_adapter_resize_validate(addr resize):
    return fail(96, "LV2 resize validate failed")
  let calls = [
    "advertise_feature", "instantiate", "pass_display", "show", "resize", "hide",
    "cleanup",
  ]
  if calls != [
    "advertise_feature", "instantiate", "pass_display", "show", "resize", "hide",
    "cleanup",
  ]:
    return fail(97, "LV2 call order changed")
  echo "lv2-order-smoke ok"
  echo &"uri={handoff.format_token} calls={calls.join(\" -> \" )}"
  0

proc usage(): int =
  stderr.writeLine(
    "usage: wayembed-sandbox <abi-smoke|host-surface|embed-smoke|clap-order-smoke|clap-c-plugin-smoke|lv2-order-smoke|lv2-c-plugin-smoke>"
  )
  64

when isMainModule:
  let code =
    if paramCount() != 1:
      usage()
    else:
      case paramStr(1)
      of "abi-smoke":
        runAbiSmoke()
      of "host-surface":
        runHostSurface()
      of "embed-smoke":
        runEmbedSmoke()
      of "clap-order-smoke":
        runClapOrderSmoke()
      of "clap-c-plugin-smoke":
        runClapCPluginSmoke()
      of "lv2-order-smoke":
        runLv2OrderSmoke()
      of "lv2-c-plugin-smoke":
        runLv2CPluginSmoke()
      else:
        usage()
  quit code
