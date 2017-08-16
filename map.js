
var ctx;
var spr;
var tile_x;
var tile_y;
var canvas_tile_count;
var map=[];
function setup_map(canvas_id,tilesheet_id,tile_x_size,tile_y_size,tile_count)
{
	var c = document.getElementById(canvas_id);
	ctx = c.getContext("2d");
	spr=document.getElementById(tilesheet_id);
	tile_x=tile_x_size
	tile_y=tile_y_size
	canvas_tile_count=tile_count
}
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
function draw_map(map){
	ctx.clearRect(0, 0, c.width, c.height);
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