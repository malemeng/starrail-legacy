extends RefCounted

static func write(world, path: String, succession_checkpoint: bool) -> bool:
	var snapshot: Dictionary = world.snapshot()
	if succession_checkpoint:
		for vessel in snapshot.ships.values():
			vessel.locked = false
			vessel.hp = maxf(vessel.hp, 1.0)
			vessel.battle.shield = false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(snapshot)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(temporary, path) == OK

static func read(world, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = file.get_var(false)
	file.close()
	return data is Dictionary and world.load_state(data)
