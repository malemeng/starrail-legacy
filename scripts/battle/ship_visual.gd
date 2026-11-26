extends Node2D

const Hulls = preload("res://hull_catalog.gd")
const WeaponArt = preload("res://art/weapon_mounts.gd")
const Pixels = preload("res://art/pixel_art.gd")
const Battle = preload("res://combat.gd")
const DamageShader = preload("res://scripts/battle/hull_damage.gdshader")

var ship: Dictionary
var model: Dictionary
var layers: Array[Node2D] = []
var hull := Sprite2D.new()
var shader := ShaderMaterial.new()
var mask := Image.create_empty(7, 5, false, Image.FORMAT_L8)
var mask_texture: ImageTexture
var cached_armor := -1.0
var cached_livery := Color.TRANSPARENT
var cached_kind := -1
var texture_key := RID()
var last_seen := -1
var shield_color := Color.WHITE
var shield_center := Vector2.ZERO
var shield_radius := 0.0
var style := Color.WHITE
var batched := false:
	set(value):
		if batched != value:
			batched = value
			visible = not value
const ECHO_INTERVAL := 0.06
const ECHO_LIFETIME := 0.35
var echo_poses: Array[Transform2D] = []
var echo_times: Array[float] = []
var echo_clock := 0.0
var next_echo := 0.0
var last_pose := Transform2D.IDENTITY
var have_pose := false
var was_phased := false

static func quad_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, -0.5, 0.0),
		Vector3(0.5, -0.5, 0.0),
		Vector3(0.5, 0.5, 0.0),
		Vector3(-0.5, 0.5, 0.0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for layer_name in ["ThrustersGroup","BaseHullSprite","HardpointMounts","DecorativeParts","TurretMounts","HullEmissiveGlow","ShieldBubble"]:
		var layer := Node2D.new()
		layer.name = layer_name
		add_child(layer)
		layers.append(layer)
		layer.draw.connect(paint.bind(layer, layers.size() - 1))
	layers[1].add_child(hull)
	mask.fill(Color.WHITE)
	mask_texture = ImageTexture.create_from_image(mask)
	shader.shader = DamageShader
	shader.set_shader_parameter("armor_mask", mask_texture)
	hull.material = shader

func sync(vessel: Dictionary, livery: Color, delta: float = 0.0) -> void:
	ship = vessel
	if cached_kind != vessel.kind or cached_livery != livery:
		cached_kind = vessel.kind
		model = Hulls.MODELS[cached_kind]
		style = livery
		shield_color = style.lightened(0.22)
		hull.texture = Pixels.ship_texture(ship.kind, Color(model.paint).lerp(livery, 0.38))
		texture_key = hull.texture.get_rid()
		hull.centered = false
		var sprite_scale := float(model.get("sprite_scale", Hulls.CLASS_SPRITE[model.size]))
		hull.scale = Vector2.ONE * sprite_scale
		hull.offset = -Vector2(model.get("sprite_center", hull.texture.get_size() * 0.5))
		var shape := Battle.Defenses.geometry(cached_kind)
		shield_radius = shape.shield_radius
		shield_center = shape.shield_center
		var rect: Rect2 = shape.rect
		shader.set_shader_parameter("pixel_scale", sprite_scale)
		shader.set_shader_parameter("mask_origin", rect.position)
		shader.set_shader_parameter("mask_extent", rect.size)
		cached_livery = livery
	var phased := Battle.phased(ship)
	var pose := Transform2D(ship.heading, ship.pos)
	if phased or not echo_poses.is_empty():
		sample_phase(pose, phased, delta)
	last_pose = pose
	have_pose = true
	if was_phased != phased:
		was_phased = phased
		modulate = Color(0.64, 0.51, 0.95, 0.52) if phased else Color.WHITE
	if batched:
		return
	transform = pose
	var armor: float = ship.battle.armor
	if not is_equal_approx(cached_armor, armor):
		var grid := Battle.Defenses.grid_for(ship)
		var full := float(Hulls.COMBAT[ship.kind].armor) * 4.0 / grid.size()
		for i in grid.size():
			var value := clampf(grid[i] / maxf(0.001, full), 0.0, 1.0)
			mask.set_pixel(i % 7, floori(i / 7.0), Color(value, value, value))
		mask_texture.update(mask)
		cached_armor = armor
	shader.set_shader_parameter("flash", ship.battle.get("hit_flash", 0.0))
	shader.set_shader_parameter("impact_local", ship.battle.get("hit_local", Vector2.ZERO))
	for i in layers.size():
		if i != 1 and i != 6:
			layers[i].queue_redraw()

func sample_phase(pose: Transform2D, phased: bool, delta: float) -> void:
	echo_clock += delta
	while not echo_times.is_empty() and echo_clock - echo_times[0] >= ECHO_LIFETIME:
		echo_times.pop_front()
		echo_poses.pop_front()
	if not phased:
		return
	if not was_phased or echo_clock >= next_echo:
		# Capture the departure on a phase jump. A jump has no flight path between its endpoints.
		var sample := last_pose if not was_phased and have_pose else pose
		# A stationary cloak should not pile identical additive silhouettes onto the hull.
		if not echo_poses.is_empty() and echo_poses.back().is_equal_approx(sample):
			echo_times[-1] = echo_clock
		else:
			echo_poses.append(sample)
			echo_times.append(echo_clock)
		next_echo = echo_clock + ECHO_INTERVAL if not was_phased else echo_clock + ECHO_INTERVAL - fmod(echo_clock - next_echo, ECHO_INTERVAL)

func paint(layer: Node2D, index: int) -> void:
	if ship.is_empty():
		return
	var state: Dictionary = ship.battle
	if index == 0:
		var speed := Vector2(state.motion).length()
		if speed < 1.0:
			return
		for nozzle: Vector2 in model.get("engine_slots", []):
			var length := clampf(4.0 + speed * 0.065, 4.0, 22.0)
			layer.draw_colored_polygon(PackedVector2Array([nozzle + Vector2(0,-2.6), nozzle - Vector2(length,0), nozzle + Vector2(0,2.6)]), Color(style.lightened(0.2), 0.75))
			layer.draw_line(nozzle, nozzle - Vector2(length * 0.6,0), Color("e7fff9"), 1.4, true)
	elif index in [2,4]:
		for i in ship.fit.weapons.size():
			var id: String = ship.fit.weapons[i]
			if id.is_empty():
				continue
			var mount: Dictionary = Hulls.slot_spec(ship.kind, i)
			var fixed: bool = mount.type == "固定"
			if fixed != (index == 2):
				continue
			var angle := float(state.turret_angles[i]) if i < state.get("turret_angles", []).size() else deg_to_rad(mount.facing)
			var recoil: float = state.recoil[i] if i < state.get("recoil", []).size() else 0.0
			var style_info := WeaponArt.profile(id)
			var pose := WeaponArt.pose(mount,style_info,angle,recoil)
			var disabled: bool = i < state.get("disabled_slots", []).size() and state.disabled_slots[i] > 0.0
			WeaponArt.draw_mount(layer,pose,style_info.family,WeaponArt.tint(disabled,recoil))
			if recoil > 0.75 and not disabled:
				layer.draw_circle(pose*Vector2(7,0),1.9*recoil,Color("ffe8aa"))
	elif index == 3:
		for part in model.get("modules",[]):
			var health: float = state.get("module_integrity",{}).get(part.mount,{}).get("hp",part.hp)
			if health <= 0.0:
				continue
			var points: PackedVector2Array = part.bounds.duplicate()
			for i in points.size():
				points[i] += Vector2(part.offset)
			var color := Color("a2abb0").lerp(Color("643c30"),1.0 - health / float(part.hp))
			layer.draw_colored_polygon(points, color.darkened(0.25))
			points.append(points[0])
			layer.draw_polyline(points,color,1.2)
		if model.get("fighter_bays", 0) > 0:
			var phase := posmod(roundi(float(state.get("battle_seconds", 0.0)) * 3.0), 4)
			layer.draw_circle(Vector2(phase - 2.0, 1.5), 1.0, Color("f8c067"))
	elif index == 5 and (state.overload > 0.0 or state.system_time > 0.0 or state.vent):
		var color := Color("dea7f7") if state.overload > 0.0 else Color("62c9ea")
		for nozzle: Vector2 in model.get("engine_slots", []):
			layer.draw_circle(nozzle, 3.2, Color(color, 0.62))
