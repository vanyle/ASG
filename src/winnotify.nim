
import oldwinapi/windows
import threadpool
import types
import asyncdispatch

const FILE_ACTION_ADDED* = 0x00000001
const FILE_ACTION_REMOVED* = 0x00000002
const FILE_ACTION_MODIFIED* = 0x00000003
const FILE_ACTION_RENAMED_OLD_NAME* = 0x00000004
const FILE_ACTION_RENAMED_NEW_NAME* = 0x00000005

{.push boundChecks: off.}

type
  FileNameArray* = array[0..0, Utf16Char]
  FILE_NOTIFY_INFORMATION* {.packed.} = object
    NextEntryOffset*: DWORD
    Action*: DWORD
    FileNameLength*: DWORD
    FileName*: FileNameArray

converter toWINBOOL*(b: bool): WINBOOL = cast[WINBOOL](b)
converter toBool*(b: WINBOOL): bool = cast[bool](b)
converter toDWORD*(x: int): DWORD = cast[DWORD](x)

proc ReadDirectoryChangesW*(
  hDirectory: HANDLE,
  lpBuffer: LPVOID, 
  nBufferLength: DWORD, 
  bWatchSubtree: WINBOOL,
  dwNotifyFilter: DWORD,
  lpBytesReturned: LPDWORD, 
  lpOverlapped: LPOVERLAPPED, 
  lpCompletionRoutine: LPOVERLAPPED_COMPLETION_ROUTINE,
): WINBOOL {.cdecl, importc, header: "<windows.h>".}

proc readEvents*(watcher: Watcher, evt: AsyncEvent, buflen: int): seq[FileAction] {.thread.} =
  let bufsize = sizeof(FILE_NOTIFY_INFORMATION) * buflen
  var buffer = alloc0(bufsize)

  let filter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE
  var bytesReturned: DWORD

  discard ReadDirectoryChangesW(
    HANDLE(watcher.fd),
    cast[LPVOID](buffer),
    bufsize,
    true, # watch sub stree
    filter,
    cast[LPDWORD](bytesReturned.addr),
    cast[LPOVERLAPPED](nil),
    cast[LPOVERLAPPED_COMPLETION_ROUTINE](nil))

  var pData = cast[ptr FILE_NOTIFY_INFORMATION](buffer)
  var ret: seq[FileAction]

  while true:
    var action: FileAction
    case pData[].Action
    of FILE_ACTION_ADDED:
      action.kind = actionCreate
    of FILE_ACTION_REMOVED:
      action.kind = actionDelete
    of FILE_ACTION_MODIFIED:
      action.kind = actionModify
    of FILE_ACTION_RENAMED_OLD_NAME:
      action.kind = actionMoveFrom
    of FILE_ACTION_RENAMED_NEW_NAME:
      action.kind = actionMoveTo
    else:
      discard

    let lenBytes = pData.FileNameLength
    if lenBytes > 0:
      var filename = newWideCString("", lenBytes div 2) # lenBytes and null character
      copyMem(filename[0].addr,pData[].Filename[0].addr, lenBytes)
      filename[lenBytes] = 0.Utf16Char # set the null char
      action.filename = $filename
    ret.add(action)
    if pData[].NextEntryOffset == 0:
      break
    pData = cast[ptr FILE_NOTIFY_INFORMATION](cast[uint64](pData) + pData[].NextEntryOffset.uint64)
  dealloc buffer
  evt.trigger()
  return ret

#
# Watcher
#

proc init*(watcher: Watcher) =
  watcher.fd = AsyncFD(CreateFile(
    cast[LPCSTR](watcher.target.cstring), 
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, 
    cast[LPSECURITY_ATTRIBUTES](nil),
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
    cast[HANDLE](nil)
  ))
  if HANDLE(watcher.fd) == INVALID_HANDLE_VALUE:
    raise newException(OSError, "not existing file or directory: " & watcher.target)
  register(watcher.fd)

proc read*(watcher: Watcher): Future[seq[FileAction]] =
  var f: Future[seq[FileAction]] = newFuture[seq[FileAction]]("watcher.read")
  let evt = newAsyncEvent()
  let r = spawn readEvents(watcher,evt,10) # we only pass evt to another thread.
  proc cb(fd: AsyncFD): bool = 
    let v = ^r
    f.complete(v) # this should be called inside the main thread so everything stays safe!
  addEvent(evt, cb)
  return f

proc close*(watcher: Watcher) =
  discard CloseHandle(HANDLE(watcher.fd))

{.pop.}