
import types
import asyncdispatch

const FILE_ACTION_ADDED* = 0x00000001
const FILE_ACTION_REMOVED* = 0x00000002
const FILE_ACTION_MODIFIED* = 0x00000003
const FILE_ACTION_RENAMED_OLD_NAME* = 0x00000004
const FILE_ACTION_RENAMED_NEW_NAME* = 0x00000005

# Manually define windows types
type
    OVERLAPPED* {.importc: "OVERLAPPED", header: "winbase.h".} = object
    SECURITY_ATTRIBUTES* {.importc: "SECURITY_ATTRIBUTES",
            header: "winbase.h".} = object

    LPCWSTR* = ptr uint16
    DWORD* = culong #  typedef unsigned long DWORD, *PDWORD, *LPDWORD; according to microsoft docs.
    WINBOOL* = int32
    WORD* = int16
    # HANDLE* = pointer
    LPVOID* = pointer
    LPDWORD* = ptr DWORD
    LPCSTR* = cstring
    LPOVERLAPPED* = ptr OVERLAPPED
    LPSECURITY_ATTRIBUTES* = ptr SECURITY_ATTRIBUTES
    LPOVERLAPPED_COMPLETION_ROUTINE* = proc (para1: DWORD, para2: DWORD,para3: LPOVERLAPPED){.stdcall.}

const
    FILE_NOTIFY_CHANGE_FILE_NAME* = 1
    FILE_NOTIFY_CHANGE_DIR_NAME* = 2
    FILE_NOTIFY_CHANGE_ATTRIBUTES* = 4
    FILE_NOTIFY_CHANGE_SIZE* = 8
    FILE_NOTIFY_CHANGE_LAST_WRITE* = 16
    FILE_NOTIFY_CHANGE_SECURITY* = 256
    INVALID_HANDLE_VALUE* = cast[HANDLE](-1)
    FILE_LIST_DIRECTORY* = 0x00000001 # directory
    FILE_SHARE_DELETE* = 4
    FILE_SHARE_READ* = 1
    FILE_SHARE_WRITE* = 2
    CREATE_NEW* = 1
    CREATE_ALWAYS* = 2
    OPEN_EXISTING* = 3
    OPEN_ALWAYS* = 4
    FILE_FLAG_OVERLAPPED* = 1073741824
    FILE_FLAG_BACKUP_SEMANTICS* = 33554432
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

proc CreateFile*(lpFileName: LPCSTR, dwDesiredAccess: DWORD,
                                    dwShareMode: DWORD,
                                    lpSecurityAttributes: LPSECURITY_ATTRIBUTES,
                                    dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD,
                                    hTemplateFile: HANDLE): HANDLE{.stdcall, dynlib: "kernel32",
        importc: "CreateFileA".}

proc CloseHandle*(hObject: HANDLE): WINBOOL{.stdcall, dynlib: "kernel32",
        importc: "CloseHandle".}

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

proc readEvents*(watcher: Watcher, buflen: int): seq[FileAction] =

    let bufsize = sizeof(FILE_NOTIFY_INFORMATION) * buflen
    var buffer = alloc0(bufsize)

    let filter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
            FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE

    var bytesReturned: DWORD

    discard ReadDirectoryChangesW(
        watcher.fd,
        cast[LPVOID](buffer),
        bufsize,
        true, # watch sub stree
        filter,
        bytesReturned.addr,
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
            var filename = newWideCString("", lenBytes.int div 2) # lenBytes and null character
            copyMem(filename[0].addr, pData[].Filename[0].addr, lenBytes)
            filename[lenBytes.int] = 0.Utf16Char # set the null char
            action.filename = $filename
        ret.add(action)
        let offset = pData[].NextEntryOffset
        if offset == 0:
            break

        pData = cast[ptr FILE_NOTIFY_INFORMATION](cast[uint64](pData) + offset.uint64)

    dealloc(buffer)
    return ret

#
# Watcher
#

proc readEventsWrapper*(watcher: Watcher, evt: AsyncEvent, buflen: int): seq[FileAction] =
    var res = readEvents(watcher, buflen)
    evt.trigger()
    return res

proc readSync*(watcher: Watcher, buflen: int = 10): seq[FileAction] =
    return readEvents(watcher, buflen)

proc init*(watcher: Watcher) =
    # This is a windows handle, but for uniformity, we pretend its an AsyncFD (=distinct int)
    watcher.fd = CreateFile(
        cast[LPCSTR](watcher.target.cstring),
        FILE_LIST_DIRECTORY,
        FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
        cast[LPSECURITY_ATTRIBUTES](nil),
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
        cast[HANDLE](nil)
    )
    if watcher.fd == INVALID_HANDLE_VALUE:
        raise newException(OSError, "not existing file or directory: " &
                watcher.target)

proc close*(watcher: Watcher) =
    discard CloseHandle(watcher.fd)

{.pop.}
