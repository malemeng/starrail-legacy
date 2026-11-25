extends VBoxContainer

const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")
const Blueprint = preload("res://scripts/ui/refit_blueprint.gd")
const ROWS := [["齐射伤害","volley","%.1f"],["满弹 DPS","dps","%.1f"],
	["持续 DPS","sustained_dps","%.1f"],["幅能 / 伤害","flux_per_damage","%.2f"],["射程","range","%.0f"],["装配点","op","%d"]]

var game
var station: Dictionary
var black := false
var slot := -1
var ship_id := 0
var ids: Array = []
var choices: OptionButton
var comparison: GridContainer
var settlement: Label
var install: Button

func configure(controller, port: Dictionary, channel: bool, index: int, target_ship_id: int = 0) -> void:
	game = controller
	station = port
	black = channel
	ship_id = target_ship_id
	game.world.market_updated.connect(market_changed)
	show_mount(index)

func market_changed(port_id: int, _ware: int, _black: bool) -> void:
	if port_id != station.id or not is_inside_tree():
		return
	if ids != Economy.slot_offers(game.world,port_id,slot,black,ship_id):
		var previous: String = ids[choices.selected] if not ids.is_empty() else ""
		show_mount(slot,true)
		if previous in ids:
			choices.select(ids.find(previous))
			preview(choices.selected)
	elif not ids.is_empty():
		update_price(ids[choices.selected])

func show_mount(index: int, rebuild: bool = false) -> void:
	if slot == index and not rebuild:
		return
	slot = index
	game.clear(self)
	ids = []
	var vessel: Dictionary = Economy.refit_target(game.world, ship_id)
	if vessel.is_empty():
		return
	var mount := Hulls.slot_spec(vessel.kind,slot)
	var current: String = vessel.fit.weapons[slot]
	var heading: Label = game.title(self,"[%d] %s · 射界 %.0f°" % [slot+1,Blueprint.mount_label(mount),mount.arc],16,Blueprint.family_color(mount.family))
	heading.tooltip_text = "可用武器：" + "、".join(mount.accepts.map(Blueprint.family_name))
	if mount.builtin:
		game.hud.hint(self,"固定装备　" + str(Hulls.WEAPONS.get(current,{}).get("name","空槽")))
		return
	ids = Economy.slot_offers(game.world,station.id,slot,black,ship_id)
	if ids.is_empty():
		game.hud.hint(self,"本站当前没有兼容此挂点的武器。")
		return
	choices = game.choice(self,ids.map(func(key): return Hulls.WEAPONS[key].name if key != "" else "卸下当前武器"))
	choices.name = "WeaponChoices"
	comparison = GridContainer.new()
	comparison.name = "Comparison"
	comparison.columns = 3
	comparison.add_theme_constant_override("h_separation",16)
	add_child(comparison)
	settlement = game.title(self,"",14,game.GOLD,true)
	install = game.button(self,"确认换装",purchase)
	install.name = "InstallWeapon"
	install.focus_mode = Control.FOCUS_ALL
	choices.item_selected.connect(preview)
	var first := 1 if ids.size() > 1 and ids[0] == current else 0
	choices.select(first)
	preview(first)

func preview(index: int) -> void:
	var key: String = ids[index]
	var vessel: Dictionary = Economy.refit_target(game.world, ship_id)
	if vessel.is_empty():
		return
	var current: String = vessel.fit.weapons[slot]
	var before := Hulls.weapon_metrics(current)
	var after := Hulls.weapon_metrics(key)
	game.clear(comparison)
	for caption in ["指标","现装\n"+str(Hulls.WEAPONS.get(current,{}).get("name","空槽")),"候选\n"+str(Hulls.WEAPONS.get(key,{}).get("name","空槽"))]:
		var header: Label = game.title(comparison,caption,14,game.GOLD)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row in ROWS:
		var field: String = row[1]
		var format: String = row[2]
		game.title(comparison,row[0],14,game.DIM)
		game.title(comparison,format % before[field] if current != "" else "—",14,game.INK)
		var label: String = format % after[field] if key != "" else "—"
		if field == "op":
			label += "  (%+d)" % (after.op-before.op)
		game.title(comparison,label,14,game.INK)
	comparison.tooltip_text = "按满编、满战备的基础武器数据计算。持续 DPS 计入弹药再生，点防武器的目标为导弹和舰载机。"
	update_price(key)

func update_price(key: String) -> void:
	var quote := Economy.refit_quote(game.world,station.id,slot,key,black,ship_id)
	var payment := "净付 ¢%d" % quote.get("net",0) if quote.get("net",0) >= 0 else "退还 ¢%d" % -int(quote.net)
	settlement.text = "%s　·　装后剩余 OP %d" % [payment,quote.free_op] if quote.has("free_op") else ""
	if not quote.ok:
		settlement.text += "　" + str(quote.reason)
	install.disabled = not quote.ok
	install.text = "确认卸下" if key == "" else "确认换装"

func purchase() -> void:
	var key: String = ids[choices.selected]
	var quote := Economy.refit_quote(game.world,station.id,slot,key,black,ship_id)
	var done: bool = quote.ok and Economy.refit_slot(game.world,station.id,slot,key,black,ship_id)
	game.hud.result(done,"已卸下武器并结算折价。" if key == "" else "已换装%s。" % Hulls.WEAPONS[key].name,quote.get("reason","换装失败。"))
