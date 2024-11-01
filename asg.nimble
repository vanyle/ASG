version       = "0.1.0"
author        = "vanyle"
description   = "An awesome static site generator"
license       = "MIT"

srcDir = "src"
binDir = "build"
bin = @["asg"]

requires "markdown"
requires "ws"
requires "chronos"
requires "htmlparser"
