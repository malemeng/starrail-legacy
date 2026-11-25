extends SceneTree

const World = preload("res://world.gd")
const E = preload("res://economy.gd")
const I = E.Industry
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"aid-invoice","systems":12,"factions":3})
	var home: Dictionary = world.ports[world.ride().dock]
	var buyer: Dictionary = world.ports[world.port(0,"求援港",home.pos+Vector2(1100,900),world.NEUTRAL,0,I.Module.HABITAT)]
	var surplus := I.Ware.RATIONS
	for port: Dictionary in world.ports.values():
		port.exports = []
		port.imports = []
		for ware: int in I.COLONY_NEEDS:
			port.stock[ware] = E.provisions_for(port,110)
	home.stock[surplus] = 220
	buyer.stock.fill(0)
	buyer.stock[I.Ware.WATER] = 40
	buyer.pop = 1200
	buyer.treasury = 10000
	var captain := world.random_person(world.NEUTRAL,home.id)
	world.people[captain].wallet = 10000
	var ship: Dictionary = world.ships[world.ship(1,captain,captain,world.NEUTRAL,0,home.pos,home.id)]
	ship.job = {"kind":"贸易","automatic":true}
	ship.operating_area = {"port":home.id,"system":0,"jumps":0}
	var route := E.trade_plan(world,ship)
	check(route.get("source",0)==home.id and route.get("relief_port",0)==buyer.id,"emergency order finds a local surplus outside both posted trade lists")
	E.step_ship(world,ship)
	var booking: Dictionary = ship.get("reservation",{})
	if booking.has("delivery_fee"):
		var fee: int = booking.delivery_fee
		var qty: int = ship.cargo[surplus]
		var sale := I.lot_invoice(buyer,surplus,qty,false)
		var before: int = buyer.treasury
		var wallet: int = world.people[captain].wallet
		check(buyer.cash_holds[ship.id]==sale.base+qty*fee and home.stock[surplus]>=E.provisions_for(home,120),"the receiver reserves both payments and the donor keeps its household buffer")
		var restored := World.new()
		check(restored.load_state(world.snapshot()) and restored.ships[ship.id].reservation.delivery_fee==fee,"the funded transport fee survives reload")
		world.berth(ship,buyer.id)
		E.step_ship(world,ship)
		check(buyer.treasury==before-sale.base-qty*fee and world.people[captain].wallet==wallet+sale.total+qty*fee and not buyer.cash_holds.has(ship.id),"real delivery pays the carrier exactly once and releases the hold")
	else:
		check(false,"accepted shipment has a payable booking")
	ship.fuel = 6
	buyer.stock[I.Ware.FUEL] = 0
	home.stock[I.Ware.FUEL] = 0
	check(E.freight_budget(world,ship,4,5,home,100)<0,"two individually short legs cannot share fuel that does not exist")
	home.stock[I.Ware.FUEL] = 3
	check(E.freight_budget(world,ship,4,5,home,3)==0 and E.freight_budget(world,ship,4,5,home,2)<0,"the transfer pump must have both the missing units and the buyer's funding")
	var other: Dictionary = world.ports[world.port(0,"备用买家",buyer.pos+Vector2.RIGHT*550,world.NEUTRAL,0,I.Module.HABITAT)]
	other.stock.fill(0)
	other.imports = [surplus]
	other.treasury = 4000
	buyer.treasury = 0
	ship.cargo[surplus] = 8
	ship.job = {"kind":"贸易","source":home.id,"target":buyer.id,"phase":1,"ware":surplus,"automatic":true}
	E.step_ship(world,ship)
	check(ship.cargo[surplus]==8 and ship.job.target==other.id and other.inbound.has(ship.id),"a loaded automatic trader keeps its cargo and books a solvent alternative")
	var donor: Dictionary = world.people[world.random_person(world.NEUTRAL,buyer.id)]
	donor.ck_traits = ["仁慈"]
	donor.wallet = 500
	var rich: Dictionary = world.people[world.random_person(world.NEUTRAL,buyer.id)]
	var poor: Dictionary = world.people[world.random_person(world.NEUTRAL,buyer.id)]
	rich.wallet = 400
	poor.wallet = 0
	rich.birth = -9000
	poor.birth = -9000
	for i in 200:
		world.Politics.npc_social_step(world,donor,"merchant")
		if donor.wallet < 500: break
	check(donor.wallet==480 and poor.wallet==20 and rich.wallet==400,"charity reaches the poorer resident despite insertion order")
	buyer.treasury = 10000
	buyer.shortage = 70
	buyer.stock.fill(0)
	for ware: int in I.EXPANSION:
		buyer.stock[ware] = I.EXPANSION[ware]
	buyer.stock[I.Ware.ENERGY] += 20
	buyer.stock[I.Ware.ICE] = 30
	var start: int = buyer.treasury
	E.plan_provisions(world,buyer,I.station_data(buyer))
	check(buyer.extension==I.Module.CHEMICAL and buyer.build_storage[I.Ware.ALLOY]==I.EXPANSION[I.Ware.ALLOY] and buyer.treasury==start-int(I.CONSTRUCTION.expansion.credits),"an isolated port funds a water plant with real ice, materials and money")
	var start_ice: int = buyer.stock[I.Ware.ICE]
	for day in range(6,int(I.CONSTRUCTION.expansion.days)+1,6):
		world.day = day
		E.produce(world,buyer)
	check(buyer.expansion==0 and I.Module.CHEMICAL in buyer.modules and buyer.build_storage[I.Ware.ALLOY]==0 and buyer.stock[I.Ware.ICE]<start_ice and buyer.stock[I.Ware.WATER]>0,"the completed public expansion consumes its material bill and produces water from ice")
	E.release_reservation(world,ship)
	world.berth(ship,home.id)
	ship.cargo.fill(0)
	ship.fuel = 100
	for port: Dictionary in world.ports.values():
		port.treasury = 0
		port.stock[surplus] = 180
	buyer.stock[surplus] = 0
	buyer.treasury = 8000
	var receiver := I.station_data(buyer)
	receiver.reserve(I.StationData.Booking.INBOUND,99999,surplus,100,world.day+900)
	var local := {0:true}
	var relief := E.harvest_trade_plan(world,ship,home,local,surplus)
	check(relief.get("target",0)==buyer.id,"a shipment due after a stockout leaves room for timely relief")
	receiver.reserve(I.StationData.Booking.INBOUND,99999,surplus,100,world.day+36)
	check(E.harvest_trade_plan(world,ship,home,local,surplus).is_empty(),"a funded shipment arriving before our ship covers the same demand")
	receiver.release(I.StationData.Booking.INBOUND,99999)
	ship.job = {"kind":"采矿","automatic":true}
	world.systems[0].ore = 40
	home.modules.append(I.Module.REFINERY)
	other.modules.append(I.Module.REFINERY)
	buyer.treasury = 0
	other.treasury = 4000
	var mining := E.mining_plan(world,ship)
	check(mining.get("target",0)==other.id and mining.quantity<=40,"a miner chooses an affordable delivery instead of the nearer insolvent refinery")
	print("AI decisions %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
