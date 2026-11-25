extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Responses = preload("res://data/campaign/event_responses.json")
const Sector = preload("res://data/campaign/sector.json")
const LEGACY_HOOKS := {"dock": ["on_dock_regular_port", "on_dock_wild_port"], "trade": ["on_trade"],
	"monthly": ["on_monthly_pulse"], "battle": ["on_battle_victory"], "succession": ["on_succession"], "jump": ["on_hyperspace_jump"]}
const ACTIONS := ["on_dock_regular_port", "on_dock_wild_port", "on_trade", "on_monthly_pulse",
	"on_battle_victory", "on_ship_captured", "on_succession", "on_hyperspace_jump"]
const LAPSED_CHOICE := "条件已变，归档此事"

static func number(value: Variant, low: float, high: float, whole: bool = true) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= low and value <= high and (not whole or value == floorf(value))

static func amounts(value: Variant, names: Array, low: int, high: int) -> bool:
	if not value is Dictionary or value.is_empty():
		return false
	for key in value:
		if key not in names or not number(value[key], low, high):
			return false
	return true

static func valid_conditions(conditions: Variant) -> bool:
	if not conditions is Dictionary:
		return false
	for key in conditions:
		var value: Variant = conditions[key]
		match key:
			"has_trait":
				if not Sector.data.traits.any(func(temperament): return temperament.id == value): return false
			"personality_gte":
				if not amounts(value, Sector.data.personality, -100, 100): return false
			"stat_gte":
				if not amounts(value, Sector.data.stats, 0, 100): return false
			"player_cargo_gte":
				if not amounts(value, Industry.WARE_ID.keys(), 1, 10000): return false
			"fuel_gte", "prize_capacity_gte", "player_suspicion_gte":
				if not number(value, 0, 10000): return false
			"at_event_port", "manager_alive", "hook_on_manager", "prize_owned":
				if not value is bool or not value: return false
			"wild_system", "docked":
				if not value is bool: return false
			_:
				return false
	return true

static func valid_option(option: Variant) -> bool:
	if not option is Dictionary or not option.get("label") is String or option.label.strip_edges().is_empty():
		return false
	if option.has("response"):
		return option.size() == 2 and Responses.data.has(option.response)
	var effect: Variant = option.get("effects")
	if not effect is Dictionary or not valid_conditions(option.get("requires", {})):
		return false
	for key in effect:
		match key:
			"credit", "stress", "experience", "merit", "prestige", "legitimacy", "suspicion", "opinion_manager":
				if not number(effect[key], -10000, 10000): return false
			"cargo":
				if not amounts(effect[key], Industry.WARE_ID.keys(), -10000, -1): return false
			"prize_crew":
				if not number(effect[key], 1, 10000): return false
			"fuel":
				if not number(effect[key], -10000, -1): return false
			"secret":
				if not effect[key] is String or effect[key].is_empty(): return false
			"consume_hook":
				if not effect[key] is bool or not effect[key]: return false
			"grant_hook_to_manager":
				var hook: Variant = effect[key]
				if not hook is Dictionary or not hook.get("kind") is String or hook.kind.is_empty(): return false
				if not number(hook.get("strength"), 1, 2) or not number(hook.get("days"), 1, 10000): return false
			_:
				return false
	var modifiers: Variant = option.get("stress_modifiers", [])
	return modifiers is Array and modifiers.all(func(mod):
		return mod is Dictionary and valid_conditions(mod.get("condition")) and number(mod.get("amount"), -1000, 1000))

static func valid_template(row: Dictionary) -> bool:
	for key in ["id", "title", "body"]:
		if not row.get(key) is String or row[key].strip_edges().is_empty(): return false
	if row.get("on_action") not in ACTIONS or not valid_conditions(row.get("trigger", {})): return false
	if not valid_conditions(row.get("pending_requires", {})) or not row.get("allow_queue", false) is bool: return false
	if not number(row.get("base_weight"), 0.001, 10000, false) or not number(row.get("cooldown_days"), 0, 10000): return false
	var options: Variant = row.get("options")
	if not options is Array or options.is_empty() or not options.all(valid_option): return false
	var modifiers: Variant = row.get("weight_multipliers", [])
	return modifiers is Array and modifiers.all(func(mod):
		return mod is Dictionary and valid_conditions(mod.get("condition")) and number(mod.get("factor"), 0.001, 100, false))

static func authored() -> Array:
	var files := ResourceLoader.list_directory("res://data/events")
	files.sort()
	var rows := []
	for file in files:
		if file.ends_with(".json"):
			var resource: JSON = load("res://data/events/" + file)
			rows.append_array(resource.data)
	return rows

# External fleet packs using the original two-button format share the same dispatcher.
static func from_legacy(row: Dictionary) -> Dictionary:
	var template := {"id": row.id, "title": row.title, "body": row.body, "on_action": LEGACY_HOOKS[row.hook],
		"base_weight": row.weight, "cooldown_days": 30,
		"options": [{"label": row.yes, "response": row.effect}, {"label": row.no, "response": "decline"}]}
	if row.effect == "risk":
		template.weight_multipliers = [{"condition": {"personality_gte": {"greed": 1}}, "factor": 3}]
	return template

static func source_ship(world, context: Dictionary) -> Dictionary:
	var ship: Dictionary = world.ships.get(context.get("vessel", 0), {})
	return ship if ship.get("captain", 0) == world.player else {}

static func live_manager(world, context: Dictionary) -> Dictionary:
	var port: Dictionary = world.ports.get(context.get("port", 0), {})
	var manager: Dictionary = world.people.get(context.get("manager", 0), {})
	if not manager.get("alive", false) or manager.id == world.player or port.get("manager", 0) != manager.id:
		return {}
	return manager

# An empty string means all predicates passed. The same explanation is displayed by both interfaces.
static func unavailable(world, context: Dictionary, conditions: Dictionary) -> String:
	var actor: Dictionary = world.active()
	for key in conditions:
		var value: Variant = conditions[key]
		match key:
			"has_trait":
				if Sector.data.traits[actor.trait].id != value:
					return "性格不符"
			"personality_gte", "stat_gte":
				var profile: Variant = actor.personality if key == "personality_gte" else actor.stats
				for aspect in value:
					if int(profile.get(aspect)) < int(value[aspect]):
						return "人物属性不足"
			"player_suspicion_gte":
				if int(actor.get("suspicion", 0)) < int(value):
					return "走私嫌疑不足"
			"fuel_gte":
				if float(source_ship(world, context).get("fuel", 0.0)) < float(value):
					return "原舰需要 %d 单位燃料" % value
			"player_cargo_gte":
				var ship := source_ship(world, context)
				for ware in value:
					var index: int = Industry.WARE_ID[ware]
					if ship.is_empty() or ship.cargo[index] < int(value[ware]):
						return "原舰需要 %d 单位%s" % [value[ware], Industry.WARES[index]]
			"wild_system":
				var system: int = context.get("system", -1)
				if system < 0 or system >= world.systems.size() or world.systems[system].get("wild", false) != value:
					return "需在外域星系"
			"docked":
				if (actor.loc != 0) != value:
					return "需在港内"
			"at_event_port":
				if actor.loc == 0 or actor.loc != context.get("port", 0) or actor.ship != context.get("vessel", 0) or source_ship(world, context).get("dock", 0) != actor.loc:
					return "需驾驶原舰停靠事发港口"
			"manager_alive", "hook_on_manager":
				var manager := live_manager(world, context)
				if manager.is_empty():
					return "原港务经理已离任"
				if key == "hook_on_manager" and int(actor.hooks.get(manager.id, {}).get("expires", -1)) < world.day:
					return "缺少对港务经理的有效把柄"
			"prize_owned", "prize_capacity_gte":
				var prize: Dictionary = world.ships.get(context.get("prize", 0), {})
				if prize.get("owner", 0) != actor.id:
					return "战利舰已不在名下"
				if key == "prize_capacity_gte" and world.Hulls.crew_limits(prize.kind).y - prize.crew < int(value):
					return "战利舰空余铺位不足"
			_:
				return "未知事件条件"
	return ""

static func weight(world, context: Dictionary, row: Dictionary) -> float:
	if not unavailable(world, context, row.get("trigger", {})).is_empty():
		return 0.0
	var result := float(row.base_weight)
	for modifier in row.get("weight_multipliers", []):
		if unavailable(world, context, modifier.condition).is_empty():
			result *= float(modifier.factor)
	return result

static func response(option: Dictionary) -> Dictionary:
	return Responses.data[option.response] if option.has("response") else option

static func option_block(world, context: Dictionary, option: Dictionary) -> String:
	var rule := response(option)
	var effect: Dictionary = rule.effects
	var required := -int(effect.get("credit", 0))
	if world.active().wallet < required:
		return "需要 ¢%d" % required
	var reason := unavailable(world, context, rule.get("requires", {}))
	if not reason.is_empty():
		return reason
	# Effects may be authored without repeating their inherent costs or target requirements.
	var costs := {}
	if effect.has("cargo"):
		var cargo := {}
		for ware in effect.cargo:
			cargo[ware] = -int(effect.cargo[ware])
		costs.player_cargo_gte = cargo
	if effect.has("fuel"):
		costs.fuel_gte = -int(effect.fuel)
	if effect.has("prize_crew"):
		costs.prize_capacity_gte = effect.prize_crew
	if effect.has("grant_hook_to_manager") or effect.has("opinion_manager"):
		costs.manager_alive = true
	if effect.get("consume_hook", false):
		costs.hook_on_manager = true
	return unavailable(world, context, costs)

static func offer(world, action: String, context: Dictionary, rows: Array) -> void:
	if rows.is_empty() or world.player == 0 or world.succession or not world.people.has(world.player):
		return
	var state: Dictionary = world.campaign
	var queue: Array = state.events.get(world.player, [])
	var history: Dictionary = state.last_event.get(world.player, {})
	if history.get(action, -1) == world.day:
		return
	var ride: Dictionary = world.ride()
	context = context.duplicate()
	context.get_or_add("vessel", ride.get("id", 0))
	context.get_or_add("system", ride.get("system", -1))
	var candidates := []
	var total := 0.0
	for row in rows:
		if not queue.is_empty() and not row.get("allow_queue", action in ["on_ship_captured", "on_succession"]):
			continue
		if history.has(row.id) and world.day - history[row.id] < row.cooldown_days:
			continue
		if queue.any(func(item): return item.id == row.id):
			continue
		var chance := weight(world, context, row)
		if chance <= 0:
			continue
		total += chance
		candidates.append([row, total])
	var roll := float(hash([world.settings.seed, world.player, world.day, action, context.get("port", 0)])) / 4294967296.0 * total
	for candidate in candidates:
		if roll >= candidate[1]:
			continue
		var row: Dictionary = candidate[0]
		history[row.id] = world.day
		history[action] = world.day
		state.last_event[world.player] = history
		queue.append({"id": row.id, "action": action, "context": context, "day": world.day})
		state.events[world.player] = queue
		world.event("待抉择 · %s（事务 → 人物与家族）" % row.title)
		world.event_offered.emit()
		return

static func prune_pending(world, catalog: Dictionary) -> void:
	var queue: Array = world.campaign.events.get(world.player, [])
	var previous_count := queue.size()
	for index in range(previous_count - 1, -1, -1):
		var item: Dictionary = queue[index]
		var row: Dictionary = catalog[item.id]
		if row.has("pending_requires") and not unavailable(world, item.context, row.pending_requires).is_empty():
			queue.remove_at(index)
	if queue.size() != previous_count:
		if queue.is_empty():
			world.campaign.events.erase(world.player)
		world.event_offered.emit()

static func describe(world, catalog: Dictionary, item: Dictionary) -> Dictionary:
	var row: Dictionary = catalog[item.id]
	var options := []
	for option in row.options:
		var reason := option_block(world, item.context, option)
		options.append({"label": option.label, "enabled": reason.is_empty(), "reason": reason})
	if not options.any(func(option): return option.enabled):
		options.append({"label": LAPSED_CHOICE, "enabled": true, "reason": ""})
	return {"id": row.id, "title": row.title, "body": str(row.body).format(item.context), "options": options,
		"on_action": item.action, "day": item.day}

static func pending(world, catalog: Dictionary) -> Dictionary:
	var queue: Array = world.campaign.events.get(world.player, [])
	return {} if queue.is_empty() else describe(world, catalog, queue.front())

static func pending_all(world, catalog: Dictionary) -> Array:
	var result := []
	for item in world.campaign.events.get(world.player, []):
		result.append(describe(world, catalog, item))
	return result

static func decide(world, catalog: Dictionary, id: String, index: int, change_stress: Callable) -> bool:
	var queue: Array = world.campaign.events.get(world.player, [])
	var position := queue.find_custom(func(item): return item.id == id)
	if position < 0 or not catalog.has(id) or index < 0 or index > catalog[id].options.size():
		return false
	var context: Dictionary = queue[position].context
	var options: Array = catalog[id].options
	var option: Dictionary
	if index == options.size():
		if options.any(func(candidate): return option_block(world, context, candidate).is_empty()):
			return false
		option = {"label": LAPSED_CHOICE, "effects": {}}
	else:
		option = options[index]
	if not option_block(world, context, option).is_empty():
		return false
	var actor: Dictionary = world.active()
	var rule := response(option)
	var effect: Dictionary = rule.effects
	var pressure := int(effect.get("stress", 0))
	for modifier in rule.get("stress_modifiers", []):
		if unavailable(world, context, modifier.condition).is_empty():
			pressure += int(modifier.amount)
	world.credit(actor.id, int(effect.get("credit", 0)))
	for key in ["merit", "experience", "prestige"]:
		actor[key] += int(effect.get(key, 0))
	if effect.has("suspicion"):
		actor.suspicion = clampi(actor.get("suspicion", 0) + int(effect.suspicion), 0, 100)
	if effect.has("legitimacy"):
		actor.legitimacy = clampi(actor.legitimacy + int(effect.legitimacy), 0, 5)
	if effect.has("secret"):
		actor.secrets.append({"kind": effect.secret, "day": world.day, "contact": context.get("manager", 0)})
	if effect.has("grant_hook_to_manager"):
		var manager := live_manager(world, context)
		var hook: Dictionary = effect.grant_hook_to_manager
		var existing: Dictionary = manager.hooks.get(actor.id, {})
		if int(existing.get("expires", -1)) < world.day or int(existing.get("strength", 0)) <= int(hook.strength):
			manager.hooks[actor.id] = {"kind": hook.kind, "strength": int(hook.strength), "expires": maxi(existing.get("expires", 0), world.day + int(hook.days))}
	if effect.get("consume_hook", false):
		actor.hooks.erase(context.manager)
	if effect.has("opinion_manager"):
		var manager := live_manager(world, context)
		manager.opinions[actor.id] = clampi(manager.opinions.get(actor.id, 0) + int(effect.opinion_manager), -100, 100)
	if effect.has("cargo"):
		var ship := source_ship(world, context)
		for ware in effect.cargo:
			ship.cargo[Industry.WARE_ID[ware]] += int(effect.cargo[ware])
	if effect.has("fuel"):
		var ship := source_ship(world, context)
		ship.fuel += float(effect.fuel)
	if effect.has("prize_crew"):
		world.ships[context.prize].crew += int(effect.prize_crew)
	change_stress.call(world, actor, pressure)
	queue.remove_at(position)
	if queue.is_empty():
		world.campaign.events.erase(actor.id)
	world.event("%s · %s" % [catalog[id].title, option.label])
	world.event_offered.emit()
	return true
