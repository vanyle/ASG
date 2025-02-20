import gitutils
import os, std/[strutils, tables, times]
import nimLUA
import asgtypes
import compilefile

proc putPostDataInLua*(L: PState, input_dir: string, output_dir: string) =
    var posts: seq[string] = @[]
    let post_file_path = joinPath(input_dir, "posts")
    if dirExists(post_file_path):
        for file in walkDirRec(post_file_path):
            if file.endswith(".md") or file.endswith(".html"):
                posts.add file
                var generated_file = changeFileExt(file, ".html")
                generated_file = joinPath(output_dir,relativePath(generated_file, input_dir))
                let result = compileFile(file, generated_file, input_dir)
                
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
        L.pushinteger(i + 1) # index starts at 1 in lua.
        
        # Create table as the key: integer -> table
        # 9 entry in table
        # We should probably use templates instead of hardcoding the 9 here.
        L.createTable(0,9)

        discard L.pushstring("title")
        discard L.pushstring(info.title.cstring)
        L.settable(-3)

        discard L.pushstring("body")
        discard L.pushstring(info.parsedBody.cstring)
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