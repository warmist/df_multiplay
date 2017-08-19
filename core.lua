--[[
	server core functionality
]]
local _ENV=mkmodule('hack.scripts.http.core')

local sock=require 'plugins.luasocket'


serv_plugin=defclass(serv_plugin)

serv_plugin.ATTRS{
	expose_pages={}, -- a list of functions or path strings (without .html) which get sent to client when they enter the "key" value
	expose_json={}, --a list of functions that send json response
	loop_tick=DEFAULT_NIL, -- callback with (server,plugin) that gets called each tick
}

server=defclass(server)
server.ATTRS{
	port=6667,
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
}
local printd
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
function make_content(r)
	return string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Length: %d\r\n\r\n%s",#r,r)
end
function make_page_not_found( r )
	return string.format("HTTP/1.0 404 Site Not Found\r\nConnection: Close\r\nContent-Length: %d\r\n\r\n%s",#r,r)
end
function make_mime_content( r,mime )
	return string.format("HTTP/1.0 200 OK\r\nConnection: Close\r\nContent-Type: %s\r\nContent-Length: %d\r\n\r\n%s",mime,#r,r)
end
function make_json_content( r )
	return make_mime_content(r,"application/json")
end
function make_json_error(err)
	return make_json_content(string.format('{"error"="%s"}',err))
end

function fill_page_data( page_text,variables )
	function replace_vars( v )
		local vname=v:sub(3,-3)
		return tostring(variables[vname])
	end
	return page_text:gsub("(!![^!]+!!)",replace_vars)
end

function server:init( args )
	self:load_default_pages()
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
		['favicon.ico']='favicon.png',
		['map.js']='map.js',
		['chat.css']='chat.css',
		['style.css']='style.css',
	}
	for k,v in pairs(assets) do
		local f=io.open('hack/scripts/http/'..v,'rb')
		self.assets[k]={data=f:read('all')}
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
			return fill_page_data(server.pages.cookie.text,{username=user.name,password=user.password})
		else
			return server:make_error(err)
		end
	end}
end
function server:make_error( err )
	return fill_page_data(self.pages.error.text,{error=err})
end
function server:login( cmd,cookies )
	if cmd.username==nil or cmd.username=="" then
		return nil,"Invalid username"
	end

	local users=self.users
	local user=users[cmd.username]
	print("Login:",cmd.username,cmd.password,user)
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
function server:get_user(cookies)
	if cookies.username==nil or cookies.username=="" or self.users[cookies.username]==nil or cookies.password~=self.users[cookies.username].password then
		return false,"Invalid login"
	end
	local user=self.users[cookies.username]
	return user
end
function server:get_unit( user )
	if user.unit_id==nil then
		return
	end
	local t=df.unit.find(user.unit_id)
	if t ==nil then
		return false,"Sorry, your unit was lost somewhere... :("
	end
	return t,user.unit_id
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
	--then json responses

	local json_req=self.pages_json[request]
	if json_req then
		if json_req.needs_auth then
			local err
			user,err=self:get_user(cookies)
			if user==nil then
				return make_json_error(err)
			end
		end
		if json_req.needs_unit then
			local err
			unit,err=self:get_unit(user)
			if unit==nil then
				return make_json_error(err)
			end
		end
		local content,err=json_req(self,commands,cookies,user,unit)
		if not content then
			return make_json_error(err)
		else
			return make_json_content(content)
		end
	end
	--page responses
	local page_req=self.pages[request]
	if page_req and page_req.data then
		if page_req.needs_auth then
			local err
			user,err=self:get_user(cookies)
			if user==nil then
				return self:make_error(err)
			end
		end
		if page_req.needs_unit then
			local err
			unit,err=self:get_unit(user)
			if unit==nil then
				return self:make_error(err)
			end
		end
		if type(page_req.data)=='function' then
			local content,err=page_req.data(self,commands,cookies,user,unit)
			if not content then
				return self:make_error(err)
			else
				return make_content(content)
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
function server:event_loop()
	self:accept_connections()
	self:serve_clients()
	self.timeout_looper=dfhack.timeout(10,'frames',self:callback('event_loop'))
end

return _ENV