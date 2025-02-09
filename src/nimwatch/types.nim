import asyncdispatch

type
    FD* = cint
    WD* = cint
    WatcherObject* = object
        poolIdx*: int
        target*: string
        stopChan*: ptr Channel[bool]
        callback*: proc (action: FileAction) {.gcsafe.}
        when defined(windows):
            fd*: AsyncFD
        elif defined(unix):
            fd*: AsyncFD
            wd*: WD
    Watcher* = ref WatcherObject
    FileActionKind* = enum
        actionCreate
        actionDelete
        actionModify
        actionMoveFrom
        actionMoveTo
        actionOther
    FileAction* = object
        kind*: FileActionKind
        filename*: string

proc `=destroy`(x: WatcherObject) =
    if x.stopChan != nil:
        x.stopChan[].send(true)
        deallocShared(x.stopChan)

proc initMemoWatcher*(): Watcher =
    result = Watcher()
    result.stopChan = cast[ptr Channel[bool]](
        allocShared0(sizeof(Channel[bool]))
    )

converter toFD*(fd: AsyncFD): FD = FD(fd)
converter toAsyncFD*(fd: FD): AsyncFD = AsyncFD(fd)