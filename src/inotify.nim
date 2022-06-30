
import posix
import types
import asyncdispatch

{.pragma: importinotify, cdecl, importc, header: "sys/inotify.h".}

const IN_MODIFY* = 0x00000002
const IN_ATTRIB* = 0x00000004
const IN_MOVED_FROM* = 0x00000040
const IN_MOVED_TO* = 0x00000080
const IN_CREATE* = 0x00000100
const IN_DELETE* = 0x00000200

const DefaultEvents* = IN_MODIFY or IN_MOVED_FROM or IN_MOVED_TO or IN_CREATE or IN_DELETE

type
  FileNameArray* = cstring
  InotifyEvent* = object
    wd*: WD
    mask*: uint32
    cookie*: uint32
    len*: uint32
    name*: cstring

let EventSize* = sizeof(InotifyEvent) - sizeof(cstring)
let BufLen* = 1024 * (EventSize + 16)

proc inotify_init*(): FD {.importinotify.}
proc inotify_add_watch*(fd: FD, target: cstring, events: cint): WD {.importinotify.}
proc inotify_rm_watch*(fd: FD, wd: WD) {.importinotify.}

proc readEvents*(fd: FD): Future[seq[FileAction]] =
  var retFuture = newFuture[seq[FileAction]]("inotify.readEvents")
  var readBuffer = newString(BufLen)
  
  proc cb(fd: AsyncFD): bool =
    result = true
    let length = read(fd, addr readBuffer[0], BufLen)

    if length < 0:
      result = false
    else:
      var actions = newSeq[FileAction]()
      var i = 0
      while i < length:
        var action: FileAction
        let event = cast[ptr InotifyEvent](addr readBuffer[i])
        if (event[].mask and IN_MODIFY) != 0:
          action.kind = actionModify
        elif (event[].mask and IN_MOVED_FROM) != 0:
          action.kind = actionMoveFrom
        elif (event[].mask and IN_MOVED_TO) != 0:
          action.kind = actionMoveTo
        elif (event[].mask and IN_DELETE) != 0:
          action.kind = actionDelete
        elif (event[].mask and IN_CREATE) != 0:
          action.kind = actionCreate
        else:
          return false
        var buf = alloc0(event.len)
        copyMem(buf, event[].name.addr, event.len)
        action.filename = $cast[cstring](buf)
        dealloc(buf)
        actions.add(action)
        i += EventSize + event[].len.int

      retFuture.complete(actions)

  addRead(fd, cb)
  return retFuture

#
# Watcher
#

proc init*(watcher: Watcher) =
  let fd = inotify_init()
  watcher.fd = fd
  watcher.wd = inotify_add_watch(fd, watcher.target, DefaultEvents)
  register(fd)

proc read*(watcher: Watcher): Future[seq[FileAction]] =
  return readEvents(watcher.fd)

proc close*(watcher: Watcher) =
  inotify_rm_watch(watcher.fd, watcher.wd)
  discard close(watcher.fd)
