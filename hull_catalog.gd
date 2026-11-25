extends RefCounted

enum Size { FRIGATE, DESTROYER, CRUISER, CAPITAL }
const SizeClasses = preload("res://data/fleet/size_classes.json")
const Industry = preload("res://scripts/economy/industry.gd")
static var CLASSES: Array = SizeClasses.data
static var CLASS_NAMES: Array = CLASSES.map(func(tier): return tier.name)
static var CLASS_SPRITE: Array = CLASSES.map(func(tier): return tier.world_units_per_pixel)
static var CLASS_RADIUS: Array = CLASSES.map(func(tier): return tier.canvas[0] * tier.world_units_per_pixel * 0.45)
const DAMAGE_NAMES := ["动能", "高爆", "能量", "破片"]
const SHIELD_MULT := [2.0, 0.5, 1.0, 0.25]
const ARMOR_MULT := [0.5, 2.0, 1.0, 0.25]
const SYSTEM_NAMES := {"boost":"高能加速", "phase":"相位闪现", "burst":"火控超频", "repair":"维修无人机"}
const ModRegistry = preload("res://scripts/fleet/mod_registry.gd")
const Fitting = preload("res://scripts/models/fitting_data.gd").FittingData

static var WEAPONS: Dictionary = load_weapons()
static var SLOTS: Dictionary = {}
static var _kind_by_id: Dictionary = {}
static var _kind_by_reference: Dictionary = {}
static var _attachments: Dictionary = {}
static var _wing_specs: Dictionary = {}
static var _mod_events: Array = []
static var COMBAT: Array = []
static var MODELS: Array = load_models()
static var _references: Dictionary = {}

static func read_catalog(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed := JSON.new()
	if parsed.parse(text) != OK or not parsed.data is Dictionary:
		push_error("舰船目录无法读取 %s（第 %d 行）" % [path, parsed.get_error_line()])
		return {}
	return parsed.data

static func load_weapons() -> Dictionary:
	var records := read_catalog("res://data/fleet/weapons.json")
	for key in records:
		var weapon: Dictionary = records[key]
		for field in ["type", "mount", "op", "ammo"]:
			weapon[field] = int(weapon[field])
		if weapon.has("burst"):
			weapon.burst = int(weapon.burst)
	return records

static func local_point(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

static func local_boundary(points: Array) -> PackedVector2Array:
	var boundary := PackedVector2Array()
	for point in points:
		boundary.append(local_point(point))
	return boundary

static func convert_module_geometry(modules: Array) -> void:
	for module in modules:
		module.offset = local_point(module.offset)
		module.bounds = local_boundary(module.bounds)

static func integer_groups(groups: Array) -> Array:
	var values: Array = []
	for group in groups:
		values.append(int(group))
	return values

static func load_models() -> Array:
	var data := read_catalog("res://data/fleet/fleet.json")
	var flights := read_catalog("res://data/fleet/wing_loadouts.json")
	for item in data.get("attachments", []):
		convert_module_geometry(item.modules)
		_attachments[item.reference] = item
	for wing in data.get("wing_specs", []):
		wing.count = int(wing.count)
		var loadout: Dictionary = flights.wings[wing.id]
		wing.merge(loadout)
		wing.materials = flights.kits[wing.kit]
		wing.payloads = []
		for weapon in loadout.weapons:
			if weapon != loadout.get("defensive_weapon",""):
				wing.payloads.append(flights.weapons[weapon])
		_wing_specs[wing.id] = wing
	var models: Array = data.get("models", [])
	models.append_array(read_catalog("res://data/fleet/local_ships.json").models)
	ModRegistry.read_packs(models, _mod_events, WEAPONS)
	var reference := Industry.reference_port()
	for kind in range(models.size()):
		var model: Dictionary = models[kind]
		model.price = Industry.ship_quote(reference,model).price
		for field in ["hp","cargo","recipe","mine","salvage","size","power","style_id","crew_min","crew_max","dp","deployment","fighter_bays","tuning_limit"]:
			model[field] = int(model[field])
		_kind_by_id[model.id] = kind
		_kind_by_reference[model.reference] = kind
		model.sprite_size = Vector2i(int(model.sprite_size[0]), int(model.sprite_size[1]))
		model.sprite_center = local_point(model.sprite_center)
		model.shield_center = local_point(model.shield_center)
		model.bounds = local_boundary(model.bounds)
		convert_module_geometry(model.modules)
		var engines: Array[Vector2] = []
		for pair in model.engine_slots:
			engines.append(local_point(pair))
		model.engine_slots = engines
		var combat: Dictionary = model.combat
		combat.op = int(combat.op)
		combat.groups = integer_groups(combat.groups)
		var keys: Array[String] = []
		for slot in model.mounts:
			slot.accepts = ModRegistry.MountFamilies.data[slot.family].accepts
			slot.offset = local_point(slot.offset)
			slot.size = int(slot.size)
			var global_key: String = model.id + "/" + slot.id
			SLOTS[global_key] = slot
			keys.append(global_key)
		combat.slots = keys
		COMBAT.append(combat)
		for preset in model.presets:
			preset.groups = integer_groups(preset.groups)
			preset.caps = int(preset.caps)
			preset.vents = int(preset.vents)
	return models

static func hull_spec(kind: int) -> Dictionary:
	return MODELS[kind] if kind >= 0 and kind < MODELS.size() else {}

static func hull_id(kind: int) -> String:
	return str(hull_spec(kind).get("id", ""))

static func operator_id(vessel: Dictionary) -> int:
	return vessel.charter.operator if vessel.has("charter") and vessel.owner == 0 else vessel.owner

static func kind_for_id(id: String) -> int:
	return int(_kind_by_id.get(id, -1))

static func kind_for_reference(id: String) -> int:
	return int(_kind_by_reference.get(id, -1))

static func attachment_spec(reference: String) -> Dictionary:
	return _attachments.get(reference, {})

static func wing_spec(id: String) -> Dictionary:
	return _wing_specs.get(id, {})

static func wing_ids() -> Array:
	return _wing_specs.keys()

static func project_id_for_reference(reference: String) -> String:
	var kind := kind_for_reference(reference)
	return hull_id(kind) if kind >= 0 else str(attachment_spec(reference).get("id",""))

static func slot_spec(kind: int, index: int) -> Dictionary:
	var model := hull_spec(kind)
	if model.is_empty() or index < 0 or index >= model.mounts.size():
		return {}
	return model.mounts[index]

static func manifest() -> Dictionary:
	if _references.is_empty():
		_references = read_catalog("res://data/fleet/manifest.json")
		var by_variant: Dictionary = {}
		var names: Dictionary = {}
		var wing_users: Dictionary = {}
		for model in MODELS:
			for wing in model.reference_wings:
				if not wing_users.has(wing):
					wing_users[wing] = []
				if model.name not in wing_users[wing]:
					wing_users[wing].append(model.name)
		for key in ["hulls","skins"]:
			for item in _references[key]:
				var kind := kind_for_reference(item.id)
				item.project_id = project_id_for_reference(item.id)
				item.record_type = key
				names[item.id] = item.get("reference_name",item.id)
				if kind >= 0:
					item.name = MODELS[kind].name
					item.category = "ship"
				else:
					var technical := attachment_spec(item.id)
					item.category = technical.get("category","auxiliary")
					item.name = archive_name(item.category,item.reference_name)
		for variant in _references.variants:
			by_variant[variant.id] = variant.hull
			variant.project_id = project_id_for_reference(variant.hull)
			variant.record_type = "variants"
			var kind := kind_for_reference(variant.hull)
			variant.category = "ship" if kind >= 0 else attachment_spec(variant.hull).get("category","auxiliary")
			variant.parent_name = names.get(variant.hull,variant.hull)
			variant.name = (MODELS[kind].name if kind >= 0 else archive_name(variant.category,variant.parent_name)) + " · " + str(variant.reference_name)
		for wing in _references.wings:
			wing.airframe = by_variant.get(wing.variant, "")
			wing.project_id = wing_spec(wing.id).get("project_id","")
			wing.record_type = "wings"
			wing.reference_name = names.get(wing.airframe,wing.airframe)
			wing.name = wing_spec(wing.id).name + "联队"
			wing.carriers = wing_users.get(wing.id,[])
	return _references

static func archive_name(category: String, reference_name: String) -> String:
	var titles := {"station":"空间站","module":"舰体模块","fighter":"舰载机","auxiliary":"辅助艇"}
	return str(titles.get(category,"设备"))+" · "+reference_name

static func mod_events() -> Array:
	return _mod_events.duplicate(true)

static func available_for_market(kind: int) -> bool:
	return bool(hull_spec(kind).get("market",false))

static func can_build_station(kind: int) -> bool:
	var spec := hull_spec(kind)
	return spec.get("size",-1) >= Size.CRUISER and "station_construction" in spec.get("capabilities",[])

static func stock_fit(kind: int) -> Dictionary:
	var spec: Dictionary = COMBAT[kind]
	return {"weapons":spec.stock.duplicate(), "groups":spec.groups.duplicate(), "auto":[false,false,false], "caps":0, "vents":0,
		"wings":MODELS[kind].reference_wings.duplicate()}

static func stock_fitting(kind: int) -> Fitting:
	return Fitting.from_dictionary(stock_fit(kind))

static func presets(kind: int) -> Array:
	return hull_spec(kind).get("presets", [])

static func preset_fit(kind: int, id_or_path: String) -> Dictionary:
	for preset in presets(kind):
		if id_or_path != preset.id and id_or_path != preset.reference_path:
			continue
		var air_group: Array = MODELS[kind].reference_wings.duplicate()
		var built_in: Array = MODELS[kind].get("builtin_wings",[])
		for bay in range(built_in.size(),mini(air_group.size(),built_in.size()+preset.wings.size())):
			air_group[bay] = preset.wings[bay-built_in.size()]
		return {"weapons":preset.weapons.duplicate(),"groups":preset.groups.duplicate(),"auto":preset.auto.duplicate(),
			"caps":preset.caps,"vents":preset.vents,"wings":air_group}
	return {}

static func weapon_compatible(kind: int, index: int, weapon_id: String) -> bool:
	var slot := slot_spec(kind, index)
	if slot.is_empty():
		return false
	if slot.builtin:
		return weapon_id == COMBAT[kind].stock[index]
	if weapon_id.is_empty():
		return true
	var weapon: Dictionary = WEAPONS.get(weapon_id, {})
	return not weapon.is_empty() and weapon.mount <= slot.size and weapon.family in slot.accepts

static func weapon_metrics(key: String) -> Dictionary:
	var weapon: Dictionary = WEAPONS.get(key,{})
	var damage := float(weapon.get("damage",0.0))
	var rate := 1.0 / maxf(float(weapon.get("cool",1.0)),0.01)
	# Combat spends one round per trigger and splits one volley's damage across its projectiles.
	var sustained_rate := minf(rate,weapon.ammo_per_sec) if int(weapon.get("ammo",0)) > 0 else rate
	return {"volley":damage, "dps":damage*rate, "sustained_dps":damage*sustained_rate,
		"flux_per_damage":float(weapon.get("flux",0.0))/damage if damage > 0.0 else 0.0,
		"range":float(weapon.get("range",0.0)), "op":int(weapon.get("op",0))}

static func fitting_cost(kind: int, input: Variant) -> int:
	if kind < 0 or kind >= MODELS.size():
		return -1
	var fit: Fitting = input if input is Fitting else null
	if input is Dictionary:
		fit = Fitting.from_dictionary(input,false,MODELS[kind].reference_wings)
	if fit == null:
		return -1
	var model: Dictionary = MODELS[kind]
	var fixed_wings: Array = model.get("builtin_wings",[])
	if fit.wings.size() != model.fighter_bays:
		return -1
	for bay in fit.wings.size():
		if not _wing_specs.has(fit.wings[bay]) or (bay < fixed_wings.size() and fit.wings[bay] != fixed_wings[bay]):
			return -1
	var spec: Dictionary = COMBAT[kind]
	if fit.weapons.size() != spec.slots.size() or fit.groups.size() != fit.weapons.size() or fit.auto.size() != 3:
		return -1
	var limit: int = MODELS[kind].tuning_limit
	if fit.caps < 0 or fit.caps > limit or fit.vents < 0 or fit.vents > limit:
		return -1
	var cost: int = fit.caps + fit.vents
	for index in range(fit.weapons.size()):
		if fit.groups[index] not in [1,2,3]:
			return -1
		var key: String = fit.weapons[index]
		if not weapon_compatible(kind,index,key):
			return -1
		if not key.is_empty():
			cost += WEAPONS[key].op
	return cost if cost <= spec.op else -1

static func battle_state(kind: int) -> Dictionary:
	var cool: Array = []
	cool.resize(COMBAT[kind].slots.size())
	cool.fill(0.0)
	return {"soft_flux":0.0,"hard_flux":0.0,"armor":COMBAT[kind].armor,"shield":false,"vent":false,"overload":0.0,
		"group":1,"cooldowns":cool,"system_cd":0.0,"system_time":0.0,"order":0,"focus":0,"retired":false,"ai":"巡航","motion":Vector2.ZERO}

static func capacity(vessel: Dictionary) -> float:
	return COMBAT[vessel.kind].capacity + vessel.fit.caps * 5.0

static func dissipation(vessel: Dictionary) -> float:
	return COMBAT[vessel.kind].dissipation + vessel.fit.vents * 1.35

static func crew_limits(kind: int) -> Vector2i:
	var model: Dictionary = MODELS[kind]
	return Vector2i(model.crew_min,model.crew_max)

static func crew_efficiency(vessel: Dictionary) -> float:
	var minimum: int = MODELS[vessel.kind].crew_min
	return clampf(float(vessel.get("crew",minimum)) / minimum,0.25,1.0)

static func station_limit(station: Dictionary) -> int:
	if station.get("capital_yard", false):
		return Size.CAPITAL
	if station.module == 2 or 2 in station.get("modules",[]) or (station.get("extension", -1) == 2 and station.get("expansion", 0) == 0):
		return Size.CRUISER
	return Size.DESTROYER

static func berth_fits(vessel: Dictionary, station: Dictionary) -> bool:
	# The contracted builder's external construction berth also serves its material deliveries.
	return not vessel.has("kind") or MODELS[vessel.kind].size <= station_limit(station) \
		or (vessel.get("id",0) > 0 and vessel.id == station.get("construction_ship",0) and can_build_station(vessel.kind))

static func model_limit(station: Dictionary, model: int) -> bool:
	return available_for_market(model) and int(MODELS[model].size) <= station_limit(station)

static func inventory(available: bool) -> Array:
	var stock: Array = []
	stock.resize(MODELS.size())
	stock.fill(0)
	if available:
		stock[0] = 1
		stock[1] = 1
	return stock
