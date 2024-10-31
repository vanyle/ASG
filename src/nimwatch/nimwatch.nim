
import types
export types
import asyncdispatch

when defined(windows):
  import winnotify
elif defined(unix):
  import inotify

proc newWatcher*(target: string): Watcher =
  new result
  result.target = target
  result.callbacks = @[]
  result.init()

proc register*(watcher: Watcher, cb: proc (action: FileAction)) =
  watcher.callbacks.add(cb)

proc watch*(watcher: Watcher) {.async.} =
  while true:
    var fut = await watcher.read()
    for action in fut:
      for i in 0..<watcher.callbacks.len:
        watcher.callbacks[i](action)


when isMainModule:
  let watcher = newWatcher("./testdir")
  watcher.register do (action: FileAction):
    echo action
  discard watcher.watch()
  runForever()
