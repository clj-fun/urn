if not table.pack then table.pack = function(...) return { n = select("#", ...), ... } end end
if not table.unpack then table.unpack = unpack end
local load = load if _VERSION:find("5.1") then load = function(x, n, _, env) local f, e = loadstring(x, n) if not f then error(e, 2) end if env then setfenv(f, env) end return f end end
local _select, _unpack, _pack, _error = select, table.unpack, table.pack, error
local _libs = {}
local _temp = (function()
	return {
		['slice'] = function(xs, start, finish)
			if not finish then finish = xs.n end
			if not finish then finish = #xs end
			return { tag = "list", n = finish - start + 1, table.unpack(xs, start, finish) }
		end,
	}
end)()
for k, v in pairs(_temp) do _libs["lua/basic-0/".. k] = v end
local _2f3d_1, _2b_1, _2d_1, error1, getIdx1, setIdx_21_1, find1, match1, sub1, concat1, unpack1, _2e2e_1, clock1, getenv1, self1, startTimer_21_1, pauseTimer_21_1, stopTimer_21_1, config1, coloredAnsi1, colored_3f_1, colored1, putError_21_1, putWarning_21_1, putVerbose_21_1, putDebug_21_1, putNodeError_21_1, putNodeWarning_21_1, doNodeError_21_1
_2f3d_1 = function(v1, v2) return (v1 ~= v2) end
_2b_1 = function(v1, v2) return (v1 + v2) end
_2d_1 = function(v1, v2) return (v1 - v2) end
error1 = error
getIdx1 = function(v1, v2) return v1[v2] end
setIdx_21_1 = function(v1, v2, v3) v1[v2] = v3 end
find1 = string.find
match1 = string.match
sub1 = string.sub
concat1 = table.concat
unpack1 = table.unpack
_2e2e_1 = (function(...)
	local args1 = _pack(...) args1.tag = "list"
	return concat1(args1)
end)
clock1 = os.clock
getenv1 = os.getenv
self1 = (function(x1, key1, ...)
	local args2 = _pack(...) args2.tag = "list"
	return x1[key1](x1, unpack1(args2, 1, args2["n"]))
end)
startTimer_21_1 = (function(timer1, name1, level1)
	local instance1 = timer1["timers"][name1]
	if instance1 then
	else
		instance1 = ({["name"]=name1,["level"]=(level1 or 1),["running"]=false,["total"]=0})
		timer1["timers"][name1] = instance1
	end
	if instance1["running"] then
		error1(_2e2e_1("Timer ", name1, " is already running"))
	end
	instance1["running"] = true
	instance1["start"] = clock1()
	return nil
end)
pauseTimer_21_1 = (function(timer2, name2)
	local instance2 = timer2["timers"][name2]
	if instance2 then
	else
		error1(_2e2e_1("Timer ", name2, " does not exist"))
	end
	if instance2["running"] then
	else
		error1(_2e2e_1("Timer ", name2, " is not running"))
	end
	instance2["running"] = false
	instance2["total"] = ((clock1() - instance2["start"]) + instance2["total"])
	return nil
end)
stopTimer_21_1 = (function(timer3, name3)
	local instance3 = timer3["timers"][name3]
	if instance3 then
	else
		error1(_2e2e_1("Timer ", name3, " does not exist"))
	end
	if instance3["running"] then
	else
		error1(_2e2e_1("Timer ", name3, " is not running"))
	end
	timer3["timers"][name3] = nil
	instance3["total"] = ((clock1() - instance3["start"]) + instance3["total"])
	return timer3["callback"](instance3["name"], instance3["total"], instance3["level"])
end)
config1 = package.config
coloredAnsi1 = (function(col1, msg1)
	return _2e2e_1("\27[", col1, "m", msg1, "\27[0m")
end)
if (config1 and (sub1(config1, 1, 1) ~= "\\")) then
	colored_3f_1 = true
elseif (getenv1 and (getenv1("ANSICON") ~= nil)) then
	colored_3f_1 = true
else
	local temp1
	if getenv1 then
		local term1 = getenv1("TERM")
		if term1 then
			temp1 = find1(term1, "xterm")
		else
			temp1 = nil
		end
	else
		temp1 = false
	end
	if temp1 then
		colored_3f_1 = true
	else
		colored_3f_1 = false
	end
end
if colored_3f_1 then
	colored1 = coloredAnsi1
else
	colored1 = (function(col2, msg2)
		return msg2
	end)
end
putError_21_1 = (function(logger1, msg3)
	return self1(logger1, "put-error!", msg3)
end)
putWarning_21_1 = (function(logger2, msg4)
	return self1(logger2, "put-warning!", msg4)
end)
putVerbose_21_1 = (function(logger3, msg5)
	return self1(logger3, "put-verbose!", msg5)
end)
putDebug_21_1 = (function(logger4, msg6)
	return self1(logger4, "put-debug!", msg6)
end)
putNodeError_21_1 = (function(logger5, msg7, node1, explain1, ...)
	local lines1 = _pack(...) lines1.tag = "list"
	return self1(logger5, "put-node-error!", msg7, node1, explain1, lines1)
end)
putNodeWarning_21_1 = (function(logger6, msg8, node2, explain2, ...)
	local lines2 = _pack(...) lines2.tag = "list"
	return self1(logger6, "put-node-warning!", msg8, node2, explain2, lines2)
end)
doNodeError_21_1 = (function(logger7, msg9, node3, explain3, ...)
	local lines3 = _pack(...) lines3.tag = "list"
	self1(logger7, "put-node-error!", msg9, node3, explain3, lines3)
	return error1((match1(msg9, "^([^\n]+)\n") or msg9), 0)
end)
return ({["startTimer"]=startTimer_21_1,["pauseTimer"]=pauseTimer_21_1,["stopTimer"]=stopTimer_21_1,["putError"]=putError_21_1,["putWarning"]=putWarning_21_1,["putVerbose"]=putVerbose_21_1,["putDebug"]=putDebug_21_1,["putNodeError"]=putNodeError_21_1,["putNodeWarning"]=putNodeWarning_21_1,["doNodeError"]=doNodeError_21_1,["colored"]=colored1})
