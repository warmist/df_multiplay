local _ENV=mkmodule('hack.scripts.http.map')
local core=require 'hack.scripts.http.core'
local map=require 'plugins.map-render'
local utils=require 'utils'

function json_map(x,y,z,w,h)
	local m=map.render_map_rect(x,y,z,w,h)
	local line=0
	local map_string=""
	for i=0,#m,4 do
		line=line+1
		local comma
		if i~=#m-3 then --omit last comma
			comma=','
		else
			comma=''
		end
		map_string=map_string..string.format("[%d, %d, %d, %d]%s",m[i],m[i+1],m[i+2],m[i+3],comma)
		if line==w then
			line=0
			map_string=map_string.."\n"
		end
	end
	return '['..map_string..']'
end
function table_map( x,y,z,w,h )
	local m=map.render_map_rect(x,y,z,w,h)
	local ret={_is_array=1}
	for i=0,#m,4 do
		table.insert(ret,{_is_array=1,m[i],m[i+1],m[i+2],m[i+3]})
	end
	return ret
end
local function respond_json_map(server,cmd,cookies,user,unit)
	local delta_z=0
	if cmd.dz and tonumber(cmd.dz) then
		delta_z=tonumber(cmd.dz)
	end
	server:unpause()

	local w=21
	return json_map(unit.pos.x-w//2-1,unit.pos.y-w//2-1,unit.pos.z+delta_z,w,w)
end
local function respond_json_map_spectate(server,cmd,cookies)
	local w=21
	if not cmd.x or not tonumber(cmd.x) then return "{error='invalid_x'}" end
	if not cmd.y or not tonumber(cmd.y) then return "{error='invalid_y'}" end
	if not cmd.z or not tonumber(cmd.z) then return "{error='invalid_z'}" end
	local x=tonumber(cmd.x)
	local y=tonumber(cmd.y)
	local z=tonumber(cmd.z)

	if server.spectate_unpauses then --FIXME: plugin.var...
		server:unpause()
	end

	return json_map(x,y,z,w,w)
end
function find_all_items(item_list,pos)
	local vec=df.global.world.items.all
	local last_min=-1
	local ret={}
	for i,v in ipairs(item_list) do
		local item,found,vector_pos=utils.binsearch(vec,v,'id',nil,last_min,#vec)
		if not found then
			return ret
		end
		if not pos then
			table.insert(ret,item)
		else
			if item.pos.x==pos.x and item.pos.y==pos.y and item.pos.z==pos.z then
				table.insert(ret,item)
			end
		end
		last_min=vector_pos
	end
	return ret
end
function list_items( pos )
	local td,to=dfhack.maps.getTileFlags(pos)
	if not to.item then
		return {}
	end
	local block=dfhack.maps.getTileBlock(pos)
	return find_all_items(block.items,pos)
end
function respond_json_look_items( server,cmd,cookies,user,unit )

	local dx,dy,dz
	if cmd.dx and tonumber(cmd.dx) then dx=tonumber(cmd.dx) else dx=0 end
	if cmd.dy and tonumber(cmd.dy) then dy=tonumber(cmd.dy) else dy=0 end
	if cmd.dz and tonumber(cmd.dz) then dz=tonumber(cmd.dz) else dz=0 end

	local tx=unit.pos.x+dx
	local ty=unit.pos.y+dy
	local tz=unit.pos.z+dz
	
	local items=list_items({x=tx,y=ty,z=tz})
	local ret={}
	for i,v in ipairs(items) do
		table.insert(ret,{name=dfhack.items.getDescription(v,0),id=v.id})
	end
	return core.json_pack_arr(ret)
end
function respond_gamestate(server, plug, req, state, hidden)
	local unit=hidden.unit
	if unit ==nil then
		state.map=nil
		return false
	end
	local delta_z=0
	if req.dz and tonumber(req.dz) then
		delta_z=tonumber(req.dz)
	end
	server:unpause()


	local w=21
	state.map=table_map(unit.pos.x-w//2-1,unit.pos.y-w//2-1,unit.pos.z+delta_z,w,w)

	return true
end
serv_map=defclass(serv_map,core.serv_plugin)
serv_map.ATTRS={
	expose_json={
		map={data=respond_json_map,needs_unit=true,needs_user=true},
		map_spectate={data=respond_json_map_spectate},
		look_items={data=respond_json_look_items,needs_unit=true,needs_user=true},
	},
	spectate_unpauses=false,
	gamestate_hook=respond_gamestate,
	name="map",
}
plug=serv_map
return _ENV