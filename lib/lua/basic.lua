local counter = 0
local function pretty(x)
	if type(x) == 'table' and x.tag then
		if x.tag == 'list' then
			local y = {}
			for i = 1, x.n do
				y[i] = pretty(x[i])
			end
			return '(' .. table.concat(y, ' ') .. ')'
		elseif x.tag == 'symbol' then
			return x.contents
		elseif x.tag == 'key' then
			return ":" .. x.value
		elseif x.tag == 'string' then
			return (("%q"):format(x.value):gsub("\n", "n"):gsub("\t", "\\9"))
		elseif x.tag == 'number' then
			return tostring(x.value)
		elseif x.tag.tag and x.tag.tag == 'symbol' and x.tag.contents == 'pair' then
			return '(pair ' .. pretty(x.fst) .. ' ' .. pretty(x.snd) .. ')'
		else
			return tostring(x)
		end
	elseif type(x) == 'string' then
		return ("%q"):format(x)
	else
		return tostring(x)
	end
end

if arg then
	if not arg.n then arg.n = #arg end
	if not arg.tag then arg.tag = "list" end
else
	arg = { tag = "list", n = 0 }
end

return {
	['='] = function(x, y) return x == y end,
	['/='] = function(x, y) return x ~= y end,
	['<'] = function(x, y) return x < y end,
	['<='] = function(x, y) return x <= y end,
	['>'] = function(x, y) return x > y end,
	['>='] = function(x, y) return x >= y end,

	['+'] = function(x, y) return x + y end,
	['-'] = function(x, y) return x - y end,
	['*'] = function(x, y) return x * y end,
	['/'] = function(x, y) return x / y end,
	['%'] = function(x, y) return x % y end,
	['^'] = function(x, y) return x ^ y end,
	['..'] = function(x, y) return x .. y end,
	['slice'] = function(xs, start, finish)
		if not finish then finish = xs.n end
		if not finish then finish = #xs end
		return { tag = "list", n = finish - start + 1, table.unpack(xs, start, finish) }
	end,
	pretty = pretty,
	['gensym'] = function(name)
		if name then
			name = "_" .. tostring(name)
		else
			name = ""
		end
		counter = counter + 1
		return { tag = "symbol", contents = ("r_%d%s"):format(counter, name) }
	end,
	_G = _G, _ENV = _ENV, _VERSION = _VERSION, arg = arg,
	assert = assert, collectgarbage = collectgarbage,
	dofile = dofile, error = error,
	getmetatable = getmetatable, ipairs = ipairs,
	load = load, loadfile = loadfile,
	next = next, pairs = pairs,
	pcall = pcall, print = print,
	rawequal = rawequal, rawget = rawget,
	rawlen = rawlen, rawset = rawset,
	require = require, select = select,
	setmetatable = setmetatable, tonumber = tonumber,
	tostring = tostring, ["type#"] = type,
	xpcall = xpcall,
	["get-idx"] = function(x, i) return x[i] end,
	["set-idx!"] = function(x, k, v) x[k] = v end
}
