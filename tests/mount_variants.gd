extends SceneTree

const Hulls = preload("res://hull_catalog.gd")
const Battle = preload("res://combat.gd")
const Registry = preload("res://scripts/fleet/mod_registry.gd")
var failures := 0
var checks := 0

class Arena:
	var projectiles := []
	func combat_event(_kind, _point, _system, _direction = Vector2.ZERO, _strength = 1.0) -> void:
		pass
	func enemy(a, b) -> bool:
		return a.flag != b.flag

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		printerr("FAIL ",label)
		failures += 1

func reject_variant(base: Dictionary, valid: Dictionary, broken: Dictionary, label: String) -> void:
	var models := [base]
	var indexes := {"beacon_ff":0}
	var events := []
	var used := {}
	var before := base.duplicate(true)
	broken.id = "waypost.invalid"
	var pack := {"id":"waypost","hulls":[valid.hulls[0],broken],"events":valid.events}
	check(not Registry.add_pack(pack,models,indexes,used,events,Hulls.WEAPONS),label)
	check(models.size() == 1 and models[0] == before and indexes.size() == 1 and used.is_empty() and events.is_empty(),label+" rolls back the whole pack")

func installed_sample() -> void:
	var kind := Hulls.kind_for_id("waypost.dispatch")
	check(kind >= 0 and Hulls.available_for_market(kind),"installed hull registered through user://mods")
	if kind < 0:
		return
	var slot := Hulls.slot_spec(kind,0)
	check(slot.id == "bay_01" and slot.offset.is_equal_approx(Vector2(2.5,-2.2)) and slot.arc == 140.0 and slot.facing == -35.0,"catalog geometry uses override")
	check(slot.type == "炮塔" and slot.size == 2 and Hulls.weapon_compatible(kind,0,"rail") and not Hulls.weapon_compatible(kind,0,"missile_00"),"refit uses mixed family and medium size")
	var aft := Hulls.slot_spec(kind,3)
	check(aft.id == "aft_pd" and aft.builtin and Hulls.SLOTS["waypost.dispatch/aft_pd"] == aft and not Hulls.weapon_compatible(kind,3,""),"new built-in slot has stable ID and is locked")
	var fit := Hulls.stock_fitting(kind)
	check(fit.weapons == ["rail_00","missile_00","pd","pd"] and fit.groups == [1,2,3,3] and Hulls.fitting_cost(kind,fit) == 16,"actual stock fit consumes all 16 OP")
	var ship := {"id":1,"kind":kind,"fit":fit,"battle":Hulls.battle_state(kind),"system":0,"pos":Vector2(23,45),
		"heading":0.16,"flag":1,"owner":0,"raid":-1}
	var arena := Arena.new()
	var muzzle := Battle.slot_position(ship,0)
	var forward := Vector2.from_angle(ship.heading + deg_to_rad(slot.facing))
	check(not Battle.fire_slot(arena,ship,0,muzzle-forward*90.0),"rotated turret rejects target outside configured arc")
	check(Battle.group_fire(arena,ship,1,muzzle+forward*90.0) == 1 and arena.projectiles[0].pos.is_equal_approx(muzzle),"primary battery actually fires from moved mount")
	var aft_muzzle := Battle.slot_position(ship,3)
	var aft_axis := Vector2.from_angle(ship.heading + deg_to_rad(aft.facing))
	var missile := {"hp":5.0,"flag":2,"system":0,"missile":true,"pos":aft_muzzle+aft_axis*35.0,"vel":-aft_axis*140.0}
	ship.battle.cooldowns[2] = 10.0
	Battle.point_defense(arena,ship,[missile],[])
	check(ship.battle.recoil[3] > 0.0 and missile.hp < 5.0,"added aft gun actually intercepts incoming missile")

func _initialize() -> void:
	var base: Dictionary = Hulls.read_catalog("res://data/fleet/fleet.json").models[0]
	var sample := Hulls.read_catalog("res://examples/mods/waypost/fleet.json")
	var models := [base]
	var indexes := {"beacon_ff":0}
	var events := []
	check(Registry.add_pack(sample,models,indexes,{},events,Hulls.WEAPONS),"sample pack accepts legal mounts")
	if models.size() > 1:
		check(models[1].mounts[1] == base.mounts[1] and models[1].mounts[3].id == "aft_pd" and base.mounts.size() == 3 and events.size() == 2,"inherits untouched slots and commits alongside sample events")
	var overlay := {"id":"mount_swap","hulls":[{"id":"beacon_ff","base":"beacon_ff","override":true,
		"mounts":[{"id":"bay_03","type":"固定","arc":12},{"id":"bay_01","group":2}]}]}
	check(Registry.add_pack(overlay,models,indexes,{},[],Hulls.WEAPONS) and models[0].name == base.name and
		models[0].mounts[2].type == "固定" and models[0].combat.groups[0] == 2 and models[0].mounts[1] == base.mounts[1],
		"sparse override retains identity and matches slot IDs in reverse order")
	var valid: Dictionary = sample.hulls[0]
	for override in [{"offset":[342,69]},{"offset":["2",1]},{"facing":"bow"},{"arc":-1},{"arc":361},{"size":1.5},
			{"family":"typo"},{"family":"missile"},{"type":"torpedo"},{"stock":"missing_weapon"},
			{"stock":"pulse_06"},{"group":4},{"accepts":["missile"]}]:
		var broken := valid.duplicate(true)
		broken.mounts[0].merge(override,true)
		reject_variant(base,sample,broken,"invalid mount "+str(override))
	var vacant := valid.duplicate(true)
	vacant.mounts[1].stock = ""
	reject_variant(base,sample,vacant,"empty built-in mount")
	var duplicate := valid.duplicate(true)
	duplicate.mounts.append(duplicate.mounts[0])
	reject_variant(base,sample,duplicate,"duplicate slot override")
	var unknown := valid.duplicate(true)
	unknown.mounts.append({"id":"bay_99","stock":"pd"})
	reject_variant(base,sample,unknown,"incomplete new mount")
	var expensive := valid.duplicate(true)
	expensive.combat.op = 15
	reject_variant(base,sample,expensive,"stock exceeds OP by one")
	if "--sample" in OS.get_cmdline_user_args():
		installed_sample()
	print("Mount variants: ",checks," checks, failures=",failures)
	quit(1 if failures else 0)
