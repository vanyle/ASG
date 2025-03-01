# Documentation

## How to run the Awesome Static Generator?

**`asg <input_directory> <output_directory>`**

Configure your build using the `config.lua` inside your `input_directory`.

The static website will be generated inside `<output_directory>`

## Input directory structure

ASG uses the following rules to generate your website:

- All markdown files get turned into webpages.
- All HTML files get also turned into webpages but without markdown preprocessing
- Lua files are ignored and not copied
- Files inside the data folder are not copied

| Original Path  | Result Path      |
| -------------- | ---------------- |
| index.md       | index.html       |
| example.html   | example.html     |
| posts/thing.md | posts/thing.html |
| posts/img.jpg  | posts/img.jpg    |
| myscript.lua   | n/a              |
| data/sheet.csv | n/a              |

The `posts` and `data` folders are special.

- `post` can stores posts if you want to build a blog. You can list all the posts using the `posts` variable in lua (see below)
- `data` can store data like CSV or TXT, or any kind of file. You can read the content of a data file in lua (see below).

## Non standard markdown features

Insert latex using `$` (dollar sign). Use 1 dollar sign for inline math and 2 dollar signs for blocks of math.

## Lua API basics

You can put inline Lua code inside `{{` and `}}` to render the output of Lua.
The Lua API is described below.
To display the build date for example, you can write something like:

```md
_Last updated: {{ os.date() }}_
```

You have also access to several variables by default like the file variable:

```md
# Some page

The file path of this page is {{ file.name }}
It was last modified at {{ file.last_modified }}
According to Git, it was created at {{ file.created_at }}
It's total size is {{ file.size }}
```

`file` always refers to the file containing the `file` variable, so take this into account when building layouts.

By convention, when using layouts, layouts substitute the `title`, `body`, `head` and `endscript` variables by the ones you
provide. The `body` variable is automatically generated and is the main content of the post.
You can change the `title` variable to change the title or your post if you want.

Sometimes, you want to insert more complex code that does not generate data directly:

```md
{%
my_var = 10

function circle(radius)
return "<div class='round' style='width:"..radius.."px'></div>"
end
%}
```

The `{%` and `%}` tags do not generate Markdown or HTML directly but define variables and functions that can be used
by the rest of the Lua code.

To define loops, use `{% for`.
ASG will try to match your loop block with an `{% end %}` block and repeat the html inside:

```html
{% fruits = {"Apple","Banana","Oranges"} %} A list of fruits:
<ul>
	{% for i in pairs(fruits) do %}
	<li id="fruit-{{i}}">{{ fruits[i] }}</li>
	{% end %}
</ul>
```

This will get parsed into:

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
but, you'll able to access all the posts using the `posts` lua iterator.

```lua

for i in posts() do
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

Data are similar to posts except they don't get rendered to the website. They are stored
inside the `data` folder.

Data can any file type like `.csv`, `.json`, `.lua`, `.txt` or `.html`.

Function of part of the Data API

- `read_data(filename) -> string`: Read the file named `filename` inside the data directory and return its content
- `read_csv(filename) -> list`: Read a `.csv` file and return a list of table that represent the rows of the CSV.

You can use `data` to generate visualisations at runtime, store assets that you want to embed in your HTML or put your custom layout files there.
See the layout section for more information about layouts.

## Standard library

By default, we provide several lua functions to help you generate HTML.

### Native functions

_These functions are implemented in Nim code_

- `include_asset(path: string)`: Read the content of a file in the `assets` folder (the one next to the asg executable) and return it.
- `setvar(key: string, value: string)`: Set a variable like the current layout. This is used to configure build options.
- `read_data(filename: string)`: Read the file named `filename` inside the `data` folder and return its content. Return an empty string if the file does not exist.
- `read_csv(filename: string)`: Read the file named `filename` inside the `data` folder and return its content as a table of table for every row of the CSV.
- `parse_html(s: string)`: Parse the HTML inside s and return a table with the headings and their content. Useful for building summaries.

### Lua functions

_These functions are implemented in `std.lua`_

- `split(s: string, sep: string)`: Cut a string `s` using `sep` as the separator. This is the opposite of `join`.

## Configuration

You should put your configuration inside the `config.lua` file at the root of your input directory, as `config.lua` is always executed first.

Use the `setvar` function to configure your build.

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

Layouts are the most powerful feature of ASG and allow you to compose HTML / MD files together.

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
