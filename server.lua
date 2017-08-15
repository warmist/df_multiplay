-- this requires a plugin that draws the map: https://github.com/warmist/dfhack/tree/twbt_experiments
--[[
	Ideas for future:
		microtransactions (for rooms and stuff :D) jkjk
		assignment to locations (e.g. performance etc)
			see if idle location can be used for direct dwarf control
		more info about dwarf
			possesions (with a way to add/remove them)
				rooms
				artifacts
				weapons etc...
			thoughts
				maybe add a way to modify thoughts?
		cheats and hacks like:
			make a dwarf punch someone
			teleport for stuck dwarves
			arena mode fights (buy stuff for dwarf and see it battle)
]]
local sock=require 'plugins.luasocket'
local map=require 'plugins.screenshot-map'
local utils=require 'utils'
local debug=require 'debug'
local args={...}


local HOST="http://dwarffort.duckdns.org/"
local DEBUG=false
local FPS_LIMIT=50


if DEBUG then
	printd=function ( ... )
		print(...)
	end
else
	printd=function ()end
end

if port and (args[1]=="-r" or args[1]=="-s") then
	port:close()
	port=nil
end
if timeout_looper then
	dfhack.timeout_active(timeout_looper,nil)
end

if args[1]=="-s" then
	print("Shutting down")
	if clients then
		for k,v in pairs(clients) do
			k:close()
		end
	end
	return
end

local page_data={}
function load_page_data()
	local files={
		'intro',
		'outro',
		'welcome',
		'login',
		'cookie',
		'play',
		'del_user',
		'unit_select'
	}
	for i,v in ipairs(files) do
		local f=io.open('hack/scripts/http/'..v..'.html','rb')
		page_data[v]=f:read('all')
		f:close()
	end

	do
		local f=io.open('hack/scripts/http/favicon.png','rb')
		page_data.favicon=f:read('all')
		f:close()
	end
end
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
function fill_page_data( page_text,variables )
	function replace_vars( v )
		local vname=v:sub(3,-3)
		return tostring(variables[vname])
	end
	return page_text:gsub("(!![^!]+!!)",replace_vars)
end
load_page_data()
load_buyables()
users=users or {Test={name="Test",password="test"}}
unit_used=unit_used or {}
port=port or sock.tcp:bind(HOST,6666)
port:setNonblocking()

local clients={}
local pause_countdown=0
function make_redirect(loc)
	return "HTTP/1.1 302 Found\nLocation: "..HOST..loc.."\n\n"
end
function make_content(r)
	return string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Length: %d\r\n\r\n%s",#r,r)
end
function make_json_content( r )
	return string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s",#r,r)
end
function respond_err() --TODO: actual error page?
	return page_data.intro..fill_page_data(page_data.welcome,{hostname=HOST})..page_data.outro
end

function switch_labor(user,labor,value )
	labor=tonumber(labor)
	value=tonumber(value)
	local u=df.unit.find(user.unit_id)
	if u.status.labors[labor]~=nil then
		u.status.labors[labor]=value
	end
end
function switch_burrow( user,burrow,value )
	burrow=tonumber(burrow)
	value=tonumber(value)
	local u=df.unit.find(user.unit_id)
	local b=df.burrow.find(burrow)
	if u and b then
		dfhack.burrows.setAssignedUnit(b,u,value==1)
	end
end
function perform_commands(user, cmd )
	if cmd=="new_unit" then
		print("New unit for user:",user.name)
		local unit=pick_target()
		user={unit_id=unit.id}
	elseif cmd=="help" then
		return respond_help()
	elseif starts_with(cmd,"labor=") then
		switch_labor(user,cmd:match("labor=([^:]+):([01])"))
	elseif starts_with(cmd,"burrow=") then
		switch_burrow(user,cmd:match("burrow=([^:]+):([01])"))
	end
end
function respond_login()
	return page_data.intro..page_data.login..page_data.outro
end
function respond_cookie(cmd)
	if cmd.username==nil or cmd.username=="" then
		return page_data.intro.."Invalid user"..page_data.outro
	end
	local user=users[cmd.username]
	if user==nil then --create new user, if one does not exist
		users[cmd.username]={password=cmd.password,name=cmd.username}
		print("New user:"..cmd.username)
		user=users[cmd.username]
	elseif user.password~=cmd.password then --check password
		return page_data.intro.."Invalid password"..page_data.outro
	end
	user.name=cmd.username
	return fill_page_data(page_data.cookie,{username=cmd.username,password=cmd.password}) --set cookies
end
function get_user(cmd, cookies)
	if cookies.username==nil or cookies.username=="" or users[cookies.username]==nil or cookies.password~=users[cookies.username].password then
		return false,page_data.intro.."Invalid login"..page_data.outro
	end
	local user=users[cookies.username]
	return user
end
function get_unit( user )
	if user.unit_id==nil then
		return
	end

	local t=df.unit.find(user.unit_id)
	if t ==nil then
		return false,page_data.intro.."Sorry, your unit was lost somewhere... :("..page_data.outro
	end
	return t,user.unit_id
end
function respond_play( cmd,cookies )

	local user,err=get_user(cmd,cookies)
	if not user then return err end
	local t,err2=get_unit(user)
	if not t then
		return nil,make_redirect("new_unit")
	end

	local w=21
	local valid_variables={
		size=w,
		canvas_w=w*16,
		canvas_h=w*16,
	}

	return page_data.intro..fill_page_data(page_data.play,valid_variables)..page_data.outro
end
function server_unpause()
	pause_countdown=10
end
function json_str( v )
	if type(v)=="string" then
		return '"'..v..'"'
	elseif type(v)=="number" then
		return v
	elseif type(v)=="boolean" then
		return v
	elseif type(v)=="table" and v._is_array==nil then
		return json_pack_obj(v)
	elseif type(v)=="table" and v._is_array then
		return json_pack_arr(v,v._is_array)
	end
end
function json_pack_arr( t,start )
	local ret=""
	local comma=""
	for i=start,#t-(1-start) do
		ret=ret..string.format('%s%s\n',comma,json_str(t[i]))
		comma=','
	end
	return string.format("[%s]",ret)
end
function json_pack_obj( t)
	local ret=""
	local comma=""
	for k,v in pairs(t) do
		ret=ret..string.format('%s"%s":%s\n',comma,k,json_str(v))
		comma=','
	end
	return string.format("{%s}",ret)
end
function respond_json_map(cmd,cookies)

	local user,err=get_user(cmd,cookies)
	if not user then return "{}" end --TODO somehow report error?
	local t,err2=get_unit(user)
	if not t then return "{}" end --TODO somehow report error?
	--valid users unpause game for some time

	local delta_z=0
	if cmd.dz and tonumber(cmd.dz) then
		delta_z=tonumber(cmd.dz)
	end
	server_unpause()

	local w=21
	local m=map.render_map_rect(t.pos.x-w//2-1,t.pos.y-w//2-1,t.pos.z+delta_z,w,w)
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

	return '{"map":['..map_string..']}'
end
function respond_json_unit_info(cmd,cookies)
	local user,err=get_user(cmd,cookies)
	if not user then return '{"error":"Invalid user"}' end --TODO somehow report error?
	local unit,err2=get_unit(user)
	if not unit then return '{"error":"Invalid unit"}' end --TODO somehow report error?

	local uname=dfhack.df2utf(dfhack.TranslateName(unit.name))
	local prof=dfhack.units.getProfessionName(unit)
	local job
	if unit.job.current_job then
		job=dfhack.job.getName(unit.job.current_job)
	else
		job=""
	end
	local ret={}
	ret.name=uname
	ret.profession=prof
	ret.job=job
	ret.labors={_is_array=0}
	for i,v in ipairs(unit.status.labors) do
		--if df.unit_labor.attrs[i].caption~=nil then
			--ret.labors[df.unit_labor.attrs[i].caption]=v
		--end
		ret.labors[i]=v
	end
	ret.burrows={}
	for i,v in ipairs(df.global.ui.burrows.list) do
		local in_burrow_state=0
		if dfhack.burrows.isAssignedUnit(v,unit) then
			in_burrow_state=1
		end
		ret.burrows[v.name]={id=v.id,name=v.name,state=in_burrow_state}
	end
	return json_pack_obj(ret)
end
function respond_delete( cmd, cookies )
	local user,err=get_user(cmd,cookies)
	if not user then return page_data.intro.."Invalid user and/or login"..page_data.outro end

	if not cmd.do_delete then
		return page_data.intro.."Are you sure you want to <a href='delete?do_delete'> DELETE</a> your account?"..page_data.outro
	else
		if user.unit_id then
			unit_used[user.unit_id]=nil
		end
		users[cookies.username]=nil
		return fill_page_data(page_data.del_user,{username=cookies.username})
	end
end
function respond_new_unit(cmd,cookies)
	return page_data.intro..page_data.unit_select..page_data.outro
end
function get_valid_unit_pos(  )
	local mx,my,mz=dfhack.maps.getTileSize()
	local x,y,z
	for i=1,100 do
		x=math.random(0,mx-1)
		y=math.random(0,my-1)
		z=math.random(0,mz-1)
		if dfhack.maps.isValidTilePos(x,y,z) then
			local attrs = df.tiletype.attrs
			local tt=dfhack.maps.getTileType(x,y,z)
			local td,to=dfhack.maps.getTileFlags(x,y,z)
			if tt and td.flow_size==0 and attrs[tt].shape==df.tiletype_shape.FLOOR then
				return x,y,z
			end
		end
	end
end
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
function respond_actual_new_unit(cmd,cookies)
	local user,err=get_user(cmd,cookies)
	if not user then return err end

	if user.unit_id then --release old one if we have one
		unit_used[user.unit_id]=nil
		user.unit_id=nil
	end

	--TODO: this is actually unnecessary if we make javascript send normal id not id,cost
	local race
	if cmd.race_~=nil then
		race=cmd.race_:match("([^%%]+)") --remove "%C<STH>"
	end
	if race==nil or tonumber(race)==nil or unit_data[tonumber(race)]==nil then
		return page_data.intro.."Error: invalid race selected"..page_data.outro
	end
	local actual_race=unit_data[tonumber(race)]

	local x,y,z=get_valid_unit_pos()
	if not x then
		return page_data.intro.."Error: could not find where to place unit"..page_data.outro
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
				local count=1
				if item_t.type==df.item_type.AMMO then --hack for now...
					count=20
				end
				add_item({type=item_t.type,subtype=item_t.subtype,mat_type=mat_t.type,mat_index=mat_t.index,count=count})
			end
		end
	end
	--str = str:gsub('%W','')
	local create_unit=dfhack.script_environment('modtools/create-unit')
	print("New unit for user:",user.name, " unit race:",actual_race.race_raw.creature_id)
	local u_id=create_unit.createUnit(actual_race.race_id,actual_race.caste_id,{x,y,z})
	if not u_id then
		return page_data.intro.."Error: failed to create unit"..page_data.outro
	end

	if cmd.unit_name~=nil and cmd.unit_name~="" then
		cmd.unit_name=cmd.unit_name:gsub('%W','')
		local unit=df.unit.find(u_id)
		unit.name.first_name=cmd.unit_name
	end
	unit_used[u_id]=true
	user.unit_id=u_id
	df.global.ui.follow_unit=u_id

	return nil, make_redirect("play")
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
function respond_json_move( cmd,cookies )
	local user,err=get_user(cmd,cookies)
	if not user then return '{"error"="invalid_login"}' end
	local unit,err2=get_unit(user)
	if not unit then return  '{"error"="invalid_unit"}' end

	if unit.flags1.dead then return '{"error"="dead"}' end

	if not cmd.dx or not tonumber(cmd.dx) then return "{error='invalid_dx'}" end
	if not cmd.dy or not tonumber(cmd.dy) then return "{error='invalid_dy'}" end
	local dz=0
	if  cmd.dz and tonumber(cmd.dz) then dz=tonumber(cmd.dz) end

	local dx=tonumber(cmd.dx)
	local dy=tonumber(cmd.dy)
	local tx=unit.pos.x+dx
	local ty=unit.pos.y+dy
	unit.idle_area.x=tx
	unit.idle_area.y=ty
	--unit.idle_area_type=df.unit_station_type.Guard
	unit.idle_area_type=df.unit_station_type.DungeonCommander
	unit.idle_area_threshold=0

	if dfhack.maps.isValidTilePos(tx,ty,unit.pos.z) and dz==0 then
		local attrs = df.tiletype.attrs
		local tt=dfhack.maps.getTileType(tx,ty,unit.pos.z)
		local td,to=dfhack.maps.getTileFlags(tx,ty,unit.pos.z)
		--printall(attrs[tt])
		--print(df.tiletype_shape[attrs[tt].shape])
		if attrs[tt].shape==df.tiletype_shape.RAMP_TOP then --down is easy, just move down
			unit.idle_area.z=unit.pos.z-1
		elseif attrs[tt].shape==df.tiletype_shape.RAMP then --up is harder. Try stepping in same general direction...
			local sx,sy=dir_signs(dx,dy)
			unit.idle_area.x=unit.idle_area.x+sx
			unit.idle_area.y=unit.idle_area.y+sy
			unit.idle_area.z=unit.pos.z+1
			---???
		end
	else
		unit.idle_area.z=unit.pos.z+dz
	end

	return "{}"
end
function respond_json_unit_list(cmd, cookies)
	--{race=race_r,caste=caste_id,caste_raw=caste_raw,cost=tonumber(cost)}
	local ret="["
	local comma=''

	for i,v in ipairs(unit_data) do
		ret=ret..string.format('%s\n{"race":"%s","caste":"%s","name":"%s","cost":%d}',comma,v.race_raw.creature_id,v.caste_raw.caste_id,v.race_raw.name[0],v.cost)
		comma=','
	end
	return ret.."]"
end
function respond_json_combat_log(cmd,cookies)
	--TODO: could ddos? find might be slow
	local C_DEFAULT_LOGSIZE=20
	local C_MAX_LOGSIZE=100

	local user,err=get_user(cmd,cookies)
	if not user then return "{error='invalid_login'}" end
	local unit,err2=get_unit(user)
	if not unit then return  "{error='invalid_unit'}" end
	local log=unit.reports.log.Combat

	local last_seen
	if cmd.last_seen==nil or tonumber(cmd.last_seen)==nil then
		last_seen=#log-C_DEFAULT_LOGSIZE
	else
		last_seen=tonumber(cmd.last_seen)
	end
	local reports = df.global.world.status.reports
	if last_seen<0 then last_seen=0 end
	if last_seen>#log or  #log-last_seen>C_MAX_LOGSIZE then
		last_seen=#log-C_DEFAULT_LOGSIZE
	end
	--print("Final last_seen:",last_seen)

	local ret=string.format('{"current_count":%d,"log":[',#log)
	local comma=''
	if #log>0 then
		for i=last_seen,#log-1 do
			local report=df.report.find(log[i])
			if report then
			local text=report.text
				text=text:gsub('"','')
				ret=ret..string.format('%s"%s"\n',comma,text)
				comma=','
			end
		end
	end
	return ret.."]}"
end
function respond_json_materials( cmd,cookies )
	local ret="["
	local comma=''

	for i,v in ipairs(mat_data) do
		ret=ret..string.format('%s\n{"name":"%s","cost":%g}',comma,v.name,v.cost)
		comma=','
	end
	return ret.."]"
end
function respond_json_items( cmd,cookies )
	local ret="["
	local comma=''

	for i,v in ipairs(item_data) do
		ret=ret..string.format('%s\n{"name":"%s","cost":%g}',comma,v.name,v.cost)
		comma=','
	end
	return ret.."]"
end
function respond_json_kills( cmd,cookies )
	local ret="["
	local comma=''

	for i,v in ipairs(df.global.world.units.active) do
		local hf_id=v.hist_figure_id
		local kills=0
		if hf_id~=-1 then
			local hf=df.historical_figure.find(hf_id)
			if hf.info and hf.info.kills then
				for i,v in ipairs(hf.info.kills.killed_count) do
					kills=kills+v
				end
			end
		end
		ret=ret..string.format('%s\n{"name":"%s","kills":%d}',comma,v.name.first_name,kills)
		comma=','
	end
	return ret.."]"
end
function responses(request,cmd,cookies)
	--------------------MISC RESPONSES
	local table_misc={
		["favicon.ico"]=function() return page_data.favicon end,
		fake_error=function () error("inside responses") end
	}

	local tm=table_misc[request]
	if tm then
		return tm(cmd,cookies)
	end
	--------------------JSON RESPONSES
	local table_json={
	map=respond_json_map,
	move_unit=respond_json_move,
	get_unit_list=respond_json_unit_list,
	get_report_log=respond_json_combat_log,
	get_materials=respond_json_materials,
	get_items=respond_json_items,
	get_kills=respond_json_kills,
	get_unit_info=respond_json_unit_info,
	}

	local tj=table_json[request]
	if tj then
		return nil,make_json_content(tj(cmd,cookies))
	end
	--------------------PAGE RESPONSES
	local table_page={
	login=respond_login,
	dologin=respond_cookie,
	play=respond_play,
	delete=respond_delete,
	new_unit=respond_new_unit,
	submit_new_unit=respond_actual_new_unit,
	}

	local tp=table_page[request]
	if tp then
		return tp(cmd,cookies)
	end
	--------------------INVALID AND HOME PAGE
	if request~="" and request~=nil then
		print("Invalid request happened:",request)
		printd("cmd:",cmd)
	end
	return respond_err()
end
function parse_cookies( text )
	local ret={}
	for entry in text:gmatch("([^;]*);? ?") do
		local k,v=entry:match("([^=]*)=([^ %c]*)")
		if k and v then
			ret[k]=v
		end
	end
	return ret
end
function parse_content( other )
	--printd("Content:"..other)
	if other~=nil then
		local command={}
		other=other:gsub("%%20"," ")--drop '?' and fix spaces
		for i in string.gmatch(other, "[^ &]+") do

   			local eq=string.find(i,"=")

   			if eq then
   				local name=string.sub(i,1,eq-1)
   				if name:sub(-6)=="%5B%5D" then --"[]" means array
   					name=name:sub(1,-7)
   					command[name]=command[name] or {}
   					table.insert(command[name],string.sub(i,eq+1))
   				else
   					command[string.sub(i,1,eq-1)]=string.sub(i,eq+1)
   				end
   			else
   				command[i]=true
   			end
		end
		return command
	end
	
end
function parse_request( client )

	local s=client:receive() --FIXME: this crashed, need pcall?
	if s==nil then
		return false
	end
	printd(s)
	local is_post

	local path,other=s:match("GET /([^ ?]*)([^ ]*)")
	if path==nil and other==nil then
		path,other=s:match("POST /([^ ?]*)([^ ]*)")
		is_post=true
		other={}
	else
		other=parse_content(other:sub(2))
	end
	printd("CON:",path)

	local post_length=0
	while s do
		s=client:receive()
		if s then
			if s==string.char(13) then
				break
			end
			s=s:gsub(string.char(13),"")

			local c=s:match("Cookie: (.*)")
			if c then
				cookies=parse_cookies(c)
			end
			if is_post then
				local c=s:match("Content%-Length: (.*)")
				if c and tonumber(c) then
					post_length=tonumber(c)
				end
			end
		end
	end
	if is_post and post_length then
		printd("Post length:",post_length)
		if post_length~=0 then
			s=client:receive(post_length)
			if s then
				other=parse_content(s)
			end
		end
	elseif is_post and not post_length then
		print("Warning: post request without content length")
	end

	return true,path,other,cookies
end
function poke_clients()
	local removed_entries={}
	for k,v in pairs(clients) do

		function do_work()
			local ok,req,cmd,cookies=parse_request(k)
			if ok then
				local r,alt=responses(req,cmd,cookies)
				if r==nil and alt then
					k:send(alt)
				else
					k:send(make_content(r))
				end
				k:close()
				removed_entries[k]=true
			else
				k:close()
				removed_entries[k]=true
			end
		end
		local err_ok,err_msg=xpcall(do_work,debug.traceback)
		if not err_ok then
			print("+++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
			print("Internal error:",err_msg)
			pcall(k.send,k,"HTTP/1.0 500 Internal Error\r\nConnection: Close\r\n\r\n")
			pcall(k.close,k)
			print("+++++++++++++++++++++++++++++++++++++++++++++++++++++++++")
			removed_entries[k]=true
		end
	end
	for k,v in pairs(removed_entries) do
		clients[k]=nil
	end
end

function accept_connections(  )

	while port:select(0,1) do
		local c=port:accept()
		--print("Opened Connection")
		clients[c]=true
		c:setNonblocking()
	end
end
function event_loop()
	accept_connections()
	if pause_countdown>0 then
		df.global.pause_state=false
		pause_countdown=pause_countdown-1
	else
		df.global.pause_state=true
	end
	poke_clients()

	timeout_looper=dfhack.timeout(10,'frames',event_loop)
end
if FPS_LIMIT then
	df.global.enabler.fps=FPS_LIMIT
end
event_loop()