local _ENV = mkmodule('hack.scripts.http.jobs')

local tile_attrs = df.tiletype.attrs

function assignJobToUnit(job,unit,from_pos)
    if unit.job.current_job ~= nil then
        --unassignJob(unit)
        return false
    end
    job.general_refs:insert("#",{new=df.general_ref_unit_workerst,unit_id=unit.id})
    unit.job.current_job=job
    unit.path.dest:assign(from_pos or unit.pos)
end

function pickup_equipment( unit,item )
	if unit.job.current_job then
		return false
	end

	local job=df.job:new()
	job.job_type=df.job_type.PickupEquipment
	assignJobToUnit(job,unit,copyall(item.pos))
	job.items:insert("#",{new=true,item=item,job_item_idx=0})
	dfhack.job.linkIntoWorld(job,true)
end

return _ENV

--:lua require'hack.scripts.http.jobs'.pickup_equipment(df.unit.find(1573),df.item.find(4071))