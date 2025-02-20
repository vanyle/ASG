import std/times

type FileInfo* = object
    filename*: string
    url*: string
    size*: int
    word_count*: int
    modified_time*: Time
    title*: string
    description*: string
    parsedBody*: string
    tags*: seq[string]

type ParseChunkType* = enum
    RawText
    LuaValue
    LuaController

type PartialParse* = object
    ## Contains a partially parsed file.
    ## The lua bits needs to be executed and converted from markdown to html afterwards.
    data*: seq[string]
    isLua*: seq[ParseChunkType]
    timestamp*: Time
    realPath*: string
    partialParseTime*: Duration # used for profiling

type HTMLHeadingResult* = tuple[rank: int, title: string, id: string]
