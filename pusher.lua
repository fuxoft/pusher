#!/usr/bin/env luajit

--PUSHER
--fuka@fuxoft.cz

_G.VERSION = string.match([[*<= Version '20180406b' =>*]], "'(.*)'")

local function myerror(err)
	print("ERROR")
	print(err)
	os.exit()
end

local function check_repo(repo)
	if not repo:match("^[%w%-]+$") then
		error("Invalid repo name: "..repo)
	end
end

local function parse_options(allowed)
	for i, opt in ipairs(allowed) do
		allowed[opt] = true
	end

	local opts = {}
	for i, arg in ipairs(arg) do
		if arg:match("=") then
			local opt, val = arg:match("(.-)=(.+)")
			assert(opt and val, "Invalid option syntax: "..arg)
			assert(#opt > 0)
			assert(#val > 0)
			opts[opt] = val
		else
			opts[arg] = true
		end
	end
	for k,v in pairs(opts) do
		if not allowed[k] then
			print("Invalid option: "..k.."="..tostring(v))
			table.sort(allowed)
			print("Allowed options: "..table.concat(allowed,", "))
			os.exit()
		end
	end

	return opts
end

local function uuid()
	local fd = assert(io.open("/proc/sys/kernel/random/uuid"))
	local str = fd:read("*l")
	fd:close()
	assert(#str > 10)
	return str
end

local function remove(id)
	assert(not id:match("[/%.]"))
	os.execute ("rm -f "..OPTS.dir..id..".txt")
end

local function purge_repo()
	local repo = OPTS.purge_repo
	check_repo(repo)
	os.execute("rm -f "..OPTS.dir..repo.."_*")
end

local function push_to()
	local repo = OPTS.push_to
	check_repo(repo)
	local data = OPTS.data
	if not data then
		data = io.read("*a")
	end
	if not data or #data == 0 then
		myerror("No data")
	end
	local id = uuid()
	local fname = OPTS.dir .. repo .. "_" .. id .. ".txt"
	local fd = assert(io.open(fname, "w"))
	fd:write(data)
	fd:close()
end

local function pop_from()
	local repo = OPTS.pop_from
	check_repo(repo)
	local fd = io.popen("ls -Q -t "..OPTS.dir..repo.."_* 2>/dev/null")
	local txt = fd:read("*a")
	fd:close()
	local fns = {}
	for fn in txt:gmatch('"(.-)"') do
		table.insert(fns, fn)
	end
	local res = {}
	while true do
		local last = table.remove(fns)
		if not last then
			return res
		end
		local id = last:match("^.+/(.-)%.")
		print("id", id)
		print("last", last)
		local fd = io.open(last)
		print("fd", fd)
		if fd then
			local txt = fd:read("*a")
			fd:close()
			if OPTS.autoremove then
				remove(id)
			end
			if txt and #txt>0 then
				table.insert(res, {id = id, data = txt})
				if not OPTS.all then
					return res
				end
			end
		end
	end
end

local function main()
	_G.OPTS = parse_options({"dir", "push_to", "data", "pop_from", "remove", "autoremove", "no_id", "all", "purge_repo"})
	OPTS.dir = OPTS.dir or "/tmp/fuxoft_pusher/"
	if not OPTS.dir:match("/$") then
		OPTS.dir = OPTS.dir .. "/"
	end
	os.execute("mkdir -p "..OPTS.dir)

	if OPTS.push_to then
		push_to()
		print("OK")
	elseif OPTS.remove then
		remove(OPTS.remove)
		print("OK")
	elseif OPTS.pop_from then
		local res = pop_from()
		if not next(res) then
			print("OK")
		else
			for i, pop in ipairs(res) do
				print("ITEM")
				print("DATA")
				print(#pop.data)
				io.write(pop.data)
				if not OPTS.no_id then
					print("ID")
					print(pop.id)
				end
			end
			print("OK")
		end
	elseif OPTS.purge_repo then
		purge_repo()
		print("OK")
	else
		myerror("Don't know what to do.")
	end
end

main()