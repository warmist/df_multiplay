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
local args={...}



local HOST="http://dwarffort.duckdns.org/"
local DEBUG=false
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
function load_buyables()
	--flip the units raws
	local raw=df.global.world.raws.creatures.all
	local unit_raw={}
	for k,v in ipairs(raw) do
		unit_raw[v.creature_id]={raw=v,id=k}
	end
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
function fill_page_data( page_text,variables )
	function replace_vars( v )
		local vname=v:sub(3,-3)
		return tostring(variables[vname])
	end
	return page_text:gsub("(!![^!]+!!)",replace_vars)
end
load_page_data()
load_buyables()
users=users or {}
unit_used=unit_used or {}
port=port or sock.tcp:bind(HOST,6666)
port:setNonblocking()

local clients={}
local pause_countdown=0

function get_window(x,y,z,w,h ) --maybe a fallback method?
	local ret={}
	local s=df.global.gps.screen
	local ww=df.global.gps.dimx
	local wh=df.global.gps.dimy
	local i=0
	for yy=y,y+h-1 do
	for xx=x,x+w-1 do
		local t=xx*wh+yy
		for j=0,3 do
			ret[i]=s[t*4+j]
			i=i+1
		end
	end
	end
	return ret
end
function pick_unused_target()
	local u=df.global.world.units.active
	if #u==0 then
		return
	end
	local count=0
	local id
	while id==nil and count<100 do
		id=math.random(0,#u-1)
		if unit_used[id] then
			id=nil
		elseif not u[id] or u[id].flags1.dead then
			id=nil
		else
			--check if unit is civ?
			return u[id],u[id].id
		end
		count=count+1
	end
	return id
end
local HTML_HEAD=[==[<html><head><meta charset="utf-8"/><style>
body{
	font-family: monospace; 
	background-color: #000000;
	margin:0px;
	color: #FF0000;
}</style></head><body>]==]
local HTML_END="</body></html>"
function unit_info(user, u )
	local uname=dfhack.df2utf(dfhack.TranslateName(u.name))
	local prof=dfhack.units.getProfessionName(u)
	local job
	if u.job.current_job then
		job=dfhack.job.getName(u.job.current_job)
	else
		job="no job"
	end
	local ret=string.format('<div class="unit">%s (%s)</div><div class="job"> %s</div><div class="labors"> Labors:<ul>',uname,prof,job)
	for i,v in ipairs(u.status.labors) do
		if df.unit_labor.attrs[i].caption~=nil then
			local num=1
			if v then
				num=0
			end
			ret=ret..string.format("<li>%s : <a href='%s?labor=%d:%d'>%s</a></li>",df.unit_labor.attrs[i].caption,
				user.name,i,num,v)
		end
	end
	ret=ret..'</ul>\n'
	ret=ret..'<div class="labors"> Burrows:<ul>'
	for i,v in ipairs(df.global.ui.burrows.list) do
		local in_burrow_text="add"
		local in_burrow_state=1
		if dfhack.burrows.isAssignedUnit(v,u) then
			in_burrow_text="remove"
			in_burrow_state=0
		end
		ret=ret..string.format("<li>%s : <a href='%s?burrow=%d:%d'>%s</a></li>",v.name,
			user.name,v.id,in_burrow_state,in_burrow_text)
	end
	ret=ret.."</ul>\n";
	return ret

end
function respond_new_user( username )
	local unit=pick_target()
	users[username]={unit_id=unit.id,name=username}
	print("New user:"..username)
	return string.format("%s You were assigned unit: %s (%d). %s",
		HTML_HEAD,dfhack.df2utf(dfhack.TranslateName(unit.name)),unit.id,HTML_END)
end
function respond_err()
	return page_data.intro..fill_page_data(page_data.welcome,{hostname=HOST})..page_data.outro
end
function respond_help()
	local r=""
	local choices={
	{"help","Print this help"},
	{"new_unit","Assign a new random unit"},
	{"labor=id:value","Set labor on or off"},
	{"burrow=id:value","Add or remove from burrow"},
	{"delete","deletes all user data"},
}
	for i,v in ipairs(choices) do
		r=r..string.format("<li>%s : %s</li>\n",v[1],v[2])
	end
	return string.format("%s <ul> %s </ul>%s",HTML_HEAD, r ,HTML_END)
end
function starts_with( s,prefix )
	return s:sub(1,#prefix)==prefix
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
	elseif cmd=="delete" then
		print("Deleting user:",user.name)
		users[user.name]=nil
		return HTML_HEAD.. "User deleted" .. HTML_END
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
		local u,u_id=pick_unused_target()
		if u_id ==nil then
			return false,page_data.intro.."Sorry, couldn't find a valid unit for you :("..page_data.outro
		end
		user.unit_id=u_id
		unit_used[u_id]=true
		return u,u_id
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
	if not t then return err2 end

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
function respond_json_map(cmd,cookies)

	local user,err=get_user(cmd,cookies)
	if not user then return "[]" end --TODO somehow report error?
	local t,err2=get_unit(user)
	if not t then return "[]" end --TODO somehow report error?
	--valid users unpause game for some time

	server_unpause()

	local w=21
	local m=map.render_map_rect(t.pos.x-w//2-1,t.pos.y-w//2-1,t.pos.z,w,w)
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

	return "["..map_string.."]"
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
	local ret=page_data.intro..page_data.unit_select

	for i,v in ipairs(unit_data) do
		ret=ret..string.format("<option value=%d>%s %s cost:%d</option>\n",i,v.race_raw.name[0],v.caste_raw.caste_id,v.cost)
	end
	ret=ret.."</select></form>"
	ret=ret.."<button type='submit' form='form1' value='submit'>Ask for new unit</button>\n"
	return ret..page_data.outro
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
function respond_actual_new_unit(cmd,cookies)
	local user,err=get_user(cmd,cookies)
	if not user then return err end

	if user.unit_id then --release old one if we have one
		unit_used[user.unit_id]=nil
		user.unit_id=nil
	end

	if cmd.race_==nil or tonumber(cmd.race_)==nil or unit_data[tonumber(cmd.race_)]==nil then
		return page_data.intro.."Error: invalid race selected"..page_data.outro
	end
	local actual_race=unit_data[tonumber(cmd.race_)]

	local x,y,z=get_valid_unit_pos()
	if not x then
		return page_data.intro.."Error: could not find where to place unit"..page_data.outro
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

	--return page_data.intro.."New unit spawned <a href='play'>Go back</a>"..page_data.outro
	--return respond_play(cmd,cookies) --TODO figure out redirect?
	return nil, "HTTP/1.1 302 Found\nLocation: "..HOST.."play\n\n"
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
	if not user then return "{error='invalid_login'}" end
	local unit,err2=get_unit(user)
	if not unit then return  "{error='invalid_unit'}" end

	if unit.flags1.dead then return "{error='dead'}" end

	if not cmd.dx or not tonumber(cmd.dx) then return "{error='invalid_dx'}" end
	if not cmd.dy or not tonumber(cmd.dy) then return "{error='invalid_dy'}" end
	--TODO figure out dz by looking if you are going up ramp etc...
	local dx=tonumber(cmd.dx)
	local dy=tonumber(cmd.dy)
	local tx=unit.pos.x+dx
	local ty=unit.pos.y+dy
	unit.idle_area.x=tx
	unit.idle_area.y=ty
	unit.idle_area_type=37 --Guard
	unit.idle_area_threshold=0

	if dfhack.maps.isValidTilePos(tx,ty,unit.pos.z) then
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
	end

	return "{}"
end
function respond_json_unit_list(cmd, cookies)
	--{race=race_r,caste=caste_id,caste_raw=caste_raw,cost=tonumber(cost)}
	local ret="["
	local comma=''

	for i,v in ipairs(unit_data) do
		ret=ret..string.format("%s\n{race:'%s',caste:'%s',name:'%s',cost:%d}",comma,v.race_raw.creature_id,v.caste_raw.caste_id,v.race_raw.name[0],v.cost)
		comma=','
	end
	return ret.."]"
end
function responses(request,cmd,cookies)

	if request=='favicon.ico' then
		return page_data.favicon
	--elseif request=='help' then
	--	return respond_help()
	elseif request=='login' then
		return respond_login()
	elseif request=='dologin' then
		return respond_cookie(cmd)
	elseif request=='play' then
		return respond_play(cmd,cookies)
	elseif request=='map' then
		return respond_json_map(cmd,cookies)
	elseif request=='delete'then
		return respond_delete(cmd,cookies)
	elseif request=='new_unit' then
		return respond_new_unit(cmd,cookies)
	elseif request=='submit_new_unit' then
		return respond_actual_new_unit(cmd,cookies)
	elseif request=='move_unit' then
		return respond_json_move(cmd,cookies)
	elseif request=='get_unit_list' then
		return respond_json_unit_list(cmd,cookies)
	else
		print("Invalid request happened:",request)
		printd("Request:",request)
		printd("cmd:",cmd)
		return respond_err()
	end

	--[[
	if users[request] then
		local r=perform_commands(users[request],cmd)
		if r then
			return r
		end
		return respond_map(users[request])
	elseif request~=nil and request~='' then
		return respond_new_user(request)
	else
		printd("Request:",request)
		printd("cmd:",cmd)
		return respond_err()
	end
	]]
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
function parse_request( client )
	local s=client:receive() --FIXME: this crashed, need pcall?
	if s==nil then
		return false
	end
	printd(s)
	local path,other=s:match("GET /([^ ?]*)([^ ]*)")
	if path==nil and other==nil then
		path,other=s:match("POST /([^ ?]*)([^ ]*)")
	end
	printd("CON:",path)
	if other~=nil then
		local command={}
		other=other:sub(2):gsub("%%20"," ")--drop '?' and fix spaces
		for i in string.gmatch(other, "[^&]*") do
   			--table.insert(command,i)
   			local eq=string.find(i,"=")
   			if eq then
   				command[string.sub(i,1,eq-1)]=string.sub(i,eq+1)
   			else
   				command[i]=true
   			end
		end
		other=command
		printd("Other:",#other)
	end


	while s do
		s=client:receive()
		if s then
			local c=s:match("Cookie: (.*)")
			if c then
				cookies=parse_cookies(c)
			end
		end
	end
	return true,path,other,cookies
end
function poke_clients()
	local removed_entries={}
	for k,v in pairs(clients) do

		local ok,req,cmd,cookies=parse_request(k)
		if ok then
			local r,alt=responses(req,cmd,cookies)
			if r==nil and alt then
				k:send(alt)
			else
				k:send(string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Length: %d\r\n\r\n%s",#r,r))
			end
			k:close()
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
event_loop()