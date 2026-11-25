extends RefCounted

## Live view of a station's v7 industrial record. Creating a view takes constant
## time. The world continues to serialize the underlying arrays and dictionaries.
enum Booking { OUTBOUND, INBOUND, CONSTRUCTION }

class Recipe:
	var inputs: Dictionary[int, int]
	var output: int
	var units: int

	func _init(materials: Dictionary[int, int], product: int, amount: int) -> void:
		inputs = materials
		output = product
		units = amount

var _record: Dictionary
var _storage_group: Array
var _wares_by_group: Array

func _init(record: Dictionary, storage_groups: Array, grouped_wares: Array) -> void:
	_record = record
	_storage_group = storage_groups
	_wares_by_group = grouped_wares

## Called once per station while loading the world, before creating live views.
static func valid_record(record: Dictionary, ware_count: int, storage_count: int, module_count: int,
		hull_count: int, methods: Dictionary) -> bool:
	for field in ["stock", "black", "build_storage", "storage_cap"]:
		var values: Variant = record.get(field)
		var count := storage_count if field == "storage_cap" else ware_count
		if not values is Array or values.size() != count:
			return false
		for units: Variant in values:
			if not units is int or units < 0:
				return false
	for field in ["inbound", "outbound", "build_inbound"]:
		var bookings: Variant = record.get(field)
		if not bookings is Dictionary:
			return false
		for ship_id: Variant in bookings:
			var entry: Variant = bookings[ship_id]
			if not ship_id is int or ship_id <= 0 or not entry is Dictionary:
				return false
			if not entry.get("ware") is int or entry.ware < 0 or entry.ware >= ware_count:
				return false
			if not entry.get("qty") is int or entry.qty <= 0 or not entry.get("expires") is int:
				return false
	for field in ["modules", "production_orders", "imports", "exports"]:
		var indices: Variant = record.get(field)
		if not indices is Array:
			return false
		var count := ware_count
		if field == "modules":
			count = module_count
		elif field == "production_orders":
			count = hull_count
		for index: Variant in indices:
			if not index is int or index < 0 or index >= count:
				return false
	return record.get("method") is String and methods.has(record.method)

static func market_quantity(record: Dictionary, ware: int, black: bool = false) -> int:
	return record.black[ware] if black else record.stock[ware]

func overview() -> Dictionary:
	return {"modules":_record.modules.duplicate(), "store":_record.stock.duplicate(),
		"build_storage":_record.build_storage.duplicate(), "inbound":_record.inbound.duplicate(true),
		"outbound":_record.outbound.duplicate(true), "build_inbound":_record.build_inbound.duplicate(true),
		"production_orders":_record.production_orders.duplicate(), "capacity":_record.storage_cap.duplicate(),
		"method":_record.method}

func _bookings(kind: Booking) -> Dictionary:
	match kind:
		Booking.OUTBOUND:
			return _record.outbound
		Booking.CONSTRUCTION:
			return _record.build_inbound
	return _record.inbound

func reserve(kind: Booking, ship_id: int, ware: int, units: int, expires: int) -> void:
	var bookings := _bookings(kind)
	bookings[ship_id] = {"ware":ware, "qty":units, "expires":expires}

func release(kind: Booking, ship_id: int) -> void:
	_bookings(kind).erase(ship_id)

func update_reservation(kind: Booking, ship_id: int, units: int) -> void:
	_bookings(kind)[ship_id].qty = units

func reserved(kind: Booking, ware: int, excluding: int = 0) -> int:
	var bookings := _bookings(kind)
	var total := 0
	for ship_id: int in bookings:
		if ship_id == excluding:
			continue
		var entry: Dictionary = bookings[ship_id]
		if entry.ware == ware or (kind == Booking.INBOUND and _storage_group[entry.ware] == _storage_group[ware]):
			total += int(entry.qty)
	return total

func available(ware: int, excluding: int = 0) -> int:
	return maxi(0, market_quantity(_record, ware) - reserved(Booking.OUTBOUND, ware, excluding))

func free_space(ware: int, excluding: int = 0) -> int:
	var group: int = _storage_group[ware]
	var capacity: int = int(_record.storage_cap[group])-int(_record.get("deal_space",{}).get(group,0))
	var stock: Array = _record.stock
	for other: int in _wares_by_group[group]:
		capacity -= int(stock[other])
	return maxi(0, capacity - reserved(Booking.INBOUND, ware, excluding))

func withdraw(ware: int, requested: int, excluding: int = 0) -> int:
	var moved := clampi(requested, 0, available(ware, excluding))
	_record.stock[ware] -= moved
	return moved

func deposit(ware: int, requested: int, excluding: int = 0) -> int:
	var moved := clampi(requested, 0, free_space(ware, excluding))
	_record.stock[ware] += moved
	return moved

func incoming(ware: int) -> int:
	var total := 0
	for booking: Dictionary in _record.inbound.values():
		if booking.ware == ware:
			total += int(booking.qty)
	return total

## An idle production line cannot fill the last space needed to receive provisions.
func production_space(ware: int, buffers: Dictionary) -> int:
	var room := free_space(ware)
	for staple: int in buffers:
		if staple != ware and _storage_group[staple] == _storage_group[ware]:
			room -= maxi(0,int(buffers[staple]) - int(_record.stock[staple]) - incoming(staple))
	return maxi(0,room)

## The black market owns a separate stockpile. Legal trades honor freight bookings.
func sell_to_ship(ware: int, signed_units: int, black: bool) -> int:
	if black:
		var moved := mini(signed_units, market_quantity(_record, ware, true))
		_record.black[ware] -= moved
		return moved
	if signed_units > 0:
		return withdraw(ware, signed_units)
	return -deposit(ware, -signed_units)

func consume(inputs: Dictionary, batches: int = 1) -> bool:
	if batches <= 0:
		return false
	for ware: int in inputs:
		var units: int = inputs[ware]
		if units < 0 or available(ware) < units * batches:
			return false
	for ware: int in inputs:
		_record.stock[ware] -= int(inputs[ware]) * batches
	return true

func process_recipe(recipe: Recipe, efficiency: float, buffers: Dictionary = {}, household_reserve: int = 0) -> void:
	var output := maxi(1, floori(recipe.units * efficiency))
	var batches := mini(4, floori(float(production_space(recipe.output,buffers)) / output))
	for ware: int in recipe.inputs:
		var usable := available(ware)
		if buffers.has(ware):
			usable = maxi(0,usable-household_reserve)
		batches = mini(batches, floori(float(usable) / recipe.inputs[ware]))
	if batches > 0:
		for ware: int in recipe.inputs:
			_record.stock[ware] -= recipe.inputs[ware] * batches
		_record.stock[recipe.output] += output * batches

func construction_needed(ware: int, bill: Dictionary, include_bookings: bool = true) -> int:
	var missing: int = int(bill.get(ware, 0)) - int(_record.build_storage[ware])
	if include_bookings:
		missing -= reserved(Booking.CONSTRUCTION, ware)
	return maxi(0, missing)

func deliver_construction(ware: int, requested: int, bill: Dictionary) -> int:
	var moved := clampi(requested, 0, construction_needed(ware, bill, false))
	_record.build_storage[ware] += moved
	return moved

func construction_funded(bill: Dictionary) -> bool:
	for ware: int in bill:
		if _record.build_storage[ware] < bill[ware]:
			return false
	return not bill.is_empty()

func consume_construction(bill: Dictionary) -> bool:
	if not construction_funded(bill):
		return false
	for ware: int in bill:
		_record.build_storage[ware] -= bill[ware]
	return true

func order_count() -> int:
	return _record.production_orders.size()

func hull_stock(kind: int) -> int:
	return _record.hulls[kind]

func withdraw_hull(kind: int) -> bool:
	if hull_stock(kind) <= 0:
		return false
	_record.hulls[kind] -= 1
	return true

func order_at(index: int) -> int:
	return _record.production_orders[index]

func enqueue_hull(kind: int, max_orders: int) -> bool:
	if order_count() >= max_orders:
		return false
	_record.production_orders.append(kind)
	return true

func complete_hull(kind: int, bill: Dictionary, commissioned: bool) -> bool:
	if commissioned and (order_count() == 0 or order_at(0) != kind):
		return false
	if not consume(bill):
		return false
	_record.hulls[kind] += 1
	if commissioned:
		_record.production_orders.pop_front()
	return true
