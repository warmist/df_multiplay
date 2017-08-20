local _ENV=mkmodule('hack.scripts.http.spectate')
local core=require'hack.scripts.http.core'


local spectate_page=core.load_page("spectate")
function respond_spectate(server,cmd,cookies)
	local m=df.global.world.map
	local w=21--plug.width
	local valid_variables={
		size=w,
		canvas_w=w*16,
		canvas_h=w*16,
		start_x=m.x_count//2,
		start_y=m.y_count//2,
		start_z=m.z_count//2,
	}

	return core.fill_page_data(spectate_page,valid_variables)
end
serv_spectate=defclass(serv_spectate,core.serv_plugin)
serv_spectate.ATTRS={
	expose_pages={
		spectate={data=respond_spectate}
	},
	width=21, --cant be used :/
	name="spectate",
}
plug=serv_spectate

return _ENV