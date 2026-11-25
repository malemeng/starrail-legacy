extends SceneTree

const World = preload("res://world.gd")
const Economy = preload("res://economy.gd")
const Hulls = preload("res://hull_catalog.gd")
var count := 0
var failed := 0

func check(value: bool, note: String) -> void:
	count += 1
	if not value:
		failed += 1
		printerr("FAIL ",note)

func _initialize() -> void:
	var world = World.new()
	world.new_game({"seed":"outfit-acquisition","systems":12,"factions":3,"avatar":{"name":"船坞测试","house":"远岸"}})
	var ship: Dictionary = world.ride()
	var station: Dictionary = world.ports[ship.dock]
	var pilot: Dictionary = world.active()
	var preset: Dictionary = Hulls.presets(ship.kind).front()
	var fit := Hulls.preset_fit(ship.kind,preset.id)
	var old: Dictionary = ship.fit.as_dictionary()
	var cost := 8*(int(fit.caps)+int(fit.vents))
	pilot.wallet = cost-1
	check(not Economy.refit_preset(world,station.id,preset.id) and ship.fit.as_dictionary() == old and pilot.wallet == cost-1,"insufficient funds leave entire fitting and wallet intact")
	pilot.wallet = 10000
	check(Economy.refit_preset(world,station.id,preset.id) and ship.fit.as_dictionary() == fit and pilot.wallet == 10000-cost,"whole fitting installed once at the correct price")
	check(not Economy.refit_preset(world,station.id,preset.id) and pilot.wallet == 10000-cost,"repeat application cannot charge again")
	var other: Dictionary = Hulls.presets(ship.kind).back()
	var before: int = pilot.wallet
	check(Economy.refit_preset(world,station.id,other.reference_path) and pilot.wallet == before,"switching fire groups does not repurchase owned equipment")
	ship.fit.weapons[1] = ""
	old = ship.fit.as_dictionary()
	for period in range(12):
		world.day = period*30
		if fit.weapons[1] not in Economy.station_weapons(world,station):
			break
	check(fit.weapons[1] not in Economy.station_weapons(world,station) and not Economy.refit_preset(world,station.id,preset.id) and ship.fit.as_dictionary() == old and pilot.wallet == before,"unavailable gun rejects entire outfit atomically")
	ship.owner = station.manager
	check(not Economy.refit_preset(world,station.id,preset.id),"cannot refit a third party's vessel")
	ship.owner = world.player
	world.depart(ship)
	check(not Economy.refit_preset(world,station.id,preset.id),"showroom requires pilot and ship physically docked")
	print("Preset checks %d/%d" % [count-failed,count])
	quit(1 if failed else 0)
