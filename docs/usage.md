# Usage

Use: `asg <input_directory> <output_directory>`
There are no arguments as the `input_directory` should contain a config file
that stores all the configuration (named `config.lua`).

The static website will be generated inside `<output_directory>`

## Input directory structure

- All markdown files get turned into webpages.
- All HTML files get also turn to webpage but without markdown preprocessing
- Simple URL scheme: 
	- index.md -> /
	- example.md -> /example.html
	- posts/thing.md -> /post/thing.html

There is a special directory: the `posts` directory that stores posts if you want to build a blog.
You can list all the posts using the `posts` variable in lua (check out the corresponding section)

## Non standard markdown features

Insert latex using `$`. (dollar sign). Use 1 dollar sign for inline math and 2 dollar signs for blocks of math.

## Lua API basics

You can put inline lua incode inside `{{` and `}}` to render custom stuff. The lua API is described below.
To display the build date for example, you have write something like:

```md
*Last updated: {{ os.date() }}*
```

You have also access to several variables by default like the page variable and do stuff like this:

```md
# Some page

The file path of this page is {{ file.name }}
It was last modified at {{ file.last_modified }}
It's total size is {{ file.size }}

```

`file` always refers to the file containing the `file` variable, so take this into account when building layouts.

By convention, when using layouts, layouts substitute the `title`, `body`, `head` and `endscript` variables by the ones you
provide. The `body` variable is automatically generated and is the main content of the post.
You can change the `title` variable to change the title or your post if you want. 


Sometimes, you want to insert more complex code that does not generate data directly. To do this, you need to write:

```md
{%
my_var = 10

function circle(radius)
	return "<div class='round' style='width:"..radius.."px'></div>"
end
%}
```

The `{%` and `%}` tags do not generate Markdown or HTML directly but define variables and functions that can be used
by the rest of the lua code.

You can also use them to define loops, if your block starts with `{% for`, then
ASG will try to match your block with an `{% end %}` block and repeat the html inside:

```html

{% fruits = {"Apple","Banana","Oranges"}  %}


A list of fruits:
<ul>
{% for i in pairs(fruits) do %}
	<li id="fruit-{{i}}">{{ fruits[i] }}</li>
{% end %}
</ul>
```

This will get parsed into (more or less because performance):
```md
{%
fruits = {"Apple","Banana","Oranges"}
result = "A list of fruits\n<ul>\n"
for i in pairs(fruits) do
	result = result .. '\t<li id=fruit-' .. i .. '>' .. fruits[i] .. '</li>\n'
end
result = result .. "</ul>"
%}
{{ result }}
```
Inside your loop, you cannot have `{% %}` brackets as those will close the loop.
This also works with `if` and `while` constructs and behave as you would expect.

## Posts

You can put `.md` files in the `posts` folder.
Those will be accessible through the `/posts/ xxx .html` url,
but, you'll able to access all the posts using the `posts` lua array.

```lua

for i in pairs(posts) do
	-- posts[i].url, posts[i].file, posts[i].size
	-- posts[i].title, posts[i].word_count
end

```

Posts can set the variables:
- `tags` (a list of strings)
- `title` (a string)
- `description` (a string)

Those might be used by templates to generate pages or to search for posts

## Data

Data are similar to posts except they don't get rendered to the website.
Data can be `.csv` or `.json` file.
Data can also be `.lua` or `.html` files

Function of part of the Data API

- `readData(filename) -> string`: Read the file named `filename` inside the data directory and return its content
- `readCSV(filename) -> list`: Read a `.csv` file and return a list of table that represent the rows of the CSV.

## Standard library

By default, we provide several lua functions to help you generate HTML.

## Configuration

Use the `setvar` function to configure your build. You can put the `setvar` calls in `config.lua` (at the root of your website folder) if you want but you don't have do.
Before any file is built, `config.lua` will always get executed.

The configuration options are (their names are explicit):
```lua

setvar("port","8080") -- default: no webserver is started

setvar("livereload","true") -- default: false (requires port to be set, otherwise, does nothing)

setvar("debugInfo","true") -- default: false

setvar("incrementalBuild","true") -- default: true

setvar("coloredErrors","true") -- default: false

setvar("profiler","true") -- default: false

```

In incremental build mode, only the file you modified gets rebuilt. This makes builds faster but might not work
if you edit a layout that get's included in another file. In that case, turn incremental builds off.

## Layouts

Layouts are stored inside the `assets` folder next to the ASG executable. You can add your custom layouts there as
well as the lua libraries you want to include.

To use a layout, call `setvar("layout", name_of_the_layout)`

Layouts can be chained (it's a bit like inheritance), so you can have multiple layouts at once, or extend existing ones.

Lua code is executed starting with the source file and down the layout chain, ending with the base layout.
Layouts cannot be used twice in the layout chain to avoid infinite loops.
You cannot set multiple layouts for one page.

The rendering algorithm for a page looks like this:
1. Take the content of the current page, execute its lua code and render its markdown to get a string.
2. If the layout variable was set:
   1. set the current page to the layout variable
   2. set the body variable to the result of the render
   3. go to step 1 (All the variables set by the page are preserved.)
3. If the layout variable was not set, write the result of the render to the output directory.

In practice, this means that to use a given template, you set a few variables that the template uses with setvar.
For example, let's say that you want to use a template for the home page of your blog, then you might write
something like:

```md
{%

title = "My blog"
homepage_layout = "light.html"
setvar("layout","classic_homepage.html")
%}

Hello, and welcome to my blog!

``` 

Then the "layout" template will use the `body` variable as well as the `homepage_layout` and `title`
variable to generate your homepage!

## Lua Runtime

By default, ASG will use Lua JIT as the lua runtime for best performance.
You can disable this by passing the `-d:nojit` flag when compiling. You'll usually do this
if you want Lua 5.4 features or if you did not install lua jit on your computer and have compilation errors.

This is not recommended as ASG is defined for Lua JIT.
