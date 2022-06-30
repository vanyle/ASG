{%
title = "Math blog"
setvar("layout","light.html")


%}

<div class='card'>

## Welcome to my blog!

This is a blog about math, programing and art!
It's generated using ASG (you can checkout more about ASG [here](https://github.com))

</div>

{% for i in pairs(posts) do %}
<div class='card'>
	<a class='title' href="{{ posts[i].url }}">{{ posts[i].title }}</a>
	<br/>
	<div class="time">{{ timeToDate(posts[i].last_modified) }}</div>
	<p>
	{{ posts[i].description }}
	</p>
	<div class="time">
	About {{ math.ceil(posts[i].word_count / 200) }} minutes to read
	</div>
</div>
{% end %}
