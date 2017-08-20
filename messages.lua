local _ENV=mkmodule('hack.scripts.http.messages')
--TODO: add general server messages for player only. E.g. you gained X money for a kill
local core=require 'hack.scripts.http.core'

function respond_json_message(server, cmd, cookies, user)
	server.message_log=server.message_log or {}
	--TODO: limit size of message_log
	local msg=core.decodeURI(cmd.msg)
	--msg=msg:sub(1,63) --TODO: fix it in play.html and set normal size
	msg=user.name..":"..core.sanitize(msg)
	table.insert(server.message_log,msg)
	print("CHAT>"..msg)
	return "{}"
end
function respond_json_message_log(server, cmd, cookies)
	--TODO: BUG FIXME eats up the first message!
	local C_DEFAULT_LOGSIZE=20
	local C_MAX_LOGSIZE=100

	local last_seen
	local log = server.message_log or {}

	if cmd.last_seen==nil or tonumber(cmd.last_seen)==nil then
		last_seen=#log-C_DEFAULT_LOGSIZE
	else
		last_seen=tonumber(cmd.last_seen)
	end

	if last_seen<1 then last_seen=1 end
	if last_seen>#log or  #log-last_seen>C_MAX_LOGSIZE then
		last_seen=#log-C_DEFAULT_LOGSIZE
	end
	--print("Final last_seen:",last_seen)
	last_seen=last_seen+1
	local ret=string.format('{"current_count":%d,"log":[',#log)
	local comma=''
	if #log>0 then
		for i=last_seen,#log do
			local text=log[i]
			if text then
				text=text:gsub('"','')
				ret=ret..string.format('%s"%s"\n',comma,text)
				comma=','
			end
		end
	end
	return ret.."]}"
end
function respond_json_combat_log(server, cmd ,cookies, user, unit)
	--TODO: could ddos? find might be slow
	local C_DEFAULT_LOGSIZE=20
	local C_MAX_LOGSIZE=100

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
			if log[i]>=0 then
				local report=df.report.find(log[i])
				if report then
				local text=report.text
					text=text:gsub('"','')
					ret=ret..string.format('%s"%s"\n',comma,text)
					comma=','
				end
			end
		end
	end
	return ret.."]}"
end
serv_messages=defclass(serv_messages,core.serv_plugin)
serv_messages.ATTRS={
	expose_json={
			get_message_log={data=respond_json_message_log},
			send_message={data=respond_json_message, needs_user=true},
			get_report_log={data=respond_json_combat_log, needs_user=true, needs_unit=true},
	},

	name="messages",
}
plug=serv_messages

return _ENV