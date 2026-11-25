extends RefCounted

const ROOT := "user://mods"
const MountFamilies = preload("res://data/fleet/mount_families.json")
const EventEngine = preload("res://scripts/campaign/event_engine.gd")
const EVENT_EFFECTS := ["aid","risk","work","study","investigate"]
const EVENT_HOOKS := ["dock","jump","monthly","battle","trade","succession"]
const HULL_VALUES := ["hp","cargo","recipe","mine","salvage","power","speed","fuel","fuel_tank",
	"burn","upkeep","deployment","dp","peak_seconds","cr_deploy","crew_min","crew_max"]
const COMBAT_VALUES := ["armor","op","capacity","dissipation"]

static func read_packs(models: Array, events: Array, weapons: Dictionary) -> void:
	var folder := DirAccess.open(ROOT)
	if folder == null:
		return
	var indexes: Dictionary = {}
	var used_events: Dictionary = {}
	for i in range(models.size()):
		indexes[models[i].id] = i
	for event in EventEngine.authored():
		used_events[event.id] = true
	var names := folder.get_directories()
	names.sort()
	for folder_name in names:
		var path := ROOT.path_join(folder_name).path_join("fleet.json")
		if not FileAccess.file_exists(path):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			push_warning("无法读取扩展包 %s" % path)
			continue
		if not add_pack(json.data, models, indexes, used_events, events, weapons):
			push_warning("扩展包配置无效，已跳过 %s" % path)

static func valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 100 and str(value).replace(".", "_").replace("-", "_").is_valid_ascii_identifier()

static func add_pack(pack: Dictionary, models: Array, indexes: Dictionary, used_events: Dictionary, events: Array, weapons: Dictionary = {}) -> bool:
	if not valid_id(pack.get("id")) or not pack.get("hulls",[]) is Array or not pack.get("events",[]) is Array:
		return false
	var staged: Dictionary = {}
	var new_events: Dictionary = {}
	for item: Variant in pack.get("hulls",[]):
		if not item is Dictionary or not valid_id(item.get("id")) or not indexes.has(item.get("base")) or staged.has(item.id):
			return false
		var replace: bool = item.get("override",false) == true
		if replace != indexes.has(item.id) or (not replace and not str(item.id).begins_with(str(pack.id) + ".")):
			return false
		var model: Dictionary = models[indexes[item.base]].duplicate(true)
		if not apply_design(item, model, weapons):
			return false
		var base_reference: String = models[indexes[item.id]].reference if replace else model.reference
		model.id = item.id
		model.reference = base_reference if replace else item.id
		model.reference_base = base_reference
		model.provider = pack.id
		model.market = true
		model.presets = []
		staged[item.id] = model
	for event: Variant in pack.get("events",[]):
		if not event is Dictionary or not valid_id(event.get("id")) or used_events.has(event.id) or new_events.has(event.id):
			return false
		if not str(event.id).begins_with(str(pack.id) + "."):
			return false
		if event.has("on_action"):
			if not EventEngine.valid_template(event):
				return false
			new_events[event.id] = event.duplicate(true)
			continue
		if event.get("hook") not in EVENT_HOOKS or event.get("effect") not in EVENT_EFFECTS:
			return false
		for key in ["title","body","yes","no"]:
			if not event.get(key) is String or str(event[key]).strip_edges().is_empty():
				return false
		var weight: Variant = event.get("weight",1)
		if typeof(weight) not in [TYPE_INT,TYPE_FLOAT] or float(weight) != floorf(weight) or weight < 1 or weight > 10000:
			return false
		var checked: Dictionary = event.duplicate(true)
		checked.weight = int(weight)
		new_events[event.id] = checked
	for id in staged:
		if indexes.has(id):
			models[indexes[id]] = staged[id]
		else:
			indexes[id] = models.size()
			models.append(staged[id])
	for id in new_events:
		used_events[id] = true
		events.append(new_events[id])
	return true

static func apply_design(item: Dictionary, model: Dictionary, weapons: Dictionary) -> bool:
	for key in ["name","role"]:
		if not item.has(key):
			continue
		if not item.get(key) is String or str(item[key]).strip_edges().is_empty():
			return false
		model[key] = item[key]
	if item.has("paint"):
		if not item.paint is String or not Color.html_is_valid(item.paint):
			return false
		model.paint = item.paint
	if not item.get("stats",{}) is Dictionary or not item.get("combat",{}) is Dictionary:
		return false
	for key in item.get("stats",{}):
		var value: Variant = item.stats[key]
		# Older ship packs may specify a sticker price. Keep their hulls, using the yard's bill of materials.
		if key == "price":
			if not valid_magnitude(value) or value < 1:
				return false
			continue
		if key not in HULL_VALUES or not valid_magnitude(value):
			return false
		if key in ["hp","crew_min","speed","recipe","power"] and value < 1 and (key != "speed" or value <= 0):
			return false
		model[key] = value
	if model.crew_max < model.crew_min:
		return false
	for key in item.get("combat",{}):
		var value: Variant = item.combat[key]
		if key not in COMBAT_VALUES or not valid_magnitude(value) or value <= 0:
			return false
		if key == "op" and value != floorf(value):
			return false
		model.combat[key] = value
	var patches: Variant = item.get("mounts",[])
	return patches is Array and apply_mounts(model, patches, weapons)

static func apply_mounts(model: Dictionary, patches: Array, weapons: Dictionary) -> bool:
	var indices := {}
	for i in model.mounts.size():
		indices[model.mounts[i].id] = i
	var seen := {}
	for patch: Variant in patches:
		if not patch is Dictionary or not valid_id(patch.get("id")) or seen.has(patch.id):
			return false
		seen[patch.id] = true
		for key in patch:
			if key not in ["id","offset","facing","arc","size","type","family","stock","group"]:
				return false
		var index: int = indices.get(patch.id,-1)
		if index < 0:
			if not patch.has_all(["offset","facing","arc","size","type","family"]):
				return false
			index = model.mounts.size()
			model.mounts.append({"id":patch.id,"reference":patch.id})
			model.combat.stock.append("")
			model.combat.groups.append(1)
		var mount: Dictionary = model.mounts[index]
		if patch.has("offset"):
			if not valid_offset(patch.offset,model.bounds):
				return false
			mount.offset = patch.offset.duplicate()
		if patch.has("facing"):
			if not finite_number(patch.facing):
				return false
			mount.facing = wrapf(patch.facing,-180.0,180.0)
		if patch.has("arc"):
			if not finite_number(patch.arc) or patch.arc < 0.0 or patch.arc > 360.0:
				return false
			mount.arc = patch.arc
		if patch.has("type"):
			if patch.type not in ["固定","炮塔"]:
				return false
			mount.type = patch.type
		if patch.has("size"):
			if not valid_tier(patch.size):
				return false
			mount.size = int(patch.size)
		if patch.has("family"):
			if not patch.family is String or not MountFamilies.data.has(patch.family):
				return false
			mount.family = patch.family
			mount.accepts = MountFamilies.data[mount.family].accepts
			mount.builtin = mount.family == "builtin"
		if patch.has("stock"):
			if not patch.stock is String:
				return false
			model.combat.stock[index] = patch.stock
		if patch.has("group"):
			if not valid_tier(patch.group):
				return false
			model.combat.groups[index] = int(patch.group)
	return stock_fits(model, weapons)

static func stock_fits(model: Dictionary, weapons: Dictionary) -> bool:
	var cost := 0
	for i in model.mounts.size():
		var mount: Dictionary = model.mounts[i]
		var id: String = model.combat.stock[i]
		if id.is_empty():
			if mount.builtin:
				return false
			continue
		var weapon: Dictionary = weapons.get(id,{})
		if weapon.is_empty() or weapon.mount > mount.size or weapon.family not in MountFamilies.data[mount.family].accepts:
			return false
		cost += int(weapon.op)
	return cost <= model.combat.op

static func finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(value)

static func valid_tier(value: Variant) -> bool:
	return finite_number(value) and value == floorf(value) and value >= 1 and value <= 3

static func valid_offset(value: Variant, bounds: Array) -> bool:
	if not value is Array or value.size() != 2 or not finite_number(value[0]) or not finite_number(value[1]):
		return false
	var polygon := PackedVector2Array()
	for vertex in bounds:
		polygon.append(Vector2(vertex[0],vertex[1]))
	return Geometry2D.is_point_in_polygon(Vector2(value[0],value[1]),polygon)

static func valid_magnitude(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(value) and value >= 0 and value <= 10000000
