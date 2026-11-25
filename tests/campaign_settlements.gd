extends SceneTree

const World = preload("res://world.gd")
const Game = preload("res://game.tscn")
const Battle = preload("res://combat.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func scenario(role := 0) -> World:
	var world := World.new()
	world.new_game({"seed":"play-logic-review","systems":12,"factions":3,"avatar":{"noble":true,"station_master":role}})
	return world

func company_ship() -> void:
	var world := scenario()
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.world = world
	game.run_bridge()
	game.set_physics_process(false)
	var ship := world.ride()
	var port: Dictionary = world.ports[ship.dock]
	world.active().wallet = 20000
	var firm_id := world.Economy.incorporate_ship(world,ship.id,"巡防航运")
	var firm: Dictionary = world.firms[firm_id]
	world.active().wallet = 0
	for buying in [true,false]:
		var quantity := 1 if buying else -1
		var quote := world.Economy.trade_quote(world,port,0,quantity)
		var balance: int = firm.treasury
		var cargo: int = ship.cargo[0]
		game.open_trade_table("station",port.id,false,0)
		var table = game.trade_table
		table.quick_buy = buying
		table.paint()
		check(quote.x == 1 and not table.submit.disabled,"funded company can trade from the warehouse")
		table.submit.pressed.emit()
		check(ship.cargo[0] == cargo + quantity and firm.treasury == balance - quantity * quote.y and world.active().wallet == 0,"warehouse settles cargo and cash to the company")
		table.close()
	var price := world.Economy.trade_quote(world,port,0,1).y
	var opening: int = firm.treasury
	var deal := world.DiplomaticTrade.propose(world,"station",port.id,[{"kind":"cash","id":0,"quantity":price}],[{"kind":"ware","id":0,"quantity":1}])
	var loaded := World.new()
	check(deal.accepted and loaded.load_state(world.snapshot()),"signed corporate cargo contract survives save/load")
	check(loaded.DiplomaticTrade.cancel(loaded,deal.deal_id) and loaded.firms[firm_id].treasury == opening and loaded.active().wallet == 0,"cancellation refunds the original corporate account")
	world.DiplomaticTrade.cancel(world,deal.deal_id)
	world.Economy.crew(world,10)
	world.depart(ship)
	ship.pos = Vector2(60000,60000)
	ship.heading = 0.0
	var target := world.ship(ship.kind,0,0,world.RAIDERS,ship.system,ship.pos+Vector2(82,0))
	var pirate: Dictionary = world.ships[target]
	pirate.hp = 0.01
	Battle.ensure_state(pirate)
	pirate.battle.armor_grid.fill(0.0)
	pirate.battle.armor = 0.0
	world.contracts[world.player] = {"type":1}
	for frame in 150:
		Battle.tick(ship,0.1,world)
		Battle.train(ship,pirate.pos,0.1)
		Battle.group_fire(world,ship,0,pirate.pos,target,world.player)
		Battle.project(world,ship.system,0.1)
		if not world.ships.has(target):
			break
	check(not world.ships.has(target) and not world.contracts.has(world.player) and world.active().wallet >= 180,"corporate flagship kill completes its captain's bounty")
	target = world.ship(ship.kind,0,0,world.RAIDERS,ship.system,ship.pos+Vector2(50,0))
	var prize: Dictionary = world.ships[target]
	prize.hp = 1.0
	check(world.Operations.begin_boarding(world,target),"launch boarding party")
	world.tick(3)
	check(prize.owner == 0 and prize.get("firm",0) == firm_id and world.can_operate(prize),"corporate prize has one legal owner and can be commanded")
	game.free()

func contractor_and_tow() -> void:
	var world := scenario()
	var port: Dictionary = world.ports[world.ride().dock]
	var kind := world.Hulls.MODELS.find_custom(func(m): return m.crew_max - m.crew_min >= 10 and m.size <= 1)
	world.pilot(world.ship(kind,world.player,0,world.NEUTRAL,port.system,port.pos,port.id))
	var ship := world.ride()
	world.Economy.crew(world,10)
	var builder: Dictionary = world.ships[world.ConstructionContract.hire(world,port.id)]
	var old_contract: Dictionary = builder.construction_contract.duplicate()
	world.depart(ship)
	world.depart(builder)
	ship.pos = builder.pos + Vector2(50,0)
	builder.hp = 1.0
	world.engage_ship(ship,builder,world.player)
	check(world.Operations.begin_boarding(world,builder.id),"board hired construction ship")
	world.tick(3)
	check(builder.owner == world.player and not builder.has("construction_contract"),"capture ends original construction contract")
	var snapshot := world.snapshot()
	var restored := World.new()
	check(restored.load_state(snapshot),"captured contractor can be saved and loaded")
	snapshot.ships[builder.id].construction_contract = old_contract
	check(restored.load_state(snapshot) and not restored.ships[builder.id].has("construction_contract"),"recover previous-version captured contractor")
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.world = world
	game.run_bridge()
	game.set_physics_process(false)
	ship.transponder = false
	ship.layer = true
	game.galaxy = true
	var wallet: int = world.active().wallet
	var day := world.day
	game.flight.tow()
	check(ship.layer and game.galaxy and ship.dock == 0 and world.day == day and world.active().wallet == wallet,"refused tow leaves the fleet, calendar and wallet intact")
	ship.transponder = true
	game.flight.tow()
	check(not ship.layer and ship.dock == port.id and world.active().loc == port.id and world.day == day+18 and world.active().wallet == wallet-mini(60,wallet),"successful tow docks first and charges once")
	game.free()

func management() -> void:
	var world := scenario(2)
	var site: Dictionary = world.ports[world.active().loc]
	site.stock[1] += 8
	site.stock[12] += 4
	site.stock[10] += 100
	check(world.Operations.start_project(world,site.id,"lab"),"employed manager can fund a laboratory")
	world.tick(90)
	check("lab" in world.campaign.unlocks.get(site.id,[]),"manager's laboratory completes on day 90")
	world = scenario()
	world.active().wallet = 20000
	var firm := world.Economy.incorporate_ship(world,world.ride().id,"商行")
	check(world.CompanyWars.start_pretext(world,firm,0,"tariff_dispute").ok,"start commercial war pretext")
	world.tick(44)
	check(not world.CompanyWars.has_ready_pretext(world,firm,0),"pretext unavailable on day 44")
	world.tick()
	check(world.CompanyWars.has_ready_pretext(world,firm,0),"world clock makes the pretext available on day 45")

func diplomacy() -> void:
	for last_port in [false,true]:
		var world := scenario()
		var port: int = world.factions[1].capital
		if last_port:
			for id in world.systems_owned(1):
				if id != port:
					world.ports[id].flag = world.NEUTRAL
		world.set_treaty(0,1,-1)
		world.WarPeace.occupy(world,port,0)
		check(world.WarPeace.sign_peace(world,0,1,[port]),"annex occupied capital by treaty")
		var capital: int = world.factions[1].capital
		check(capital == 0 and not world.factions[1].alive if last_port else world.ports[capital].flag == 1,"loser is eliminated or gets its own replacement capital")
	var world := scenario()
	world.active().flag = 0
	world.factions[0].leader = world.player
	world.people[world.factions[1].leader].opinions[world.player] = 60
	world.active().wallet = 10000
	world.set_treaty(0,1,-1)
	var port: int = world.factions[1].capital
	world.WarPeace.occupy(world,port,0)
	var treaty := [{"kind":"treaty","id":1,"quantity":1}]
	var price: int = world.DiplomaticTrade.preview(world,"faction",1,[],treaty).cash_delta
	var signed := world.DiplomaticTrade.propose(world,"faction",1,[{"kind":"cash","id":0,"quantity":price}],treaty)
	check(signed.accepted and world.DiplomaticTrade.confirm(world,signed.deal_id).accepted,"ratify paid truce")
	check(world.ports[port].flag == 1 and not world.ports[port].has("occupied_from") and world.WarPeace.in_truce(world,0,1),"paid truce returns wartime occupations")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	company_ship()
	fleet_authority()
	contractor_and_tow()
	management()
	diplomacy()
	print("Campaign settlements %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func fleet_authority() -> void:
	var world := scenario()
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	game.world = world
	game.run_bridge()
	game.set_physics_process(false)
	var home: Dictionary = world.ports[world.ride().dock]
	var owner := world.player
	var captain := world.random_person(world.NEUTRAL,home.id)
	var ship: Dictionary = world.ships[world.ship(0,owner,captain,world.NEUTRAL,home.system,home.pos,home.id)]
	world.active().wallet = 25000
	var firm := world.Economy.incorporate_ship(world,ship.id,"舰队经营")
	game.watch_ship_id = ship.id
	check(game.viewed_ship().id == ship.id,"asset camera stays on a corporate ship")
	game.tab = "事务"
	game.campaign_panel.section = 2
	game.campaign_panel.fleet_ship = ship.id
	game.refresh()
	check(game.body.find_children("*","Button",true,false).any(func(b):return b.text == "加入队尾"),"corporate ship is selectable on the fleet order screen")
	check(world.Economy.queue_order(world,ship.id,home.id,"buy",0,2),"director can queue purchase")
	var old_save := world.snapshot()
	old_save.ships[ship.id].order_queue[0].erase("issuer")
	var copy := World.new()
	check(copy.load_state(old_save) and copy.ships[ship.id].order_queue[0].issuer == owner,"previously queued order recovers its director")
	var observer := world.random_person(world.NEUTRAL,home.id)
	world.player = observer
	var bridge := preload("res://agent_bridge.gd").new()
	bridge.game = game
	var bank: int = world.firms[firm].treasury
	var result := bridge.dispatch("start_pretext",{"firm_id":firm,"target_flag":0})
	check(not result.ok and world.firms[firm].treasury == bank,"agent cannot spend another director's funds on a pretext")
	var before: int = ship.cargo[0]
	world.Economy.step_order(world,ship)
	check(ship.cargo[0] == before+2 and ship.last_order.moved == 2,"another actor's turn executes the director's order")
	world.player = owner
	world.Economy.queue_order(world,ship.id,home.id,"buy",0,2)
	world.firms[firm].director = observer
	world.Economy.step_order(world,ship)
	check(ship.cargo[0] == before+2 and ship.last_order.moved == 0,"revoked director's order cannot spend company money")
	world.firms[firm].director = owner
	world.CompanyWars.grant_pretext(world,firm,0)
	check(bridge.dispatch("declare_company_war",{"firm_id":firm,"target_flag":0}).ok,"director's bridge can declare a genuine commercial war")
	bank = world.firms[firm].treasury
	result = bridge.dispatch("sign_company_peace",{"firm_id":firm,"target_flag":0,"winner":"firm"})
	check(result.ok and result.result.reparations == 0 and world.firms[firm].treasury == bank,"caller cannot award itself unearned reparations")
	world.campaign.unlocks[home.id] = ["teleport"]
	check(world.Operations.teleport(world,ship.id) and world.ride().id == ship.id,"director can teleport to corporate bridge")
	game.free()
