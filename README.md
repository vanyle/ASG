# Awesome Static generator

⭐ A program that converts markdown files into static websites. ⭐

## Features

- Write pages in Markdown
- Use ready-made templates to customize your website
- Extend existing templates or create your own
- Support latex, mermaid diagrams and code highlighting
- Convert Obsidian/Typora notes into a fancy static website
- Generate home page and links
- Lua scripting for templates
- Generate short HTML with fast load times by building dependencies and only including them when necessary
- Standalone executable (no dependencies)
- View your website as you type and save with live reloading.
- Reasonable build times

## Why / Use-cases

There are many static site generators that can be used to write blogs, however, most lack at least some of the following features:

- No dependencies (No Ruby, No Node js, nothing to install other than the executable)
- Turing-complete templates (templates can really do anything, like fetching data from the web or running other programs)
- Templates are not based on a domain specific language (aka they use an executing well known language)
- Reasonable build times (a.k.a not noticable for regular users)

You can view ASG (Awesome static generator) as a compiler for HTML (or anything really).
You can build websites quicker with it (or just generate plain text).

You have access to components, you can make interactive demos and tutorials, everything!
With pandoc, you can even convert this to a pdf.

The templates provided are very powerful as they can define lua function that you can later use, making asg
incredibly useful when creating interactive documents (with graphs and others), or just making blogs.

ASG is written in Nim with bits of Lua code for the HTML generation. It's overall pretty fast. In live reload mode
the time between you saving your file and the browser refreshing to render the new page is about 10 ms, which
is good enough for live preview.

ASG might be slower is you put very complex tasks in LUA (or a sleep / network access).

We might consider switching from Lua 5.3 to Lua JIT in a later version for this reason.


## Usage

Use: `asg <input_directory> <output_directory>`
There are no arguments as the `input_directory` should contain a config file
that stores all the configuration.

The static website will be generated inside `<output_directory>`

More information available inside [the usage manual](./USAGE.md)

## Examples

You can see examples in the `examples` folder.
Every subfolder of examples contains a different website that can be built.
You can take an example an extend it to create your own website!