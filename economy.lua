local _ENV=mkmodule('hack.scripts.http.economy')

local core=require 'hack.scripts.http.core'
local utils=require 'utils'
local printd=core.printd
--[[
	Economy plugin into server
		Gives access to buying units, items, gaining money through kills
]]
local USE_MONEY=true
local KILL_MONEY=5
local unit_data={}
function find_caste( race_raw,caste_name )
	for i,v in ipairs(race_raw.caste) do
		if v.caste_id==caste_name then
			return i,v
		end
	end
end
local item_data={}
function parse_item_token( text )
	printd("Loading item:"..text)
	local t_s,rest=text:match("([^:]*):(.*)")
	if t_s==nil then return nil, "Invalid token" end
	if df.item_type[t_s]==nil then return nil, "Could not find:"..t_s end


	local cost
	local rest,cost=rest:match("([^%s]*)%s*(.*)")
	if cost==nil or tonumber(cost)==nil then return nil,"Invalid cost" end
	cost=tonumber(cost)

	local _,obj=utils.linear_index(df.global.world.raws.itemdefs.all,rest,"id")
	if obj==nil then return nil,"Invalid subtype:"..rest end

	local ret={type=df.item_type[t_s],subtype=obj.subtype,name=rest}

	return ret,cost
end
local mat_data={}
function parse_mat_token( text )
	printd("Loading mat:"..text)
	local t_s,cost=text:match("([^%s]*)%s*(.*)")
	if t_s==nil then return nil, "Invalid token" end
	local mat=dfhack.matinfo.find(t_s)
	if mat==nil then return nil,"Could not find material:"..t_s end

	if cost==nil or tonumber(cost)==nil then return nil,"Invalid cost" end
	cost=tonumber(cost)

	return mat,cost
end

function load_buyables()
	--flip the units raws
	local raw=df.global.world.raws.creatures.all
	local unit_raw={}
	for k,v in ipairs(raw) do
		unit_raw[v.creature_id]={raw=v,id=k}
	end
	--load units
	do
		local f=io.open('hack/scripts/http/unit_list.txt',rb)
		local line_num=1
		for l in f:lines() do
			local race,caste,cost=l:match("([^:]*):(%a*)%s*(.*)")
			if race==nil or caste==nil or cost==nil or tonumber(cost)==nil then
				print("Error parsing line:",line_num,race,caste,tonumber(cost))
			else
				if unit_raw[race]==nil then
					print("Could not find race:"..race)
				else
					local race_r=unit_raw[race].raw
					local race_id=unit_raw[race].id
					local caste_id,caste_raw=find_caste(race_r,caste)
					if caste_id==nil then print("Could not find caste:",caste, " for unit race:",race) else
						table.insert(unit_data,
							{
							race_raw=race_r,race_id=race_id,
							caste_id=caste_id,caste_raw=caste_raw,
							cost=tonumber(cost)
							})
					end
				end
			end
			line_num=line_num+1
		end
	end
	--load items
	do
		local f=io.open('hack/scripts/http/equipment.txt',rb)
		local line_num=1
		for l in f:lines() do
			if l:sub(1,1)~="#" then
				local item,cost=parse_item_token(l)
				if item==nil then
					print("Error parsing line:",line_num,"Err:",cost)
				else
					table.insert(item_data,{type=item.type,subtype=item.subtype,cost=cost,name=item.name})
				end
			end
			line_num=line_num+1
		end
	end
	--load materials
	do
		local f=io.open('hack/scripts/http/materials.txt',rb)
		local line_num=1
		for l in f:lines() do
			if l:sub(1,1)~="#" then
				local mat,cost=parse_mat_token(l)
				if mat==nil then
					print("Error parsing line:",line_num,"Err:",cost)
				else
					table.insert(mat_data,{type=mat.type,index=mat.index,subtype=mat.subtype,cost=cost,name=mat.material.state_name.Solid})
				end
			end
			line_num=line_num+1
		end
	end
end

function respond_new_unit(server,cmd,cookies)
	return fill_page_data(page_data.unit_select,{use_money=USE_MONEY})
end
local get_valid_unit_pos=core.get_valid_unit_pos
function add_item(item_def)
	local as=df.global.world.arena_spawn.equipment
	as.item_types:insert("#",item_def.type)
	as.item_subtypes:insert("#",item_def.subtype)
	as.item_materials.mat_type:insert("#",item_def.mat_type)
	as.item_materials.mat_index:insert("#",item_def.mat_index)
	as.item_counts:insert("#",item_def.count)
end
function clear_items()
	local as=df.global.world.arena_spawn.equipment
	as.item_types:resize(0)
	as.item_subtypes:resize(0)
	as.item_materials.mat_type:resize(0)
	as.item_materials.mat_index:resize(0)
	as.item_counts:resize(0)
end
function respond_actual_new_unit(cmd,cookies,user)

	if user.unit_id then --release old one if we have one
		server.unit_used[user.unit_id]=nil
		user.unit_id=nil
	end

	--TODO: this is actually unnecessary if we make javascript send normal id not id,cost
	local race
	if cmd.race_~=nil then
		race=cmd.race_:match("([^%%]+)") --remove "%C<STH>"
	end
	if race==nil or tonumber(race)==nil or unit_data[tonumber(race)]==nil then
		return "Error: invalid race selected"
	end
	local sum_cost=0
	local actual_race=unit_data[tonumber(race)]
	sum_cost=sum_cost+actual_race.cost
	local x,y,z

	if FORTMODE then
		x,y,z=get_valid_unit_pos(spawn_burrow)
	else
	 	x,y,z=get_valid_unit_pos()
	end

	if not x then
		return "Error: could not find where to place unit"
	end


	clear_items()
	if cmd.items then
		for i,v in ipairs(cmd.items) do
			local sp=utils.split_string(v,"%%2C")
			local item=tonumber(sp[1])
			local mat=tonumber(sp[2])
			--print(i,item,mat)
			if item==nil then
				print("Invalid item:"..v)
			elseif mat==nil then
				print("Invalid mat:"..v)
			elseif item_data[item]==nil then
				print("Item not found:"..v)
			elseif mat_data[mat]==nil then
				print("Mat not found:"..v)
			else
				local item_t=item_data[item]
				local mat_t=mat_data[mat]
				sum_cost=sum_cost+mat_t.cost*item_t.cost
				local count=1
				if item_t.type==df.item_type.AMMO then --hack for now...
					count=20
				end
				add_item({type=item_t.type,subtype=item_t.subtype,mat_type=mat_t.type,mat_index=mat_t.index,count=count})
			end
		end
	end
	sum_cost=math.floor(sum_cost)
	if USE_MONEY then
		user.money=user.money or 0
		if sum_cost>user.money then
			return "Error: not enough money"
		else
			user.money=user.money-sum_cost
		end
	end
	--str = str:gsub('%W','')
	df.global.world.arena_spawn.side=0
	
	print("New unit for user:",user.name, " unit race:",actual_race.race_raw.creature_id)
	local u_id
	if FORTMODE then
		u_id=create_unit.createUnitInFortCivAndGroup(actual_race.race_id,actual_race.caste_id,{x,y,z})
	else
		u_id=core.create_unit_simple(actual_race.race_id,actual_race.caste_id,{x=x,y=y,z=z})
	end
	if not u_id then
		return "Error: failed to create unit"
	end

	if cmd.unit_name~=nil and cmd.unit_name~="" then
		cmd.unit_name=cmd.unit_name:gsub('%W','')
		local unit=df.unit.find(u_id)
		unit.name.first_name=cmd.unit_name
	end
	server.unit_used[u_id]=user
	user.unit_id=u_id
	df.global.ui.follow_unit=u_id

	return nil, make_redirect("play")
end

function respond_json_unit_list(server, cmd, cookies)
	local ret="["
	local comma=''

	for i,v in ipairs(unit_data) do
		ret=ret..string.format('%s\n{"race":"%s","caste":"%s","name":"%s","cost":%d}',comma,
			v.race_raw.creature_id,v.caste_raw.caste_id,v.race_raw.name[0],v.cost)
		comma=','
	end
	return ret.."]"
end
function respond_json_materials(server, cmd, cookies )
	local ret="["
	local comma=''

	for i,v in ipairs(mat_data) do
		ret=ret..string.format('%s\n{"name":"%s","cost":%g}',comma,v.name,v.cost)
		comma=','
	end
	return ret.."]"
end
function respond_json_items(server, cmd, cookies )
	local ret="["
	local comma=''

	for i,v in ipairs(item_data) do
		ret=ret..string.format('%s\n{"name":"%s","cost":%g}',comma,v.name,v.cost)
		comma=','
	end
	return ret.."]"
end
function respond_json_user_info(server, cmd, cookies, user )
	local info={}
	info.money=user.money or 0
	return core.json_pack_obj(info)
end
function respond_json_kills(server, cmd,cookies )
	local ret="["
	local comma=''

	local kills={}
	for i,v in ipairs(df.global.world.incidents.all) do
		local killer=v.killer
		if killer~=-1 then
			kills[killer]=kills[killer] or 0
			kills[killer]=kills[killer]+1
		end
	end
	for k,v in pairs(kills) do
		local u=df.unit.find(k)
		ret=ret..string.format('%s\n{"name":"%s","kills":%d}',comma,u.name.first_name,v)
		comma=','
	end
	return ret.."]"
end
function respond_actual_new_unit(server,cmd,cookies,user)
	server.unit_used=server.unit_used or {}
	if user.unit_id then --release old one if we have one
		server.unit_used[user.unit_id]=nil
		user.unit_id=nil
	end

	--TODO: this is actually unnecessary if we make javascript send normal id not id,cost
	local race
	if cmd.race_~=nil then
		race=cmd.race_:match("([^%%]+)") --remove "%C<STH>"
	end
	if race==nil or tonumber(race)==nil or unit_data[tonumber(race)]==nil then
		return nil,"Invalid race selected"
	end
	local sum_cost=0
	local actual_race=unit_data[tonumber(race)]
	sum_cost=sum_cost+actual_race.cost
	local x,y,z=core.get_valid_unit_pos()

	if not x then
		return nil,"Could not find where to place unit"
	end

	clear_items()
	if cmd.items then
		for i,v in ipairs(cmd.items) do
			local sp=utils.split_string(v,"%%2C")
			local item=tonumber(sp[1])
			local mat=tonumber(sp[2])
			--print(i,item,mat)
			if item==nil then
				print("Invalid item:"..v)
			elseif mat==nil then
				print("Invalid mat:"..v)
			elseif item_data[item]==nil then
				print("Item not found:"..v)
			elseif mat_data[mat]==nil then
				print("Mat not found:"..v)
			else
				local item_t=item_data[item]
				local mat_t=mat_data[mat]
				sum_cost=sum_cost+mat_t.cost*item_t.cost
				local count=1
				if item_t.type==df.item_type.AMMO then --hack for now...
					count=20
				end
				add_item({type=item_t.type,subtype=item_t.subtype,mat_type=mat_t.type,mat_index=mat_t.index,count=count})
			end
		end
	end
	sum_cost=math.floor(sum_cost)
	if USE_MONEY then
		user.money=user.money or 0
		if sum_cost>user.money then
			return "Error: not enough money"
		else
			user.money=user.money-sum_cost
		end
	end

	df.global.world.arena_spawn.side=0

	print("New unit for user:",user.name, " unit race:",actual_race.race_raw.creature_id)
	local u_id=core.create_unit_simple(actual_race.race_id,actual_race.caste_id,{x=x,y=y,z=z})

	if not u_id then
		return nil,"Failed to create unit"
	end

	if cmd.unit_name~=nil and cmd.unit_name~="" then
		cmd.unit_name=cmd.unit_name:gsub('%W','')
		local unit=df.unit.find(u_id)
		unit.name.first_name=cmd.unit_name
	end
	server.unit_used[u_id]=user
	user.unit_id=u_id
	df.global.ui.follow_unit=u_id

	return nil,nil, core.make_redirect("play")
end
local new_unit_page=core.load_page('unit_select')
function respond_new_unit(server,cmd,cookies)
	return core.fill_page_data(new_unit_page,{use_money=USE_MONEY})
end
local play_page=core.load_page("play")
function respond_play( server,cmd,cookies,user )
	local unit,err2=server:get_unit(user)
	if not unit then
		return nil,nil,core.make_redirect("new_unit")
	end

	local w=21
	local valid_variables={
		size=w,
		canvas_w=w*16,
		canvas_h=w*16,
	}

	return core.fill_page_data(play_page,valid_variables)
end

function unit_death_callback(server, u_id )
	--print("Unit death:",u_id)
	local u=df.unit.find(u_id)
	if not u then print("WARN: unit not found!"); return end

	local inc_id=u.counters.death_id
	if inc_id==-1 then print("WARN: not dead unit called callback!") return end
	local killer=df.incident.find(inc_id).killer

	if server.unit_used[killer] then
		local user=server.unit_used[killer]
		if type(user)=='table' then --TODO: remove this @CLEANUP
			local money=user.money
			if money then
				user.money=money+KILL_MONEY
			else
				user.money=KILL_MONEY
			end
			printd("User:",user.name, " killed!")
		end
		--TODO: send message to player
	else
		--print("Killer is not used:",killer)
	end
end

serv_economy=defclass(serv_economy,core.serv_plugin)
serv_economy.ATTRS={
	expose_json={
		get_unit_list={data=respond_json_unit_list},
		get_materials={data=respond_json_materials},
		get_items={data=respond_json_items},
		get_kills={data=respond_json_kills},
		get_user_info={data=respond_json_user_info,needs_user=true},
	},
	expose_pages={
		play={data=respond_play,needs_user=true},
		new_unit={data=respond_new_unit,needs_user=true},
		submit_new_unit={data=respond_actual_new_unit,needs_user=true},
	},
	name="economy",
	server=DEFAULT_NIL,
}
function serv_economy:init(args)
	assert(self.server~=nil,"Server var needs to be set")
	self.server.unit_used=self.server.unit_used or {}
	load_buyables()
	local eventful=require 'plugins.eventful'
	eventful.onUnitDeath.multiplay=function(u_id) unit_death_callback(self.server,u_id) end
	eventful.enableEvent(eventful.eventType.UNIT_DEATH,100)
end
plug=serv_economy

return _ENV