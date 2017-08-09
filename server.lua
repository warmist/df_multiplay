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
local DEBUG=true
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
		'play'
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
function fill_page_data( page_text,variables )
	function replace_vars( v )
		local vname=v:sub(3,-3)
		return tostring(variables[vname])
	end
	return page_text:gsub("(!![^!]+!!)",replace_vars)
end
load_page_data()
users=users or {}
unit_used=unit_used or {}
port=port or sock.tcp:bind(HOST,6666)
port:setNonblocking()

local clients={}

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
		else
			--check if unit is civ?
			return u[id],id
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
function respond_map(user)
	local ret=HTML_HEAD
	local S=[===[
	<canvas id="canvas" width="!!canvas_w!!" height="!!canvas_h!!"></canvas><br>
	<img id="tilesheet" src="http://i.imgur.com/fUGSAWC.png" alt="tilesheet" style="display: none;">
	<script>
	var c = document.getElementById("canvas");
	var ctx = c.getContext("2d");
	var spr=document.getElementById("tilesheet");
	var tile_x=16;
	var tile_y=16;
	var canvas_tile_count=!!size!!;
	var map=[!!map!!];
	var color_map=[[0,0,0],[0,0,128],[0,128,0],[0,128,128],
		[128,0,0],[128,0,128],[128,128,0],[192,192,192],
		[128,128,128],[0,0,255],[0,255,0],[0,255,255],
		[255,0,0],[255,0,255],[255,255,0],[255,255,255]];
	function color(id){
		var c=color_map[id]
  		return "rgb("+c[0]+","+c[1]+","+c[2]+")";
	}
	function draw_bg( x,y,bg ){
		ctx.fillStyle=color(bg);
		ctx.fillRect(x*tile_x,y*tile_y,tile_x,tile_y);
	}
	function draw_tile( x,y,tile){
		var sx=tile%16;
		var sy=Math.floor(tile/16);
		ctx.drawImage(spr,sx*tile_x,sy*tile_y,tile_x,tile_y,x*tile_x,y*tile_y,tile_x,tile_y);
	}
	function color_tiles( x,y,fg,bright ){
		ctx.fillStyle=color(fg+bright*8);
		ctx.fillRect(x*tile_x,y*tile_y,tile_x,tile_y);
	}
	function draw_map(){
		ctx.globalCompositeOperation="source-over";
		for(var x=0;x<canvas_tile_count;x++)
		for(var y=0;y<canvas_tile_count;y++)
		{
			var t=map[x+y*canvas_tile_count]
			draw_tile(x,y,t[0]);
		}
		
		ctx.globalCompositeOperation="source-atop";
		for(var x=0;x<canvas_tile_count;x++)
		for(var y=0;y<canvas_tile_count;y++)
		{
			var t=map[x+y*canvas_tile_count]
			color_tiles(x,y,t[1],t[3]);
		}
		
		ctx.globalCompositeOperation="destination-over";
		for(var x=0;x<canvas_tile_count;x++)
		for(var y=0;y<canvas_tile_count;y++)
		{
			var t=map[x+y*canvas_tile_count]
			draw_bg(x,y,t[2]);
		}
	}
	draw_map();
	</script>
	]===]
	local t=df.unit.find(user.unit_id)--df.global.world.units.active[unit_id]--pick_target()
	local w=15
	local m=map.render_map_rect(t.pos.x-w//2-1,t.pos.y-w//2-1,t.pos.z,w,w)
	local line=""
	local map_string=""
	--local skip_first=false
	for i=0,#m,4 do
		--if not skip_first then --temp fix because render map returns one img too little?
		if m[i]~=0 then
			line=line..string.char(m[i])
		else
			line=line..' '
		end
		map_string=map_string..string.format("[%d, %d, %d, %d],",m[i],m[i+1],m[i+2],m[i+3])
		--end
		--skip_first=false
		if #line==w then
			--ret=ret..dfhack.df2utf(line).."<br>\n"
			line=""
			map_string=map_string.."\n"
			--skip_first=true
		end
	end
	local valid_variables={
		map=map_string,
		size=w,
		canvas_w=w*16,
		canvas_h=w*16,
	}
	function replace_vars( v )
		local vname=v:sub(3,-3)
		return tostring(valid_variables[vname])
	end
	ret=ret..S:gsub("(!![^!]+!!)",replace_vars)
	ret=ret..unit_info(user,t)
	ret=ret..HTML_END
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
		users[cmd.username]={password=cmd.password}
	elseif user.password~=cmd.password then --check password
		return page_data.intro.."Invalid password"..page_data.outro
	end
	return fill_page_data(page_data.cookie,{username=cmd.username,password=cmd.password}) --set cookies
end
function respond_play( cmd,cookies )

	if cookies.username==nil or cookies.username=="" or cookies.password~=users[cookies.username].password then
		return page_data.intro.."Invalid login"..page_data.outro
	end

	local user=users[cookies.username]
	if user.unit_id==nil then
		local u,u_id=pick_unused_target()
		if u_id ==nil then
			return page_data.intro.."Sorry, couldn't find a valid unit for you :("..page_data.outro
		end
		user.unit_id=u_id
		unit_used[u_id]=true
	end

	local t=df.unit.find(user.unit_id)
	if t ==nil then
		return page_data.intro.."Sorry, your unit was lost somewhere... :("..page_data.outro
	end

	local w=15
	local m=map.render_map_rect(t.pos.x-w//2-1,t.pos.y-w//2-1,t.pos.z,w,w)
	local line=""
	local map_string=""
	--local skip_first=false
	for i=0,#m,4 do
		--if not skip_first then --temp fix because render map returns one img too little?
		if m[i]~=0 then
			line=line..string.char(m[i])
		else
			line=line..' '
		end
		map_string=map_string..string.format("[%d, %d, %d, %d],",m[i],m[i+1],m[i+2],m[i+3])
		--end
		--skip_first=false
		if #line==w then
			--ret=ret..dfhack.df2utf(line).."<br>\n"
			line=""
			map_string=map_string.."\n"
			--skip_first=true
		end
	end
	local valid_variables={
		map=map_string,
		size=w,
		canvas_w=w*16,
		canvas_h=w*16,
	}

	return page_data.intro..fill_page_data(page_data.play,valid_variables)..page_data.outro
	--ret=ret..unit_info(user,t)
end
function respond_map(cmd,cookies)

	--[[ --if map needed auth anytime
	if cookies.username==nil or cookies.username=="" or cookies.password~=users[cookies.username] then
		return page_data.intro.."Invalid login"..page_data.outro
	end
	]]
	return ""
end
function responses(request,cmd,cookies)

	if request=='favicon.ico' then
		return page_data.favicon
	elseif request=='help' then
		return respond_help()
	elseif request=='login' then
		return respond_login()
	elseif request=='dologin' then
		return respond_cookie(cmd)
	elseif request=='play' then
		return respond_play(cmd,cookies)
	elseif request=='map' then
		return respond_map(cmd,cookies)
	else
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
	local s=client:receive()
	if s==nil then
		return false
	end
	printd(s)
	local path,other=s:match("GET /([^ ?]*)([^ ]*)")
	if path==nil and other==nil then
		path,other=s:match("POST /([^ ?]*)([^ ]*)")
	end
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
	end
	printd("CON:",path,#other)

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
			local r=responses(req,cmd,cookies)
			k:send(string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Length: %d\r\n\r\n%s",#r,r))
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
	poke_clients()
	timeout_looper=dfhack.timeout(10,'frames',event_loop)
end
event_loop()