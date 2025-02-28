<div align="center">
    <h1>Awesome Static Generator</h1>
    <em>⭐ Converts Markdown into a Website ⭐</em>
    <div>
    <img alt="badge release asg" src="https://github.com/vanyle/asg/actions/workflows/release.yml/badge.svg"/>
    <img alt="badge test asg" src="https://github.com/vanyle/asg/actions/workflows/test.yml/badge.svg"/>
    </div>
</div>

## The concept

Create websites like blogs, documentation or portfolio by writing [Lua](https://www.lua.org/) code!

```md
Last updated at *{{ os.date() }}*

# Fibonacci
{%
	fiboList = {1, 1}
    for i=2,10 do
        table.insert(fiboList, fiboList[i] + fiboList[i-1])
    end
%}

## List of fibonacci numbers
<ul>
{% for i, v in pairs({unpack(fiboList,3)}) do %}
	<li>The {{ i+2 }}th fibonacci number is $ {{ v }} = {{ fiboList[i+1] }} + {{ fiboList[i]}} $.</li>
{% end %}
</ul>
```

You can mix markdown, lua and latex! ASG is the ideal playground to learn Lua or build your website.
Get started using [a theme](./assets/themes/) or from scratch.

The modern theme looks like this:

![modern theme](./docs/modern_theme.png)

## Getting started

Go to the [release page](https://github.com/vanyle/ASG/releases) and download the latest version for your OS.
Unzip the file where you want and add the location to your path.

ASG supports Windows, Linux and MacOS, but we only generate binaries for Windows and Linux. MacOS binaries are available on request.

On Linux, using bash, you can do:
```bash
cd ~
curl -L https://github.com/vanyle/ASG/releases/download/0.0.1/asg-0.0.1-linux-amd64.tar.gz > asg.tar.gz && tar xzf asg.tar.gz
mv build asg
rm asg.tar.gz
# Add asg to your path. for example, if you are using bash, add the following to your .bashrc
export PATH="~/asg:$PATH"
```

To start ASG, do: `asg <input_directory> <output_directory>`

There are no other arguments as the `input_directory` should contain a config file that stores all the configuration.

The static website will be generated inside `<output_directory>`

More information available inside [the usage manual](./docs/usage.md)

Check out [how to use ASG with Github Pages to publish your website](./docs/github.md)

## Key features

- Write markdown
- **Lua scripting** for templates
- Use ready-made templates to customize your website
- Extend existing templates or create your own
- Support **latex**, **mermaid diagrams** and **code highlighting**
- Convert Obsidian/Typora notes into a fancy static website
- Generate home page and links
- Generate short HTML with fast load times by building dependencies and only including them when necessary
- **Standalone executable** (no dependencies)
- View your website as you type and save with **live reloading**.
- Incremental build support
- Reasonable (sub-second) build times, even when incremental builds are disabled

## What makes ASG different from other website generators?

There are many static site generators that can be used to write blogs, however, most lack at least some of the following features:

- No dependencies (No Ruby, No Node, No Lua installation, nothing to install other than the executable)
- Turing-complete templates (templates can really do anything, like fetching data from the web or running other programs)
- Templates are not based on a domain specific language (aka they use an executing well known language)
- Reasonable build times (a.k.a not noticable for regular users)

You can view ASG (Awesome Static Generator) as a compiler for HTML (or anything really).
You can build websites quicker with it (or just generate plain text).

You have access to components, you can make interactive demos and tutorials, everything!
With pandoc, you can even convert this to a pdf.

The templates provided are very powerful as they can define lua function that you can later use, making asg
incredibly useful when creating interactive documents (with graphs and others), or just making blogs.

ASG is written in Nim with bits of Lua code for the HTML generation. It's overall pretty fast. In live reload mode
the time between you saving your file and the browser refreshing to render the new page is about 10 ms, which
is good enough for live preview.

ASG might be slower is you put very complex tasks in LUA (or a sleep / network access).

## Examples

You can see examples in the [`tests/input` folder](./tests/input/).
Every subfolder contains a different website that can be built.
You can take an example an extend it to create your own website!
