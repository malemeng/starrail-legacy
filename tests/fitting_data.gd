extends SceneTree

const Hulls = preload("res://hull_catalog.gd")
const Ship = preload("res://scripts/models/ship_data.gd")
const Fitting = preload("res://scripts/models/fitting_data.gd").FittingData
const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Battle = preload("res://combat.gd")
var checks := 0
var failures := 0

func check(condition: bool, caption: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",caption)

func _initialize() -> void:
	var grouped := Fitting.new()
	grouped.weapons.assign(["gun","pd","","gun"])
	grouped.groups.assign([2,2,1,2])
	var catalog := {"gun":{"pd":false},"pd":{"pd":true}}
	check(grouped.fire_groups(catalog) == [[],[0,3],[]],"indexed fire groups preserve slot order and skip point defense")
	grouped.groups[3] = 3
	check(grouped.fire_groups(catalog) == [[],[0],[3]],"active battle group changes invalidate the slot index")
	grouped.weapons[1] = "gun"
	check(grouped.fire_groups(catalog) == [[],[0,1],[3]],"replacing point defense invalidates the slot index")
	var kind := Hulls.kind_for_id("beacon_ff")
	var vessel := Ship.create(5,kind,2,2,1,0,Vector2.ZERO,Vector2.ZERO,4,[0])
	var fit: Fitting = vessel.fit
	check(fit != null and fit.weapons.get_typed_builtin() == TYPE_STRING and fit.groups.get_typed_builtin() == TYPE_INT and fit.auto.get_typed_builtin() == TYPE_BOOL,"typed live fitting on a new vessel")
	check(Hulls.fitting_cost(kind,fit) == Hulls.fitting_cost(kind,Hulls.stock_fit(kind)),"stock OP matches public catalog dictionary")
	var original := fit.as_dictionary()
	var independent := fit.copy()
	independent.weapons[0] = ""
	check(fit.as_dictionary() == original and not fit.matches(independent),"refit trial never mutates live fitting")
	var external := fit.as_dictionary()
	external.auto[0] = true
	check(not fit.auto[0] and not external.auto.is_typed(),"detached plain arrays for agent output")
	var json_record: Dictionary = JSON.parse_string(JSON.stringify(original))
	check(fit.matches(Fitting.from_dictionary(json_record,true)),"JSON number round trip")
	json_record.groups[0] = 2.5
	check(Fitting.from_dictionary(json_record,true) == null,"reject fractional JSON group")
	for invalid in [{"groups":[true,1]},{"caps":"3"},{"weapons":[false,0]},{"auto":[1,false,false]}]:
		var invalid_record := original.duplicate(true)
		invalid_record.merge(invalid,true)
		check(Fitting.from_dictionary(invalid_record) == null,"reject malformed dictionary "+str(invalid))
	fit.groups[0] = 2
	fit.caps = 1
	fit.auto[1] = true
	vessel.battle.cooldowns[0] = 0.45
	var record := Ship.encode(vessel)
	check(record.fit is Dictionary and not record.fit.has("weapons") and record.fit.mounts[Hulls.slot_spec(kind,0).id].group == 2,"V7 stable mount IDs on disk")
	check(not record.fit.auto.is_typed() and record.fit.auto != [false,false,false] and fit.auto[1],"V7 booleans are detached and untyped")
	var compatible := bytes_to_var(var_to_bytes(record)) as Dictionary
	var loaded := Ship.decode(compatible,1)
	check(loaded.fit is Fitting and loaded.fit.matches(fit) and loaded.battle.cooldowns[0] == 0.45,"binary V7 save reconstructs independent runtime fitting")
	compatible.fit.auto[1] = false
	check(loaded.fit.auto[1] and fit.auto[1],"old snapshot edits cannot modify a live vessel")
	compatible.fit.mounts[Hulls.slot_spec(kind,0).id].group = "2"
	check(Ship.decode(compatible,1).is_empty(),"V7 reader rejects malformed mount metadata")
	verify_carrier()
	print("Fitting data checks %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func verify_carrier() -> void:
	var world := World.new()
	world.new_game({"seed":"wing-refit","systems":12,"factions":3})
	var port: Dictionary = world.ports[world.ride().dock]
	var kind := Hulls.kind_for_reference("heron")
	var id: int = world.ship(kind,world.player,0,world.active().flag,port.system,port.pos,port.id)
	check(world.pilot(id),"pilot boards test carrier at a real dock")
	var carrier: Dictionary = world.ride()
	var pilot: Dictionary = world.active()
	var stock: Array = carrier.fit.wings.duplicate()
	var legacy := Ship.encode(carrier)
	legacy.fit.erase("wings")
	check(Ship.decode(legacy,carrier.cargo.size()).fit.wings == stock,"older V7 carrier save uses its hull's original wings")
	var invalid: Fitting = carrier.fit.copy()
	invalid.wings.pop_back()
	check(not world.outfit(id,invalid),"carrier rejects wrong bay count")
	invalid = carrier.fit.copy()
	invalid.wings[0] = "invalid_wing"
	check(not world.outfit(id,invalid),"carrier rejects unknown wing")
	var fixed := Hulls.kind_for_reference("shepherd")
	var fixed_fit := Hulls.stock_fitting(fixed)
	fixed_fit.wings[0] = stock[0]
	check(Hulls.fitting_cost(fixed,fixed_fit) < 0,"built-in mining drones cannot be replaced")
	var wanted: Array = ["gladius_wing","claw_wing","claw_wing"]
	var price := 14*8 + int(Hulls.wing_spec(wanted[0]).price) + 2*int(Hulls.wing_spec(wanted[1]).price) - 3*floori(Hulls.wing_spec(stock[0]).price*0.5)
	pilot.wallet = price-1
	check(not Economy.refit_preset(world,port.id,"heron_Attack2") and carrier.fit.wings == stock and pilot.wallet == price-1,"unaffordable wings and tuning roll back together")
	pilot.wallet = 10000
	check(Economy.refit_preset(world,port.id,"heron_Attack2") and carrier.fit.wings == wanted and pilot.wallet == 10000-price,"real carrier preset settles wing purchases and trade-ins")
	world.depart(carrier)
	var enemy := {"id":-1,"pos":port.pos+Vector2(990,0)}
	Battle.ensure_state(carrier)
	Battle.Wings.advance(world,carrier,enemy,0.1,Battle)
	check(carrier.battle.fighter_wings.map(func(w): return w.id) == wanted and carrier.battle.fighter_wings[0].sortie,"first preset launches assigned squadrons")
	check(world.berth(carrier,port.id),"carrier redocks normally")
	check(Economy.refit_preset(world,port.id,"heron_Strike"),"install the same carrier's strike preset")
	var reloaded := World.new()
	check(reloaded.load_state(world.snapshot()),"whole V7 world reloads with edited carrier and previous sorties")
	carrier = reloaded.ride()
	reloaded.depart(carrier)
	Battle.Wings.advance(reloaded,carrier,enemy,0.1,Battle)
	var after: Array = carrier.battle.fighter_wings.map(func(w): return w.id)
	check(after == ["dagger_wing","dagger_wing","broadsword_wing"] and carrier.battle.fighter_wings[0].role == "bomber" and carrier.battle.fighter_wings[0].sortie,"post-load departure launches new bombers in the correct bays")
