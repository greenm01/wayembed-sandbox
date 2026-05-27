import std/os
from posix import EINTR, POLLERR, POLLHUP, POLLIN, POLLNVAL, TPollfd, Tnfds, errno, poll

type PollResult* = object
  ready*: bool
  interrupted*: bool
  failed*: bool
  errorCode*: OSErrorCode

proc waitForFd*(fd: cint, timeoutMs: int): PollResult =
  if fd < 0:
    result.failed = true
    return

  var item = TPollfd(fd: fd, events: POLLIN, revents: 0)
  let ready = poll(addr item, Tnfds(1), cint(timeoutMs))
  if ready < 0:
    if errno == EINTR:
      result.interrupted = true
      return
    result.failed = true
    result.errorCode = OSErrorCode(errno)
    return

  result.ready = (item.revents and (POLLIN or POLLERR or POLLHUP or POLLNVAL)) != 0
