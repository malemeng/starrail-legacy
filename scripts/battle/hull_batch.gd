extends MultiMeshInstance2D

const Hulls = preload("res://hull_catalog.gd")
const Defenses = preload("res://scripts/battle/defenses.gd")
const ShipVisual = preload("res://scripts/battle/ship_visual.gd")
const Surface = preload("res://scripts/battle/hull_batch.gdshader")
const TILE := 224
const COLUMNS := 8
const LIMIT := COLUMNS * COLUMNS
var entries: Dictionary = {}
var atlas := Image.create_empty(TILE*COLUMNS,TILE*COLUMNS,false,Image.FORMAT_RGBA8)
var armor := Image.create_empty(35,LIMIT,false,Image.FORMAT_RF)
var mapping := Image.create_empty(2,LIMIT,false,Image.FORMAT_RGBAF)
var armor_texture: ImageTexture
var map_texture: ImageTexture
var marks: Array = []
var armor_row := Image.new()
var row_keys: Array[RID] = []
var row_entries: Array[Dictionary] = []
var phase_tints := PackedByteArray()
var flashes: Array[Color] = []
var mapping_dirty := false
var atlas_dirty := false
var armor_dirty := false
var used := 0

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = LIMIT
	multimesh.visible_instance_count = 0
	armor.fill(Color.WHITE)
	marks.resize(LIMIT)
	row_keys.resize(LIMIT)
	row_entries.resize(LIMIT)
	phase_tints.resize(LIMIT)
	flashes.resize(LIMIT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = ImageTexture.create_from_image(atlas)
	armor_texture = ImageTexture.create_from_image(armor)
	map_texture = ImageTexture.create_from_image(mapping)
	var paint := ShaderMaterial.new()
	paint.shader = Surface
	paint.set_shader_parameter("armor",armor_texture)
	paint.set_shader_parameter("mapping",map_texture)
	material = paint

func add_vessel(view: ShipVisual) -> bool:
	if used == LIMIT:
		return false
	var row := used
	var key := view.texture_key
	var new_row := row_keys[row] != key
	var entry: Dictionary = row_entries[row]
	if new_row:
		entry = entries.get(key,{})
	if entry.is_empty():
		if entries.size() == LIMIT:
			return false
		var source: Texture2D = view.hull.texture
		var size_px := source.get_size()
		var model: Dictionary = view.model
		var slot := entries.size()
		var origin := Vector2i(slot % COLUMNS, floori(slot / float(COLUMNS))) * TILE
		atlas.blit_rect(source.get_image(), Rect2i(Vector2i.ZERO, Vector2i(size_px)), origin)
		var side := float(atlas.get_width())
		var scale_factor: float = model.sprite_scale
		var dimensions := size_px * scale_factor
		var center: Vector2 = model.sprite_center
		var box: Rect2 = Defenses.geometry(view.ship.kind).rect
		var offset := (-center * scale_factor - box.position) / box.size
		var extent := dimensions / box.size
		entry = {"uv":Color(origin.x/side, origin.y/side, size_px.x/side, size_px.y/side),
			"size":dimensions, "origin":dimensions * 0.5 - center * scale_factor,
			"remap":Color(offset.x, offset.y, extent.x, extent.y), "center_uv":center / size_px,
			"armor_factor":35.0 / maxf(0.001, 4.0 * float(Hulls.COMBAT[view.ship.kind].armor))}
		entries[key] = entry
		atlas_dirty = true
	used += 1
	var ship: Dictionary = view.ship
	var dimensions: Vector2 = entry.size
	var pose := view.last_pose
	multimesh.set_instance_transform_2d(row,Transform2D(pose.x*dimensions.x,pose.y*dimensions.y,pose*entry.origin))
	if new_row or phase_tints[row] != int(view.was_phased):
		phase_tints[row] = int(view.was_phased)
		multimesh.set_instance_color(row,view.modulate)
	if new_row:
		row_keys[row] = key
		row_entries[row] = entry
		multimesh.set_instance_custom_data(row,entry.uv)
		mapping.set_pixel(0,row,entry.remap)
		mapping_dirty = true
	var tag := Vector2(ship.id,ship.battle.armor)
	if marks[row] == null or marks[row] != tag:
		marks[row] = tag
		var grid := Defenses.grid_for(ship)
		armor_row.set_data(grid.size(),1,false,Image.FORMAT_RF,grid.to_byte_array())
		armor.blit_rect(armor_row,Rect2i(0,0,grid.size(),1),Vector2i(0,row))
		armor_dirty = true
	var heat: float = ship.battle.get("hit_flash",0.0)
	if new_row or heat > 0.0 or flashes[row].b > 0.0:
		var hit: Vector2 = Vector2(ship.battle.get("hit_local",Vector2.ZERO)) / dimensions + entry.center_uv
		var flash := Color(hit.x,hit.y,heat,entry.armor_factor)
		if flashes[row] != flash:
			flashes[row] = flash
			mapping.set_pixel(1,row,flash)
			mapping_dirty = true
	return true

func flush() -> void:
	multimesh.visible_instance_count = used
	if atlas_dirty:
		texture.update(atlas)
		atlas_dirty = false
	if armor_dirty:
		armor_texture.update(armor)
		armor_dirty = false
	if mapping_dirty:
		map_texture.update(mapping)
		mapping_dirty = false
	used = 0
