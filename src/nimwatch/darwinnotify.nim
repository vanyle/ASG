import types
import strutils

# MacOS implementation for watching file changes
#[
    incompatible function pointer types passing:
        Got:

        'void (ConstFSEventStreamRef, void *, NI, void *, FSEventStreamEventFlags *, FSEventStreamEventId *)'
        void (const struct __FSEventStream *, void *, unsigned long, void *, unsigned int *, unsigned long long *)
        Expected:

        'FSEventStreamCallback _Nonnull'
        void (*)(const struct __FSEventStream * _Nonnull, void * _Nullable, unsigned long, void * _Nonnull, const unsigned int * _Nonnull, const unsigned long long * _Nonnull)
    ]#

{.passL: "-framework Cocoa -framework IOKit -framework CoreVideo".}

type
    ConstFSEventStreamRef {.importc, header: "CoreServices/CoreServices.h".} = pointer
    FSEventStreamEventFlags {.importc, header: "CoreServices/CoreServices.h".} = uint32
    FSEventStreamEventId {.importc, header: "CoreServices/CoreServices.h".} = object
    FSEventStreamCallback = proc(streamRef: ConstFSEventStreamRef, ctx: pointer,
            count: uint, paths: pointer, flags: ptr FSEventStreamEventFlags,
            ids: ptr FSEventStreamEventId) {.cdecl.}

    CFIndex = int64
    CFAllocator = pointer
    FSEventStreamContext {.importc, header: "CoreServices/CoreServices.h".} = object
        version: CFIndex
        info: pointer            # userdata
        retain: pointer          # nullable
        release: pointer         # nullable
        copyDescription: pointer # nullable

    CFTimeInterval = float64
    FSEventStreamCreateFlags = uint32
    CFMutableArrayRef = distinct pointer
    CFArrayRef = CFMutableArrayRef # cast away mutability info in this simplified implementation.
    CFStringRef = distinct pointer
    CFStringEncoding = uint32
    CFRunLoopRef = distinct pointer

    FSEventStreamRef = distinct pointer
    CFRunLoopMode {.importc: "CFRunLoopMode".} = distinct pointer

proc CFArrayCreateMutable(alloc: CFAllocator, capacity: CFIndex,
        callbacks: pointer): CFMutableArrayRef {.importc,
                header: "CoreFoundation/CoreFoundation.h".}

proc CFStringCreateWithCString(alloc: CFAllocator, cStr: cstring,
        encoding: CFStringEncoding): CFStringRef {.importc,
                header: "CoreFoundation/CoreFoundation.h".}

proc CFArrayAppendValue(thearray: CFMutableArrayRef, value: pointer) {.importc,
        header: "CoreFoundation/CoreFoundation.h".}

proc CFRunLoopGetCurrent(): CFRunLoopRef {.importc,
        header: "CoreFoundation/CoreFoundation.h".}

proc CFRunLoopRun() {.importc, header: "CoreFoundation/CoreFoundation.h".}
proc CFRunLoopStop(rl: CFRunLoopRef) {.importc,
        header: "CoreFoundation/CoreFoundation.h".}

#let kFSEventStreamCreateFlagNone {.importc,
#        nodecl.}: FSEventStreamCreateFlags
let kFSEventStreamCreateFlagFileEvents {.importc,
        nodecl.}: FSEventStreamCreateFlags
let kCFStringEncodingUTF8 {.importc, nodecl.}: CFStringEncoding
let kFSEventStreamEventIdSinceNow: FSEventStreamEventId = cast[
        FSEventStreamEventId](0xFFFFFFFFFFFFFFFF)
let kCFRunLoopDefaultMode {.importc, nodecl.}: CFRunLoopMode

let kFSEventStreamEventFlagItemCreated {.importc,
        nodecl.}: FSEventStreamEventFlags
let kFSEventStreamEventFlagItemModified {.importc,
        nodecl.}: FSEventStreamEventFlags
let kFSEventStreamEventFlagItemRenamed {.importc,
        nodecl.}: FSEventStreamEventFlags
let kFSEventStreamEventFlagItemRemoved {.importc,
        nodecl.}: FSEventStreamEventFlags

proc FSEventStreamCreate(
    allocator: CFAllocator,
    callback: ptr FSEventStreamCallback,
    context: ptr FSEventStreamContext,
    pathsToWatch: CFArrayRef,
    sinceWhen: FSEventStreamEventId,
    latency: CFTimeInterval, flags: FSEventStreamCreateFlags
): FSEventStreamRef {.importc, header: "CoreServices/CoreServices.h".}

proc FSEventStreamScheduleWithRunLoop(stream: FSEventStreamRef,
        runLoop: CFRunLoopRef, runLoopMode: CFRunLoopMode) {.importc,
header: "CoreServices/CoreServices.h".}

proc FSEventStreamStart(stream: FSEventStreamRef): bool {.importc,
header: "CoreServices/CoreServices.h".}

proc FSEventStreamStop(stream: FSEventStreamRef) {.importc,
header: "CoreServices/CoreServices.h".}

proc FSEventStreamRelease(stream: FSEventStreamRef) {.importc,
header: "CoreServices/CoreServices.h".}

proc event_callback(streamRef: ConstFSEventStreamRef, ctx: pointer,
            count: uint, paths: pointer, flags: ptr FSEventStreamEventFlags,
            ids: ptr FSEventStreamEventId) {.cdecl.} =

    var typedPaths = cast[ptr UncheckedArray[cstring]](paths)
    var typedEvents = cast[ptr UncheckedArray[FSEventStreamEventFlags]](flags)
    var userData = cast[ptr seq[FileAction]](ctx)


    for i in 0..<count:
        var path: cstring = typedPaths[i]
        var flag: FSEventStreamEventFlags = typedEvents[i]
        var actionKind = FileActionKind.actionOther

        if (flag.uint32 and kFSEventStreamEventFlagItemModified.uint32) != 0:
            actionKind = FileActionKind.actionModify
        if (flag.uint32 and kFSEventStreamEventFlagItemRemoved.uint32) != 0:
            actionKind = FileActionKind.actionDelete
        if (flag.uint32 and kFSEventStreamEventFlagItemCreated.uint32) != 0:
            actionKind = FileActionKind.actionCreate
        if (flag.uint32 and kFSEventStreamEventFlagItemRenamed.uint32) != 0:
            actionKind = FileActionKind.actionMoveTo

        var filename = $path
        # Send the basename for consistency with other platforms.
        var basename = filename.rsplit("/", 1)[1]

        userData[].add(FileAction(
            filename: basename,
            kind: actionKind
        ))

    CFRunLoopStop(CFRunLoopGetCurrent())

var global_callback = event_callback

proc readSync*(watcher: Watcher, buflen: int = 10): seq[FileAction] =
    var flags = kFSEventStreamCreateFlagFileEvents
    var filesModified: seq[FileAction]
    var ctx = FSEventStreamContext(version: 0, info: filesModified.addr)

    var dirToWatch = watcher.target

    var paths = CFArrayCreateMutable(nil, 1, nil);
    var cfs_path = CFStringCreateWithCString(nil, dirToWatch.cstring, kCFStringEncodingUTF8)
    CFArrayAppendValue(paths, cast[pointer](cfs_path));

    # For some dumb reason, the C API is a pointer to a function pointer but in reality,
    # You need to pass a simple function pointer here hence the cast of event_callback.
    var stream = FSEventStreamCreate(
        nil, cast[ptr FSEventStreamCallback](global_callback), ctx.addr, paths,
        kFSEventStreamEventIdSinceNow,
        0.0, flags)
    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(),
                                    kCFRunLoopDefaultMode)
    discard FSEventStreamStart(stream)

    CFRunLoopRun()
    FSEventStreamStop(stream)
    FSEventStreamRelease(stream)
    return filesModified


proc init*(watcher: Watcher) =
    discard

proc close*(watcher: Watcher) =
    discard