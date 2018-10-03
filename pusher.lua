#!/usr/bin/env luajit
--Pusher
--fuka@fuxoft.cz

_G.VERSION = ([[*<= Version '20181001a' =>*]]):match("'(.+)'")
_G.SOCKET = require("socket")
_G.DB = {channels={}}

local function log(str)
	print(os.date()..":",tostring(str))
end

local function parse_options(args, allowed)
	if not args then
		args = arg
	else
		assert(type(args) == "string")
		local a0 = args
		args = {}
		for a in (a0..","):gmatch("(.-),") do
			table.insert(args, a)
		end
	end

	for i, opt in ipairs(allowed) do
		allowed[opt] = true
	end

	local opts = {}
	for i, arg in ipairs(args) do
		if arg:match("=") then
			local opt, val = arg:match("(.-)=(.+)")
			if not (opt and val and #opt > 0 and #val > 0) then
				return nil, "Invalid option syntax: "..arg
			end
			opts[opt] = val
		else
			opts[arg] = true
		end
	end
	for k,v in pairs(opts) do
		if not allowed[k] then
			return nil, ("Invalid option: "..k.."="..tostring(v))
		end
	end

	return opts
end

local function unique_id()
	if not DB.uid then
		DB.uid = {}
	end
	local uid = DB.uid

	local function increment(d)
		if not uid[d] then
			uid[d]=1
			return
		end
		uid[d] = uid[d] + 1
		if uid[d] >= 62 then
			uid[d] = 0
			increment(d + 1)
		end
	end

	increment(1)
	local chrs = {}
	-- print("nums", table.concat(uid, ", "))
	for i = #uid, 1, -1 do
		local b = uid[i]
		if b <=9 then
			table.insert(chrs, tostring(b))
		elseif b <= 35 then -- 10 - 35
			table.insert(chrs, string.char(87 + b))
		else -- 36 - 61
			table.insert(chrs, string.char(29 + b))
		end
	end

	DB.changed = true
	return table.concat(chrs)
end

local function create_server(pars)
	local server = assert(SOCKET.bind("localhost", assert(pars.port)))
	--server:setoption("reuseaddr", true)
	local ip, port = server:getsockname()
	--server:settimeout(2)
	return server
end

local function accept(pars)
	local server = assert(pars.server)
	local client = server:accept()
	if not client then
		return nil, "Cannot start client"
	end
	client:settimeout(1)
	local p_addr, p_port = client:getpeername()
	if p_addr == "127.0.0.1" then
		local headers = {}
		repeat
			local line, err = client:receive()
			if err then
				return nil, "Header receive error"
			end
			print("Header: "..line)
			if not headers[1] then
				headers[1] = line
			else
				local key, val = line:match("^(.-): (.+)$")
				if key and val then
					headers[key:lower()] = val
				end
			end
		until line == ""
		local result = {headers = headers, client = client}
		local bodylen = tonumber(headers["content-length"])

		if bodylen then
			--print("bodylen", bodylen)
			local body, err = client:receive(bodylen)
			if not body then
				return nil, err.." (body)"
			end
			result.body = body
		end
		return result
		--[[
		client:send("HTTP/1.1 200 OK\r\n\r\n")
		local bodylen = tonumber(headers["content-length"])

		if bodylen then
			local body, err = client:receive(bodylen)
			if not body then
				return nil, err
			end
			client:send("AHOJ"..math.random().."\r\n")
			client:send("Got body bytes: "..#body.."\r\n")
		end
		client:send("--BYE--\r\n")
		print("Closing")
		client:close()
		]]
	else
		client:close()
		return nil, "Blocked connection attempt from "..p_addr
	end
end

local function format_response(tbl)
	return table.concat(tbl, "\r\n").."\r\n"
end

local function http_error(text)
	local client = assert(CONN.client)
	local msg = {"HTTP/1.1 400 Bad Request","","ERROR: "..text}
	client:send(format_response(msg))
	client:close()
end

local function http_response(text)
	if type(text) == "table" then
		text = table.concat(text, "\r\n")
	end
	local client = assert(CONN.client)
	local msg = {"HTTP/1.1 200 OK","",text}
	client:send(format_response(msg))
	client:close()
end

local function get_messages()
	local channel = assert(CONN.parameters.channel)
	local msgs = DB.channels[channel]
	if not msgs then
		msgs = {}
	end
	if not msgs[1] then
		return nil
	end
	if CONN.parameters.all then
		if CONN.parameters.autodelete then
			DB.channels[channel] = nil
			DB.changed = true
		end
		return msgs
	end
	--get Single message
	local msg = msgs[1]
	if CONN.parameters.autodelete then
		table.remove(msgs,1)
		DB.changed = true
		if not msgs[1] then
			DB.channels[channel] = nil
		end
	end
	return {msg}
end

local function push_message()
	local channel = assert(CONN.parameters.channel)
	local body = assert(CONN.parameters.message)
	if not DB.channels[channel] then
		DB.channels[channel] = {}
	end
	local uid = unique_id()
	local ch = DB.channels[channel]
	local msg = {body = body, id = uid, time = os.time()}
	table.insert(ch, msg)
	DB.changed = true
	while #ch > 100 do
		table.remove(ch, 1)
	end
	return msg
end

local savers = {
	boolean = tostring,
	number = tostring,
	string = function(str)
		return string.format("%q", str)
	end,
	["function"] = function (x)
		error("Trying to save function")
	end
}

local function save_db()
	local fname = assert(OPTIONS.persistent)
	local result = {}
	local function add(str)
		table.insert(result, str)
	end
	local function save_something(x)
		if type(x) == "table" then
			add("{")
			for k, v in pairs(x) do
				--print("save table ", tostring(k), tostring(v))
				add('[')
				add(save_something(k))
				add(']=')
				add(save_something(v))
				add(", ")
			end
			add("}")
		else
			add(savers[type(x)](x))
		end
	end
	add("local all = ")
	local channels = DB.channels
	DB.channels = nil
	save_something(DB)
	add("\nlocal channels = ")
	add("{")
	for chid, ch in pairs(channels) do
		add("\n[")
		save_something(chid)
		add("]={")
		for i, msg in ipairs(ch) do
			add(string.format("{id='%s',time=%s,body=%q}, ", msg.id, msg.time, msg.body))
		end
		add("},")
	end
	add("\n}")
	add("\nall.channels = channels\nreturn all")
	DB.channels = channels
	local fd = assert(io.open(fname, "w"))
	fd:write(table.concat(result))
	fd:close()
end

local function main()
	log("Pusher starting, v. "..VERSION)
	if OPTIONS.persistent then
		local fd = io.open(OPTIONS.persistent)
		if fd then fd:close()
			DB = dofile(OPTIONS.persistent)
			log("Database restored from "..OPTIONS.persistent)
		else
			save_db()
			log("New database created: "..OPTIONS.persistent)
		end
	end

	local server = assert(create_server({port=OPTIONS.port}))

	while true do
		DB.changed = nil
		local conn, err = accept({server=server})
		if not conn then
			log("Accept Error: "..err)
		else
			_G.CONN = conn
			--[[
			for k,v in pairs (CONN.headers) do
				print(k, v)
			end
			--]]
			local pars = CONN.headers[1]:match("^.- /(.+) HTTP/%d%.%d")
			if pars and #pars > 1 then
				pars, err = parse_options(pars, {"unique_id", "channel", "push", "get", "all", "autodelete", "delete", "no_id", "no_age", "purge_channel", "download", "message", "quit"})
				if not pars then
					http_error(err)
				else
					CONN.parameters = pars
					if type(pars.channel) ~= "string" then
						pars.channel = "default"
					end
					if not pars.channel:match("^[%w_]*$") then
						http_error("Invalid channel id: "..tostring(pars.channel))
					else
						--HERE WE GO
						if pars.delete then
							local id = pars.delete
							for chid, ch in pairs(DB.channels) do
								for i, msg in ipairs(ch) do
									if msg.id == id then
										table.remove(ch, i)
										DB.changed = true
										goto delete_done
									end
								end
							end
							::delete_done::
							http_response("DONE")
						elseif pars.unique_id then
							local id = unique_id()
							http_response(id)
						elseif pars.purge_channel then
							DB.channels[pars.channel] = nil
							DB.changed = true
							http_response("DONE")
						elseif pars.get then
							local msgs = get_messages() or {}
							--print("messages got:", #msgs)
							local result = {}
							local time0 = os.time()
							for _i, msg in ipairs(msgs) do
								table.insert(result, "MESSAGE")
								table.insert(result, #msg.body)
								table.insert(result, msg.body)
								if not pars.no_id then
									table.insert(result, "ID")
									table.insert(result, msg.id)
								end
								if not pars.no_age then
									table.insert(result, "AGE")
									table.insert(result, time0 - msg.time)
								end
							end
							table.insert(result, "DONE")
							http_response(result)
						elseif pars.download then
							pars.all = nil
							pars.autodelete = true
							local msgs = get_messages()
							if not msgs then
								--CONN.client:send("HTTP/1.1 404 Not Found\r\n\r\nNo message in channel "..pars.channel.."\r\n")
								CONN.client:send("HTTP/1.1 404 No message in channel '"..pars.channel.."'\r\n\r\n")
								CONN.client:close()
							else
								assert(not msgs[2])
								CONN.client:send("HTTP/1.1 200 OK\r\nContent-Length: "..#msgs[1].body.."\r\n\r\n"..msgs[1].body)
								CONN.client:close()
							end
						elseif pars.push then
							if not pars.message then
								pars.message = CONN.body
							end
							if not (pars.message and #pars.message > 0) then
								http_error("Message body not present or empty")
							else
								local msg = push_message()
								local reply = {}
								if not pars.no_id then
									reply = {"ID",msg.id}
								end
								table.insert(reply, "DONE")
								http_response(reply)
							end
						elseif pars.quit=="yes_please" then
							log("User requested quit")
							http_response("DONE")
							os.exit()
						else
							http_error("Don't know what to do.")
						end
						--END handling of request. Each branch above is responsible for client:close()
					end
				end
			else
				http_error("Invalid HTTP request: "..CONN.headers[1])
			end
		end
		if OPTIONS.persistent and DB.changed then
			DB.changed = nil
			save_db()
		end
	end
end

local function main0()
	_G.OPTIONS = parse_options(nil, {"port", "persistent"})
	OPTIONS.port = OPTIONS.port or 8000
	::main_loop::
	local stat, err = pcall(main)
	if not stat then
		print("*** Error: "..err)
		local wait = 5
		print("Restarting in "..wait.." seconds")
		assert(os.execute("sleep "..wait)==0)
		goto main_loop
	end
end

main0()