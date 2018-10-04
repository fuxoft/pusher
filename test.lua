#!/usr/bin/env luajit

local function com(str)
	local cmd = "curl localhost:8080/"..str
	print(">>>>> "..cmd)
	assert(0 == os.execute(cmd))
end

local function binary_message()
	local res = {}
	for i = 1, math.random(1000) + 1000 do
		table.insert(res, string.char(math.random(256)-1))
	end
	return table.concat(res)
end

local function prtmsg(data)
	if #data <50 then
		return (data)
	else
		return("<"..#data.." bytes>")
	end
end

local function main()
	--com("quit=yes_please") --To be sure
	os.execute("rm -f log.txt")
	os.execute("rm -f db.txt")
	os.execute("./pusher.lua port=8080 persistent=db.txt > log.txt &")
	print("Pusher started.")
	os.execute("sleep 1")
	local msgs = 100
	math.randomseed(1)
	for i = 1,msgs do
		local channel = "chan"..math.random(5)
		local msg
		if math.random()>0.5 then
			msg = math.random(999999)..math.random(999999)..math.random(999999)
			com(string.format("push,channel=%s,message=%s",channel,msg))
		else
			msg = binary_message()
			print("Push binary msg")
			local fd = assert(io.popen("curl -H 'Expect:' localhost:8080/push,channel="..channel.." --data-binary @-", "w"))
			fd:write(msg)
			fd:close()
			print("Pushed "..prtmsg(msg))
		end
	end
	--os.exit()
	math.randomseed(1)
	for i = 1,msgs do
		local channel = "chan"..math.random(5)
		local msg
		if math.random()>0.5 then
			msg = math.random(999999)..math.random(999999)..math.random(999999)
		else
			msg = binary_message()
		end
		local fd = io.popen("wget --quiet localhost:8080/download,channel="..channel.." -O-")
		local got = fd:read("*a")
		fd:close()
		print("got "..prtmsg(got))
		assert(got == msg, (prtmsg(got).. "~="..prtmsg(msg)))
	end

	com("quit=yes_please")
	print("Pusher stopped, OK.")
end

main()