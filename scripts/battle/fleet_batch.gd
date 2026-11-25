extends MultiMeshInstance2D

# Every segment is an independently colored, transformed quad. One canvas draw
# covers thrusters, wings and projectile trails. Textured guns are batched by family.
const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const ShipVisual = preload("res://scripts/battle/ship_visual.gd")
const Ordnance = preload("res://scripts/battle/ordnance_visuals.gd")
const WingVisuals = preload("res://scripts/battle/wing_visuals.gd")
const SHOT_COLORS := [Color("b1d4eb"), Color("f4a273"), Color("69cedc"), Color("bbbd86")]
const RESTING_SLOTS := []
var count := 0
var projectile_count := 0
var native: RefCounted
var native_events := false
var weapons := preload("res://scripts/battle/weapon_batch.gd").new()
const STRIDE := 12
var instances := PackedFloat32Array()

func _ready() -> void:
	add_child(weapons)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = 2048
	instances.resize(multimesh.instance_count * STRIDE)
	multimesh.visible_instance_count = 0

func segment(start: Vector2, end: Vector2, width: float, color: Color) -> void:
	var delta := end - start
	if delta.length_squared() < 0.001:
		return
	var offset := count * STRIDE
	if offset >= instances.size():
		instances.resize(instances.size() * 2)
	var normal := delta.orthogonal().normalized() * width
	# RenderingServer stores a 2D transform as two padded rows, followed by RGBA.
	instances[offset] = delta.x
	instances[offset+1] = normal.x
	instances[offset+3] = (start.x + end.x) * 0.5
	instances[offset+4] = delta.y
	instances[offset+5] = normal.y
	instances[offset+7] = (start.y + end.y) * 0.5
	instances[offset+8] = color.r
	instances[offset+9] = color.g
	instances[offset+10] = color.b
	instances[offset+11] = color.a
	count += 1

func sync(visuals: Dictionary, shots: Array, effects: Array, system: int, wings: Array) -> void:
	count = 0
	projectile_count = 0
	if native == null and ClassDB.class_exists(&"FleetStrokes"):
		native = ClassDB.instantiate(&"FleetStrokes")
		native_events = native.has_method(&"events")
	if native != null:
		native.begin_frame()
	var capacity := 0
	for view: ShipVisual in visuals.values(): capacity += view.ship.fit.weapons.size()
	weapons.begin(capacity)
	for view: ShipVisual in visuals.values():
		var ship: Dictionary = view.ship
		var model: Dictionary = view.model
		var state: Dictionary = ship.battle
		var transform := view.last_pose
		for part in model.get("modules", []):
			var integrity: Dictionary = state.get("module_integrity",{}).get(part.mount,{})
			if integrity.get("hp",part.hp) <= 0:
				continue
			var points: PackedVector2Array = part.bounds
			var origin: Vector2 = part.offset
			var hull_tone := Color("a2abb0").lerp(Color("643c30"),1.0 - float(integrity.get("hp",part.hp)) / float(part.hp))
			for i in points.size():
				segment(transform*(origin+points[i-1]),transform*(origin+points[i]),1.5,hull_tone)
		var speed := Vector2(state.motion).length()
		if speed > 1.0 and native != null:
			native.engines(transform,model.engine_slots,clampf(speed*0.06,3.0,18.0),view.style.lightened(0.3))
		elif speed > 1.0:
			for nozzle: Vector2 in model.engine_slots:
				segment(transform*nozzle, transform*(nozzle - Vector2(clampf(speed*0.06,3.0,18.0),0)), 2.6, view.style.lightened(0.3))
		# Newly spawned and dock-released ships may be drawn before their first combat tick.
		var angles: Array = state.get("turret_angles",RESTING_SLOTS)
		var recoil_by_slot: Array = state.get("recoil",RESTING_SLOTS)
		var disabled: Array = state.get("disabled_slots",RESTING_SLOTS)
		for i in ship.fit.weapons.size():
			var id: String = ship.fit.weapons[i]
			if id.is_empty(): continue
			var mount: Dictionary = model.mounts[i]
			var angle: float = angles[i] if i < angles.size() else deg_to_rad(float(mount.facing))
			var recoil: float = recoil_by_slot[i] if i < recoil_by_slot.size() else 0.0
			weapons.add_mount(transform,mount,id,angle,recoil,i < disabled.size() and disabled[i] > 0)
	weapons.finish()
	for flight in wings:
		WingVisuals.formation(flight[0],flight[1],flight[2],segment)
	var remaining: Array = shots
	if native != null:
		remaining = native.projectiles(shots,system,SHOT_COLORS,Ordnance.GLYPHS)
		projectile_count = native.projectile_count()
	for shot in remaining:
		if shot.system != system:
			continue
		if native == null:
			projectile_count += 1
		var kind: String = shot.get("ordnance","")
		if Ordnance.GLYPHS.has(kind):
			Ordnance.draw_shot(kind, shot.pos, shot.vel, segment)
			continue
		if shot.get("mine",false):
			segment(Vector2(shot.pos)-Vector2(4,0),Vector2(shot.pos)+Vector2(4,0),3.5,Color("ee8955"))
			continue
		var axis := Vector2(shot.vel).normalized()
		segment(Vector2(shot.pos) - axis * (11.0 if shot.missile else 18.0), shot.pos, 1.7, SHOT_COLORS[shot.type])
		if shot.missile:
			segment(Vector2(shot.pos)-axis*21.0,Vector2(shot.pos)-axis*11.0,2.4, Color("a6a19b"))
	if native_events:
		native.events(effects,system)
	else:
		draw_events(effects,system)
	var output := instances
	if native != null:
		output = native.buffer(instances,count)
		count += native.count()
	if output.size() != multimesh.instance_count * STRIDE:
		multimesh.instance_count = output.size() / STRIDE
	multimesh.buffer = output
	multimesh.visible_instance_count = count

func draw_events(effects: Array, system: int) -> void:
	for particle in effects:
		var event: Dictionary = particle.event
		if event.system != system:
			continue
		var age: float = particle.age
		var at: Vector2 = event.pos
		var fade := clampf(1.0 - age * 3.0, 0.0, 1.0)
		match event.kind:
			"beam":
				segment(at,at+Vector2(event.direction),2.0,Color(0.7,0.96,1.0,fade))
			"emp","intercept","shield":
				var side := Vector2(event.direction).orthogonal().normalized()
				segment(at - side*6.0,at + side*6.0,2.0,Color(0.65,0.74,1.0,fade))
			"impact","muzzle","rupture":
				var axis := Vector2.from_angle(float(event.serial))
				segment(at - axis*3.0,at + axis * (5.0+age*15),2.1,Color(1.0,0.69,0.37,fade))
			"system","overload","vent":
				var radius := 4.0 + age * 20.0
				var tone := Color(0.59,0.86,1.0,fade)
				segment(at-Vector2(radius,0),at-Vector2(radius*0.5,0),1.7,tone)
				segment(at+Vector2(radius*0.5,0),at+Vector2(radius,0),1.7,tone)
