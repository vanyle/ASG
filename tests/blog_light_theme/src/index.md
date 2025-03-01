{%
title = "Math blog"
setvar("layout",theme .. ".html")
head = ""

%}

## Welcome to my blog!

<main>

<p>

This is a blog about math, programing and art!
It's generated using ASG (you can checkout more about ASG [here](https://github.com/vanyle/asg))

Build using {{ _VERSION }}

</p>

</main>

## Latest posts

{% for post in posts() do %}
<a href="{{ post.url }}">
<div class='card'>
	<h3 class='title'>
	{{ post.title }}
	</h3>
	<div class="time">{{ timeToDate(post.last_modified_os) }}</div>
	<p>
	{{ post.description }}
	</p>
	<div class="time">
	About {{ math.ceil(post.word_count / 200) }} minutes to read
	</div>
</div>
</a>
{% end %}
