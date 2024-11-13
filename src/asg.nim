#? replace(sub = "\t", by = "  ")

import markdown
import std/strutils, std/os, std/times, std/terminal, std/re, std/sequtils, std/algorithm
import nimLUA
import std/tables, std/sets, std/strtabs
import std/asynchttpserver
import std/asyncdispatch
import ws
import nimwatch/nimwatch
import gitutils
import pkg/htmlparser, xmltree

let parameters = commandLineParams()
if parameters.len != 2:
	echo "Usage: asg <input_directory> <output_directory>"
	echo "Read the README.md for more info!"
	quit()

type FileInfo = object
	filename: string
	url: string
	size: int
	word_count: int
	modified_time: Time
	title: string
	description: string
	parsedBody: string
	tags: seq[string]

type ParseChunkType = enum
	RawText
	LuaValue
	LuaController

type PartialParse = object
	## Contains a partially parsed file.
	## The lua bits needs to be executed and converted from markdown to html afterwards.
	data: seq[string]
	isLua: seq[ParseChunkType]
	timestamp: Time
	realPath: string
	partialParseTime: Duration # used for profiling

var L: PState = nil.PState
var c = initGfmConfig()
let input_dir = parameters[0]
let output_dir = parameters[1]
var globalVarTable: Table[string,string]

var fileParseInfo: Table[string,FileInfo]
var parsingCache: Table[string, PartialParse]

proc setvar(varname: string, varcontent: string): int =
	globalVarTable[varname] = varcontent
	return 0

proc include_asset(asset_name: string): string =
	let path = joinPath(getAppDir(), "assets", asset_name)
	if fileExists(path):
		return readFile(path)
	else:
		return ""

type HTMLHeadingResult = tuple[rank: int, title: string, id: string]

proc parseHTMLHeadings(html_source: string): seq[HTMLHeadingResult] =
	# result: seq[HTMLHeadingResult] = @[]
	var parsed = parseHTML(html_source)
	var res: seq[HTMLHeadingResult]
	var toProcess = @[parsed]
	while toProcess.len > 0:
		let node = toProcess.pop()
		case node.kind
		of xnElement:
			let attributes = node.attrs
			let nodeId: string = if attributes.hasKey("id"): attributes["id"] else: ""

			if node.tag == "h1":
				res.add((rank: 1, title: node.innerText, id: nodeId))
			elif node.tag == "h2":
				res.add((rank: 2, title: node.innerText, id: nodeId))
			elif node.tag == "h3":
				res.add((rank: 3, title: node.innerText, id: nodeId))
			elif node.tag == "h4":
				res.add((rank: 4, title: node.innerText, id: nodeId))
			elif node.tag == "h5":
				res.add((rank: 5, title: node.innerText, id: nodeId))
			elif node.tag == "h6":
				res.add((rank: 6, title: node.innerText, id: nodeId))
			else:
				for child in node:
					toProcess.add(child)
		else:
			discard

	return res.reversed()

	


proc displayError(error_msg: string,error_file: string,error_code:string = "") =
	if "coloredErrors" in globalVarTable and globalVarTable["coloredErrors"] == "true":
		styledEcho fgRed, "Compilation Error:"
		styledEcho "    Concerning ",error_file
		styledEcho "    ", error_msg
		if error_code != "":
			styledEcho bgRed,"    Code responsible:"
			if error_code.len > 400:
				styledEcho error_code[0..400], "... (omited)" # display first 100 characters to avoid spam
			else:
				styledEcho error_code
			styledEcho bgRed,"-----"
	else:
		echo "Compilation Error:"
		echo "    Concerning ",error_file
		echo "    ", error_msg
		if error_code != "":
			echo "    Code responsible:"
			if error_code.len > 400:
				echo error_code[0..400], "... (omited)" # display first 100 characters to avoid spam
			else:
				echo error_code
			echo "-----"

proc splitButKeep(s: string, sep: string): seq[string] = 
	## Example: splitButKeep("a, b, c",",") = @["a",","," b",","," c"]
	result = @[]
	var lastCut = 0
	var i = 0
	while i < s.len:
		# echo "i=",i," | s.len=",s.len
		if s[i ..< min(s.len, i + sep.len)] == sep:
			result.add($s[lastCut..<i])
			result.add(sep)
			i += sep.len
			lastCut = i
		i += 1
	let ending = min(i, s.len)
	if lastCut < ending:
		result.add($s[lastCut..<ending])



proc tokenizeForLua(s: string, splitters: seq[string]): seq[string] =
	# Sort of a fancy split function.
	# This can be faster using a queue structure
	# so that we don't have the copy operation for every splitter.
	var bits: seq[string] = @[s]
	for i in splitters:
		var newbits: seq[string] = @[]
		for j in bits:
			if j == i:
				newbits.add(j)
			else:
				newbits.add j.splitButKeep(i)
		bits = newbits
	return bits

proc tokenizeFile(path: string): PartialParse =
	## Pure function (but reads IO)
	## Takes the content of a file and outputs a partially parsed version.
	## Does not execute lua, nor markdown and is memoized.

	if path in parsingCache:
		let time = parsingCache[path].timestamp
		# call to getLastModificationTime should be cached by OS and therefore quite fast (laster than a read for example)
		if getLastModificationTime(parsingCache[path].realpath) <= time:
			return parsingCache[path]
	# Let's perform a partial parse and memoize the result!
	var in_path = path
	var start_of_partial_parse = now()

	# Try 1: relative to cwd.
	# Try 2: relative to executable
	# Try 3: relative to executable/assets
	if not fileExists(in_path):
		in_path = joinPath(input_dir, path)

	if not fileExists(in_path):
		in_path = joinPath(getAppDir(), path)

	if not fileExists(in_path):
		in_path = joinPath(getAppDir(),"assets", path)	

	if not fileExists(in_path):
		displayError("Unable to find file", in_path)
		return

	var fcontent = ""
	try:
		fcontent = readFile(in_path)
	except:
		displayError("Unable to read file",in_path)
		return
	let timestamp = getLastModificationTime(in_path)

	if in_path.endswith(".lua"):
		# We do only 1 pass that we mark as lua-only.
		parsingCache[path] = PartialParse(
			realpath: in_path,
			data: @[fcontent],
			isLua: @[LuaController],
			timestamp: timestamp,
			partialParseTime: now() - start_of_partial_parse
		)
		return parsingCache[path]
	var lua_template_formats: HashSet[string] = toHashSet([".txt",".md",".css",".js",".html",".asg"])
	var lua_format = false

	for extension in lua_template_formats:
		if in_path.endswith(extension): # yes, you can do this faster with radix trees. I don't care
			lua_format = true
			break

	if not lua_format:
		let pp = PartialParse(
			realpath: in_path,
			data: @[fcontent],
			isLua: @[RawText],
			timestamp: timestamp,
			partialParseTime: now() - start_of_partial_parse
		)
		if fcontent.len < 1024 * 1024 * 10: # 10 Mo: don't fill ram with the cache
			parsingCache[path] = pp
		return parsingCache[path]
	var tokens = tokenizeForLua(fcontent, @["{{","}}","{%","%}"])
	var data: seq[string]
	var isLua: seq[ParseChunkType]

	var inLua = false
	var inLuaController = false
	var endOfLoopInterpreter = false
	var inLoopInterpreter = false # loop or other lua control structure like if (might also add function support ?)
	var luaCodeBuffer = ""

	for t in tokens:
		if t == "{{":
			inLua = true
		elif t == "}}":
			inLua = false
		elif t == "{%":
			inLuaController = true
		elif t == "%}":
			inLuaController = false
			if inLoopInterpreter:
				if endOfLoopInterpreter:
					inLoopInterpreter = false
					endOfLoopInterpreter = false
					luaCodeBuffer.add "return table.concat(result)"
					# run the lua code buffer and add result to r.
					data.add luaCodeBuffer
					isLua.add LuaValue

					luaCodeBuffer = ""
				else:
					endOfLoopInterpreter = true
		else:
			if inLoopInterpreter:
				# Generate lua code based on the html and stuff.
				if inLua:
					luaCodeBuffer.add "table.insert(result,(" & t & "))\n"
				elif inLuaController:
					luaCodeBuffer.add t.strip() & "\n"
				else: # insert raw html
					luaCodeBuffer.add "table.insert(result, [=====[" & t & "]=====])\n"
			elif inLua:
				data.add "return " & t
				isLua.add LuaValue

			elif inLuaController:
				# Use content following the controller section as argument for lua.
				# If we start a loop, we go into loop execution mode
				let tstrip = t.strip()
				if tstrip.startswith("for ") or tstrip.startswith("if ") or tstrip.startswith("while "):
					inLoopInterpreter = true
					endOfLoopInterpreter = false
					luaCodeBuffer = "result = {}\n"
					luaCodeBuffer.add (tstrip & "\n")
					# we represent the lua string as a table that we concat later for performance reasons.
					# This is because lua strings are immutable so repeated concatenation is an O(n^2) instead of O(n)
				else:
					data.add t
					isLua.add LuaController
			else:
				data.add t
				isLua.add RawText

	let pp = PartialParse(
			realpath: in_path,
			data: data,
			isLua: isLua,
			timestamp: timestamp,
			partialParseTime: now() - start_of_partial_parse
		)
	if fcontent.len < 1024 * 1024 * 10: # 10 Mo: don't fill ram with the cache
		parsingCache[path] = pp
	return parsingCache[path]

proc compileFile(p: string, out_path: string, recursionPath: seq[string] = @[]): string =
	##[
		Read the file located at `in_path` and turn it into the
		file inside `out_path`.
		If `out_path` is not provided, no output is generated.
		This function is not pure and can modify the lua state machine.
	]##
	
	let partialParse = tokenizeFile(p)
	if partialParse.realpath == "":
		return ""

	var rp = recursionPath
	rp.add(partialParse.realpath)

	# Regular HTML / MD parsing
	# CONTENT -> Data reading -> File/Page processing -> Lua execution -> Markdown -> Finish

	var r = ""
	var html = ""

	# Setup file object to target the current file processed (in_path)
	# file.name, file.size, file.last_modified.
	L.createTable(0,3) # 3 entry in table

	discard L.pushstring("name")
	discard L.pushstring(partialParse.realpath.cstring)
	L.settable(-3)

	discard L.pushstring("size")
	let fsize_int = getFileSize(partialParse.realpath)
	let fsize = $fsize_int
	discard L.pushstring(fsize.cstring)
	L.settable(-3)

	discard L.pushstring("last_modified")
	let ftime = partialParse.timestamp.format("dd/MM/yy HH:mm:ss")
	discard L.pushstring(ftime.cstring)
	L.settable(-3)

	L.setglobal("file")

	for i in 0..<partialParse.data.len:
		let t = partialParse.data[i]
		let isL = partialParse.isLua[i]
		case isL:
		of RawText:
			r.add t
		of LuaValue:
			let execution_result = L.dostring t
			if execution_result != 0:
				let err_msg = L.tostring(-1.cint)
				displayError(err_msg, partialParse.realpath, t) 
			else:
				r.add L.tostring(-1.cint)
		of LuaController:
			let execution_result = L.dostring t
			if execution_result != 0:
				let err_msg = L.tostring(-1.cint)
				displayError(err_msg, partialParse.realpath, t) 


	if partialParse.realpath.endswith(".md"):
		html = markdown(r, c)
	elif partialParse.realpath.endswith(".html"):
		html = r

	var tags: seq[string] = @[]
	if "tags" in globalVarTable:
		tags = globalVarTable["tags"].split(",")

	# Remove html tags.
	# Note that html tags cannot be parsed with a regex.
	# This is only for word count, so it's fine, doesn't matter if we are wrong for weird edge cases.
	var stripped_content = html.replace(re"<[^>]*>")
	var word_count = stripped_content.split(" ").len

	var lines = stripped_content.split("\n")
	lines = lines.filterIt(it.strip().len != 0)

	var title = ""
	if "title" in globalVarTable:
		title = globalVarTable["title"]
	elif lines.len > 0:
		# By definition, the title is the first line
		title = lines[0]
		

	var description = ""
	if "description" in globalVarTable:
		description = globalVarTable["description"]
	elif lines.len > 1:
		description = lines[1]

	if "layout" in globalVarTable and globalVarTable["layout"] != "":
		# put html as body of layout.
		if globalVarTable["layout"] in rp:
			rp.add(globalVarTable["layout"])
			echo "Warning: Infinite inclusion loop in layouts. Stopping"
			echo "The inclusion stack is: ", rp.join(",")
			echo "(The last file is repeated, this is a loop)"
		else:
			discard L.pushstring(html.cstring)
			L.setglobal("body")
			html = compileFile(globalVarTable["layout"], out_path, rp)

	# Generate a file parse info object.
	# But don't do this for layouts, only root files.
	let fpi = FileInfo(
		filename: partialParse.realpath,
		url: "",
		size: fsize_int.int,
		word_count: word_count,
		modified_time: partialParse.timestamp,
		title: title,
		description: description,
		parsedBody: html,
		tags: tags
	)
	fileParseInfo[p] = fpi

	return html

let EmptyAction = FileAction(filename: "", kind: actionCreate)
proc build(act: FileAction = EmptyAction) =
	L = newNimLua()
	# Setup lua api
	L.bindFunction(setvar)
	L.bindFunction(include_asset)
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

	# Posts data
	var posts: seq[string] = @[]
	let post_file_path = joinPath(input_dir,"posts")
	if dirExists(post_file_path):
		for file in walkDirRec(post_file_path):
			if file.endswith(".md") or file.endswith(".html"):
				posts.add file
				var generated_file = changeFileExt(file, ".html")
				generated_file = joinPath(output_dir,relativePath(generated_file, input_dir))
				let result = compileFile(file,generated_file)
				
				if not fileExists(parentDir(generated_file)):
					createDir(parentDir(generated_file))
				try:
					writeFile(generated_file, result)
				except IOError:
					discard # file is probably already in use, too bad!

	#[
		posts = {post1, post2, {file: input/filename, url: filename.html}}
	]#
	L.createTable(0.cint, posts.len.cint)
	for i in 0..<posts.len:
		if posts[i] notin fileParseInfo: continue
		let info = fileParseInfo[posts[i]]
		
		var generated_file = changeFileExt(posts[i], ".html")
		let url = joinPath(".",relativePath(generated_file, input_dir))
		L.pushinteger(i)
		
		# Create table as the key: integer -> table
		# 9 entry in table
		# We should probably use templates instead of hardcoding the 9 here.
		L.createTable(0,9)

		discard L.pushstring("title")
		discard L.pushstring(info.title.cstring)
		L.settable(-3)

		discard L.pushstring("tags")
		discard L.pushstring(info.tags.join(",").cstring)
		L.settable(-3)

		discard L.pushstring("word_count")
		L.pushinteger(info.wordCount)
		L.settable(-3)

		discard L.pushstring("description")
		discard L.pushstring(info.description.cstring)
		L.settable(-3)

		discard L.pushstring("file")
		discard L.pushstring(posts[i].cstring)
		L.settable(-3)
		
		discard L.pushstring("url")
		discard L.pushstring(url.cstring)
		L.settable(-3)

		discard L.pushstring("name")
		let name = changeFileExt(lastPathPart(url), "") # remove extension for "name"
		discard L.pushstring(name.cstring)
		L.settable(-3)

		# We provide 3 date related to file modification:
		# modification time as provided by git (default)
		# modification time as provided by the OS.
		# creation time as provided by git
		
		block:
			let blameInfo = gitBlame(posts[i])
			
			discard L.pushstring("last_modified")
			if blameInfo.modificationCommits.len > 0:
				let ftime = getGitModificationTime(blameInfo).format("dd/MM/yy HH:mm:ss")
				discard L.pushstring(ftime.cstring)
			else:
				discard L.pushstring("".cstring)
			L.settable(-3)

			discard L.pushstring("created_at")
			if blameInfo.modificationCommits.len > 0:
				let ftime = getGitCreationTime(blameInfo).format("dd/MM/yy HH:mm:ss")
				discard L.pushstring(ftime.cstring)
			else:
				discard L.pushstring("".cstring)
			L.settable(-3)

		block:
			discard L.pushstring("last_modified_os")
			# use same format as lua for dates
			let ftime = getLastModificationTime(posts[i]).format("dd/MM/yy HH:mm:ss")
			discard L.pushstring(ftime.cstring)
			L.settable(-3)

		discard L.pushstring("size")
		let size: int = (getFileSize(posts[i])).int
		L.pushinteger(size)
		L.settable(-3)

		L.settable(-3) # stack layout: table, integer, {file,url}
	L.setglobal("posts")

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
			if file.endswith(".md") or file.endswith(".html"):
				var generated_file = changeFileExt(file, ".html")
				generated_file = joinPath(output_dir,relativePath(generated_file, input_dir))
				let result = compileFile(file,generated_file)
				
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
				let result = compileFile(file,generated_file)
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
var monitor = newWatcher(input_dir)

proc rebuild(act: FileAction) {.gcsafe.} =
	{.gcsafe.}:
		build(act)
		let profiler = "profiler" in globalVarTable and globalVarTable["profiler"] == "true"

		if profiler:
			echo connections.len, " clients notified of change."
		for i in 0..<connections.len:
			discard connections[i].send "reload"

# Server listening function
proc serverHandler() {.async.} =
	var server = newAsyncHttpServer()
	let outd = output_dir
	let profiler = "profiler" in globalVarTable and globalVarTable["profiler"] == "true"

	proc cb(req: Request) {.async gcsafe.}  =
		# Handle websockets
		if req.url.path == "/ws":
			if profiler:
				echo "New websocket connection!"
			var ws: WebSocket = nil
			try:
				ws = await newWebSocket(req)
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
				ws.close()
				connections.delete(connections.find(ws))
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

	while true:
		if server.shouldAcceptRequest():
			await server.acceptRequest(cb)
		else:
			await sleepAsync(500)


proc asyncMain() {.async.} =
	# Live reload and server stuff
	if "livereload" in globalVarTable and globalVarTable["livereload"] == "true":
		monitor.register(rebuild)
		asyncCheck monitor.watch()
		echo "Live reload enabled."
	
	if "port" in globalVarTable:
		port = globalVarTable["port"].parseInt
		await serverHandler()

proc main() =
	build()
	waitFor asyncMain()

main()