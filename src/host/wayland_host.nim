type HostSurface* = object
  width*: int32
  height*: int32

proc openHostSurface*(width, height: int32): HostSurface =
  ## Placeholder for the next milestone.
  HostSurface(width: width, height: height)
