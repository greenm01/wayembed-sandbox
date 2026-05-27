import ./wayembed

const
  WayembedAdapterAbiVersion* = 1'u32
  WayembedAdapterClapExperimentalApi* = "wayembed.experimental.clap.wayland"
  WayembedAdapterLv2ExperimentalUri* = "https://wayembed.org/ns/ext/wayland-ui"
  WayembedAdapterFormatUnknown* = 0'u32
  WayembedAdapterFormatClap* = 1'u32
  WayembedAdapterFormatLv2* = 2'u32

type
  WayembedAdapterHandoff* {.
    importc: "wayembed_adapter_handoff", header: "wayembed_adapters.h", bycopy
  .} = object
    size*: uint32
    version*: uint32
    format*: uint32
    server*: ptr WayembedServer
    display*: ptr WlDisplay
    format_token*: cstring
    format_userdata*: pointer

  WayembedAdapterResize* {.
    importc: "wayembed_adapter_resize", header: "wayembed_adapters.h", bycopy
  .} = object
    size*: uint32
    version*: uint32
    width*: int32
    height*: int32
    scale*: cdouble

proc wayembed_adapter_abi_version*(): uint32 {.
  cdecl, importc, header: "wayembed_adapters.h"
.}

proc wayembed_adapter_handoff_init*(
  handoff: ptr WayembedAdapterHandoff,
  format: uint32,
  server: ptr WayembedServer,
  display: ptr WlDisplay,
): bool {.cdecl, importc, header: "wayembed_adapters.h".}

proc wayembed_adapter_handoff_validate*(
  handoff: ptr WayembedAdapterHandoff
): bool {.cdecl, importc, header: "wayembed_adapters.h".}

proc wayembed_adapter_resize_validate*(
  resize: ptr WayembedAdapterResize
): bool {.cdecl, importc, header: "wayembed_adapters.h".}
