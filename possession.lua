local _ENV=mkmodule('hack.scripts.http.possession')

local core=require 'hack.scripts.http.core'

function wipe_unit_labors( unit )
	for k,v in pairs(unit.status.labors) do
		unit.status.labors[k]=false
	end
end
function respond_actual_new_unit(server,cmd,cookies,user)
	server.unit_used=server.unit_used or {}
	if user.unit_id then --release old one if we have one
		server.unit_used[user.unit_id]=nil
		user.unit_id=nil
	end

	--TODO: this is actually unnecessary if we make javascript send normal id not id,cost
	if cmd.unit~=nil then
		cmd.unit=cmd.unit:match("([^%%]+)") --remove "%C<STH>"
	end
	if not cmd.unit or not tonumber(cmd.unit) then return nil,"Invalid unit id" end

	local unit_id=tonumber(cmd.unit)
	local unit=df.unit.find(unit_id)
	if not unit then return nil, "Unit not found" end

	if server.unit_used[unit_id] then return nil, "Unit already used" end

	--TODO check if unit is our civ unit
	server.unit_used[unit_id]=user
	user.unit_id=unit_id
	df.global.ui.follow_unit=unit_id
	wipe_unit_labors(unit)
	return nil,nil, core.make_redirect("play")
end
local new_unit_page=core.load_page('unit_select_dwarf')
function respond_new_unit(server,cmd,cookies)
	return new_unit_page
end
local play_page=core.load_page("play_dwarf")
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
local job_page=core.load_page("new_job")
function respond_new_job( server,cmd,cookies,user,unit )
	local w=21
	local valid_variables={
		size=w,
		canvas_w=w*16,
		canvas_h=w*16,
		start_x=unit.pos.x-w//2,
		start_y=unit.pos.y-w//2,
		start_z=unit.pos.z,
	}

	return core.fill_page_data(job_page,valid_variables)
end

--[[ JOBS =============================]]
local jb=require 'hack.scripts.http.jobs'
reload'hack.scripts.http.jobs'
function get_pos( cmd )
	if not cmd.tx or not tonumber(cmd.tx) then return nil, "invalid tx" end
	if not cmd.ty or not tonumber(cmd.ty) then return nil, "invalid ty" end
	if not cmd.tz or not tonumber(cmd.tz) then return nil, "invalid tz" end
	return {x=tonumber(cmd.tx),y=tonumber(cmd.ty),z=tonumber(cmd.tz)}
end
function job_fish( unit,cmd )
	local trg,err=get_pos(cmd)
	if not trg then return false,err end

	if not jb.fish(unit,trg) then
		return false,"Failed to start fishing"
	end
	return true
end
--[[===================================]]
function respond_submit_job( server,cmd,cookies,user,unit )
	if not cmd.job_id or not tonumber(cmd.job_id) then return nil, "Invalid job id" end
	
	local jobs={
		job_fish,
	}
	local t_job=jobs[tonumber(cmd.job_id)]
	if t_job==nil then return nil, "Invalid job" end

	local ok,err=t_job(unit,cmd)
	if not ok  then
		return nil,err
	end
	return nil,nil,core.make_redirect("play")
end
function unit_info( u )
	local ret={}
	ret.name=dfhack.df2utf(dfhack.TranslateName(u.name))
	ret.name_eng=dfhack.df2utf(dfhack.TranslateName(u.name,true))
	ret.prof=dfhack.units.getProfessionName(u)
	ret.prof_real=dfhack.units.getProfessionName(u,true)
	ret.id=u.id
	--TODO: squad
	--TODO: more info...
	return ret
end
function respond_json_get_unit_list()
	local ret={}
	for i,v in ipairs(df.global.world.units.active) do
		if dfhack.units.isCitizen(v) and dfhack.units.isAlive(v) then
			table.insert(ret,unit_info(v))
		end
	end
	return core.json_pack_arr(ret)
end

function get_activity_name(act,unit_id)
    return dfhack.with_temp_object(--this is needed because the activity vmethod uses strange calling conv.
        df.new "string",
        function(str,act,unit_id)
            act:getName(unit_id,str)
            return str.value
        end,
        act,unit_id
    )
end
function get_activity( arr,unit_id )
	for k,v in ipairs(arr) do
		local act=df.activity_entry.find(v)
		--TODO check types?
		for i,v in ipairs(act.events) do
			if not v.flags.dismissed and v.parent_event_id==-1 then --the second thing limits this to only parent activity
				--table.insert(ret.activity,{name=})
				return get_activity_name(v,unit_id)..string.format(" (%s)",df.activity_event_type[v:getType()])
			end
		end
	end
end
function respond_json_status(server,cmd,cookies,user,unit)
	local ret={}
	ret.paused=df.global.pause_state
	if unit.job.current_job then
		ret.job=dfhack.job.getName(unit.job.current_job)
		ret.busy=ret.job
	else
		ret.job="NO JOB"
	end

	ret.activity=get_activity(unit.social_activities,unit.id)
	ret.activity=ret.activity or get_activity(unit.activities,unit.id)
	ret.activity=ret.activity or "NO ACTIVITY"
	--TODO: squad activity
	ret.busy=ret.busy or ret.activity

	return core.json_pack_obj(ret)
end
serv_possesion=defclass(serv_possesion,core.serv_plugin)
serv_possesion.ATTRS={
	expose_json={
		get_unit_list={data=respond_json_get_unit_list,needs_user=true},
		get_status={data=respond_json_status,needs_user=true,needs_unit=true},
	},
	expose_pages={
		play={data=respond_play,needs_user=true},
		new_unit={data=respond_new_unit,needs_user=true},
		submit_new_unit={data=respond_actual_new_unit,needs_user=true},
		new_job={data=respond_new_job,needs_user=true,needs_unit=true},
		submit_new_job={data=respond_submit_job,needs_user=true,needs_unit=true},
	},
	name="possession",
}
plug=serv_possesion

return _ENV