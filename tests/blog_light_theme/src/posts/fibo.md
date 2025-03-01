{%
	setvar("layout",theme .. ".html")
	head = ""
	current_year = os.date("%Y")
%}

{%
	example_count = 30
%}


## Fibonacci numbers

Fibonacci numbers are a sequence that verifies the equation: $f_{n+1} = f_{n+1} + f_{n}$ with \\[f_0 = 0, f_1 = 1\\].

The program below will print the first {{example_count}} fibonacci numbers:

<style>
.py-code > *{
	padding: 16px;
}
</style>
<div class="py-code">
{{ highlight_syntax([[
a,b = 0,1
for i in range(30):
    print(a)
    a,b = b, a+b
]], "py") }}
</div>

Quick explaination of how the program works with a diagram.

```mermaid
  sequenceDiagram
    A->>B: A+B
    B->>A: B
```

The output will be:

{%
s = ""
a,b = 0,1
value_table = {}
for i=0,example_count,1 do
	table.insert(value_table, a)
	a,b = b+a,a
end
%}

{% for i in pairs(value_table) do %}
The {{i}}th fibonacci number is {{ value_table[i] }} <br/>
{% end %}


You can also compute fibonacci recursively.

{%

function fibo_rec(n)
	if n <= 1 then
		return 1
	end
	return fibo_rec(n-1) + fibo_rec(n-2)
end

%}

The 10th fibonacci number is {{ fibo_rec(30) }}