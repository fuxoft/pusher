#!/usr/bin/env luajit
--Pusher
--fuka@fuxoft.cz

_G.VERSION = ([[*<= Version '20181005d' =>*]]):match("'(.+)'")
_G.SOCKET = require ("socket.unix")

local function clear_db()
	_G.DB = {channels={}}
end

local function log(str)
	print(os.date()..":",tostring(str))
end

clear_db()

local function parse_options(args, allowed)
	if not args then
		args = arg
	else
		assert(type(args) == "string")
		local a0 = args
		args = {}
		for a in (a0.."|"):gmatch("(.-)|") do
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
	local server = assert(SOCKET())
	local bind, err = server:bind(pars.socket)
	if err then
		if err:match("ddress already in use") then --Try removing used socket and tretry bind
			os.execute("rm -f "..pars.socket)
			server = assert(SOCKET())
			bind = assert(server:bind(pars.socket))
		else
			error(err)
		end
	end
	assert(server:listen())
	--server:settimeout(2)
	return server
end

local function accept(pars)
	local server = assert(pars.server)
	local client, err = server:accept()
	if not client then
		return nil, "Cannot start server: "..err
	end
	client:settimeout(1)

	local header, err = client:receive()
	if err then
		return nil, "Header receive error: "..err
	end

	return {client = client, header = header}
end

local function sock_error(text)
	local msg = "ERROR: "..text
	local client = assert(CONN.client)
	client:send(msg.."\n")
	client:close()
end

local function sock_response(text)
	if type(text) == "table" then
		text = table.concat(text, "\n")
	end
	local client = assert(CONN.client)
	client:send(text.."\n")
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

	local server = assert(create_server({socket=OPTIONS.socket}))

	while true do
		DB.changed = nil
		local conn, err = accept({server=server})
		if not conn then
			log("Header accept Error: "..err)
		else
			_G.CONN = conn
			--print("header:", conn.header)
			if #(CONN.header or "") == 0 then
				sock_error("Empty request")
			else
				pars, err = parse_options(CONN.header, {"unique_id", "channel", "push", "get", "all", "autodelete", "delete", "no_id", "no_age", "purge_channel", "message", "length", "quit", "reset"})
				if not pars then
					sock_error(err)
				else
					CONN.parameters = pars
					if type(pars.channel) ~= "string" then
						pars.channel = "default"
					end
					if not pars.channel:match("^[%w_]*$") then
						sock_error("Invalid channel id: "..tostring(pars.channel))
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
							sock_response("DONE")
						elseif pars.unique_id then
							local id = unique_id()
							sock_response({"ID",id,"DONE"})
						elseif pars.purge_channel then
							DB.channels[pars.channel] = nil
							DB.changed = true
							sock_response("DONE")
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
							sock_response(result)
						elseif pars.push then
							if not pars.message then
								local len = CONN.client:receive() or "?"
								len = math.floor(tonumber(len) or 0)
								if len > 0 then
									pars.message = CONN.client:receive(len) or ""
								end
							end
							if not (pars.message and #pars.message > 0) then
								sock_error("Message body not present or empty")
							else
								local msg = push_message()
								local reply = {}
								if not pars.no_id then
									reply = {"ID",msg.id}
								end
								table.insert(reply, "DONE")
								sock_response(reply)
							end
						elseif pars.quit=="yes_please" then
							log("User requested quit")
							sock_response("DONE")
							os.exit()
						elseif pars.reset=="yes_please" then
							log("User requested database reset")
							clear_db()
							DB.changed = true
							sock_response("DONE")
						else
							sock_error("Don't know what to do.")
						end
						--END handling of request. Each branch above is responsible for client:close()
					end
				end
			end
		end
		if OPTIONS.persistent and DB.changed then
			DB.changed = nil
			save_db()
		end
	end
end

local function main0()
	_G.OPTIONS = parse_options(nil, {"socket", "persistent"})
	if OPTIONS.persistent then
		assert(type(OPTIONS.persistent)=="string", "'persistent' value must be a filename")
	end
	OPTIONS.socket = OPTIONS.socket or "/tmp/pusher_socket"
	::main_loop::
	local stat, err = pcall(main)
	if not stat then
		print("*** Error: "..err)
		local wait = 5
		print("Restarting in "..wait.." seconds")
		assert(os.execute("sleep "..wait)==0)
		goto main_loop
	end
	error("WTF are we doing down here?")
end

main0()