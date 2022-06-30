{%
	setvar("layout","assets/light.html")
	head = ""
	birth = 2000
	current_year = os.date("%Y")
%}

{%
	example_count = 30
%}


## Fibonacci numbers

Fibonacci numbers are a sequence that verifies the equation: \\( f_{n+1} = f_{n+1} + f_{n} \\) with \\( f_0 = 0, f_1 = 1 \\).

*Written at {{ os.date() }}*

Hi, I'm {{ name }}, I'm {{ math.floor(current_year - birth) }} years old and i like rambling about my life on the internet.


The program below will print the first {{example_count}} fibonacci numbers:
```python
a,b = 0,1
for i in range({{example_count}}):
	print(a)
	a,b = b, a+b
```

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


