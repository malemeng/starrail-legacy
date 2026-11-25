extends SceneTree

const Batch = preload("res://scripts/battle/fleet_batch.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var result := GDExtensionManager.load_extension("res://native/battle/fleet_collision.gdextension") if OS.has_feature("windows") else -1
	if not ClassDB.class_exists(&"FleetStrokes"):
		print("Native fleet strokes unavailable on ",OS.get_name()," (",result,")")
		quit(1 if OS.has_feature("windows") else 0)
		return
	var native: RefCounted = ClassDB.instantiate(&"FleetStrokes")
	var batch := Batch.new()
	root.add_child(batch)
	native.begin_frame()
	var pose := Transform2D(0.32,Vector2(-12,29))
	var point := Vector2(9,-5)
	var axis := Vector2.from_angle(0.85)
	var gun_end := point + axis * 4.0
	native.mounts(pose,[{"offset":point,"size":2,"facing":-15.0}],["test"],[0.85],[1.0],[0.2])
	batch.segment(pose * point,pose * gun_end,2.4,Color("976657"))
	batch.segment(pose * gun_end,pose * (gun_end+axis*3),2.2,Color("ffe4a4"))
	native.engines(pose,[point],6.0,Color.CYAN)
	batch.segment(pose * point,pose * (point-Vector2(6,0)),2.6,Color.CYAN)
	native.shield(point,30.0,0.6,0.5,Color.WHITE)
	for i in 3:
		batch.segment(point + Vector2.from_angle(0.35 + 0.5*i/3)*30,point + Vector2.from_angle(0.35 + 0.5*(i+1)/3)*30,1.6,Color.WHITE)
	var shot := {"pos":Vector2(2,3),"vel":Vector2.RIGHT,"system":0,"type":2,"missile":true}
	var flare := shot.duplicate()
	flare.ordnance = "flare"
	var distant := shot.duplicate()
	distant.system = 1
	var extras: Array = native.projectiles([shot,flare,distant],0,Batch.SHOT_COLORS,{"flare":true})
	check(extras == [flare] and native.projectile_count() == 2,"Local projectile count or special dispatch differs")
	batch.segment(shot.pos-Vector2(11,0),shot.pos,1.7,Batch.SHOT_COLORS[2])
	batch.segment(shot.pos-Vector2(21,0),shot.pos-Vector2(11,0),2.4,Color("a6a19b"))
	check(native.count() == batch.count,"Different number of rendered strokes")
	var packed: PackedFloat32Array = native.buffer(PackedFloat32Array(),0)
	for i in batch.count * Batch.STRIDE:
		if absf(packed[i]-batch.instances[i]) > 0.0001:
			check(false,"Different vertex or color at offset %d" % i)
	var single := PackedFloat32Array()
	single.resize(Batch.STRIDE)
	single.fill(0.5)
	packed = native.buffer(single,1)
	check(packed.slice(batch.count*Batch.STRIDE,(batch.count+1)*Batch.STRIDE) == single,"Custom effects lost at end of native batch")
	native.begin_frame()
	var mount := {"offset":point,"size":2,"facing":-15.0}
	native.hull_mounts(5,pose,[mount],["test"],[],[],[])
	var cached: PackedFloat32Array = native.buffer(PackedFloat32Array(),0)
	native.begin_frame()
	native.mounts(pose,[mount],["test"],[],[],[])
	check(cached.slice(0,Batch.STRIDE) == native.buffer(PackedFloat32Array(),0).slice(0,Batch.STRIDE),"Cached geometry differs on a resting turret")
	native.begin_frame()
	batch.count = 0
	var effects := []
	for kind in ["beam","emp","intercept","shield","impact","muzzle","rupture","system","overload","vent","unknown"]:
		effects.append({"event":{"kind":kind,"serial":71,"system":2,"direction":Vector2(0.65,-0.4),"pos":point},"age":0.12})
	effects.append({"event":{"kind":"beam","system":7},"age":0.1})
	native.events(effects,2)
	batch.draw_events(effects,2)
	packed = native.buffer(single,1)
	check(native.count() == batch.count and packed.slice(0,Batch.STRIDE) == single,"Script-only details must precede event strokes")
	for i in batch.count * Batch.STRIDE:
		if absf(batch.instances[i]-packed[i+Batch.STRIDE]) > 0.0001:
			check(false,"Event geometry, fade or order differs at offset %d" % i)
	print("Fleet strokes: ",batch.count," quads, ",failures," differences")
	batch.free()
	quit(1 if failures else 0)
