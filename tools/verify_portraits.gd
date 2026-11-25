extends SceneTree

const World = preload("res://world.gd")
const Portrait = preload("res://portrait.gd")
const Pixels = preload("res://art/pixel_art.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ",label)

func region_hash(look: Dictionary, area: Rect2i) -> int:
	return hash(Pixels.portrait(look).get_region(area).get_data())

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"layered-portraits","systems":24,"factions":8})
	var actor := world.active()
	actor.look = {"face":0,"skin":1,"cut":1,"hair":0,"eyes":1,"iris":0,"nose":2,"mouth":2,"wear":2,"mark":0}
	actor.birth = world.day - 39*360
	var genes: Dictionary = actor.look.duplicate()
	var faces := {}
	var cuts := {}
	var uniforms := {}
	var area := Rect2i(30,18,68,67)
	var garment := Rect2i(0,103,128,41)
	for flag in range(8):
		actor.flag = flag
		var look := Portrait.for_actor(world,actor)
		check(look.uniform == flag and look.uniform_style == world.factions[flag].style,"faction identity "+str(flag))
		faces[region_hash(look,area)] = true
		# Matching trim/lighting and a common phenotype isolate each uniform's trim pattern.
		look.uniform_color = "00ff00"
		look.uniform_style = 0
		look.regalia = false
		var img := Pixels.portrait(look)
		var stitches := PackedByteArray()
		for y in range(103,144):
			for x in range(128):
				stitches.append(1 if img.get_pixel(x,y) == Color.GREEN else 0)
		cuts[hash(stitches)] = true
		uniforms[region_hash(look,garment)] = true
	check(faces.size() == 1 and cuts.size() == 8 and uniforms.size() == 8,"eight independently cut uniforms on one unchanged face")
	actor.flag = -1
	var unaligned := Portrait.for_actor(world,actor)
	check(not unaligned.has("uniform") and unaligned.wear == 2,"civilian creator clothing")
	check(Pixels.portrait(unaligned).get_size() == Vector2i(128,144),"native portrait size")
	var adult := region_hash(unaligned,area)
	actor.birth = world.day - 50*360
	var mature := Portrait.for_actor(world,actor)
	check(mature.age_band == 1 and region_hash(mature,area) != adult,"silver hair and creases at fifty")
	actor.birth = world.day - 68*360
	var senior := Portrait.for_actor(world,actor)
	check(senior.age_band == 2 and region_hash(senior,area) != region_hash(mature,area),"late-life ageing")
	actor.death_day = world.day - 19*360
	check(Portrait.for_actor(world,actor).age_band == 0,"memorial portrait remains at death age")
	actor.erase("death_day")
	actor.birth = world.day-39*360
	actor.stress = 210
	var stressed := Portrait.for_actor(world,actor)
	check(stressed.stress_tier == 2 and region_hash(stressed,area) != adult,"severe stress changes eyes and hair")
	actor.stress = 0
	actor.injured_until = world.day + 30
	var injured := Portrait.for_actor(world,actor)
	check(injured.wounded and region_hash(injured,area) != adult,"injury has a visible bandage")
	world.day += 31
	check(not Portrait.for_actor(world,actor).wounded,"healed injury clears the dressing")
	actor.health = 0.3
	var sick := Portrait.for_actor(world,actor)
	check(sick.low_health and region_hash(sick,area) != adult,"illness changes eyelids")
	actor.erase("health")
	actor.flag = 1
	actor.noble = true
	world.factions[1].leader = 0
	var ordinary := Portrait.for_actor(world,actor)
	world.factions[1].leader = actor.id
	var leader := Portrait.for_actor(world,actor)
	check(leader.regalia and region_hash(leader,garment) != region_hash(ordinary,garment),"faction leader regalia")
	var crest := int(leader.crest)
	for culture in ["岚湾","群岛","石泽","刀谷","岸灯"]:
		actor.culture = culture
		if int(Portrait.for_actor(world,actor).crest) != crest:
			break
	check(region_hash(Portrait.for_actor(world,actor),garment) != region_hash(leader,garment),"culture modifies heraldic pin")
	var tex := Pixels.portrait_texture(leader)
	var count := Pixels.portrait_cache.size()
	check(tex == Pixels.portrait_texture(leader),"stable phenotype texture reused")
	check(tex != Pixels.portrait_texture(sick) and count == Pixels.portrait_cache.size(),"state replaces cached appearance")
	var child := Portrait.inherit(actor.look,actor.look,world.rng)
	check(actor.look == genes and not child.has("uniform") and not child.has("wounded"),"campaign appearance never overwrites inherited genes")
	print("Portrait checks ",checks,", failures ",failures)
	quit(1 if failures else 0)
