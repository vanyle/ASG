import osproc, strutils, os
from times import nil

type Commit = object
    hash: string
    message: string
    author: string
    date: string

type BlameInfo = object
    modificationCommits*: seq[Commit] # most recent first, oldest last

proc gitBlame*(path: string): BlameInfo = 
    try:
        if not fileExists(path):
            return BlameInfo(modificationCommits: @[])

        let parentFolder = parentDir(path)
        let filename =  extractFilename(path)

        let output = execProcess("git", args=["log","--follow",filename], workingDir=parentFolder, options={poUsePath})
        let lines = output.splitLines()

        var blameInfo: BlameInfo
        var currentCommit: Commit

        var i = 0
        while i < lines.len:
            let l = lines[i]
            if l.startswith("commit"):
                currentCommit.hash = l.split(" ",1)[1]
            elif l.startswith("Author: "):
                currentCommit.author = l.split(" ",1)[1]
            elif l.startswith("Date: "):
                currentCommit.date = l.split(" ",1)[1].strip()
            elif l.len == 0:
                var m = ""
                inc i
                while i < lines.len and lines[i].len > 0:
                    m.add lines[i].strip()
                    inc i
                currentCommit.message = m
                blameInfo.modificationCommits.add currentCommit
                currentCommit = Commit()
            inc i

        return blameInfo
    except OSError as e:
        return BlameInfo()

proc getGitModificationTime*(bi: BlameInfo): times.Time =
    if bi.modificationCommits.len == 0:
        # If the file is not in Git, it is new.
        return times.toTime(times.now())
    let dateString = bi.modificationCommits[0].date
    # format: Fri Nov 1 14:07:05 2024 +0100
    try:
        return times.parseTime(dateString, "ddd MMM d HH:mm:ss yyyy ZZZ", times.utc())
    except times.TimeParseError:
        return times.toTime(times.now())

proc getGitCreationTime*(bi: BlameInfo): times.Time =
    if bi.modificationCommits.len == 0:
        return times.toTime(times.now())
    let dateString = bi.modificationCommits[^1].date
    try:
        return times.parseTime(dateString, "ddd MMM d HH:mm:ss yyyy ZZZ", times.utc())
    except times.TimeParseError:
        return times.toTime(times.now())
