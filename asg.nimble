version       = "0.1.0"
author        = "vanyle"
description   = "An awesome static site generator"
license       = "MIT"

let suffix = when defined(linux):
    ""
    elif defined(windows):
    ".exe"
    elif defined(macosx):
    ""
    else:
    ""
var targetOS = when defined(mingw):
        "windows"
    else:
        hostOS

srcDir = "src"
binDir = "build"
bin = @["asg"]
namedBin = {"asg": "asg-" & targetOS & "-" & hostCPU & suffix}.toTable

requires "markdown"
requires "ws"
requires "chronos"
requires "htmlparser"
