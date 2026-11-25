extends SceneTree

const World = preload("res://world.gd")
const Society = preload("res://scripts/campaign/society.gd")
var checks := 0
var failures := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",text)

func valid_personality(actor: Dictionary) -> bool:
	var groups := 0
	for pair: Array in Society.CK_PERSONALITY_PAIRS:
		var count: int = actor.ck_traits.count(pair[0]) + actor.ck_traits.count(pair[1])
		if count > 1:
			return false
		groups += count
	return groups in [2,3]

func expected_stats(actor: Dictionary) -> Dictionary:
	var values := {}
	for i in Society.rules.stats.size():
		values[Society.rules.stats[i]] = 5 + int(Society.rules.traits[actor.trait].stats[i]) + absi(hash([actor.id,actor.house,i])) % 5
	for label in actor.ck_traits:
		for key in Society.CK_TRAIT_MODS[label]:
			values[key] = maxi(1,int(values[key]) + int(Society.CK_TRAIT_MODS[label][key]))
	return values

func check_grants_and_saves(world) -> void:
	var actor: Dictionary = world.active()
	var labels: Array = actor.ck_traits.duplicate()
	var stats: Dictionary = actor.stats.to_dict()
	for pair: Array in Society.CK_PERSONALITY_PAIRS:
		if pair[0] in labels or pair[1] in labels:
			Society.apply_trait_mod(actor,pair[0])
			Society.apply_trait_mod(actor,pair[1])
			check(actor.ck_traits == labels and actor.stats.to_dict() == stats,"a repeated or opposite grant leaves labels and attributes unchanged")
			break
	Society.apply_trait_mod(actor,"隐士")
	Society.apply_trait_mod(actor,"隐士")
	check(actor.ck_traits.count("隐士") == 1 and actor.stats.learning == int(stats.learning)+2,"a coping trait can coexist with personality and changes attributes only once")
	var snapshot: Dictionary = world.snapshot()
	var restored := World.new()
	check(restored.load_state(snapshot) and restored.active().ck_traits == actor.ck_traits and restored.active().stats.to_dict() == actor.stats.to_dict(),"valid traits and their modifiers round-trip")
	for pair: Array in Society.CK_PERSONALITY_PAIRS:
		if pair[0] not in labels and pair[1] not in labels:
			continue
		var same: String = pair[0] if pair[0] in labels else pair[1]
		var opposite: String = pair[1] if same == pair[0] else pair[0]
		for value in [same,opposite]:
			var malformed := snapshot.duplicate(true)
			malformed.people[actor.id].ck_traits.append(value)
			check(not restored.load_state(malformed) and restored.active().ck_traits == actor.ck_traits,"an invalid saved pair cannot replace the active world")
		break

func _initialize() -> void:
	var people_count := 0
	var newborns := 0
	var congenital := 0
	for i in 8:
		var world := World.new()
		var seed_name := "人物审阅-1122" if i == 0 else "trait-draw-%d" % i
		world.new_game({"seed":seed_name,"systems":24,"factions":5})
		check(world.people.values().all(valid_personality),"each generated person has two or three distinct personality groups in "+seed_name)
		people_count += world.people.size()
		if i == 0:
			print("Original audit world: %d people" % world.people.size())
			check_grants_and_saves(world)
		var parent := world.active()
		var partner: Dictionary = world.people[world.random_person(world.NEUTRAL,parent.loc,parent.house,1-parent.gender)]
		partner.opinions[parent.id] = 80
		check(world.Politics.marry(world,parent.id,partner.id),"the test household marries at its home port")
		for adult: Dictionary in [parent,partner]:
			Society.apply_trait_mod(adult,"聪慧")
		for birth in 4:
			var child_id: int = world.Politics.child(world,parent.id,partner.id)
			if not world.people.has(child_id):
				check(false,"childbirth created a registered child")
				continue
			var child: Dictionary = world.people[child_id]
			newborns += 1
			congenital += int("聪慧" in child.ck_traits)
			check(valid_personality(child) and child.ck_traits.count("聪慧") <= 1 and child.stats.to_dict() == expected_stats(child),"newborn modifiers match their distinct personality and congenital traits")
	check(congenital > 0 and newborns == 32,"congenital traits still pass to the next generation")
	print("Personality traits %d/%d; %d initial characters, %d newborns, %d with the parents' congenital trait" % [checks-failures,checks,people_count,newborns,congenital])
	quit(1 if failures else 0)
