extends RefCounted

class FittingData extends RefCounted:
	## A vessel owns one fitting. In flight the arrays use catalog mount order.
	## ShipData translates these positions to stable mount IDs when writing a V7 save.
	var weapons: Array[String] = []
	var groups: Array[int] = []
	var auto: Array[bool] = []
	var wings: Array[String] = []
	var caps: int = 0
	var vents: int = 0
	var _grouped_weapons: Array[String] = []
	var _group_assignments: Array[int] = []
	var _direct_fire_slots: Array = []

	static func index_fire_groups(guns: Array, assignments: Array, catalog: Dictionary) -> Array:
		var slots := [[],[],[]]
		for i in guns.size():
			var spec: Dictionary = catalog.get(guns[i],{})
			var group: int = assignments[i]
			if group >= 1 and group <= slots.size() and not spec.is_empty() and not spec.get("pd",false):
				slots[group - 1].append(i)
		return slots

	func fire_groups(catalog: Dictionary) -> Array:
		if _direct_fire_slots.is_empty() or groups != _group_assignments or weapons != _grouped_weapons:
			_group_assignments = groups.duplicate()
			_grouped_weapons = weapons.duplicate()
			_direct_fire_slots = index_fire_groups(weapons,groups,catalog)
		return _direct_fire_slots

	static func from_dictionary(record: Dictionary, json_numbers := false, default_wings: Array = []) -> FittingData:
		var installed: Variant = record.get("weapons")
		var assignments: Variant = record.get("groups")
		var automatic: Variant = record.get("auto")
		if not installed is Array or not assignments is Array or not automatic is Array:
			return null
		if installed.size() != assignments.size() or automatic.size() != 3:
			return null
		var fit := FittingData.new()
		for weapon in installed:
			if not weapon is String:
				return null
			fit.weapons.append(weapon)
		for group in assignments:
			if not valid_integer(group,1,3,json_numbers):
				return null
			fit.groups.append(int(group))
		for enabled in automatic:
			if not enabled is bool:
				return null
			fit.auto.append(enabled)
		var air_group: Variant = record.get("wings",default_wings)
		if not air_group is Array:
			return null
		for wing in air_group:
			if not wing is String:
				return null
			fit.wings.append(wing)
		var capacitors: Variant = record.get("caps",0)
		var radiators: Variant = record.get("vents",0)
		if not valid_integer(capacitors,0,2147483647,json_numbers) or not valid_integer(radiators,0,2147483647,json_numbers):
			return null
		fit.caps = int(capacitors)
		fit.vents = int(radiators)
		return fit

	static func valid_integer(value: Variant, minimum: int, maximum: int, json_numbers: bool) -> bool:
		if value is int:
			return value >= minimum and value <= maximum
		# Godot JSON numbers are floats. Accept only exact, in-range whole numbers.
		return json_numbers and value is float and value >= minimum and value <= maximum and value == floor(value)

	func as_dictionary() -> Dictionary:
		# Use detached, untyped arrays at the save and agent protocol boundaries.
		var installed := []
		var assignments := []
		var automatic := []
		var air_group := []
		installed.assign(weapons)
		assignments.assign(groups)
		automatic.assign(auto)
		air_group.assign(wings)
		return {"weapons":installed,"groups":assignments,"auto":automatic,"caps":caps,"vents":vents,"wings":air_group}

	func copy() -> FittingData:
		var result := FittingData.new()
		result.weapons.assign(weapons)
		result.groups.assign(groups)
		result.auto.assign(auto)
		result.wings.assign(wings)
		result.caps = caps
		result.vents = vents
		return result

	func matches(other: FittingData) -> bool:
		return other != null and weapons == other.weapons and groups == other.groups and auto == other.auto and caps == other.caps and vents == other.vents and wings == other.wings
