function circle(radius)
	local svg = [[
<svg width="100" height="100">
  <circle cx="50" cy="50" r="]] .. radius .. [[" stroke="green" stroke-width="4" fill="yellow" />
</svg>
	]]

	return svg
end

function split (inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

function timeToDate(t)
	return split(t," ")[1]
end

function plot(f, start_val, end_val, step)
	local svg = {}
	start_val = start_val or 0
	end_val = end_val or 20
	step = step or 1

	local values = {}
	local height = 100
	local width = 300
	local v_begin = f(start_val)
	local max_val = v_begin
	local min_val = max_val
	for i=start_val,end_val,step do
		local v = f(i)
		table.insert(values, v)
		if v >= max_val then max_val = v end
		if v <= min_val then min_val = v end
	end

	local xscale = width / (end_val - start_val)
	local yscale = height / (max_val - min_val)
	local xoffset = start_val
	local yoffset = min_val

	table.insert(svg,[[
<svg width="300" height="100">
<path d="]])


	table.insert(svg,"M " .. 0 .. " " .. height - (v_begin * yscale) .. " ")

	for i in pairs(values) do
		table.insert(svg,"L " .. i .. " " .. (height - (values[i] - yoffset) * yscale) .. " ")
	end


	table.insert(svg,[[" fill="transparent" stroke="black"/>]])

	table.insert(svg,"</svg>")
	return table.concat(svg)

end