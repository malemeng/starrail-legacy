extends RefCounted

const Config = preload("res://data/economy/industry.json")

## Opening capital exists once per galaxy. Discovery allocates an existing balance.
static func establish(world) -> void:
	var terms: Dictionary = Config.data.station_capital
	var core_ports: int = world.systems.size() + 1 # The second orbital refinery in the mining system.
	for region in world.systems:
		core_ports += region.planets.size()
	world.campaign.market_capital = {"core":core_ports * int(terms.core_port),"frontier":int(terms.frontier_fund)}

static func open(world, station: Dictionary, ready: bool) -> void:
	if station.has("treasury"):
		return
	station.treasury = 0
	station.black_treasury = 0
	station.operating_profit = 0
	station.cash_holds = {}
	if not ready or station.owner != 0:
		return
	var pools: Dictionary = world.campaign.market_capital
	var terms: Dictionary = Config.data.station_capital
	var wild: bool = world.systems[station.system].get("wild",false)
	var key := "frontier" if wild else "core"
	var capital := mini(int(pools[key]),int(terms.frontier_port if wild else terms.core_port))
	pools[key] -= capital
	station.treasury = capital
	if world.is_regular(station):
		var pool := mini(capital,int(terms.black_cash))
		station.treasury -= pool
		station.black_treasury = pool

static func balance(station: Dictionary) -> int:
	return station.get("treasury",0)

static func available(station: Dictionary, except_order: int = 0) -> int:
	var uncommitted := balance(station)
	var holds: Dictionary = station.get("cash_holds",{})
	for ship in holds:
		if ship != except_order:
			uncommitted -= int(holds[ship])
	return maxi(0,uncommitted)

static func post(world, station: Dictionary, amount: int, category: String, operating: bool = true, except_order: int = 0) -> bool:
	if amount < 0 and -amount > available(station,except_order):
		return false
	station.treasury += amount
	if operating:
		station.operating_profit += amount
	world.Finances.record(world,station.owner,station,category,amount,false,not operating)
	return true

static func can_withdraw(world, station: Dictionary, person_id: int) -> bool:
	var shares: Dictionary = world.StationEquity.cap_table(world,station)
	return world.oversees(station.owner) and shares.total > 0 and shares.people.get(person_id,0) == shares.total

static func transfer(world, station: Dictionary, person_id: int, amount: int) -> bool:
	var actor: Dictionary = world.people.get(person_id,{})
	if amount == 0 or station.is_empty() or actor.is_empty() or person_id != world.player or not world.oversees(station.owner) or amount > actor.wallet:
		return false
	if amount < 0 and not can_withdraw(world,station,person_id):
		return false
	if not post(world,station,amount,"注资" if amount > 0 else "提款",false):
		return false
	world.credit(person_id,-amount)
	if amount < 0:
		station.operating_profit = mini(station.operating_profit,station.treasury)
	return true

static func market(world, station: Dictionary, amount: int, order: int = 0) -> void:
	if not post(world,station,amount,"货物销售" if amount > 0 else "货物采购",true,order):
		return
	world.Finances.record(world,station.owner,station,"",amount,true)
	if amount > 0 and station.firm != 0:
		world.firms[station.firm].revenue += amount
