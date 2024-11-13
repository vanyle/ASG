{%
title = "Math blog"
setvar("layout",theme .. ".html")
head = ""

%}

## Welcome to my blog!

<main>

<p>

This is a blog about math, programing and art!
It's generated using ASG (you can checkout more about ASG [here](https://github.com))

Build using {{ jit.version }}

</p>

</main>

## Latest posts

{% for i in ipairs(posts) do %}
<a href="{{ posts[i].url }}">
<div class='card'>
		<h3 class='title'>
		{{ posts[i].title }}
		</h3>
		<div class="time">{{ timeToDate(posts[i].last_modified) }}</div>
		<p>
		{{ posts[i].description }}
		</p>
		<div class="time">
		About {{ math.ceil(posts[i].word_count / 200) }} minutes to read
		</div>
</div>
</a>
{% end %}
