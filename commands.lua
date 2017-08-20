local _ENV=mkmodule('hack.scripts.http.commands')

local core=require 'hack.scripts.http.core'
local jobs=require 'hack.scripts.http.jobs'

function respond_json_equip(server,cmd,cookies,user,unit)
	if not cmd.id or not tonumber(cmd.id) then return nil,"invalid_item_id" end

	local item=df.item.find(tonumber(cmd.id))
	if not item then return nil,"item_not_found" end

	local ret=jobs.pickup_equipment(unit,item)
	if not ret then return nil,"failed" end

	return "{}"
end
function respond_json_haul(server,cmd,cookies,user,unit)
	if not cmd.id or not tonumber(cmd.id) then return nil,"invalid_item_id" end

	local item=df.item.find(tonumber(cmd.id))
	if not item then return nil,"item_not_found" end

	local dx=item.pos.x-unit.pos.x
	local dy=item.pos.y-unit.pos.y
	local dz=item.pos.z-unit.pos.z
	if dx ~=0 or dy~=0 or dz~=0 then return nil,"item_too_far" end

	local ret=dfhack.items.moveToInventory(item,unit,0,0)
	if not ret then return nil,"failed" end
	return "{}"
end
function respond_json_drop_haul(server,cmd,cookies,user,unit)

	local item
	for i,v in ipairs(unit.inventory) do
		if v.mode==0 then
			item=v
			break
		end
	end
	if not item then return "no_item_hauled" end

	local ret=dfhack.items.moveToGround(item.item,copyall(unit.pos))
	if not ret then  return "failed_to_drop" end
	return "{}"
end
function dir_signs( dx,dy )
	local sx,sy
	sx=0
	sy=0
	if dx>0 then sx=1 end
	if dy>0 then sy=1 end
	if dx<0 then sx=-1 end
	if dy<0 then sy=-1 end
	return sx,sy
end
function respond_json_move( server,cmd,cookies,user,unit )

	if unit.flags1.dead then return nil,"dead" end

	if not cmd.dx or not tonumber(cmd.dx) then return nil,'invalid_dx' end
	if not cmd.dy or not tonumber(cmd.dy) then return nil,'invalid_dy' end
	local dz=0
	if  cmd.dz and tonumber(cmd.dz) then dz=tonumber(cmd.dz) end

	local dx=tonumber(cmd.dx)
	local dy=tonumber(cmd.dy)
	local tx=unit.pos.x+dx
	local ty=unit.pos.y+dy
	unit.idle_area.x=tx
	unit.idle_area.y=ty
	--unit.idle_area_type=df.unit_station_type.Guard
	--unit.idle_area_type=df.unit_station_type.DungeonCommander
	unit.idle_area_type=df.unit_station_type.SquadMove
	unit.idle_area_threshold=0

	--ramp fixup  TODO: could be plugin setting
	if dfhack.maps.isValidTilePos(tx,ty,unit.pos.z) and dz==0 then
		local attrs = df.tiletype.attrs
		local tt=dfhack.maps.getTileType(tx,ty,unit.pos.z)
		local td,to=dfhack.maps.getTileFlags(tx,ty,unit.pos.z)

		if attrs[tt].shape==df.tiletype_shape.RAMP_TOP then --down is easy, just move down
			unit.idle_area.z=unit.pos.z-1
		elseif attrs[tt].shape==df.tiletype_shape.RAMP then --up is harder. Try stepping in same general direction...
			local sx,sy=dir_signs(dx,dy)
			unit.idle_area.x=unit.idle_area.x+sx
			unit.idle_area.y=unit.idle_area.y+sy
			unit.idle_area.z=unit.pos.z+1
		end
	else
		unit.idle_area.z=unit.pos.z+dz
	end
	--invalidate old path
	unit.path.dest={x=unit.idle_area.x,y=unit.idle_area.y,z=unit.idle_area.z}
	unit.path.goal=88 --SQUAD STATION
	unit.path.path.x:resize(0)
	unit.path.path.y:resize(0)
	unit.path.path.z:resize(0)
	return "{}"
end

serv_commands=defclass(serv_commands,core.serv_plugin)
serv_commands.ATTRS={
	expose_json={
		--items
		haul_item={data=respond_json_haul,needs_user=true,needs_unit=true},
		drop_hauled_item={data=respond_json_drop_haul,needs_user=true,needs_unit=true},
		equip_item={data=respond_json_equip,needs_user=true,needs_unit=true},
		--movement
		move_unit={data=respond_json_move,needs_user=true,needs_unit=true},
	},

	name="commands",
}
plug=serv_commands

return _ENV