extends SceneTree

const Game = preload("res://game.tscn")
var game
var world
var station: Dictionary
var ship: Dictionary
var checks := 0
var failures := 0
var warehouse_wares := {}

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",description)
	return ok

func button(container: Node, caption: String) -> Button:
	for item: Button in container.find_children("*","Button",true,false):
		if item.is_visible_in_tree() and item.text.begins_with(caption):
			return item
	return null

func click(target: Button, allow_disabled: bool = false) -> bool:
	if not check(is_instance_valid(target) and (allow_disabled or not target.disabled),"the requested interaction is available"):
		return false
	await process_frame
	var parent := target.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(target)
		parent = parent.get_parent()
	await process_frame
	var point := target.get_global_rect().get_center()
	var clip := Rect2(Vector2.ZERO,root.size)
	parent = target.get_parent()
	while parent:
		if parent is Control and parent.clip_contents:
			clip = clip.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	if not check(clip.has_point(point),"the visible button receives normal pointer input"):
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
	await process_frame
	return true

func enter_number(field: LineEdit, amount: int) -> bool:
	if not check(is_instance_valid(field) and field.is_visible_in_tree() and field.editable,"an editable visible quantity field is available"):
		return false
	field.grab_focus()
	field.select_all()
	for digit in str(amount):
		for down in [true,false]:
			var key := InputEventKey.new()
			key.keycode = digit.unicode_at(0)
			key.unicode = key.keycode
			key.pressed = down
			root.push_input(key,true)
	await process_frame
	return check(is_instance_valid(field) and field.text==str(amount),"the form retains the numeric input")

func market_balances() -> Dictionary:
	return {"wallet":world.active().wallet,"treasury":station.treasury,"profit":station.operating_profit,
		"cargo":ship.cargo.duplicate(),"stock":station.stock.duplicate(),"black":station.black.duplicate(),
		"suspicion":world.active().get("suspicion",0),"attention":world.attention}

func market_row(ware: int) -> Button:
	var label: Label = game.hud.market_rows.get(ware)
	return button(label.get_parent(),"交易") if is_instance_valid(label) else null

func select_text(picker: OptionButton, text: String) -> bool:
	if not check(is_instance_valid(picker) and not picker.disabled,"a partner or asset selector is available"):
		return false
	for i in picker.item_count:
		if picker.get_item_text(i).begins_with(text):
			if picker.selected != i:
				picker.select(i)
				picker.item_selected.emit(i)
				await process_frame
			return true
	return check(false,"selector has item "+text)

func select_category(text: String) -> bool:
	for field: OptionButton in game.trade_table.find_children("*","OptionButton",true,false):
		for i in field.item_count:
			if field.get_item_text(i)==text:
				return await select_text(field,text)
	return check(false,"listed partner category "+text)

func select_person(id: int) -> bool:
	var table = game.trade_table
	var picker: OptionButton = table.find_child("TradePartner",true,false)
	var people: Array = table.partners.filter(func(row): return row.kind=="person")
	var index := people.find_custom(func(entry): return entry.id==id)
	if not check(index>=0 and index<picker.item_count,"the representative is individually selectable"):
		return false
	for other in range(picker.item_count):
		if other!=index and people[other].name==people[index].name:
			check(picker.get_item_text(index)!=picker.get_item_text(other),"different people with the same name have distinct visible account labels")
	picker.select(index)
	picker.item_selected.emit(index)
	await process_frame
	return true

func labels_contain(container: Node, text: String) -> bool:
	for label: Label in container.find_children("*","Label",true,false):
		if label.is_visible_in_tree() and text in label.text:
			return true
	return false

func icon_in(container: Node, kind: String, id: int) -> TextureRect:
	for icon: TextureRect in container.find_children("*","TextureRect",true,false):
		if icon.get_meta("asset_kind","")==kind and icon.get_meta("asset_id",-1)==id:
			return icon
	return null

func matching_icon(container: Node, kind: String, id: int) -> bool:
	var graphic := icon_in(container,kind,id)
	return is_instance_valid(graphic) and graphic.texture==load("res://scripts/ui/cargo_icons.gd").texture(kind,id)

func check_catalog_icons() -> void:
	var atlas = load("res://scripts/ui/cargo_icons.gd")
	var regions := {}
	var fingerprints := {}
	var media := []
	for id in world.WARES.size():
		media.append(["ware",id])
	for kind in ["cash","company_share","station_share","treaty"]:
		media.append([kind,0])
	for asset in media:
		var icon: AtlasTexture = atlas.texture(asset[0],asset[1])
		if not check(icon!=null and icon.get_width()>0 and icon.get_height()>0 and not regions.has(icon.region),"the catalog assigns a distinct, nonempty atlas region to %s %d" % asset):
			continue
		regions[icon.region]=true
		if DisplayServer.get_name()=="headless":
			continue
		var pixels := icon.get_image()
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(pixels.get_data())
		var content := hasher.finish().hex_encode()
		check(pixels.get_used_rect().has_area() and not fingerprints.has(content),"the actual rendered tile is nonblank and has its own pixels: %s %d" % asset)
		fingerprints[content]=true

func check_warehouse_icons() -> void:
	for id: int in game.hud.market_rows:
		var label: Label = game.hud.market_rows[id]
		var row := label.get_parent()
		if check(matching_icon(row,"ware",id),"the displayed warehouse row uses its catalog illustration for "+str(world.WARES[id])):
			warehouse_wares[id]=true

func distinct_feedback(table: Control) -> bool:
	var display = table.find_child("ConsentMeter",true,false).get_parent()
	return not display.factors.is_visible_in_tree() or display.factors.text != display.details.text

func add_asset(giving: bool, text: String, quantity: int) -> bool:
	var selector := "GiveAsset" if giving else "WantAsset"
	var picker := game.trade_table.find_child(selector,true,false) as OptionButton
	if not await select_text(picker,text) or not await click(button(picker.get_parent(),"添加")):
		return false
	if quantity > 1:
		picker = game.trade_table.find_child(selector,true,false)
		for label: Label in picker.get_parent().get_parent().find_children("*","Label",true,false):
			if label.text == text:
				var fields := label.get_parent().find_children("*","LineEdit",false,false)
				if not fields.is_empty():
					return await enter_number(fields[0],quantity)
		return check(false,"the new draft line has a quantity for "+text)
	return true

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or "--capture" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_temp_dir().path_join(name+".png"))==OK,"capture the game viewport "+name)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440,900)
	game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	world = game.world
	world.new_game({"seed":"signed-cargo-table","systems":12,"factions":3,"overrides":[{"regime":2}],"avatar":{"name":"顾春","house":"南桥"}})
	ship = world.ride()
	station = world.ports[ship.dock]
	world.active().wallet = 5000
	for ware in [0,1,2]:
		station.stock[ware] = maxi(station.stock[ware],30)
	station.black[6] = maxi(station.black[6],5)
	game.run_bridge()
	game.set_physics_process(false)
	await process_frame
	if not await click(button(game.dock_view.stage,"货栈")):
		finish()
		return
	check_catalog_icons()
	check_warehouse_icons()
	var rows_clean: bool = not game.hud.market_rows.is_empty()
	for label: Label in game.hud.market_rows.values():
		var actions := label.get_parent().find_children("*","Button",false,false)
		rows_clean = rows_clean and actions.size()==1 and actions[0].text=="交易"
	check(rows_clean and button(game.body,"打开交易窗口") != null,"the warehouse offers a trade window and each commodity row has only its trading entry")
	var scroll := game.body.get_parent() as ScrollContainer
	scroll.ensure_control_visible(game.hud.market_rows[0])
	await capture("starrail-warehouse")
	if not await click(market_row(0)):
		finish()
		return
	check(is_instance_valid(game.trade_table) and game.trade_table.visible,"selecting a posted commodity enters the unified trading window")
	await exercise_table()
	finish()

func exercise_table() -> void:
	var table = game.trade_table
	var qty: LineEdit = table.find_child("TradeQuantity",true,false)
	var representative: int = table.matching_partner().representative
	check(matching_icon(table,"ware",0) and distinct_feedback(table),"the single-item dialog repeats the warehouse icon and displays each reason only once")
	check(table.kind=="station" and table.partner_id==station.id and qty.text=="1" and labels_contain(table,world.name_of(representative)) and labels_contain(table,"首件") and labels_contain(table,"成交后余额"),"a posted good opens one unit with its signer, price and resulting balance")
	await capture("starrail-market-item")
	var ledger := market_balances()
	var cost: int = world.Economy.lot_quote(station,0,1,true,world.active().origin).y
	if not await click(button(table,"确认买入")):
		return
	check(ship.cargo[0]==ledger.cargo[0]+1 and station.stock[0]==ledger.stock[0]-1 and world.active().wallet==ledger.wallet-cost and station.treasury==ledger.treasury+cost,"single-unit confirmation moves exactly one unit and its quoted cash between real accounts")
	qty = table.find_child("TradeQuantity",true,false)
	ledger = market_balances()
	cost = world.Economy.lot_quote(station,0,3,true,world.active().origin).y
	if not await enter_number(qty,3):
		return
	check(market_balances()==ledger and labels_contain(table,"共付 ¢%d" % cost),"batch quantity reprices without exchanging cargo")
	if not await click(button(table,"确认买入")):
		return
	check(ship.cargo[0]==ledger.cargo[0]+3 and station.stock[0]==ledger.stock[0]-3 and world.active().wallet==ledger.wallet-cost and station.treasury==ledger.treasury+cost,"the same commodity screen settles a multiunit quote")
	if not await select_text(table.find_child("TradeSide",true,false),"卖出"):
		return
	ledger = market_balances()
	cost = world.Economy.lot_quote(station,0,1,false,world.active().origin).y
	if not await click(button(table,"确认卖出")):
		return
	check(ship.cargo[0]==ledger.cargo[0]-1 and station.stock[0]==ledger.stock[0]+1 and world.active().wallet==ledger.wallet+cost and station.treasury==ledger.treasury-cost,"ordinary selling uses the same real account in the opposite direction")
	if not await click(button(table,"组合交易")):
		return
	check(table.quick_ware<0 and labels_contain(table,"我给出") and labels_contain(table,"我想要"),"switching from a single commodity opens both sides of a deal")
	if not await click(button(table,"关闭")) or not await click(button(game.body,"打开交易窗口")):
		return
	table = game.trade_table
	ledger = market_balances()
	if not await add_asset(true,world.WARES[0],1) or not await add_asset(false,world.WARES[1],3) or not await add_asset(false,world.WARES[2],2):
		return
	var giving: Control = table.find_child("GiveColumn",true,false)
	var wanting: Control = table.find_child("WantColumn",true,false)
	check(matching_icon(giving,"ware",0) and matching_icon(wanting,"ware",1) and matching_icon(wanting,"ware",2),"each actual draft line uses the same ware picture as its corresponding warehouse row")
	var asset_menu: OptionButton = table.find_child("WantAsset",true,false)
	var menu_matches := true
	for i in asset_menu.item_count:
		var asset: Dictionary = table.catalog.want[i]
		menu_matches = menu_matches and asset_menu.get_item_icon(i)==load("res://scripts/ui/cargo_icons.gd").texture(asset.kind,asset.id)
	check(menu_matches,"available assets use the same icons in the selector and the offer")
	var bar: ProgressBar = table.find_child("ConsentMeter",true,false)
	var declined := int(bar.value)
	var submit := button(table,"提出交易")
	if not check(submit.disabled and declined<int(world.EquityOrders.TERMS.consent_threshold) and market_balances()==ledger,"an underpriced multigood offer is visibly declined without settling either side") or not await click(submit,true):
		return
	check(table.deal_id==0 and market_balances()==ledger,"attempting to submit the declined terms leaves cargo, wallets and warehouses unchanged")
	if not await click(button(table,"补齐差价")):
		return
	var premium: int = table.amount_of(table.give,"cash",0)
	bar = table.find_child("ConsentMeter",true,false)
	check(premium>0 and bar.value>declined and bar.value>=world.EquityOrders.TERMS.consent_threshold and market_balances()==ledger,"balancing the actual difference adds cash to the player's side and changes the live agreement score")
	check(matching_icon(table.find_child("GiveColumn",true,false),"cash",0) and distinct_feedback(table),"the balancing credits are visible with their own coin icon and a single reason")
	await capture("starrail-trade-table")
	if not await click(button(table,"提出交易")):
		return
	check(table.deal_id>0 and table.find_child("GiveAsset",true,false)==null and labels_contain(table,"对方已签") and ship.cargo[1]==ledger.cargo[1] and ship.cargo[2]==ledger.cargo[2] and station.stock[0]==ledger.stock[0] and station.treasury==ledger.treasury,"a signed combination locks the listed terms in escrow without prematurely crediting the other side")
	check(matching_icon(table,"ware",0) and matching_icon(table,"ware",1) and matching_icon(table,"ware",2) and matching_icon(table,"cash",0),"the fixed settlement list contains the same commodity and credit illustrations")
	if not await click(button(table,"撤回提案")):
		return
	check(table.deal_id==0 and market_balances()==ledger,"cancelling before delivery restores every escrowed ware and credit")
	if not await click(button(table,"提出交易")):
		return
	if not await click(button(table,"确认交割")):
		return
	check(table.deal_id==0 and ship.cargo[0]==ledger.cargo[0]-1 and ship.cargo[1]==ledger.cargo[1]+3 and ship.cargo[2]==ledger.cargo[2]+2 and station.stock[0]==ledger.stock[0]+1 and station.stock[1]==ledger.stock[1]-3 and station.stock[2]==ledger.stock[2]-2 and world.active().wallet==ledger.wallet-premium and station.treasury==ledger.treasury+premium,"one atomic settlement exchanges both goods plus cash and consumes the original signed proposal")
	var company: int = world.firms.keys().front()
	var director: int = world.firms[company].director
	if not await select_category("人物") or not await select_person(director):
		return
	check(table.kind=="person" and table.partner_id==director and labels_contain(table,"私人账户") and table.catalog.want.any(func(asset): return asset.kind=="company_share"),"the same table identifies a real shareholder (expected %s #%d, selected %s #%d, catalog %s)" % [world.name_of(director),director,table.kind,table.partner_id,table.catalog.want])
	if not await select_category("公司"):
		return
	check(table.kind=="company" and labels_contain(table,world.name_of(table.matching_partner().representative)) and table.catalog.want.any(func(asset): return asset.kind=="station_share"),"a company shows its representative and actually held station shares")
	if not await select_category("势力"):
		return
	check(table.kind=="faction" and labels_contain(table,world.name_of(table.matching_partner().representative)),"the faction table names its authorized representative")
	if not await click(button(table,"关闭")) or not await click(button(game.body,"黑市")):
		return
	check_warehouse_icons()
	check(warehouse_wares.size()==world.WARES.size() and warehouse_wares.has(6),"public and black-market shelves together show all sixteen commodity icons")
	if not await click(market_row(6)):
		return
	table = game.trade_table
	ledger = market_balances()
	cost = world.Economy.lot_quote(station,6,1,true,world.active().origin,true).y
	check(table.black and table.matching_partner().representative!=representative and labels_contain(table,"黑市"),"the private black-market broker has a distinct trading identity")
	if not await click(button(table,"确认买入")):
		return
	check(ship.cargo[6]==ledger.cargo[6]+1 and station.black[6]==ledger.black[6]-1 and station.stock==ledger.stock and station.treasury==ledger.treasury and world.active().wallet==ledger.wallet-cost and world.active().suspicion>ledger.suspicion,"contraband draws from the black-market stocks, charges its price and increases the captain's smuggling suspicion")

func finish() -> void:
	game.free()
	print("Trade table UI %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
