--[[
	server core functionality
	TODO:
		no easy way to pass plugin settings to functions
		use json lib for serialization deserialization
]]
local _ENV=mkmodule('hack.scripts.http.core')

local sock=require 'plugins.luasocket'
--TODO move to a plug
function find_burrow(name)
	local b=df.global.ui.burrows.list
	for i,v in ipairs(b) do
		if v.name==name then
			return v
		end
	end
	print("WARN:"..name.." burrow not found")
end

local SPAWN_MOBS=15
local npc_spawn
if SPAWN_MOBS then
	npc_spawn=find_burrow("SPAWN_MOBS")
	--print("npc_spawn:",npc_spawn)
end
function create_unit_simple( race_id,caste_id,pos,count )
	local create_unit=dfhack.script_environment('modtools/create-unit')
	local u=create_unit.createUnitBase(race_id,caste_id,nil,pos,
		nil,nil,nil,nil,nil,nil,nil,nil,
		count or 1
		)

	return u[1].id
end
serv_plugin=defclass(serv_plugin)

serv_plugin.ATTRS{
	expose_pages={}, -- added to server pages list
	expose_json={}, --added to server json pages list
	expose_assets={}, -- same with assets
	loop_tick=DEFAULT_NIL, -- callback with (server,plugin) that gets called each tick
	gamestate_hook=DEFAULT_NIL, --callback with (server,plugin,request_table,current_state,hidden_state). This is main client game loop function
	name=DEFAULT_NIL,
}

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
	start=start or 1
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
function json_unpack_obj( s )
	return require('json').decode(s)
end


server=defclass(server)
server.ATTRS{
	port=80,
	host="http://dwarffort.duckdns.org/", --not sure if needed
	port_inst=DEFAULT_NIL,
	clients={},
	pages={}, --html pages
	pages_json={}, --json responses
	assets={}, --images and co...
	timeout_looper=DEFAULT_NIL,
	page_vars={
		message_of_the_day=""
	}, --global page variables

	users={},
	pause_countdown=0,
}
if DEBUG then
	printd=function ( ... )
		print(...)
	end
else
	printd=function ()end
end

function make_redirect(loc)
	return "HTTP/1.1 302 Found\nLocation: "..loc.."\n\n"
end
function make_content(r,alt,ext_header)
	if r then --FIXME: quick hack for alternative returns. Refactor responses
		return string.format("HTTP/2.0 200 OK\r\nConnection: Close\r\n%sContent-Length: %d\r\n\r\n%s",ext_header or "",#r,r)
	else
		return alt
	end
end
function make_page_not_found( r )
	return string.format("HTTP/1.0 404 Site Not Found\r\nConnection: Close\r\nContent-Length: %d\r\n\r\n%s",#r,r)
end
function make_mime_content( r,mime,ext_header )
	return string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Type: %s\r\nContent-Length: %d\r\n%s\r\n%s",mime,#r,ext_header or "",r)
end
function make_cookie_header( cookies )
	local ret=""
	for k,v in pairs(cookies) do
		ret=ret..string.format("Set-Cookie: %s=%s\r\n",k,v)
	end
	return ret
end
function make_json_content( r )
	return make_mime_content(r,"application/json")
end
function make_json_error(err)
	return make_json_content(string.format('{"error":"%s"}',err))
end

function fill_page_data( page_text,variables )
	function replace_vars( v )
		local vname=v:sub(3,-3)
		return tostring(variables[vname])
	end
	return page_text:gsub("(!![^!]+!!)",replace_vars)
end
function server:install_plugin(plug)
	assert(plug.name~=nil)
	print("Installing plugin:",plug.name)
	for k,v in pairs(plug.expose_assets) do
		self.assets[k]=v
	end
	for k,v in pairs(plug.expose_json) do
		self.pages_json[k]=v
	end
	for k,v in pairs(plug.expose_pages) do
		self.pages[k]=v
	end
	self.plugins[plug.name]=plug
end
function server:init( args )
	self:load_default_pages()
	self.plugins={}
end
function load_page( name )
	local f=io.open('hack/scripts/http/'..name..'.html','rb')
	local ret
	if not f then
		error("File failed to open:"..name)
	else
		ret=f:read('all')
		f:close()
	end
	return ret
end
function server:load_default_pages()
	local assets={
		['favicon.ico']={'favicon.png',"image/png"},
		['map.js']={'map.js',"application/javascript"},
		['chat.css']={'chat.css',"text/css"},
		['style.css']={'style.css',"text/css"},
	}
	for k,v in pairs(assets) do
		local f=io.open('hack/scripts/http/'..v[1],'rb')
		self.assets[k]={data=f:read('all'),mime=v[2]}
		f:close()
	end

	local files={
		'welcome',
		'login',
	}
	for i,v in ipairs(files) do
		self.pages[v]={data=load_page(v)}
	end
	self.pages[""]=self.pages.welcome
	--special pages
	local files_special={
		'cookie',
		'error'
	}
	for i,v in ipairs(files_special) do
		self.pages[v]={text=load_page(v)}
	end
	self.pages.dologin={data=
	function (server,cmd,cookies)
		local user,err=server:login(cmd,cookies)
		if user then
			local ret=make_content(server.pages.cookie.text,nil,make_cookie_header{username=user.name,password=user.password})
			return nil,nil, ret
		else
			return server:make_error(err)
		end
	end}
end
function server:make_error( err )
	return make_content(fill_page_data(self.pages.error.text,{error=err}))
end
function server:login( cmd,cookies )
	if cmd.username==nil or cmd.username=="" then
		return nil,"Invalid username"
	end

	local users=self.users
	local user=users[cmd.username]
	if user==nil then --create new user, if one does not exist
		users[cmd.username]={password=cmd.password,name=cmd.username}
		print("New user:"..cmd.username)
		user=users[cmd.username]
		user.name=cmd.username
		return user
	elseif user.password~=cmd.password then --check password
		return nil, "Wrong password"
	end
	return user
end
function server:save_users(path)
	local user_save={}
	for k,v in pairs(self.users) do
		local tbl={name=v.name,password=v.password,money=v.money or 0}
		if v.unit_id then
			tbl.unit_id=v.unit_id
		end
		table.insert(user_save,tbl)
	end
	local f=io.open(path or "user_db.dat",'wb')
	f:write(json_pack_arr(user_save))
	f:close()
end
function server:load_users(path)
	pcall(function()
	local f=require'json'.decode_file(path or "user_db.dat")
	for i,v in ipairs(f) do
		self.users[v.name]={name=v.name,password=v.password,money=v.money}
		if v.unit_id then
			self.users[v.name].unit_id=v.unit_id
			self.unit_used=self.unit_used or {}
			self.unit_used[v.unit_id]=self.users[v.name]
		end
	end
	end)
end
function server:stop()
	if self.port_inst then
		self.port_inst:close()
		self.port_inst=nil
	else
		print("WARN: server already closed")
	end
	for k,v in pairs(self.clients) do
		k:close()
	end
	if self.timeout_looper then
		dfhack.timeout_active(self.timeout_looper,nil)
		self.timeout_looper=nil
	end
	self:save_users()
end
function server:shutdown()
	self:stop()
	print("Server shutting down")
end
function server:restart()
	self:stop()
	self:start()
end
function server:start()
	if self.timeout_looper then
		error("server already running")
	end
	self.port_inst=self.port_inst or sock.tcp:bind(self.host,self.port)
	self.port_inst:setNonblocking()
	self:event_loop()
end
function server:accept_connections()
	while self.port_inst:select(0,1) do
		local c=self.port_inst:accept()
		self.clients[c]=true
		c:setNonblocking()
	end
end
function server:unpause()--TODO: move to a plugin
	self.pause_countdown=10 --TODO: config this
end
function get_valid_unit_pos( burrow )
	local x,y,z
	if burrow then
		for i=1,100 do

			local blocks=dfhack.burrows.listBlocks(burrow)
			local m_block=blocks[math.random(0,#blocks-1)]

			local lx=math.random(0,15)
			local ly=math.random(0,15)
			if dfhack.burrows.isAssignedBlockTile(burrow,m_block,lx,ly) then
				x=lx+m_block.map_pos.x
				y=ly+m_block.map_pos.y
				z=m_block.map_pos.z
				if dfhack.maps.isValidTilePos(x,y,z) then
					local attrs = df.tiletype.attrs
					local tt=dfhack.maps.getTileType(x,y,z)
					local td,to=dfhack.maps.getTileFlags(x,y,z)
					if tt and not td.hidden and td.flow_size==0 and attrs[tt].shape==df.tiletype_shape.FLOOR then
						return x,y,z
					end
				end
			end
		end
	else
		local mx,my,mz=dfhack.maps.getTileSize()
		for i=1,1000 do
			x=math.random(0,mx-1)
			y=math.random(0,my-1)
			z=math.random(0,mz-1)
			if dfhack.maps.isValidTilePos(x,y,z) then
				local attrs = df.tiletype.attrs
				local tt=dfhack.maps.getTileType(x,y,z)
				local td,to=dfhack.maps.getTileFlags(x,y,z)
				if tt and not td.hidden and td.flow_size==0 and attrs[tt].shape==df.tiletype_shape.FLOOR then
					return x,y,z
				end
			end
		end
	end
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
function parse_content( other,is_json)
	if is_json then
		return json_unpack_obj(other)
	end
	if other~=nil then
		local command={}
		other=other:gsub("%%20"," ")--drop '?' and fix spaces
		for i in string.gmatch(other, "[^&]+") do

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
	local s=client:receive()
	if s==nil then return false	end --failed to read even a bit
	printd(s)

	local is_post
	local is_json
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
				if s:match("Content%-Type: application%/json") then
					is_json=true
				end
			end
		end
	end
	if is_post and post_length then
		printd("Post length:",post_length)
		if post_length~=0 then
			s=client:receive(post_length)
			if s then
				other=parse_content(s,is_json)
			end
		end
	elseif is_post and not post_length then
		print("Warning: post request without content length")
	end

	return true,path,other,cookies
end
function server:get_user(cookies)
	if cookies.username==nil or cookies.username=="" or self.users[cookies.username]==nil or cookies.password~=self.users[cookies.username].password then
		return false,"Invalid login"
	end
	local user=self.users[cookies.username]
	return user
end
function server:get_unit( user )
	if user.unit_id==nil then
		return false,"No unit id"
	end
	local t=df.unit.find(user.unit_id)
	if t ==nil then
		return false,"Unit id invalid"
	end
	return t,user.unit_id
end
function server:respond_gamestate(commands,cookies)
	local user=self:get_user(cookies)
	local unit
	if user then
		unit=self:get_unit(user)
	end
	local hidden={user=user,unit=unit}
	local state={}
	for name,plug in pairs(self.plugins) do
		if plug.gamestate_hook then
			plug.gamestate_hook(self,plug,commands,state,hidden)
		end
	end
	return make_json_content(json_pack_obj(state))
end
function server:respond( request,commands,cookies)
	request=request or "" --fix nil request
	local user,unit
	--first dumb asset responses
	local assets_req=self.assets[request]
	if assets_req then
		if assets_req.mime then
			return make_mime_content(assets_req.data)
		else
			return make_content(assets_req.data)
		end
	end
	--then special gamestate logic
	if request=="gamestate" then
		return self:respond_gamestate(commands,cookies)
	end
	--then json responses

	local json_req=self.pages_json[request]
	if json_req then
		if json_req.needs_user or json_req.needs_unit then
			local err
			user,err=self:get_user(cookies)
			if not user then
				return make_json_error(err)
			end
		end
		if json_req.needs_unit then
			local err
			unit,err=self:get_unit(user)
			if not unit then
				return make_json_error(err)
			end
		end
		local content,err=json_req.data(self,commands,cookies,user,unit)
		if not content then
			return make_json_error(err)
		else
			return make_json_content(content)
		end
	end
	--page responses
	local page_req=self.pages[request]
	if page_req and page_req.data then
		if page_req.needs_user or page_req.needs_unit then
			local err
			user,err=self:get_user(cookies)
			if not user then
				return self:make_error(err)
			end
		end
		if page_req.needs_unit then
			local err
			unit,err=self:get_unit(user)
			if not unit then
				return self:make_error(err)
			end
		end
		if type(page_req.data)=='function' then
			local content,err,content_alt=page_req.data(self,commands,cookies,user,unit) --FIXME: again very nasty hack...
			if not content and not content_alt then
				return self:make_error(err)
			elseif content then
				return make_content(content)
			else
				return content_alt
			end
		else
			return make_content(fill_page_data(page_req.data,self.page_vars))
		end
	end
	--page not found error
	print("Invalid request happened:",request)
	return make_page_not_found("Page not found")
end
function server:serve_clients()
	local removed_entries={}
	for k,v in pairs(self.clients) do
		function do_work()
			local ok,req,cmd,cookies=parse_request(k)
			if ok then
				local response_text=self:respond(req,cmd,cookies)
				k:send(response_text)
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
		self.clients[k]=nil
	end
end
function clear_items()
	local as=df.global.world.arena_spawn.equipment
	as.item_types:resize(0)
	as.item_subtypes:resize(0)
	as.item_materials.mat_type:resize(0)
	as.item_materials.mat_index:resize(0)
	as.item_counts:resize(0)
end
function spawn_mob()
	if npc_spawn then
		local x,y,z=get_valid_unit_pos(npc_spawn)
		if x then
			df.global.world.arena_spawn.side=66
			clear_items()
			create_unit_simple(576,math.random(0,1),{x=x,y=y,z=z}) --TODO more customization? TODO: check if race exists
			--local u=df.unit.find(u_id) --not used currently but we could do something with it?
		end
	end
end
function count_mobs()
	local count=0
	for i,v in ipairs(df.global.world.units.active) do
		if not v.flags2.killed and v.enemy.enemy_status_slot==66 then
			count=count+1
		end
	end
	return count
end

function server:event_loop()
	self:accept_connections()
	self:serve_clients()
	--TODO: move to a plugin
	-- [[
	if self.pause_countdown>0 then
		df.global.pause_state=false
		self.pause_countdown=self.pause_countdown-1
	else
		df.global.pause_state=true
	end
	--]]
	--TODO move to a plugin
	local m_count=count_mobs()
		--print("Count:",m_count,SPAWN_MOBS)
	if m_count<SPAWN_MOBS then
		spawn_mob()
	end
	self.timeout_looper=dfhack.timeout(10,'frames',self:callback('event_loop'))
end

function sanitize(txt)
    local replacements = {
        ['&' ] = '&amp;',
        ['<' ] = '&lt;',
        ['>' ] = '&gt;',
        ['\n'] = '<br/>'
    }
    return txt
        :gsub('[&<>\n]', replacements)
        :gsub(' +', function(s) return ' '..('&nbsp;'):rep(#s-1) end)
end

function encodeURI(str)
	if (str) then
		str = string.gsub (str, "\n", "\r\n")
		str = string.gsub (str, "([^%w ])",
			function (c) return string.format ("%%%02X", string.byte(c)) end)
		str = string.gsub (str, " ", "+")
   end
   return str
end

function decodeURI(s)
	if(s) then
		s = string.gsub(s, '%%(%x%x)', 
			function (hex) return string.char(tonumber(hex,16)) end )
	end
	return s
end

return _ENV