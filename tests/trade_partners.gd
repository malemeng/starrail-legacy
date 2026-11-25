extends SceneTree

const World = preload("res://world.gd")
const Partners = preload("res://scripts/economy/trade_partners.gd")
var runs := 0
var failures := 0

func check(truth: bool, msg: String) -> void:
	runs += 1
	if not truth:
		failures += 1
		printerr("FAIL ",msg)

func quantity(rows: Array, kind: String, id: int) -> int:
	for row: Dictionary in rows:
		if row.kind==kind and row.id==id:
			return row.quantity
	return 0

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"real-market-partners","systems":20,"factions":4,"overrides":[{"regime":4}]})
	var player := world.active()
	var ship := world.ride()
	var home: Dictionary = world.ports[ship.dock]
	var flag := 0
	var corp: int = world.factions[flag].firm
	var chair: Dictionary = world.people[world.firms[corp].director]
	var trader_id := world.random_person(world.NEUTRAL,home.id)
	var trader: Dictionary = world.people[trader_id]
	var merchant: Dictionary = world.ships[world.ship(0,trader_id,trader_id,world.NEUTRAL,home.system,home.pos,home.id)]
	merchant.cargo[0] = 10
	merchant.reservation = {"ware":0,"qty":3,"loaded":true}
	var buyers := Partners.partners(world)
	var types := {}
	for contact: Dictionary in buyers:
		types[contact.kind]=true
		check(world.Equity.adult(world,world.people[contact.representative]) and not world.oversees(contact.representative),"only living independent representatives speak for accounts")
	check(types.has_all(["person","station","company","faction"]),"public port reaches the four separate types of trading partner")
	check(Partners.participant(world,"person",trader_id).ship==merchant.id and quantity(Partners.assets(world,"person",trader_id),"ware",0)==7,"only seven uncommitted units aboard the merchant's own ship are available")
	merchant.owner = chair.id
	check(Partners.participant(world,"person",trader_id).ship==0 and quantity(Partners.assets(world,"person",trader_id),"ware",0)==0,"a hired captain cannot sell another owner's cargo")
	merchant.owner = trader_id
	world.depart(merchant)
	check(Partners.participant(world,"person",trader_id).is_empty(),"a departed unknown merchant cannot transmit cargo to the port")
	home.stock[6] = 9
	home.black[6] = 3
	home.black_treasury = 51
	check(quantity(Partners.assets(world,"station",home.id),"ware",6)==0 and quantity(Partners.assets(world,"station",home.id,true),"ware",6)==3,"only the black counter lists its own three units of contraband")
	check(quantity(Partners.assets(world,"station",home.id,true),"cash",0)==51 and quantity(Partners.assets(world,"station",home.id),"cash",0)==world.Treasury.available(home),"neither market may spend the other's cash")
	var distant: Dictionary = world.ports[world.factions[1].capital]
	check(Partners.participant(world,"station",distant.id,true).is_empty(),"an illicit desk cannot deliver from a remote port")
	chair.wallet = 87
	world.firms[corp].treasury = 214
	world.factions[flag].treasury = 748
	check(quantity(Partners.assets(world,"person",chair.id),"cash",0)==87 and quantity(Partners.assets(world,"company",corp),"cash",0)==214 and quantity(Partners.assets(world,"faction",flag),"cash",0)==748,"a ruler's wallet, company treasury and public budget are distinct even when the same person signs")
	var other_flag := 1
	var enemy: Dictionary = world.factions[other_flag]
	world.set_treaty(flag,other_flag,-1)
	player.flag = flag
	check(not Partners.treaty(world,other_flag).ok,"a civilian cannot settle a war in the name of the whole faction")
	world.factions[flag].leader = player.id
	world.people[enemy.leader].opinions[player.id] = 60
	var pacts := Partners.assets(world,"faction",other_flag)
	check(quantity(pacts,"treaty",other_flag)==1 and world.treaty(flag,other_flag).state==-1,"the foreign leader can negotiate a live truce with the ruling player while preview leaves the war intact")
	check(Partners.treaty(world,other_flag,true).ok and world.treaty(flag,other_flag).state==0 and world.treaty(flag,other_flag).truce_until>world.day and quantity(Partners.assets(world,"faction",other_flag),"treaty",other_flag)==0,"an accepted treaty changes real relations and cannot be sold twice")
	player.ship = 0
	player.loc = home.id
	check(Partners.location(world)==home.id and not Partners.participant(world,"person",chair.id).is_empty() and quantity(Partners.assets(world,"player",player.id),"ware",0)==0,"a civilian at port can reach people without trading nonexistent ship cargo")
	print("Trade counterparties and mandates %d/%d" % [runs-failures,runs])
	quit(1 if failures else 0)
