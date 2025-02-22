import std/[tables, asynchttpserver, asyncdispatch, strutils, sequtils, os, times]
import nimLUA
import ws
import nimwatch/nimwatch
import asgtypes
import compilefile
import parseposts

let parameters = commandLineParams()
if parameters.len != 2:
    echo "Usage: asg <input_directory> <output_directory>"
    echo "Read the README.md for more info!"
    quit()

let input_dir = parameters[0]
let output_dir = parameters[1]

proc shouldFileNotBeCompiled(basePath: string): bool = 
    if basePath.startswith("data/") or basePath.startswith("/data/"):
        return true
    return false

proc read_data*(filename: string): string =
    let path = joinPath(input_dir, "data", filename)
    if fileExists(path):
        return readFile(path)
    return ""

proc read_csv*(filename: string): seq[seq[string]] =
    let content = read_data(filename)
    if content == "":
        return @[]
    return content.splitLines.mapIt(it.split(','))

let EmptyAction = FileAction(filename: "", kind: actionCreate)
proc build(act: FileAction = EmptyAction) =
    L = newNimLua()
    # Setup lua api
    L.bindFunction(setvar)
    L.bindFunction(include_asset)
    L.bindFunction(read_data)
    L.bindFunction:
        parseHTMLHeadings -> "parse_html"

    let standard_library_path = joinPath(getAppDir(), "assets/std.lua")
    if fileExists(standard_library_path):
        L.doFile(standard_library_path)
    else:
        displayError("Standard library not found",standard_library_path)

    let start_of_build = now()

    # Load config
    let execution_result = L.doFile(joinPath(input_dir,"config.lua"))
    if execution_result != 0:
        let err_msg = L.tostring(-1.cint)
        displayError(err_msg, joinPath(input_dir,"config.lua"))

    let forceNoIncremental = "incrementalBuild" notin globalVarTable or globalVarTable["incrementalBuild"] == "false"

    putPostDataInLua(L, input_dir, output_dir)

    if act.filename == "":
        # clean output repo except for .git
        for file in walkDir(output_dir):
            let p = file.path
            if not p.startswith("."):
                # Ignore symbolic directories
                if file.kind == pcFile:
                    discard tryRemoveFile(p)
                elif file.kind == pcLinkToDir:
                    removeDir(p)
        discard existsOrCreateDir(output_dir)

    # Start by building the posts to generate the post list.
    if act.filename == "" or forceNoIncremental:
        for file in walkDirRec(input_dir):
            let relative = relativePath(file, input_dir, '/').replace("\\","/")
            if shouldFileNotBeCompiled(relative):
                continue

            if file.endswith(".md") or file.endswith(".html"):
                var generated_file = changeFileExt(file, ".html")
                generated_file = joinPath(output_dir, relativePath(generated_file, input_dir))
                let result = compileFile(file, generated_file, input_dir)
                
                if "outfile" in globalVarTable:
                    generated_file = joinPath(output_dir,relativePath(globalVarTable["outfile"], input_dir))
                    globalVarTable.del("outfile")

                if not fileExists(parentDir(generated_file)):
                    createDir(parentDir(generated_file))
                try:
                    writeFile(generated_file, result)
                except IOError:
                    echo "File already in use, skipping: ",generated_file
                    discard # file is probably already in use, too bad!
            elif not file.endswith(".lua"):
                # Copy the file.
                var generated_file = joinPath(output_dir,relativePath(file, input_dir))
                if not fileExists(parentDir(generated_file)):
                    createDir(parentDir(generated_file))
                try:
                    copyFile(file, generated_file)
                except OSError:
                    discard
    else:
        let file = joinPath(input_dir,act.filename)
        if file.endswith(".md") or file.endswith(".html"):
            if "profiler" in globalVarTable and globalVarTable["profiler"] == "true":
                echo "Rebuilding only: ",file
            var generated_file = changeFileExt(file, ".html")
            generated_file = joinPath(output_dir,relativePath(generated_file, input_dir))
            # Find what to rebuild based on the action.
            if act.kind == actionDelete or act.kind == actionMoveFrom:
                if fileExists(generated_file):
                    discard tryRemoveFile(generated_file)
            else:
                # We can't just rename on a rename action because the lua might use the file name to generate the content.
                let result = compileFile(file, generated_file, input_dir)
                if "outfile" in globalVarTable:
                    generated_file = joinPath(output_dir,relativePath(globalVarTable["outfile"], input_dir))
                    globalVarTable.del("outfile")

                if not fileExists(parentDir(generated_file)):
                    createDir(parentDir(generated_file))
                try:
                    writeFile(generated_file, result)
                except IOError:
                    discard
        elif not file.endswith(".lua"):
            var generated_file = joinPath(output_dir,relativePath(file, input_dir))
            if act.kind == actionDelete or act.kind == actionMoveFrom:
                if fileExists(generated_file):
                    discard tryRemoveFile(generated_file)
            else:
                # Copy the file
                if not fileExists(parentDir(generated_file)):
                    createDir(parentDir(generated_file))
                try:
                    copyFile(file, generated_file)
                except OSError:
                    discard

    L.close()

    if "profiler" in globalVarTable and globalVarTable["profiler"] == "true":
        echo "--> Total build time: ",(now() - start_of_build)


var port = 8080
var connections {.threadvar.}: seq[WebSocket]
var reloadChannel: Channel[string]
reloadChannel.open()

proc rebuild(act: FileAction) {.gcsafe.} =
    {.gcsafe.}:
        build(act)
        # let profiler = "profiler" in globalVarTable and globalVarTable["profiler"] == "true"
        reloadChannel.send("reload")

# Server listening function
proc serverHandler() {.async.} =
    var server = newAsyncHttpServer()
    let outd = output_dir
    let profiler = "profiler" in globalVarTable and globalVarTable["profiler"] == "true"

    proc livereloadChannelReceiver() {.async gcsafe.} =
        while true:
            let msgCount = reloadChannel.peek()
            if msgCount == -1:
                break
            if msgCount == 0:
                await sleepAsync(100)
                continue
            let reloadRequest = reloadChannel.recv()
            if profiler:
                echo connections.len," clients notified of change"
            for ws in connections:
                asyncCheck ws.send("reload")

    proc cb(req: Request) {.async gcsafe.}  =
        # Handle websockets
        if req.url.path == "/ws":
            if profiler:
                echo "New websocket connection!"
            var ws: WebSocket = nil
            try:
                ws = await newWebSocket(req)
                {.gcsafe.}:
                    connections.add ws
                while ws.readyState == Open:
                    discard await ws.receiveStrPacket()

            except WebSocketClosedError:
                discard
            except WebSocketProtocolMismatchError:
                echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
            except WebSocketError:
                echo "Unexpected socket error: ", getCurrentExceptionMsg()
            if ws != nil:
                if profiler:
                    echo "Websocket connection closed!"
                {.gcsafe.}:
                    connections.delete(connections.find(ws))
                ws.close()
            return

        # Handle serving output directory
        # Serve file based on req.url
        # echo (req.reqMethod, req.url, req.headers)
        var p = req.url.path
        if p == "/":
            p = "/index.html"
        p = normalizedPath(p)
        var content = "404 - File not found"
        try:
            content = readFile(joinPath(outd, p))
        except IOError:
            discard # Occurs when the path is not valid.
            # echo "IOError: ",e.msg

        var headers: seq[(string,string)]
        await req.respond(Http200, content, headers.newHttpHeaders())

    server.listen(Port(port))
    echo "Listening at: http://localhost:",port

    let livereload = "livereload" in globalVarTable and globalVarTable["livereload"] == "true"
    if livereload:
        asyncCheck liveReloadChannelReceiver()

    while true:
        if server.shouldAcceptRequest():
            await server.acceptRequest(cb)
        else:
            await sleepAsync(500)


proc asyncMain() {.async.} =
    # Live reload and server stuff
    if "livereload" in globalVarTable and globalVarTable["livereload"] == "true":
        var monitor = newWatcher(input_dir, rebuild)
        echo "Live reload enabled."
    
    if "port" in globalVarTable:
        port = globalVarTable["port"].parseInt
        await serverHandler()

proc main() =
    build()
    waitFor asyncMain()

main()