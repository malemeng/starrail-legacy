extends RefCounted

enum Ware { ORE, ALLOY, FUEL, RATIONS, HULL_PARTS, WATER, LUXURY, SILICON, ICE, GAS, ENERGY, WAFER, ELECTRONICS, ORDNANCE, ENGINE_PARTS, SCRAP }
enum Module { MINE, REFINERY, YARD, DEFENSE, HABITAT, SOLAR, CHEMICAL, ELECTRONICS, COMPONENTS, RECYCLER }
enum Storage { SOLID, LIQUID, CONTAINER }
const SCRAP := Ware.SCRAP

const Config = preload("res://data/economy/industry.json")
const StationData = preload("res://scripts/models/station_data.gd")
const Treasury = preload("res://scripts/economy/station_treasury.gd")
static var RULES: Dictionary = ordered_rules(Config.data)
static var MARKET: Dictionary = RULES.commodity_market
static var TARGET_STOCK: Array = RULES.wares.map(func(row): return int(row.get("target_stock",MARKET.target_stock)))
static var WARE_ID: Dictionary = index_by_id(RULES.wares)
static var DOCK_SUPPLIES: Array = MARKET.dock_supplies.map(func(id): return WARE_ID[id])
static var MODULE_ID: Dictionary = index_by_id(RULES.modules)
static var STORAGE_ID: Dictionary = index_by_id(RULES.storage)
static var WARES: Array = RULES.wares.map(func(row): return row.name)
static var MODULES: Array = RULES.modules.map(func(row): return row.name)
static var BASE: Array = RULES.wares.map(func(row): return int(row.price))
static var STORAGE: Array = RULES.wares.map(func(row): return STORAGE_ID[row.storage])
static var STORAGE_CAPS: Array = RULES.storage.map(func(row): return int(row.capacity))
static var WARES_BY_STORAGE: Array = group_wares()
static var CONSTRUCTION: Dictionary = RULES.construction
static var FOUNDATION: Dictionary = materials(CONSTRUCTION.foundation.bill)
static var EXPANSION: Dictionary = materials(CONSTRUCTION.expansion.bill)
static var COLONY_NEEDS: Array = RULES.colony.consumption.map(func(id): return WARE_ID[id])
static var PROVISION_STOCK_TARGETS: Dictionary = {Ware.WATER:2*TARGET_STOCK[Ware.WATER],Ware.RATIONS:2*TARGET_STOCK[Ware.RATIONS]}
static var BLACK_SEED: Dictionary = materials(RULES.colony.initial_black_market)
static var RECIPES: Dictionary = compile_recipes()
static var PRIMARY_RECIPES: Dictionary = index_primary_recipes()

static func index_primary_recipes() -> Dictionary:
	var map := {}
	for module in RECIPES:
		if module == Module.RECYCLER:
			continue
		for recipe: StationData.Recipe in RECIPES[module]:
			if not map.has(recipe.output):
				map[recipe.output] = recipe
	return map

static func material_cost_factor(station: Dictionary, ware: int, black: bool = false) -> float:
	if not PRIMARY_RECIPES.has(ware) or station.is_empty() or (not black and station.get("surface_yields",{}).has(ware)):
		return 1.0
	var recipe: StationData.Recipe = PRIMARY_RECIPES[ware]
	var base_sum := 0.0
	var local_sum := 0.0
	for in_ware: int in recipe.inputs:
		var qty := float(recipe.inputs[in_ware])
		var base_p := float(BASE[in_ware])
		var local_stock := StationData.market_quantity(station, in_ware, black)
		var local_p := float(unit_price(base_p, local_stock, stock_target(in_ware), float(MARKET.ceiling_multiplier)))
		base_sum += base_p * qty
		local_sum += local_p * qty
	if base_sum <= 0.0:
		return 1.0
	return clampf(0.45 + 0.55 * (local_sum / base_sum), 0.85, 1.55)

static func ordered_rules(data: Dictionary) -> Dictionary:
	var config := data.duplicate(true)
	for category in ["wares","modules","storage"]:
		var rows: Array = config[category]
		rows.sort_custom(func(first,second): return int(first.slot)<int(second.slot))
		var ids := {}
		for i in range(rows.size()):
			assert(int(rows[i].slot)==i and not ids.has(rows[i].id),"Repeated or missing %s slot/ID at %d" % [category,i])
			ids[rows[i].id] = i
	return config

static func index_by_id(values: Array) -> Dictionary:
	var result := {}
	for i in range(values.size()):
		result[values[i].id] = i
	return result

static func materials(spec: Dictionary) -> Dictionary[int, int]:
	var bill: Dictionary[int, int] = {}
	for id in spec:
		bill[WARE_ID[id]] = int(spec[id])
	return bill

static func compile_recipes() -> Dictionary:
	var recipes := {}
	for module in RULES.modules:
		var items: Array[StationData.Recipe] = []
		for item in module.get("recipes",[]):
			items.append(StationData.Recipe.new(materials(item["in"]),WARE_ID[item.out],int(item.units)))
		recipes[MODULE_ID[module.id]] = items
	return recipes

static func group_wares() -> Array:
	var groups := []
	for _group in STORAGE_CAPS:
		groups.append([])
	for ware in range(STORAGE.size()):
		groups[STORAGE[ware]].append(ware)
	return groups

static func station_data(station: Dictionary) -> StationData:
	return StationData.new(station, STORAGE, WARES_BY_STORAGE)

static func valid_station(station: Dictionary, hull_count: int) -> bool:
	return StationData.valid_record(station, WARES.size(), STORAGE_CAPS.size(), MODULES.size(),
			hull_count, RULES.shipbuilding)

static func initial_black_market() -> Array:
	var goods := []
	goods.resize(WARES.size())
	goods.fill(0)
	for ware in BLACK_SEED:
		goods[ware] = BLACK_SEED[ware]
	return goods

static func setup(world, station: Dictionary, ready: bool) -> void:
	if station.has("modules"):
		return
	var modules: Array = [station.module] if ready else []
	# Populated ports start with working infrastructure; new construction starts empty.
	if ready and not world.systems[station.system].get("wild", false):
		for id in RULES.modules[station.module].get("initial",[]):
			var extra: int = MODULE_ID[id]
			if extra not in modules:
				modules.append(extra)
	station.modules = modules
	station.build_storage = world.quantities([])
	station.outbound = {}
	station.inbound = {}
	station.build_inbound = {}
	station.production_orders = []
	station.method = "universal"
	station.storage_cap = STORAGE_CAPS.duplicate()
	station.black.resize(WARES.size())
	for i in range(WARES.size()):
		if station.black[i] == null:
			station.black[i] = 0
		if ready and RULES.wares[i].has("seed_stock"):
			station.stock[i] = int(RULES.wares[i].seed_stock)
	update_market(station)

static func update_market(station: Dictionary) -> void:
	var exports: Array = station.get("surface_yields",{}).keys() if station.build == 0 and not station.get("landing_only",false) else []
	var imports := COLONY_NEEDS.duplicate()
	for module in station.modules:
		for id in RULES.modules[module].get("primary",[]):
			exports.append(WARE_ID[id])
		if module == Module.YARD:
			var method: Dictionary = RULES.shipbuilding[station.method]
			var inputs: Array = method.mass.keys() + method.size.keys()
			for id in inputs:
				if WARE_ID[id] not in imports:
					imports.append(WARE_ID[id])
		for recipe: StationData.Recipe in RECIPES[module]:
			if recipe.output not in exports:
				exports.append(recipe.output)
			for input in recipe.inputs:
				if input not in imports:
					imports.append(input)
	station.exports = exports
	station.imports = imports

## Seed independent regional working stocks once; subsequent balances come from production and trade.
static func seed_industry_stock(station: Dictionary, sector_seed: String) -> void:
	var rolls := RandomNumberGenerator.new()
	rolls.seed = hash([sector_seed,station.system,"industry_stock"])
	var rules: Dictionary = RULES.opening_industry_stock
	for ware: int in station.imports:
		if ware not in COLONY_NEEDS:
			var fraction := rolls.randf_range(rules.input_fraction[0],rules.input_fraction[1])
			station.stock[ware] = mini(station.stock[ware],roundi(stock_target(ware)*fraction))
	var outputs: Array = station.exports
	if outputs.is_empty():
		return
	var specialty: int = outputs[rolls.randi_range(0,outputs.size()-1)]
	var inventory := station_data(station)
	var priority := [specialty]
	for ware: int in outputs:
		if ware != specialty and ware not in station.imports:
			priority.append(ware)
	for ware: int in priority:
		var band: Array = rules.specialty_fraction if ware == specialty else rules.output_fraction
		var units := roundi(stock_target(ware)*rolls.randf_range(band[0],band[1]))
		inventory.deposit(ware,units-int(station.stock[ware]))

static func available(station: Dictionary, ware: int, excluding: int = 0) -> int:
	return station_data(station).available(ware, excluding)

static func space(station: Dictionary, ware: int, excluding: int = 0) -> int:
	return station_data(station).free_space(ware, excluding)

static func consume(station: Dictionary, inputs: Dictionary, batches: int = 1) -> bool:
	return station_data(station).consume(inputs, batches)

static func vessel_recipe(model: Dictionary, method: String = "universal") -> Dictionary:
	var bill := {}
	var spec: Dictionary = RULES.shipbuilding[method]
	var factors := {"mass":int(model.recipe),"size":int(model.size)+1,"mounts":mount_grades(model),"bays":int(model.fighter_bays)}
	for feature in factors:
		for id in spec[feature]:
			var units := ceili(float(spec[feature][id]) * factors[feature])
			if units > 0:
				var ware: int = WARE_ID[id]
				bill[ware] = int(bill.get(ware,0)) + units
	return bill

static func mount_grades(model: Dictionary) -> int:
	var total := 0
	for mount in model.mounts:
		total += int(mount.size)
	return total

static func supports_method(model: Dictionary, method: String) -> bool:
	var spec: Dictionary = RULES.shipbuilding[method]
	return model.size <= spec.get("max_size",3) and model.combat.system not in spec.get("excluded_systems",[])

static func labor_hours(model: Dictionary, method: String) -> int:
	var work: Dictionary = RULES.ship_market.worker_hours
	var standard_hours: float = model.recipe * work.per_hull_unit + mount_grades(model) * work.per_mount_grade + model.fighter_bays * work.per_bay
	return ceili(standard_hours * float(RULES.shipbuilding[method].labor_factor))

static func labor_charge(hours: int) -> int:
	return ceili(hours * float(RULES.ship_market.shipwright_hourly_wage))

## x = units, y = total credits. Returning the stock through the spread never generates cash.
static func price_rate(ware: int, buying: bool, origin: int) -> float:
	return BASE[ware] * (MARKET.ask_rate if buying else MARKET.bid_rate) * (MARKET.merchant_ask_discount if origin==1 and buying else 1.0)

static func tariff_rate(station: Dictionary, black: bool = false) -> float:
	return float(station.get("tariff_rate",0.0)) if not black and station.get("tariff_flag",-1)>=0 else 0.0

static func stock_target(ware: int) -> float:
	return TARGET_STOCK[ware]

static func bid_ceiling(station: Dictionary, ware: int, black: bool = false) -> float:
	# A port can take goods for resale, but only local users pay shortage prices.
	if black or ware in station.get("imports",[]) or ware in DOCK_SUPPLIES:
		return MARKET.ceiling_multiplier
	if ware == Ware.ALLOY and Module.DEFENSE in station.get("modules",[]):
		return MARKET.ceiling_multiplier
	return MARKET.resale_bid_ceiling

static func unit_price(rate: float, stock: int, target: float, ceiling: float, staple: bool = false) -> int:
	var scarcity := clampf(MARKET.empty_stock_multiplier - stock / target * MARKET.stock_sensitivity,MARKET.floor_multiplier,ceiling)
	if staple:
		# Apply the same declining premium to purchases and sales at each stock level.
		scarcity *= 1.0 + clampf(1.0 - stock / target,0.0,1.0)
	return maxi(1,roundi(rate * scarcity))

## Base is the station's consideration; total is what the trader pays or receives.
## The receiving port must fund both the seller's proceeds and the sovereign's tax.
static func lot_invoice(station: Dictionary, ware: int, units: int, buying: bool, origin: int = -1, black: bool = false, budget: int = 2147483647, delivery_fee: int = 0) -> Dictionary:
	var target := stock_target(ware)
	var stock := StationData.market_quantity(station,ware,black) + (0 if buying else 1)
	var rate := price_rate(ware,buying,origin) * material_cost_factor(station,ware,black)
	var ceiling := float(MARKET.ceiling_multiplier) if buying else bid_ceiling(station,ware,black)
	var tariff := tariff_rate(station,black)
	var staple := not black and ware in COLONY_NEEDS
	var result := {"units":0,"base":0,"tax":0,"total":0}
	for i in range(units):
		var base: int = result.base+unit_price(rate,stock,target,ceiling,staple)
		var tax := roundi(base*tariff)
		var total := base+tax if buying else base-tax
		if (total if buying else base+delivery_fee*(i+1))>budget:
			break
		result.units += 1
		result.base = base
		result.tax = tax
		result.total = total
		stock += -1 if buying else 1
	return result

static func lot_quote(station: Dictionary, ware: int, units: int, buying: bool, origin: int = -1, black: bool = false, budget: int = 2147483647) -> Vector2i:
	var invoice := lot_invoice(station,ware,units,buying,origin,black,budget)
	return Vector2i(invoice.units,invoice.total)

## Returns units and gross profit at both markets' changing prices.
static func freight_quote(source: Dictionary, dest: Dictionary, ware: int, units: int, budget: int, internal_source: bool = false, internal_destination: bool = false, delivery_fee: int = 0) -> Vector2i:
	var target := stock_target(ware)
	var ask := price_rate(ware,true,-1) * material_cost_factor(source,ware)
	var bid := price_rate(ware,false,-1) * material_cost_factor(dest,ware)
	var ask_ceiling := float(MARKET.ceiling_multiplier)
	var destination_ceiling := bid_ceiling(dest,ware)
	var ask_tax := 0.0 if internal_source else tariff_rate(source)
	var bid_tax := 0.0 if internal_destination else tariff_rate(dest)
	var source_stock := StationData.market_quantity(source,ware)
	var dest_stock := StationData.market_quantity(dest,ware)
	var result := Vector2i.ZERO
	var source_value := 0
	var dest_value := 0
	var buyer_budget := Treasury.available(dest)
	var staple := ware in COLONY_NEEDS
	for i in units:
		source_value += unit_price(ask,source_stock-i,target,ask_ceiling,staple)
		dest_value += unit_price(bid,dest_stock+i+1,target,destination_ceiling,staple)
		var spent := source_value+roundi(source_value*ask_tax)
		var freight := (i+1)*delivery_fee
		var receipts := dest_value-roundi(dest_value*bid_tax)+freight
		if receipts-spent<=result.y or (not internal_source and spent>budget) or (not internal_destination and dest_value+freight>buyer_budget):
			break
		result.x += 1
		result.y = receipts-spent
	return result

static func reference_port() -> Dictionary:
	var stock := []
	stock.resize(WARES.size())
	stock.fill(int(RULES.ship_market.reference_market_stock))
	return {"stock":stock,"method":"universal","tax_rate":RULES.ship_market.reference_port_tax,"tariff_flag":0,"tariff_rate":RULES.ship_market.reference_port_tax}

static func ship_quote(station: Dictionary, model: Dictionary) -> Dictionary:
	var method: String = station.method
	var buildable := supports_method(model,method)
	if not buildable:
		method = "universal"
	var materials := []
	var material_cost := 0
	var bill := vessel_recipe(model,method)
	for ware: int in bill:
		var units: int = bill[ware]
		var cost := lot_quote(station,ware,units,true).y
		materials.append({"ware":ware,"units":units,"cost":cost})
		material_cost += cost
	var market: Dictionary = RULES.ship_market
	var hours := labor_hours(model,method)
	var labor_cost := labor_charge(hours)
	var cost := material_cost + labor_cost
	var fee := roundi(cost * float(market.yard_overhead_rate))
	var tax := roundi((cost + fee) * float(station.get("tax_rate",0)))
	return {"method":method,"local_buildable":buildable,"materials":materials,"material_cost":material_cost,
		"labor_hours":hours,"hourly_wage":market.shipwright_hourly_wage,"labor_cost":labor_cost,
		"yard_fee":fee,"tax":tax,"price":cost+fee+tax}

