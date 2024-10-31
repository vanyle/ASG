version       = "0.1.0"
author        = "vanyle"
description   = "An awesome static site generator"
license       = "MIT"

srcDir = "src"
bin = @["asg"]

requires "markdown"
requires "ws"
requires "fsnotify"
requires "chronos"
requires "weave"