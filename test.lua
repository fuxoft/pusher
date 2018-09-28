#!/usr/bin/env luajit

math.randomseed(1)

local function exe(str)
	print("-------- "..str)
	os.execute(str)
end

local function get(str)
	print("--get--- "..str)
	local fd = io.popen(str)
	return fd
end

local function random_data(bin)
	if not bin then
		local str = math.random(999999)
		return (str.."-MIDDLE-"..str)
	else
		local str = ""
		for i = 1, math.random(100) + 10 do
			str = str .. string.char(math.random(256) - 1)
		end
		return(str.."-MIDDLE-"..str)
	end
end

local function check_data(str)
	local p1, mid, p2 = str:match("^(.+)%-MIDDLE%-(.+)$")
	assert(p1 == p2)
end

local function main()
	exe("pusher purge_repo=test")
	exe("pusher purge_repo=test2")
	for i = 1, 3 do
		exe("pusher push_to=test data="..random_data())
		exe("pusher push_to=test2 data="..random_data())
		local fd = io.popen("pusher push_to=test","w")
		fd:write(random_data(true))
		fd:close()
	end
	exe("pusher pop_from=test all no_id autoremove")
end

main()