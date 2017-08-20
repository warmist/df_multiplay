local core=require'hack.scripts.http.core'
reload'hack.scripts.http.core'

local args={...}
local FPS_LIMIT=50
--[[
	TODO:
		* change game mode should stop the server
]]

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

if not server then
	server=core:server{users=users}
end

local map=require'hack.scripts.http.map'
reload'hack.scripts.http.map'
server:install_plugin(map.plug{})

local spectate=require'hack.scripts.http.spectate'
reload'hack.scripts.http.spectate'
server:install_plugin(spectate.plug{})

local messages=require'hack.scripts.http.messages'
reload'hack.scripts.http.messages'
server:install_plugin(messages.plug{})
server.page_vars.message_of_the_day="Experimenting with new server..."

local commands=require'hack.scripts.http.commands'
reload'hack.scripts.http.commands'
server:install_plugin(commands.plug{})

server.page_vars.message_of_the_day="Experimenting with new server..."

if df.global.gametype==df.game_type.DWARF_ARENA or df.global.gametype==df.game_type.ADVENTURE_ARENA then
	local economy=require'hack.scripts.http.economy'
	reload'hack.scripts.http.economy'
	server:install_plugin(economy.plug{})
else
	error("This mode is not supported")
end

if FPS_LIMIT then
	df.global.enabler.fps=FPS_LIMIT
end

server:start()