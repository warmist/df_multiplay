local core=require'hack.scripts.http.core'
reload'hack.scripts.http.core'

local args={...}

if args[1]=="-r" and server then
	server:stop()
elseif args[1]=='-s' and server then
	server:stop()
	return
end

local users={} --TODO save/load users
if server then
	users=server.users
end

server=core:server{}
server.page_vars.message_of_the_day="Experimenting with new server..."
server:start()