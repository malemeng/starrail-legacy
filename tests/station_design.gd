extends SceneTree

const World = preload("res://world.gd")
const Hulls = preload("res://hull_catalog.gd")
const Celestial = preload("res://celestial.gd")
const Economy = preload("res://economy.gd")
const Design = preload("res://scripts/models/station_design.gd")
const Geometry = preload("res://scripts/models/station_geometry.gd")
const Saves = preload("res://scripts/services/save_manager.gd")
var checks := 0
var failures := 0

func expect(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)
	return condition

func assemble(world: World, station: Dictionary, ship: Dictionary, bill: Dictionary) -> void:
	for ware: int in bill:
		ship.cargo[ware] = bill[ware]
	Economy.donate(world,station.id)
	for shift in range(5):
		Economy.produce(world,station)

func check_layouts() -> void:
	for invalid: Array in [[Design.CORE],[Vector2i.DOWN],[Vector2i(-3,0)],[Vector2i(-1,-1)],[Vector2i.LEFT,Vector2i.LEFT]]:
		expect(not Design.issue(invalid).is_empty(),"reject blocked, disconnected or out-of-bounds placements")
	var world := World.new()
	world.new_game({"seed":"player-station-designer","systems":12,"factions":3})
	var ship: Dictionary = world.ride()
	var home: Dictionary = world.ports[ship.dock]
	var original := Geometry.layout(home)
	expect(original.parts.size() == home.modules.size()+1 and original.links.size() >= home.modules.size(),"default port uses its actual industrial modules and connections")
	var rotated := home.duplicate()
	rotated.berth_heading = original.outward.angle()+PI*0.37
	rotated.pos = Geometry.berth_for_core(rotated,original.design_origin+Vector2(150,-75),rotated.berth_heading)
	var spinning := Geometry.layout(rotated)
	expect(spinning.signature == original.signature and spinning.design_origin.is_equal_approx(original.design_origin+Vector2(150,-75)),
		"spin and translation carry the berth with a fixed assembled shape")
	var region: Dictionary = world.systems[ship.system]
	var planet: Dictionary = region.planets[0]
	var actor := world.active()
	actor.wallet = 12000
	var site_position := Celestial.construction_point(region,planet,planet.pos+Vector2.RIGHT)
	var engineers := Hulls.MODELS.filter(func(model): return Hulls.can_build_station(Hulls.kind_for_id(model.id)))
	var engineer := Hulls.kind_for_id("gantry_ca")
	expect(engineers.size() == 1 and engineers.front().id == "gantry_ca" and Hulls.MODELS[engineer].size == Hulls.Size.CRUISER,
		"the construction capability belongs to the dedicated engineering cruiser")
	for kind: int in [ship.kind,Hulls.kind_for_reference("venture"),Hulls.kind_for_reference("heron")]:
		var ordinary := world.ship(kind,world.player,0,ship.flag,home.system,home.pos,home.id)
		world.pilot(ordinary)
		var pilot := world.ride()
		world.depart(pilot)
		pilot.pos = site_position
		expect(Economy.deploy(world,0,pilot.pos) == 0 and actor.wallet == 12000,"ordinary frigate, cruiser or carrier cannot construct a station")
		world.berth(pilot,home.id)
	var price: int = Economy.ship_quote(home,engineer).price
	actor.wallet += price
	var stock_before: int = home.hulls[engineer]
	var bought := Economy.buy_ship(world,home.id,engineer,price)
	if not expect(stock_before > 0 and bought != 0 and world.pilot(bought) and home.hulls[engineer] == stock_before-1 and actor.wallet == 12000,
		"a real costed shipyard purchase puts an operational construction cruiser under player command"):
		return
	ship = world.ride()
	world.depart(ship)
	ship.pos = planet.pos
	expect(Economy.deploy(world,0,ship.pos) == 0 and actor.wallet == 12000,"a construction cruiser cannot establish a project through the surface")
	ship.pos = planet.pos + Vector2.RIGHT * (Celestial.gravity_radius(region,planet) + 1.0)
	expect(Economy.deploy(world,0,ship.pos) == 0 and actor.wallet == 12000,"outside the physical gravity boundary the builder spends nothing")
	ship.pos = planet.pos + Vector2.RIGHT * (Celestial.gravity_radius(region,planet) - 1.0)
	expect(Celestial.orbit_at(region,ship.pos) == 0 and Economy.deploy(world,Economy.Industry.Module.YARD,ship.pos) == 0 and actor.wallet == 12000,
		"a berth just inside the gravity circle cannot leave the proposed station core outside it")
	ship.pos = site_position
	expect(Celestial.orbit_at(region,ship.pos) == 0 and Economy.build_ship_for(world,ship.pos) == bought,"the construction waypoint identifies the planet and the physically present builder")
	var foundation: Dictionary = Economy.Industry.CONSTRUCTION.foundation
	var expand_terms: Dictionary = Economy.Industry.CONSTRUCTION.expansion
	expect(Economy.deploy(world,0,ship.pos,[Vector2i.DOWN]) == 0 and actor.wallet == 12000,
		"an invalid foundation layout spends nothing")
	var id := Economy.deploy(world,0,ship.pos,[Vector2i.LEFT])
	if not expect(id > 0,"place a mine on the chosen left attachment"):
		return
	var site: Dictionary = world.ports[id]
	var built := Geometry.layout(site)
	expect(actor.wallet == 12000-foundation.credits and site.modules.is_empty() and site.construction_ship == bought and built.parts.back().pending,"construction charges once and reserves an inactive module")
	world.berth(ship,id)
	Economy.produce(world,site)
	expect(site.build == foundation.days,"unfunded construction stalls")
	assemble(world,site,ship,Economy.Industry.FOUNDATION)
	expect(site.build == 0 and site.modules == [0] and not Geometry.layout(site).parts.back().pending,"actual construction materials activate precisely the purchased mine")
	var credits: int = actor.wallet
	var stock: Array = site.stock.duplicate()
	expect(not Economy.redesign(world,id,[Vector2i.LEFT,Vector2i.RIGHT]) and not Economy.expand(world,id,5,Vector2i.LEFT) and actor.wallet == credits,
		"layout editing cannot add production and duplicate paid modules cannot charge")
	expect(Economy.expand(world,id,5,Vector2i.UP,[Vector2i.RIGHT]) and site.expansion == expand_terms.days and actor.wallet == credits-expand_terms.credits,
		"one purchase both rearranges existing modules and reserves a new construction slot")
	expect(Design.cells(site) == [Vector2i.RIGHT,Vector2i.UP] and site.modules == [0] and site.stock == stock and Geometry.layout(site).parts.back().pending,
		"pending solar station section is visible and cannot produce")
	var from_save := World.new()
	var filename := "user://station-design-%d.sav" % OS.get_process_id()
	expect(Saves.write(world,filename,false) and Saves.read(from_save,filename) and Design.cells(from_save.ports[id]) == Design.cells(site) and from_save.ports[id].expansion == expand_terms.days,
		"actual save and reload preserve the arranged modules and reserved work")
	DirAccess.remove_absolute(filename)
	var invalid := world.snapshot()
	invalid.ports[id].design_cells = [Vector2i.RIGHT,Vector2i.RIGHT]
	expect(not from_save.load_state(invalid),"corrupt layouts cannot duplicate occupied slots on load")
	assemble(world,site,ship,Economy.Industry.EXPANSION)
	expect(site.expansion == 0 and site.extension == -1 and site.modules == [0,5] and not Geometry.layout(site).parts.back().pending,
		"completed expansion activates the reserved module exactly once")
	credits = actor.wallet
	stock = site.stock.duplicate()
	expect(Economy.redesign(world,id,[Vector2i.LEFT,Vector2i(-1,-1)]) and site.stock == stock and site.modules == [0,5] and actor.wallet == credits,
		"rearranging built industry preserves money, production, inventory and module order")
	var shape := Geometry.layout(site)
	var part: Dictionary = shape.parts.back()
	var target: Vector2 = Transform2D(shape.angle,shape.center)*Vector2(part.center)
	var obstruction := {"pos":target,"radius":5.0}
	expect(Geometry.intersects_body(shape,obstruction),"body collision uses each actual placed module")
	var direction := Vector2.from_angle(shape.angle)
	var adjacent := Geometry.make(target+direction*80.0,direction.angle(),170.0,1)
	expect(Geometry.overlaps(shape,adjacent) and Geometry.overlaps(adjacent,shape),"module collision with a neighboring station is symmetric")
	region.planets.append(obstruction)
	expect(not Economy.redesign(world,id,Design.cells(site)) and not Economy.expand(world,id,1,Vector2i.UP) and actor.wallet == credits,
		"obstructed module reservations cannot overlap a body or charge the buyer")
	region.planets.pop_back()
	var owner: int = site.owner
	site.owner = 0
	expect(not Economy.redesign(world,id,[Vector2i.UP,Vector2i.LEFT]),"visitors cannot rearrange another operator's station")
	site.owner = owner
	world.depart(ship)
	expect(not Economy.redesign(world,id,[Vector2i.UP,Vector2i.LEFT]),"relayout is a docked operation")
	world.berth(ship,home.id)
	home.owner = actor.id
	expect(Economy.order_hull(world,home.id,engineer),"a shipyard can commission the same engineering cruiser to replace the purchased hull")
	var bill := Economy.Industry.vessel_recipe(Hulls.MODELS[engineer],home.method)
	for ware: int in bill:
		home.stock[ware] = bill[ware]
	for i in range(30):
		world.day += 30
		Economy.shipyard(world,home)
		if home.production_orders.is_empty():
			break
	expect(home.production_orders.is_empty() and home.hulls[engineer] == stock_before and bill.keys().all(func(ware): return home.stock[ware] == 0),
		"replacing the bought engineering cruiser consumes its actual material bill and worker shifts")

func _initialize() -> void:
	check_layouts()
	print("Station design %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
