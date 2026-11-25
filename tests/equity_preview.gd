extends SceneTree

const World = preload("res://world.gd")
var count := 0
var failed := 0

func check(passed: bool, label: String) -> void:
	count += 1
	if not passed:
		failed += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	var world := World.new()
	world.new_game({"seed":"measure-intent","systems":14,"factions":4,"overrides":[{"regime":4}]})
	var firm: int = world.factions[0].firm
	var holder: int = world.firms[firm].director
	var person: Dictionary = world.people[holder]
	world.active().wallet = 200000
	person.wallet = 0
	person.opinions[world.player] = 55
	var rate: int = world.Equity.overview(world,firm).unit_price
	var snapshot := world.snapshot()
	var offer: Dictionary = world.EquityOrders.preview(world,"company",firm,holder,2,true,rate*3)
	check(world.snapshot()==snapshot and offer.accepted and not offer.binding and offer.decider==holder,"opening a negotiation neither creates a book nor reserves anything")
	var price := int(offer.unit_price)
	var last := -1
	for limit in [1,maxi(2,price/2),price-1,price,price*2]:
		var preview: Dictionary = world.EquityOrders.preview(world,"company",firm,holder,1,true,limit)
		check(preview.score>=last and (preview.score>=preview.threshold)==preview.accepted and not preview.factors.is_empty(),"raising the buyer's offer approaches the same observable signature threshold")
		last = preview.score
	var bad: Dictionary = world.EquityOrders.propose(world,"company",firm,holder,1,true,price-1)
	check(not bad.accepted and world.snapshot()==snapshot,"submitting a below-threshold bid has the same refusal as its preview and changes nothing")
	var close: Dictionary = world.EquityOrders.preview(world,"company",firm,holder,2,true,price)
	var signed: Dictionary = world.EquityOrders.propose(world,"company",firm,holder,2,true,price)
	check(signed.accepted==close.accepted and signed.score==close.score and signed.unit_price==close.unit_price and signed.order_id>0,"preview and submission evaluate identical terms")
	var before := world.snapshot()
	var binding: Dictionary = world.EquityOrders.preview(world,"company",firm,holder,1,true,price)
	var excess: Dictionary = world.EquityOrders.preview(world,"company",firm,holder,3,true,price)
	check(binding.accepted and binding.binding and not excess.accepted and excess.binding and world.snapshot()==before,"signed quantity is binding and repeatedly inspecting the book has no effects")
	var rejected: Dictionary = world.EquityOrders.propose(world,"company",firm,holder,1,true,price-1)
	check(not rejected.accepted and not rejected.has("order_id") and rejected.standing_order_id==signed.order_id and world.snapshot()==before,"a declined inquiry may reference a standing quote without issuing an executable order ID")
	world.day = int(signed.expires)
	before = world.snapshot()
	var expired: Dictionary = world.EquityOrders.preview(world,"company",firm,holder,1,true,price)
	check(not expired.binding and world.snapshot()==before and world.EquityOrders.state(world).orders.has(signed.order_id),"read-only preview neither revives nor clears a lapsed order")
	var buyer: int = world.random_person(world.NEUTRAL,world.firms[firm].hq)
	world.ports[world.firms[firm].hq].manager = buyer
	world.people[holder].shares[firm] -= 4
	world.active().shares[firm] = 4
	world.people[buyer].wallet = 50000
	world.people[buyer].opinions[world.player] = 65
	before = world.snapshot()
	var keen: Dictionary = world.EquityOrders.preview(world,"company",firm,buyer,1,false,1)
	var expensive: Dictionary = world.EquityOrders.preview(world,"company",firm,buyer,1,false,keen.unit_price*2)
	check(keen.accepted and not expensive.accepted and keen.score>expensive.score and world.snapshot()==before,"asking less helps a willing buyer; the price slider never escrows their wallet")
	var bid: Dictionary = world.EquityOrders.propose(world,"company",firm,buyer,1,false,1)
	check(bid.accepted and world.people[buyer].wallet==50000-bid.unit_price,"only submitting reserves the bid")
	var site: Dictionary = world.ports[world.firms[firm].hq]
	before = world.snapshot()
	var station: Dictionary = world.EquityOrders.preview(world,"station",site.id,-firm,1,true,200000)
	check(station.accepted and not station.binding and station.decider==holder and world.snapshot()==before,"station equity uses the same read-only consent and its actual corporate signatory")
	person.opinions[world.player] = -100
	var dislike: Dictionary = world.EquityOrders.preview(world,"station",site.id,-firm,1,true,200000)
	check(not dislike.accepted and dislike.score==0 and dislike.decider==holder,"refusal to negotiate is distinct from being a few credits short")
	print("Equity consent preview %d/%d" % [count-failed,count])
	quit(1 if failed else 0)
