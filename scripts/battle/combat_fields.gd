extends Node2D

const Battle = preload("res://combat.gd")
const Shield = preload("res://scripts/battle/shield_arc.gdshader")
const Steam = preload("res://scripts/battle/vent_steam.gdshader")
const ShipVisual = preload("res://scripts/battle/ship_visual.gd")
const ARC_STEPS := 64
var shields: MultiMeshInstance2D
var steam: MultiMeshInstance2D
var trails := Node2D.new()
var echo_batches: Dictionary = {}
var echo_material := CanvasItemMaterial.new()
var vent_ports: Dictionary = {}
var vent_poses: Dictionary = {}
var plume_time := 0.0
var shield_count := 0
var jet_count := 0
var ship_capacity := 0

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	steam = batch(quad, Steam)
	shields = batch(arc_mesh(), Shield)
	add_child(steam)
	add_child(shields)
	echo_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

func batch(mesh: Mesh, shader: Shader = null) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_2D
	instances.use_colors = true
	instances.use_custom_data = shader != null
	instances.mesh = mesh
	node.multimesh = instances
	if shader != null:
		var material := ShaderMaterial.new()
		material.shader = shader
		node.material = material
	return node

func reserve(instances: MultiMesh, count: int) -> void:
	if instances.instance_count < count:
		instances.instance_count = nearest_po2(maxi(count, 8))

func arc_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in ARC_STEPS + 1:
		var fraction := float(i) / ARC_STEPS
		var direction := Vector2.from_angle((fraction - 0.5) * TAU)
		for side in 2:
			var point := direction * (0.72 if side == 0 else 1.012)
			vertices.append(Vector3(point.x, point.y, 0.0))
			uv.append(Vector2(fraction, side))
		if i < ARC_STEPS:
			var a := i * 2
			indices.append_array(PackedInt32Array([a,a+1,a+2,a+1,a+3,a+2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func begin(ship_count: int, delta: float) -> void:
	plume_time = fposmod(plume_time + delta, TAU * 100.0)
	ship_capacity = ship_count
	shield_count = 0
	jet_count = 0
	for group in echo_batches.values():
		group.views.clear()
		group.count = 0

func add_vessel(view: ShipVisual) -> void:
	var ship: Dictionary = view.ship
	var state: Dictionary = ship.battle
	if state.shield and state.get("shield_arc_live", 0.0) > 0.01:
		if shield_count == 0:
			reserve(shields.multimesh, ship_capacity)
			shields.material.set_shader_parameter("pulse_time", fmod(plume_time * 20.0, TAU))
		var facing: float = state.shield_offset
		var hit := angle_difference(facing, float(state.get("shield_hit_angle",0.0)))
		shields.multimesh.set_instance_transform_2d(shield_count, Transform2D(ship.heading + facing,
			Vector2.ONE * view.shield_radius, 0.0, view.last_pose * view.shield_center))
		shields.multimesh.set_instance_color(shield_count, view.shield_color)
		shields.multimesh.set_instance_custom_data(shield_count, Color(state.shield_arc_live / TAU,
			hit / TAU + 0.5, state.get("shield_flash",0.0), clampf(Battle.fraction(ship),0.0,1.0)))
		shield_count += 1
	if state.vent:
		if jet_count == 0:
			reserve(steam.multimesh, ship_capacity * 2)
		add_steam(ship, view.last_pose)
	if not view.echo_poses.is_empty():
		var source := view.hull.texture
		if not echo_batches.has(source):
			var node := batch(steam.multimesh.mesh)
			node.material = echo_material
			node.texture = source
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			trails.add_child(node)
			echo_batches[source] = {"node":node,"views":[],"count":0}
		var group: Dictionary = echo_batches[source]
		group.views.append(view)
		group.count += view.echo_poses.size()

func ports(kind: int) -> PackedVector2Array:
	if vent_ports.has(kind):
		return vent_ports[kind]
	var shape := Battle.Defenses.geometry(kind)
	var box: Rect2 = shape.rect
	var x := box.position.x + box.size.x * 0.38
	var outline: PackedVector2Array = shape.bounds
	var low := INF
	var high := -INF
	for i in outline.size():
		var a := outline[i-1]
		var b := outline[i]
		if x < minf(a.x,b.x) or x > maxf(a.x,b.x) or is_equal_approx(a.x,b.x):
			continue
		var y := lerpf(a.y,b.y,(x-a.x)/(b.x-a.x))
		low = minf(low, y)
		high = maxf(high, y)
	var result := PackedVector2Array([Vector2(x,low),Vector2(x,high)])
	vent_ports[kind] = result
	return result

func add_steam(ship: Dictionary, pose: Transform2D) -> void:
	if not vent_poses.has(ship.kind):
		var outlets := ports(ship.kind)
		var length := clampf(outlets[0].distance_to(outlets[1]) * 0.85 + 12.0, 18.0, 85.0)
		var poses: Array[Transform2D] = []
		for i in 2:
			var outward := Vector2(-0.20, float(i * 2 - 1)).normalized()
			poses.append(Transform2D(outward * length, outward.orthogonal() * length * 0.47,
				outlets[i] + outward * length * 0.5))
		vent_poses[ship.kind] = poses
	var local: Array[Transform2D] = vent_poses[ship.kind]
	for i in 2:
		steam.multimesh.set_instance_transform_2d(jet_count, pose * local[i])
		steam.multimesh.set_instance_custom_data(jet_count, Color(fposmod(plume_time * 3.4 + ship.id * 0.17 + i * 0.43, 1.0),0,0))
		jet_count += 1

func finish() -> void:
	shields.multimesh.visible_instance_count = shield_count
	steam.multimesh.visible_instance_count = jet_count
	for group in echo_batches.values():
		var instances: MultiMesh = group.node.multimesh
		reserve(instances, group.count)
		var row := 0
		for view: ShipVisual in group.views:
			var dimensions := view.hull.texture.get_size() * view.hull.scale
			var center := dimensions * 0.5 + view.hull.offset * view.hull.scale
			for i in view.echo_poses.size():
				var pose := view.echo_poses[i]
				var life := 1.0 - (view.echo_clock - view.echo_times[i]) / ShipVisual.ECHO_LIFETIME
				instances.set_instance_transform_2d(row, Transform2D(pose.x * dimensions.x, pose.y * dimensions.y, pose * center))
				instances.set_instance_color(row, Color(0.54,0.36,0.96,life * 0.55))
				row += 1
		instances.visible_instance_count = row
