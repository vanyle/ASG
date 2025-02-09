import types, locks
export types

when defined(windows):
    import winnotify
elif defined(linux):
    import inotify
elif defined(macosx):
    import darwinnotify
else:
    import nonotify

var watcherPool: seq[Watcher] = @[]
var threads: seq[Thread[int]] = @[]
var watcherPoolLock: Lock
initLock(watcherPoolLock)

proc watchDirThread(watcherId: int) =
    while true:
        var watcher: Watcher = nil
        {.gcsafe.}:
            withLock watcherPoolLock:
                watcher = watcherPool[watcherId]
            if watcher == nil:
                break
            if watcher.stopChan == nil:
                break
            var shouldStop = watcher.stopChan[].tryRecv()
            if shouldStop.dataAvailable:
                break
            var events = watcher.readSync()
            if events.len > 0:
                watcher.callback(events[0])

    {.gcsafe.}:
        withLock watcherPoolLock:
            let watcher = watcherPool[watcherId]
            deallocShared(watcher.stopChan)
            watcher.close()
            watcher.stopChan = nil

proc forceStop*(watcher: Watcher) =
    if watcher.stopChan != nil:
        watcher.stopChan[].send(true)
    watcherPool[watcher.poolIdx] = nil

proc newWatcher*(path: string, cb: proc (
        action: FileAction) {.gcsafe.}): Watcher =
    ## Create a new `Watcher` object that notifies you when changes occur inside `path` by calling `cb`.
    ## Be careful, `cb` will be called from another thread so be mindful of how memory is shared between `cb` and the rest of your program.
    ## The watcher can be stopped using `forceStop`.
    
    result = initMemoWatcher() # allocate memory
    result.target = path
    result.callback = cb
    result.init()
    result.stopChan[].open()

    var idx = -1
    for i,w in watcherPool.mpairs():
        if w == nil:
            watcherPool[i] = result
            idx = i
            break
    if idx == -1:
        idx = watcherPool.len
        watcherPool.add(result)

    result.poolIdx = idx

    threads.add(Thread[int]())
    createThread(threads[threads.len - 1],watchDirThread, idx)