extends SceneTree

const Game = preload("res://game.tscn")
const Agent = preload("res://agent_bridge.gd")
const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")
const Market = preload("res://scripts/ui/refit_market.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var api := Agent.new()
	api.game = game
	check(api.dispatch("new_game",{"seed":"bench-preview","systems":12,"factions":3}).ok,"new game")
	game.tab = "港口"
	game.dock_view.mode = "refit"
	game.refresh()
	await process_frame
	var world = game.world
	var vessel: Dictionary = world.ride()
	var port: Dictionary = world.ports[vessel.dock]
	var old: String = vessel.fit.weapons[0]
	var outpost := {"id":port.id,"module":Economy.Industry.Module.MINE,"modules":[Economy.Industry.Module.MINE],"build":0}
	check("lance" not in Economy.station_weapons(world,outpost),"ordinary mine uses light catalog")
	outpost.modules.append(Economy.Industry.Module.YARD)
	check("lance" in Economy.station_weapons(world,outpost),"adding a shipyard unlocks heavy public weapons")
	var request := {"slot":0,"weapon":""}
	var wallet: int = world.active().wallet
	var quote: Dictionary = api.dispatch("refit_quote",request).result
	check(quote.ok and quote.before.dps > 0 and quote.after.dps == 0 and quote.net < 0,"trade-in quote with weapon performance")
	check(world.active().wallet == wallet and vessel.fit.weapons[0] == old,"preview has no side effects")
	var store: Market = game.body.find_child("WeaponChoices",true,false).get_parent()
	var blueprint = game.dock_view.blueprint
	var motion := InputEventMouseMotion.new()
	motion.position = blueprint.mount_point(2)
	blueprint._gui_input(motion)
	check(blueprint.hovered == 2 and store.slot == 2 and game.dock_view.slot_index == 0,"hover previews real mount without changing selection")
	blueprint.mouse_exited.emit()
	check(store.slot == 0 and blueprint.hovered == -1,"leaving the blueprint restores the selected slot")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = blueprint.mount_point(2)
	blueprint._gui_input(click)
	check(game.dock_view.slot_index == 2 and game.dock_view.blueprint.active == 2,"click selects the visible mount and its fire group")
	await process_frame
	blueprint = game.dock_view.blueprint
	click.position = blueprint.mount_point(0)
	blueprint._gui_input(click)
	store = game.body.find_child("WeaponChoices",true,false).get_parent()
	check(store.comparison.get_child_count() == 21,"compare both guns on six metrics")
	store.choices.select(store.ids.find(""))
	store.choices.item_selected.emit(store.choices.selected)
	store.install.pressed.emit()
	check(vessel.fit.weapons[0] == "" and world.active().wallet == wallet-quote.net,"UI trades in gun at quoted price")
	check(Hulls.fitting_cost(vessel.kind,vessel.fit) == quote.used_op,"quote OP matches installed loadout")
	request.weapon = old
	var stock: Array = port.stock
	var ware := Economy.Industry.Ware.ORDNANCE
	var available: int = stock[ware]
	var buy: Dictionary = api.dispatch("refit_quote",request).result
	check(buy.ok and buy.free_op == Hulls.COMBAT[vessel.kind].op-buy.used_op,"reverse quote")
	stock[ware] = 0
	store = game.body.find_child("WeaponChoices",true,false).get_parent()
	store.choices.select(store.ids.find(old))
	store.choices.item_selected.emit(store.choices.selected)
	world.market_updated.emit(port.id,ware,false)
	check(store.install.disabled,"open refit screen reflects depleted stock")
	stock[ware] = available
	world.market_updated.emit(port.id,ware,false)
	check(not store.install.disabled and store.ids[store.choices.selected] == old,"restock enables the current offer in place")
	stock[ware] = 0
	wallet = world.active().wallet
	check(not api.dispatch("refit_quote",request).result.ok and not api.dispatch("refit_slot",request).ok,"stale quote rechecks public stock before payment")
	check(vessel.fit.weapons[0] == "" and world.active().wallet == wallet and stock[ware] == 0,"rejected purchase is atomic")
	request.black = true
	var black_quote: Dictionary = api.dispatch("refit_quote",request).result
	var suspicion := int(world.active().get("suspicion",0))
	check(black_quote.ok and black_quote.net == Economy.weapon_price(old,true,true) and black_quote.net != buy.net,"black market uses its own material basis and price")
	var sold := api.dispatch("refit_slot",request)
	check(sold.ok and sold.result.free_op == black_quote.free_op and wallet-world.active().wallet == black_quote.net,"black market settles matching quote")
	check(stock[ware] == 0 and world.active().suspicion == suspicion+4,"black market bypasses public ordnance with suspicion cost")
	stock[ware] = available
	check(not Economy.refit_quote(world,port.id,0,"invalid").ok,"unknown weapon rejected")
	check(not Economy.refit_quote(world,port.id,0,"lance").ok,"incompatible size rejected")
	check(not Economy.refit_quote(world,port.id,10000,old).ok,"missing mount rejected")
	var missile := Hulls.weapon_metrics("missile")
	check(is_equal_approx(missile.sustained_dps,Hulls.WEAPONS.missile.damage*Hulls.WEAPONS.missile.ammo_per_sec) and missile.sustained_dps < missile.dps,"magazines limit long-run DPS")
	if "--capture" in OS.get_cmdline_user_args():
		game.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("starrail-refit-bench.png"))
	print("REFIT BENCH ",checks-failures,"/",checks)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
