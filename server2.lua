local core=require'hack.scripts.http.core'
reload'hack.scripts.http.core'

local args={...}
local FPS_LIMIT=50
--[[
	TODO:
		* change game mode should stop the server
		* saving/loading users
]]
local is_restart=false
if args[1]=="-r" and server then
	server:stop()
	is_restart=true
elseif args[1]=='-s' and server then
	server:stop()
	return
elseif args[1]=='-k' and server then
	print("Deleting server data")
	server:stop()
	server=nil
	return
end

if not server then
	server=core:server{}
end
server:load_users()
function inst_plug( name, do_reload,args)
	local plug=require('hack.scripts.http.'.. name)
	if do_reload then
		reload('hack.scripts.http.'.. name)
	end
	server:install_plugin(plug.plug(args or {}))
end
local general_plugs={
	'map',
	'messages',
	'commands',
	'spectate',
}
for i,v in ipairs(general_plugs) do
	inst_plug(v,is_restart)
end

server.page_vars.message_of_the_day="Arena mode running"

if df.global.gametype==df.game_type.DWARF_ARENA or df.global.gametype==df.game_type.ADVENTURE_ARENA then
	inst_plug('economy',is_restart,{server=server})
elseif df.global.gametype==df.game_type.DWARF_MAIN or df.global.gametype==DWARF_RECLAIM or df.global.gametype==DWARF_UNRETIRE then
	inst_plug('possession',is_restart,{server=server})
else
	error("This mode is not supported")
end


if FPS_LIMIT then
	df.global.enabler.fps=FPS_LIMIT
end

server:start()