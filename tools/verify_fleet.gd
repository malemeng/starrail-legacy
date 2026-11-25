extends SceneTree

const Hulls = preload("res://hull_catalog.gd")
const Pixels = preload("res://art/pixel_art.gd")
const CampaignPanel = preload("res://scripts/ui/campaign_panel.gd")
var failures := 0
var checks := 0

class ArchiveUI extends RefCounted:
	var DIM := Color.GRAY
	var INK := Color.WHITE

	func choice(parent: Control, options: Array, selected: int) -> OptionButton:
		var field := OptionButton.new()
		parent.add_child(field)
		for label in options:
			field.add_item(label)
		field.select(selected)
		return field

	func title(parent: Control, value: String, _font_size: int, _ink: Color, _wrap := false) -> Label:
		var label := Label.new()
		label.text = value
		parent.add_child(label)
		return label

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(note)

func _initialize() -> void:
	var manifest := Hulls.manifest()
	var expected := {"hulls":200,"skins":66,"wings":31,"variants":447}
	for key in expected:
		check(manifest.get(key,[]).size() == expected[key], "reference count for "+key)
		for item in manifest.get(key, []):
			check(not str(item.project_id).is_empty(),"missing original entity for "+str(item.id))
	var anchors := ["kite","buffalo","wolf","shepherd","crig","dominator","venture","onslaught","atlas"]
	var silhouettes: Dictionary = {}
	var fits := 0
	for kind in range(Hulls.MODELS.size()):
		var model := Hulls.hull_spec(kind)
		var ref: String = model.reference
		check(Hulls.kind_for_id(model.id) == kind and Hulls.kind_for_reference(ref) == kind, "id roundtrip: "+ref)
		if kind < anchors.size():
			check(ref == anchors[kind], "starter order: "+ref)
		check(not Geometry2D.triangulate_polygon(model.bounds).is_empty(),"invalid collision polygon "+ref)
		for slot in model.mounts:
			check(Geometry2D.is_point_in_polygon(slot.offset, model.bounds), "misplaced mount "+ref+"/"+slot.id)
		check(Hulls.fitting_cost(kind,Hulls.stock_fit(kind)) >= 0, "illegal stock fit "+ref)
		for preset in Hulls.presets(kind):
			var fit := Hulls.preset_fit(kind,preset.reference_path)
			check(Hulls.fitting_cost(kind,fit) >= 0,"illegal preset "+preset.reference_path)
			fits += 1
		if not model.has("provider"):
			var sprite := Pixels.hull(kind,Color.WHITE)
			check(sprite.get_size() == model.sprite_size and sprite.get_pixel(0,0).a == 0.0, "sprite bounds "+ref)
			var silhouette := BitMap.new()
			silhouette.create_from_image_alpha(sprite)
			var signature := hash(silhouette.convert_to_image().get_data())
			check(not silhouettes.has(signature), "identical silhouette: "+ref+" and "+str(silhouettes.get(signature,"")))
			silhouettes[signature] = ref
	check(fits == 350,"expected 350 standalone ship loadout records")
	if "--sample" in OS.get_cmdline_user_args():
		var kind := Hulls.kind_for_id("waypost.dispatch")
		check(kind >= 175 and Hulls.available_for_market(kind),"external ship appears in the ordinary registry and market")
		check(Hulls.mod_events().size() == 2,"both sample events registered")
		if kind >= 0:
			check(Hulls.hull_spec(kind).cargo == 52 and Hulls.fitting_cost(kind,Hulls.stock_fit(kind)) >= 0,"external balance and stock loadout")
	var pane := VBoxContainer.new()
	var archive := CampaignPanel.new()
	archive.game = ArchiveUI.new()
	archive.index(pane)
	var query := pane.get_child(1) as LineEdit
	var list := pane.get_child(3) as ItemList
	var details := pane.get_child(4) as Label
	check(list.item_count == 744,"archive total across hulls, skins, fittings and wings")
	for search in ["Dominator", "戍星", "warden_ca"]:
		query.text_changed.emit(search)
		check(list.item_count > 0 and details.text.contains("战场长度"),"archive bidirectional lookup "+search)
	query.text_changed.emit("broadsword_wing")
	check(details.text.contains("联队") and details.text.contains("机体"),"fighter archive detail")
	query.text_changed.emit("module_bastion_pd1")
	check(details.text.contains("附属模块"),"station module isn't presented as a playable ship")
	pane.free()
	print("Fleet checks: %d; failures: %d; ship designs: %d; deployable presets: %d" % [checks, failures,Hulls.MODELS.size(),fits])
	quit(1 if failures else 0)
