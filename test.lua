#!/usr/bin/env luajit

_G.SOCK_UNIX = require("socket.unix")

local function binary_message()
	local res = {}
	for i = 1, math.random(1000) + 1000 do
		table.insert(res, string.char(math.random(256)-1))
	end
	return table.concat(res)
end

local function get_responses(sock)
	local res = {}
	while true do
		local line = assert(sock:receive())
		--print("rcvd line", line)
		if line:match("^ERROR") then
			return nil, line
		end
		if line=="DONE" then
			return res
		end
		local val
		if line=="MESSAGE" then
			len = assert(tonumber(sock:receive()))
			val = assert(sock:receive(len))
			assert(sock:receive(1)=="\n")
		else
			val = assert(sock:receive())
		end
		res[line] = assert(val)
		local prt = val
		if #val > 20 then
			prt = "<"..#val.." bytes>"
		end
		print("Got:", line, prt)
	end
end

local function conn(str)
	local sock = assert(SOCK_UNIX())
	assert(#str >= 3)
	local c = assert(sock:connect("/tmp/pusher_socket"))
	print(">>>>> "..str)
	assert(sock:send(str.."\n"))
	return sock
end

local function main()

	local sock = conn("reset=yes_please")
	assert(get_responses(sock))

	local sock = conn("unique_id")
	local resp = assert(get_responses(sock))
	assert(resp.ID == "1")

	local sent = {}

	math.randomseed(1)
	for i = 1, 100 do
		local msg = "ahoj"..math.random(99999) .. math.random(99999) .. math.random(99999)
		if math.random() > 0.5 then
			msg = binary_message()
		end
		local sock
		if #msg < 100 then
			sock = conn("push|message="..msg)
		else
			sock = conn("push")
			assert(sock:send(#msg.."\n"..msg))
		end
		local resp = assert(get_responses(sock))
		sent[assert(resp.ID)] = msg
	end

	local sock = conn("delete=10")
	assert(get_responses(sock))
	sent["10"] = nil

	for i = 1, 99 do
		local sock = conn("get|autodelete")
		local resp = assert(get_responses(sock))
		assert(sent[resp.ID] == resp.MESSAGE)
		sent[resp.ID] = nil
		assert(tonumber(resp.AGE) <= 1)
	end

	assert(not next(sent))

	local sock = conn("unique_id")
	local resp = assert(get_responses(sock))
	assert(resp.ID == "1E")
	print("Seems OK")
end

main()