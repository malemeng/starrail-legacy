extends RefCounted

const PERSONALITY_PAIRS := [
	["勇敢", "怯懦"], ["慷慨", "贪婪"], ["仁慈", "残忍"],
	["勤勉", "懒惰"], ["诚实", "狡诈"], ["狂热", "愤世"]
]

static func can_add_trait(held: Array, label: String) -> bool:
	if label in held:
		return false
	for pair: Array in PERSONALITY_PAIRS:
		if label in pair:
			return pair[0] not in held and pair[1] not in held
	return true

class Attributes:
	const KEYS := [&"diplomacy",&"martial",&"stewardship",&"intrigue",&"learning",&"prowess"]
	var diplomacy: int
	var martial: int
	var stewardship: int
	var intrigue: int
	var learning: int
	var prowess: int

	static func from_dict(data: Dictionary) -> Attributes:
		var attributes := Attributes.new()
		for key in KEYS:
			if not data.get(key) is int:
				return null
			attributes.set(key, data[key])
		return attributes

	func to_dict() -> Dictionary:
		var values := {}
		for key in KEYS:
			values[String(key)] = get(key)
		return values

static func create(id: int, label: String, house: String, birth: int, flag: int, location: int,
		origin: int, temperament: int, appearance: Dictionary, lifespan: int, gender: int = 0) -> Dictionary:
	return {"id": id, "name": label, "house": house, "birth": birth, "flag": flag, "noble": false,
		"gender": gender, "loc": location, "ship": 0, "alive": true, "wallet": 0, "origin": origin, "trait": temperament,
		"shares": {}, "look": appearance.duplicate(true), "parents": [], "spouse": 0, "children": [], "law": 0,
		"endorsement": 0, "employer": 0, "opinions": {}, "last_child": -4000, "lifespan": lifespan,
		"loyalty": 55 + (20 if temperament == 2 else 0)}

static func encode(actor: Dictionary) -> Dictionary:
	var saved := actor.duplicate(true)
	saved.stats = actor.stats.to_dict()
	return saved

static func decode_into(actor: Dictionary) -> bool:
	for field in ["stress","break_level","trait","birth","lifespan","origin","flag","loc","ship","wallet"]:
		if not actor.get(field) is int:
			return false
	for field in ["parents","children","secrets","ck_traits"]:
		if not actor.get(field) is Array:
			return false
	var held := []
	for label in actor.ck_traits:
		if not label is String or not can_add_trait(held,label):
			return false
		held.append(label)
	for field in ["stats","personality","look","hooks","perks","opinions"]:
		if not actor.get(field) is Dictionary:
			return false
	var attributes := Attributes.from_dict(actor.stats)
	if attributes == null or not actor.get("name") is String or not actor.get("house") is String:
		return false
	actor.stats = attributes
	if not actor.has("gender"):
		actor.gender = absi(int(actor.get("id", 0))) % 2
	return true
