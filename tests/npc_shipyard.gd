extends SceneTree

const World = preload("res://world.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func rejected(world: World, buyer: Dictionary, yard: Dictionary, kind: int, reason: String) -> void:
	var before := var_to_bytes(world.snapshot())
	var ship: int = world.Politics.npc_buy_ship(world,buyer,yard,kind)
	check(ship == 0 and var_to_bytes(world.snapshot()) == before,reason)

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"gemini-change-review","systems":12,"factions":3})
	var yard: Dictionary = world.ports[world.active().loc]
	var buyer: Dictionary = world.people[world.random_person(1,yard.id)]
	var kind: int = world.ride().kind
	var price: int = world.Economy.ship_quote(yard,kind).price
	buyer.wallet = price+100
	yard.owner = world.player
	yard.flag = 0
	yard.hulls[kind] = 1
	world.set_treaty(0,1,-1)
	rejected(world,buyer,yard,kind,"enemy buyers cannot pay for or receive a hull")
	world.set_treaty(0,1,0)
	yard.coalition_blockade = true
	rejected(world,buyer,yard,kind,"a blockade prevents even a fully funded NPC purchase")
	yard.erase("coalition_blockade")
	var firm: int = world.firms.keys().front()
	yard.firm = firm
	world.firms[firm].embargo = buyer.flag
	rejected(world,buyer,yard,kind,"the operating company's embargo binds private buyers")
	yard.firm = 0
	buyer.loc = world.systems[1].ports.front()
	rejected(world,buyer,yard,kind,"a buyer at a different port cannot buy remotely")
	buyer.loc = yard.id
	yard.landing_only = true
	rejected(world,buyer,yard,kind,"a landing-only facility cannot sell a hull")
	yard.erase("landing_only")
	yard.build = 1
	rejected(world,buyer,yard,kind,"an unfinished shipyard cannot deliver its marked stock")
	yard.build = 0
	buyer.wallet = price-1
	rejected(world,buyer,yard,kind,"insufficient funds do not change the station or roster")
	buyer.wallet = price+100
	var cash: int = yard.treasury
	var profit: int = yard.operating_profit
	var ship: int = world.Politics.npc_buy_ship(world,buyer,yard,kind,"巡逻")
	check(ship > 0 and yard.hulls[kind] == 0 and buyer.wallet == 100,"retail inventory and the NPC wallet settle at the quoted price")
	check(yard.treasury == cash+price and yard.operating_profit == profit+price,"the yard receives the same sale amount as operating income")
	var books: Dictionary = world.campaign.financial_days[world.day][world.player][yard.id]
	check(books.lines["船坞售舰"].income == price,"the station owner's finance report contains the NPC sale exactly once")
	check(buyer.ship == ship and world.ships[ship].owner == buyer.id and world.ships[ship].job.kind == "巡逻","the buyer receives title and commands the chosen patrol hull")
	print("NPC retail invoice ",price,", buyer ",price+100," -> ",buyer.wallet,", shipyard ",cash," -> ",yard.treasury)
	buyer.wallet = price
	rejected(world,buyer,yard,kind,"a second attempt cannot sell a hull that has already left stock")
	yard.hulls[kind] = 1
	world.depart(world.ships[ship])
	buyer.loc = yard.id
	rejected(world,buyer,yard,kind,"the upgrading captain's actual ship must also be berthed at the seller")
	autonomous_purchases()
	print("NPC shipyard settlement %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func autonomous_purchases() -> void:
	var world := World.new()
	world.new_game({"seed":"two-private-shipyard-sales","systems":12,"factions":3})
	var yard_id := world.port(0,"民用船坞",Vector2(400,300),world.NEUTRAL,world.player,world.Industry.Module.YARD)
	var yard: Dictionary = world.ports[yard_id]
	var buyer: Dictionary = world.people[world.random_person(world.NEUTRAL,yard.id)]
	buyer.ck_traits = []
	world.day = buyer.id % 30
	var starter: int = world.Hulls.kind_for_id("beacon_ff")
	var upgrade: int = world.Hulls.kind_for_id("raven_dd")
	yard.hulls.fill(0)
	yard.hulls[starter] = 1
	var initial: int = world.Economy.ship_quote(yard,starter).price
	buyer.wallet = initial
	check(world.Politics.choose_work_ship(buyer,yard,{},"") == -1,
		"a trader who can only pay the invoice keeps saving for a first cargo")
	var working_cash := 40 + 24*world.Economy.price(yard,world.Industry.Ware.RATIONS,true)
	buyer.wallet += working_cash
	var cash: int = yard.treasury
	world.Politics.npc_autonomous_step(world)
	var old: int = buyer.ship
	check(old != 0 and buyer.wallet == working_cash and yard.hulls[starter] == 0 and yard.treasury == cash+initial,
		"the merchant pays the full invoice and can finance a first cargo")
	if old == 0:
		return
	yard.hulls[upgrade] = 1
	var next_price: int = world.Economy.ship_quote(yard,upgrade).price
	buyer.wallet = next_price
	check(world.Politics.choose_work_ship(buyer,yard,world.ships[old],"贸易") == -1,
		"an upgrade may not use up operating cash")
	buyer.wallet += working_cash
	world.day += 30
	world.Politics.npc_autonomous_step(world)
	check(buyer.ship != old and world.ships[buyer.ship].kind == upgrade and world.ships[buyer.ship].captain == buyer.id,
		"the same merchant takes command of the purchased upgrade")
	check(world.ships[old].owner == buyer.id and world.ships[old].captain == 0 and buyer.wallet == working_cash and yard.hulls[upgrade] == 0,
		"the upgrade preserves title to the earlier hull without double-assigning its captain")
	check(yard.treasury == cash+initial+next_price,"the yard receives both autonomous purchases in full")
	var restored := World.new()
	check(restored.load_state(world.snapshot()) and restored.ports[yard.id].treasury == yard.treasury and restored.people[buyer.id].ship == buyer.ship,
		"ownership and both settled yard payments survive a save and reload")
