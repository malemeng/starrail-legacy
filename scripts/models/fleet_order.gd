extends RefCounted

const LIMIT := 16
const LABELS := {"dock":"停靠","buy":"买入","sell":"卖出","load":"从仓库装船","unload":"向仓库卸货","escort_to":"护送旗舰到港"}
const ROLES := {"ATTACK":"攻击","INTERCEPT":"截击","BOMBARD":"轰炸","DEFEND":"护卫","SUPPLY":"补给","MIMIC":"模仿"}

static func carries_goods(kind: String) -> bool:
	return kind in ["buy","sell","load","unload"]

static func valid(order: Variant, ware_count: int) -> bool:
	if not order is Dictionary or not order.get("kind") in LABELS or not order.get("port") is int or order.port <= 0:
		return false
	if order.kind == "escort_to":
		return order.get("commander") is int and order.commander > 0
	if carries_goods(order.kind):
		return order.get("ware") is int and order.ware in range(ware_count) and order.get("quantity") is int and order.quantity > 0
	return true

static func describe(world, order: Dictionary) -> String:
	var port: Dictionary = world.ports.get(order.port,{})
	var label: String = LABELS[order.kind]
	if carries_goods(order.kind):
		label += " %s ×%d" % [world.WARES[order.ware],order.quantity]
	return "%s · %s" % [label,port.get("name","失联港口")]
