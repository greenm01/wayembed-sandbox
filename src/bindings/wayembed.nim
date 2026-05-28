{.passC: "-I/home/niltempus/dev/wayembed/include".}
{.passL: "/home/niltempus/dev/wayembed/zig-out/lib/libwayembed.a".}
{.passL: "-lwayland-server".}
{.passL: "-lwayland-client".}

type
  WlCompositor* {.
    importc: "struct wl_compositor", header: "wayembed.h", incompleteStruct
  .} = object
  WlDisplay* {.importc: "struct wl_display", header: "wayembed.h", incompleteStruct.} = object
  WlEventQueue* {.
    importc: "struct wl_event_queue", header: "wayembed.h", incompleteStruct
  .} = object
  WlProxy* {.importc: "struct wl_proxy", header: "wayembed.h", incompleteStruct.} = object
  WlSeat* {.importc: "struct wl_seat", header: "wayembed.h", incompleteStruct.} = object
  WlShm* {.importc: "struct wl_shm", header: "wayembed.h", incompleteStruct.} = object
  WlSubcompositor* {.
    importc: "struct wl_subcompositor", header: "wayembed.h", incompleteStruct
  .} = object
  WlSurface* {.importc: "struct wl_surface", header: "wayembed.h", incompleteStruct.} = object
  WlOutput* {.importc: "struct wl_output", header: "wayembed.h", incompleteStruct.} = object
  XdgWmBase* {.importc: "struct xdg_wm_base", header: "wayembed.h", incompleteStruct.} = object
  ZwpLinuxDmabufV1* {.
    importc: "struct zwp_linux_dmabuf_v1", header: "wayembed.h", incompleteStruct
  .} = object

  WayembedServer* {.importc: "wayembed_server", header: "wayembed.h", incompleteStruct.} = object
  WayembedClient* {.importc: "wayembed_client", header: "wayembed.h", incompleteStruct.} = object
  WayembedEmbed* {.importc: "wayembed_embed", header: "wayembed.h", incompleteStruct.} = object
  WayembedSnapshot* {.
    importc: "wayembed_snapshot", header: "wayembed.h", incompleteStruct
  .} = object

const
  WayembedAbiVersion* = 2'u32

  WayembedFeatureCompositor* = 1'u64 shl 0
  WayembedFeatureSubcompositor* = 1'u64 shl 1
  WayembedFeatureSurface* = 1'u64 shl 2
  WayembedFeatureShmBuffer* = 1'u64 shl 3
  WayembedFeatureEmbedSession* = 1'u64 shl 4
  WayembedFeatureSeat* = 1'u64 shl 5
  WayembedFeaturePointer* = 1'u64 shl 6
  WayembedFeatureKeyboard* = 1'u64 shl 7
  WayembedFeatureTouch* = 1'u64 shl 8
  WayembedFeatureOutput* = 1'u64 shl 9
  WayembedFeatureXdgShell* = 1'u64 shl 10
  WayembedFeatureClientFd* = 1'u64 shl 11

  WayembedEmbedStatusOk* = 0'u32
  WayembedEmbedStatusInvalidArgument* = 1'u32
  WayembedEmbedStatusClientClosing* = 2'u32
  WayembedEmbedStatusAlreadyEmbedded* = 3'u32
  WayembedEmbedStatusUnknownSurface* = 4'u32
  WayembedEmbedStatusSurfaceHasRole* = 5'u32
  WayembedEmbedStatusUnsupported* = 6'u32
  WayembedEmbedStatusUpstreamFailed* = 7'u32
  WayembedEmbedStatusUnknownEmbed* = 8'u32

type
  WayembedOutputInfo* {.importc: "wayembed_output_info", header: "wayembed.h", bycopy.} = object
    size*: uint32
    version*: uint32
    x*: int32
    y*: int32
    physical_width*: int32
    physical_height*: int32
    subpixel*: int32
    make*: cstring
    model*: cstring
    transform*: int32
    mode_flags*: uint32
    mode_width*: int32
    mode_height*: int32
    mode_refresh*: int32
    scale*: int32
    name*: cstring
    description*: cstring

  WayembedSnapshotCounts* {.
    importc: "wayembed_snapshot_counts", header: "wayembed.h", bycopy
  .} = object
    size*: uint32
    version*: uint32
    clients*: csize_t
    resources*: csize_t
    surfaces*: csize_t
    buffers*: csize_t
    embeds*: csize_t
    outputs*: csize_t

  WayembedFeatures* {.importc: "wayembed_features", header: "wayembed.h", bycopy.} = object
    size*: uint32
    version*: uint32
    flags*: uint64

  WayembedEmbedAttachInfo* {.
    importc: "wayembed_embed_attach_info", header: "wayembed.h", bycopy
  .} = object
    size*: uint32
    version*: uint32
    client*: ptr WayembedClient
    parent_surface*: ptr WlSurface
    child_surface*: ptr WlSurface

  GetCompositorCb* = proc(userdata: pointer): ptr WlCompositor {.cdecl.}
  GetSubcompositorCb* = proc(userdata: pointer): ptr WlSubcompositor {.cdecl.}
  GetShmCb* = proc(userdata: pointer): ptr WlShm {.cdecl.}
  GetSeatCb* = proc(userdata: pointer): ptr WlSeat {.cdecl.}
  GetXdgWmBaseCb* = proc(userdata: pointer): ptr XdgWmBase {.cdecl.}
  GetDmabufCb* = proc(userdata: pointer): ptr ZwpLinuxDmabufV1 {.cdecl.}
  GetSubsurfaceOffsetCb* = proc(
    userdata: pointer,
    x: ptr int32,
    y: ptr int32,
    display: ptr WlDisplay,
    parent: ptr WlSurface,
    child: ptr WlSurface,
  ): bool {.cdecl.}
  ClientCallback* = proc(userdata: pointer, client: ptr WayembedClient) {.cdecl.}
  SurfaceCreatedCallback* = proc(
    userdata: pointer, client: ptr WayembedClient, plugin_child_surface: ptr WlSurface
  ) {.cdecl.}
  ProtocolErrorCallback* =
    proc(userdata: pointer, client: ptr WayembedClient, code: uint32) {.cdecl.}
  EmbedCallback* = proc(userdata: pointer, embed: ptr WayembedEmbed) {.cdecl.}
  EmbedResizedCallback* = proc(
    userdata: pointer, embed: ptr WayembedEmbed, width: int32, height: int32
  ) {.cdecl.}
  GetSeatCapabilitiesCb* = proc(userdata: pointer): uint32 {.cdecl.}
  GetSeatNameCb* = proc(userdata: pointer): cstring {.cdecl.}
  GetOutputInfoCb* =
    proc(userdata: pointer, info: ptr WayembedOutputInfo): bool {.cdecl.}

  WayembedHostInterface* {.
    importc: "wayembed_host_interface", header: "wayembed.h", bycopy
  .} = object
    size*: uint32
    version*: uint32
    userdata*: pointer
    get_compositor*: GetCompositorCb
    get_subcompositor*: GetSubcompositorCb
    get_shm*: GetShmCb
    get_seat*: GetSeatCb
    get_xdg_wm_base*: GetXdgWmBaseCb
    get_dmabuf*: GetDmabufCb
    get_subsurface_offset*: GetSubsurfaceOffsetCb
    on_client_connected*: ClientCallback
    on_surface_created*: SurfaceCreatedCallback
    on_client_closed*: ClientCallback
    on_protocol_error*: ProtocolErrorCallback
    on_embed_mapped*: EmbedCallback
    on_embed_resized*: EmbedResizedCallback
    on_embed_destroyed*: EmbedCallback
    get_seat_capabilities*: GetSeatCapabilitiesCb
    get_seat_name*: GetSeatNameCb
    get_output_info*: GetOutputInfoCb

proc wayembed_abi_version*(): uint32 {.cdecl, importc, header: "wayembed.h".}
proc wayembed_get_features*(
  features: ptr WayembedFeatures
): bool {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_create*(
  host: ptr WayembedHostInterface, queue: ptr WlEventQueue
): ptr WayembedServer {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_destroy*(
  server: ptr WayembedServer
) {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_get_fd*(
  server: ptr WayembedServer
): cint {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_dispatch*(
  server: ptr WayembedServer
) {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_flush*(
  server: ptr WayembedServer
) {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_snapshot*(
  server: ptr WayembedServer
): ptr WayembedSnapshot {.cdecl, importc, header: "wayembed.h".}

proc wayembed_snapshot_get_counts*(
  snapshot: ptr WayembedSnapshot, counts: ptr WayembedSnapshotCounts
): bool {.cdecl, importc, header: "wayembed.h".}

proc wayembed_snapshot_free*(
  snapshot: ptr WayembedSnapshot
) {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_open_client_display*(
  server: ptr WayembedServer
): ptr WlDisplay {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_close_client_display*(
  server: ptr WayembedServer, display: ptr WlDisplay
): bool {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_open_client_fd*(
  server: ptr WayembedServer, out_client: ptr ptr WayembedClient
): cint {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_close_client*(
  server: ptr WayembedServer, client: ptr WayembedClient
): bool {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_create_proxy*(
  server: ptr WayembedServer, client_display: ptr WlDisplay, host_object: ptr WlProxy
): ptr WlProxy {.cdecl, importc, header: "wayembed.h".}

proc wayembed_server_destroy_proxy*(
  server: ptr WayembedServer, proxy: ptr WlProxy
) {.cdecl, importc, header: "wayembed.h".}

proc wayembed_embed_attach*(
  info: ptr WayembedEmbedAttachInfo, out_embed: ptr ptr WayembedEmbed
): uint32 {.cdecl, importc, header: "wayembed.h".}

proc wayembed_embed_adopt_subsurface*(
  info: ptr WayembedEmbedAttachInfo, out_embed: ptr ptr WayembedEmbed
): uint32 {.cdecl, importc, header: "wayembed.h".}

proc wayembed_embed_resize*(
  embed: ptr WayembedEmbed, width: int32, height: int32
): uint32 {.cdecl, importc, header: "wayembed.h".}

proc wayembed_embed_id*(
  embed: ptr WayembedEmbed
): uint32 {.cdecl, importc, header: "wayembed.h".}

proc wayembed_embed_client*(
  embed: ptr WayembedEmbed
): ptr WayembedClient {.cdecl, importc, header: "wayembed.h".}
