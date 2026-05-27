import std/[os, strformat]

import bindings/wayembed
import bindings/wayembed_adapters

var connectedCount = 0
var closedCount = 0
var mappedCount = 0
var resizedCount = 0
var destroyedCount = 0
var lastClient: ptr WayembedClient = nil

proc onClientConnected(userdata: pointer, client: ptr WayembedClient) {.cdecl.} =
  discard userdata
  if client != nil:
    inc connectedCount
    lastClient = client

proc onClientClosed(userdata: pointer, client: ptr WayembedClient) {.cdecl.} =
  discard userdata
  if client != nil:
    inc closedCount

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

proc resetCounters() =
  connectedCount = 0
  closedCount = 0
  mappedCount = 0
  resizedCount = 0
  destroyedCount = 0
  lastClient = nil

proc runAbiSmoke(): int =
  resetCounters()

  if wayembed_abi_version() != WayembedAbiVersion:
    return fail(1, "wayembed ABI version mismatch")
  if wayembed_adapter_abi_version() != WayembedAdapterAbiVersion:
    return fail(2, "wayembed adapter ABI version mismatch")

  var features = WayembedFeatures(
    size: uint32(sizeof(WayembedFeatures)), version: WayembedAbiVersion, flags: 0
  )
  if not wayembed_get_features(addr features):
    return fail(3, "wayembed_get_features failed")
  if (features.flags and expectedFeatureMask()) != expectedFeatureMask():
    return fail(4, &"missing feature flags: {features.flags}")

  var host = makeHostInterface()
  let server = wayembed_server_create(addr host, nil)
  if server == nil:
    return fail(5, "wayembed_server_create returned nil")
  defer:
    wayembed_server_destroy(server)

  if wayembed_server_get_fd(server) < 0:
    return fail(6, "server fd is invalid")

  let emptySnapshot = wayembed_server_snapshot(server)
  if emptySnapshot == nil:
    return fail(7, "empty snapshot failed")
  var emptyCounts = WayembedSnapshotCounts(
    size: uint32(sizeof(WayembedSnapshotCounts)), version: WayembedAbiVersion
  )
  if not wayembed_snapshot_get_counts(emptySnapshot, addr emptyCounts):
    wayembed_snapshot_free(emptySnapshot)
    return fail(8, "snapshot counts failed")
  wayembed_snapshot_free(emptySnapshot)
  if emptyCounts.clients != 0:
    return fail(9, "new server unexpectedly has clients")

  let display = wayembed_server_open_client_display(server)
  if display == nil:
    return fail(10, "open client display failed")

  wayembed_server_dispatch(server)
  if connectedCount != 1 or lastClient == nil:
    discard wayembed_server_close_client_display(server, display)
    return fail(11, "client connection callback did not fire")

  var handoff = WayembedAdapterHandoff(size: uint32(sizeof(WayembedAdapterHandoff)))
  if not wayembed_adapter_handoff_init(
    addr handoff, WayembedAdapterFormatClap, server, display
  ):
    discard wayembed_server_close_client_display(server, display)
    return fail(12, "adapter handoff init failed")
  if not wayembed_adapter_handoff_validate(addr handoff):
    discard wayembed_server_close_client_display(server, display)
    return fail(13, "adapter handoff validate failed")
  if $handoff.format_token != WayembedAdapterClapExperimentalApi:
    discard wayembed_server_close_client_display(server, display)
    return fail(14, "unexpected CLAP adapter token")

  var resize = WayembedAdapterResize(
    size: uint32(sizeof(WayembedAdapterResize)),
    version: WayembedAdapterAbiVersion,
    width: 640,
    height: 480,
    scale: 1.0,
  )
  if not wayembed_adapter_resize_validate(addr resize):
    discard wayembed_server_close_client_display(server, display)
    return fail(15, "valid resize rejected")
  resize.width = -1
  if wayembed_adapter_resize_validate(addr resize):
    discard wayembed_server_close_client_display(server, display)
    return fail(16, "invalid resize accepted")

  if not wayembed_server_close_client_display(server, display):
    return fail(17, "close client display failed")
  wayembed_server_dispatch(server)
  if closedCount != 1:
    return fail(18, "client close callback did not fire")

  echo "abi-smoke ok"
  echo &"callbacks: connected={connectedCount} closed={closedCount}"
  0

proc pending(name: string): int =
  stderr.writeLine(&"{name} is not implemented yet")
  stderr.writeLine("next step: add the visible Wayland host surface and plugin fixture")
  64

proc usage(): int =
  stderr.writeLine(
    "usage: wayembed-sandbox <abi-smoke|host-surface|embed-smoke|clap-order-smoke>"
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
        pending("host-surface")
      of "embed-smoke":
        pending("embed-smoke")
      of "clap-order-smoke":
        pending("clap-order-smoke")
      else:
        usage()
  quit code
