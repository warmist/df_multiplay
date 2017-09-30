--TODO
--[[
function spawn_mob()
	if npc_spawn then
		local x,y,z=get_valid_unit_pos(npc_spawn)
		if x then
			df.global.world.arena_spawn.side=66
			clear_items()
			local create_unit=dfhack.script_environment('modtools/create-unit')
			printd("Spawning mob:",x,y,z)
			local u_id=create_unit.createUnit(576,math.random(0,1),{x,y,z}) --TODO more customization?
			local u=df.unit.find(u_id)
		end
	end
end
function count_mobs()
	local count=0
	for i,v in ipairs(df.global.world.units.active) do
		if not v.flags1.dead and v.enemy.enemy_status_slot==66 then
			count=count+1
		end
	end
	return count
end
local m_count=count_mobs()
		--print("Count:",m_count,SPAWN_MOBS)
		if m_count<SPAWN_MOBS then
			spawn_mob()
		end
]]