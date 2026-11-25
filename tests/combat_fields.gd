extends SceneTree

const Fields = preload("res://scripts/battle/combat_fields.gd")
const Visual = preload("res://scripts/battle/ship_visual.gd")
const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
var failures := 0
var viewport := SubViewport.new()
var world_layer := Node2D.new()
var fields := Fields.new()
var view := Visual.new()
var ship: Dictionary

class Arena:
	func combat_event(_kind, _point, _system, _direction, _strength = 1.0) -> void:
		pass

func check(ok: bool, label: String) -> void:
	if not ok:
		printerr("FAIL ",label)
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func submit(delta: float, copies: int = 1) -> void:
	view.batched = copies >= 12
	view.sync(ship, Color("8dd5de"), delta)
	fields.begin(copies, delta)
	for i in copies:
		fields.add_vessel(view)
	fields.finish()

func capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func glow(image: Image, point: Vector2) -> float:
	var peak := 0.0
	var p := Vector2i((world_layer.transform * point).round())
	for x in range(-2,3):
		for y in range(-2,3):
			peak = maxf(peak, image.get_pixelv(p + Vector2i(x,y)).v)
	return peak

func light_sum(image: Image) -> float:
	var total := 0.0
	for x in range(0,image.get_width(),4):
		for y in range(0,image.get_height(),4):
			total += image.get_pixel(x,y).v
	return total

func run() -> void:
	var gpu := DisplayServer.get_name() != "headless"
	viewport.size = Vector2i(440,360)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(world_layer)
	world_layer.add_child(fields.trails)
	world_layer.add_child(fields)
	root.add_child(view)
	var kind := Hulls.kind_for_reference("eagle")
	ship = {"id":7,"kind":kind,"system":0,"heading":-0.35,"pos":Vector2.ZERO,"fit":Hulls.stock_fit(kind),
		"battle":Hulls.battle_state(kind),"hp":Hulls.MODELS[kind].hp,"locked":true,"dock":0}
	Battle.ensure_state(ship)
	var state: Dictionary = ship.battle
	var shape := Battle.Defenses.geometry(kind)
	var radius: float = shape.shield_radius
	world_layer.transform = Transform2D(0.0, Vector2.ONE * 105.0 / radius, 0.0, Vector2(220,180))
	state.shield = true
	state.shield_arc_live = 1.8
	state.shield_offset = 1.0
	var center := Battle.Defenses.shield_world_center(ship)
	var facing: float = ship.heading + state.shield_offset
	var contact := center + Vector2.from_angle(facing + 0.56) * radius
	Battle.hit(Arena.new(),ship,0.2,0,contact,-Vector2.from_angle(facing + 0.56))
	check(is_equal_approx(state.shield_flash, 1.0),"combat hit recorded")
	submit(0.0)
	check(fields.shield_count == 1 and fields.jet_count == 0,"one shield in sparse mode")
	if gpu:
		var image := await capture()
		var front := center + Vector2.from_angle(facing + 0.56) * radius * 0.95
		var unhit := center + Vector2.from_angle(facing - 0.56) * radius * 0.95
		var rear := center - Vector2.from_angle(facing) * radius * 0.98
		check(glow(image,front) > glow(image,unhit) + 0.13,"bright shield hit at rotated impact")
		check(glow(image,rear) < 0.02,"shield arc clipped at rear")
		var side := center + Vector2.from_angle(facing + 0.56 - 0.42) * radius * 0.97
		var before := glow(image,side)
		state.shield_flash = 0.5
		submit(0.125)
		image = await capture()
		check(glow(image,side) > before + 0.12,"ripple travels away from impact")
		state.shield_flash = 0.0
		submit(0.125)
		image = await capture()
		check(glow(image,side) < before + 0.06,"impact light fades")
	submit(0.0,40)
	check(fields.shields.multimesh.visible_instance_count == 40,"all dense shields are submitted")
	for design in Hulls.MODELS.size():
		var pair := fields.ports(design)
		check(pair[0].is_finite() and pair[1].is_finite() and pair[0].y < pair[1].y,"two hull-edge outlets for %d" % design)
	state.shield = false
	state.vent = true
	submit(0.02,40)
	check(fields.shield_count == 0 and fields.steam.multimesh.visible_instance_count == 80,"all dense hulls vent from both sides")
	submit(0.05)
	if gpu:
		var steam := await capture()
		var pose := Transform2D(ship.heading,ship.pos)
		var outlets := fields.ports(kind)
		for i in 2:
			var outward := Vector2(-0.2,float(2*i-1)).normalized()
			check(glow(steam,pose * (outlets[i] + outward * 3.0)) > 0.15,"visible vent plume %d" % i)
	state.vent = false
	state.phase_active = true
	var departure: Vector2 = ship.pos
	ship.pos = Vector2(42,0)
	submit(0.02)
	check(fields.jet_count == 0 and view.echo_poses[0].origin == departure,"jump leaves source silhouette")
	for i in 6:
		ship.pos += Vector2(3,0)
		submit(0.06,40)
	check(view.echo_poses.size() >= 5 and view.echo_poses.size() <= 6,"bounded phase trail in dense mode")
	var group: Dictionary = fields.echo_batches[view.hull.texture]
	check(group.node.multimesh.visible_instance_count == 40 * view.echo_poses.size(),"all dense silhouettes submitted")
	var clock_before_pause := view.echo_clock
	submit(0)
	check(view.echo_clock == clock_before_pause,"paused trail is stationary")
	state.phase_active = false
	submit(0.36)
	check(view.echo_poses.is_empty() and group.node.multimesh.visible_instance_count == 0,"phase trail expires")
	if gpu:
		ship.pos = Vector2.ZERO
		submit(0.0)
		state.phase_active = true
		ship.pos = Vector2(80,0)
		submit(0.02)
		var bright: float = light_sum(await capture())
		state.phase_active = false
		submit(0.175)
		var fading: float = light_sum(await capture())
		submit(0.18)
		var expired: float = light_sum(await capture())
		check(bright > fading * 1.15 and fading > expired + 1.0,"rendered hull silhouette dims and disappears")
	print("Combat fields: 1/40 hull rendering paths, all hull vent positions, phase lifetime, GPU pixel checks=",gpu,", failures=", failures)
	quit(1 if failures else 0)
