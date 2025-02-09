import types
import asyncdispatch

# Import windows things:

const
  FILE_ACTION_ADDED = 0x00000001
  FILE_ACTION_REMOVED = 0x00000002
  FILE_ACTION_MODIFIED = 0x00000003
  FILE_ACTION_RENAMED_OLD_NAME = 0x00000004
  FILE_ACTION_RENAMED_NEW_NAME = 0x00000005

  FILE_NOTIFY_CHANGE_FILE_NAME = 1
  FILE_NOTIFY_CHANGE_DIR_NAME = 2
  FILE_NOTIFY_CHANGE_ATTRIBUTES = 4
  FILE_NOTIFY_CHANGE_SIZE = 8
  FILE_NOTIFY_CHANGE_LAST_WRITE = 16
  #FILE_NOTIFY_CHANGE_SECURITY = 256

  FILE_LIST_DIRECTORY = 0x00000001
  FILE_SHARE_DELETE = 4
  FILE_SHARE_READ = 1
  FILE_SHARE_WRITE = 2

  #CREATE_ALWAYS = 2
  OPEN_EXISTING = 3
  #OPEN_ALWAYS = 4

  FILE_FLAG_BACKUP_SEMANTICS = 33554432
  FILE_FLAG_OVERLAPPED = 1073741824

  INVALID_HANDLE_VALUE = -1

{.push boundChecks: off.}

type
  DWORD = int32
  WINBOOL = int32

  HANDLE = pointer
  LPCSTR = cstring
  LPVOID = pointer
  LPDWORD = ptr DWORD

  OVERLAPPED {.final, pure.} = object
    Internal: DWORD
    InternalHigh: DWORD
    Offset: DWORD
    OffsetHigh: DWORD
    hEvent: HANDLE

  LPOVERLAPPED = ptr OVERLAPPED
  LPOVERLAPPED_COMPLETION_ROUTINE = proc (para1: DWORD, para2: DWORD,
      para3: LPOVERLAPPED){.stdcall.}

  SECURITY_ATTRIBUTES {.final, pure.} = object
    nLength: DWORD
    lpSecurityDescriptor: LPVOID
    bInheritHandle: WINBOOL

  LPSECURITY_ATTRIBUTES = ptr SECURITY_ATTRIBUTES


proc CreateFile*(lpFileName: LPCSTR, dwDesiredAccess: DWORD,
                   dwShareMode: DWORD,
                   lpSecurityAttributes: LPSECURITY_ATTRIBUTES,
                   dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD,
                   hTemplateFile: HANDLE): HANDLE{.stdcall, dynlib: "kernel32",
      importc: "CreateFileA".}

proc CloseHandle*(hObject: HANDLE): WINBOOL{.stdcall, dynlib: "kernel32",
    importc: "CloseHandle".}

# --------------------------------

type
  FileNameArray* = array[0..0, Utf16Char]
  FILE_NOTIFY_INFORMATION* {.packed.} = object
    NextEntryOffset*: DWORD
    Action*: DWORD
    FileNameLength*: DWORD
    FileName*: FileNameArray

converter toWINBOOL(b: bool): WINBOOL = cast[WINBOOL](b)
converter toBool(b: WINBOOL): bool = cast[bool](b)
converter toDWORD(x: int): DWORD = cast[DWORD](x)

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

proc readSync*(watcher: Watcher, buflen: int = 10): seq[FileAction] =
  # Block the thread until changes occur.
  let bufsize = sizeof(FILE_NOTIFY_INFORMATION) * buflen
  var buffer = alloc0(bufsize)

  let filter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_ATTRIBUTES or
      FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE
  var bytesReturned: DWORD

  discard ReadDirectoryChangesW(
    cast[HANDLE](watcher.fd),
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
      copyMem(filename[0].addr, pData[].Filename[0].addr, lenBytes)
      filename[lenBytes] = 0.Utf16Char # set the null char
      action.filename = $filename
    ret.add(action)
    if pData[].NextEntryOffset == 0:
      break
    pData = cast[ptr FILE_NOTIFY_INFORMATION](cast[uint64](pData) + pData[].NextEntryOffset.uint64)
  dealloc buffer

  return ret


proc readEvents*(watcher: Watcher, evt: AsyncEvent, buflen: int): seq[FileAction] =
  var ret = readSync(watcher, buflen)
  evt.trigger()
  return ret

#
# Watcher
#

proc init*(watcher: Watcher) =
  watcher.fd = cast[AsyncFD](CreateFile(
    cast[LPCSTR](watcher.target.cstring),
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    cast[LPSECURITY_ATTRIBUTES](nil),
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
    cast[HANDLE](nil)
  ))
  if cast[int](watcher.fd) == INVALID_HANDLE_VALUE:
    raise newException(OSError, "not existing file or directory: " & watcher.target)
  register(watcher.fd)


proc close*(watcher: Watcher) =
  discard CloseHandle(cast[HANDLE](watcher.fd))

{.pop.}