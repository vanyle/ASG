import types

#[
    When file watching is not supported on this platform, we use the noNotify backend which
    never notifies of any change.
]#

proc readSync*(watcher: Watcher, buflen: int = 10): seq[FileAction] =
    return @[]

proc init*(watcher: Watcher) =
    discard

proc close*(watcher: Watcher) =
    discard