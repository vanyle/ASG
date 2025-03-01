{%
setvar("layout",theme .. ".html")

%}

# Graphs

What are graphs? And how we can use them to get a better understanding of functions?

Well, let's say you have a function, like:
$$ f: x \to x^2 $$
You want to have a visual representation of it.
Well you may want to draw the set of points \\\[(x, f(x))\\\] on a 2d plane.

For this function above, this may look like this:

{%
function f(x)
	return math.sin(x)
end
%}

{{ plot(f,0,20,0.1) }}

This is another plot:

{{ plot(f,0,20,0.2) }}

