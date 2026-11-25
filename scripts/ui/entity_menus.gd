extends RefCounted

# Only resolve names on a context click. The current world also contains people and
# places that appeared after the last UI refresh or after loading a different save.
const BINDING := &"context_entity"
var game
var origin: Window
var anchor := Vector2.ZERO
var covered_panels: Array[WeakRef] = []

func reveal_panel() -> void:
	var table = game.trade_table
	if is_instance_valid(table) and table.visible:
		covered_panels.append(weakref(table))
		table.hide()
	if is_instance_valid(origin) and origin != game.get_window() and origin.visible:
		covered_panels.append(weakref(origin))
		origin.hide()
	if game.tactics.visible: game.set_tactics(false)
	if game.side_collapsed: game.toggle_side_panel()
	game.system_chart = false

func restore_panels() -> void:
	var previous := covered_panels.duplicate()
	covered_panels.clear()
	for ref: WeakRef in previous:
		var panel = ref.get_ref()
		if is_instance_valid(panel) and panel.is_inside_tree():
			if panel is Window: panel.popup()
			else: panel.show()
	game.refresh()

class WindowInput extends Node:
	var menus
	func _input(event: InputEvent) -> void:
		var window := get_window()
		if menus.handle(window,event):
			window.set_input_as_handled()

func setup(host) -> void:
	game = host
	game.get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if node is Window and not node.has_meta("entity_popup") and game.is_ancestor_of(node):
		_attach.call_deferred(weakref(node))

func _attach(ref: WeakRef) -> void:
	var window: Window = ref.get_ref()
	if window and window.is_inside_tree() and not window.is_queued_for_deletion():
		var input := WindowInput.new()
		input.menus = self
		window.add_child(input)

static func ref_for(kind: String, id: int, system: int = -1) -> Dictionary:
	return {"kind":kind,"id":id,"system":system}

static func bind(control: Control, kind: String, id: int, system: int = -1) -> void:
	control.set_meta(BINDING,ref_for(kind,id,system))

func present(menu: PopupMenu) -> void:
	var win := origin if is_instance_valid(origin) and origin.visible else game.get_window() as Window
	menu.set_meta("entity_popup",true)
	if win == game.get_window():
		game.add_child(menu)
	else:
		win.add_child(menu)
	menu.popup_hide.connect(menu.queue_free,CONNECT_ONE_SHOT)
	menu.popup_on_parent(Rect2i(Vector2i(anchor),menu.get_contents_minimum_size()))

func handle(window: Window, event: InputEvent) -> bool:
	if not game.playing or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if window.has_meta("entity_popup"):
		return false
	origin = window
	anchor = event.position
	if window is PopupMenu:
		if not window.get_parent() is OptionButton:
			return false
		var index := option_at(window,event.position)
		if index < 0 or index >= window.item_count:
			return false
		var parent_window := window.get_parent().get_window()
		anchor = parent_window.get_screen_transform().affine_inverse() * (window.get_screen_transform() * event.position)
		origin = parent_window
		var candidates := resolve_row(window.get_item_text(index),window.get_item_metadata(index))
		if candidates.is_empty():
			return false
		window.hide()
		open_matches(candidates)
		return true
	var hovered := window.gui_get_hovered_control()
	if hovered and (hovered is LineEdit or hovered is TextEdit or hovered is ScrollBar):
		return false
	var start: Node = hovered if hovered else (game if window == game.get_window() else window)
	var control := text_at(start,event.position)
	var binding := {}
	var parent: Node = control if control else hovered
	while parent is Control:
		if parent.has_meta(BINDING):
			binding = parent.get_meta(BINDING)
			break
		parent = parent.get_parent()
	if control:
		var local: Vector2 = control.get_global_transform_with_canvas().affine_inverse() * event.position
		var matches := []
		if control.has_method("context_at"):
			var entity: Dictionary = control.context_at(local)
			if not entity.is_empty(): matches.append(entity)
		else:
			matches = control_matches(control,local,binding)
		if not matches.is_empty():
			open_matches(matches)
			return true
	if not binding.is_empty():
		open_matches([binding])
		return true
	if hovered and hovered.has_method("context_at"):
		var match_ref: Dictionary = hovered.context_at(hovered.get_global_transform_with_canvas().affine_inverse() * event.position)
		if not match_ref.is_empty():
			open_matches([match_ref])
			return true
	if window == game.get_window() and is_instance_valid(game.canvas) and game.canvas.is_visible_in_tree() and (not hovered or hovered == game.canvas or hovered.is_ancestor_of(game.canvas)):
		var canvas_ref: Dictionary = game.canvas.context_at(game.canvas.get_global_transform_with_canvas().affine_inverse()*event.position)
		if not canvas_ref.is_empty():
			open_matches([canvas_ref])
			return true
	return false

# A popup keeps keyboard focus on the selected option even when the pointer is
# on a different row. Use its scrolled content area for pointer interactions.
static func option_at(popup: PopupMenu, pos: Vector2) -> int:
	var scrollers := popup.find_children("*","ScrollContainer",true,false)
	if scrollers.is_empty() or popup.item_count == 0:
		return -1
	var viewport: ScrollContainer = scrollers[0]
	if not viewport.get_global_rect().has_point(pos) or (viewport.get_v_scroll_bar().visible and viewport.get_v_scroll_bar().get_global_rect().has_point(pos)):
		return -1
	var content: Control = viewport.get_child(0,true)
	var y := pos.y-content.get_global_rect().position.y
	var font := popup.get_theme_font("font")
	var font_size := popup.get_theme_font_size("font_size")
	var separation := popup.get_theme_constant("v_separation")
	for index in popup.item_count:
		var icon := popup.get_item_icon(index)
		var height := maxf(font.get_height(font_size),icon.get_height() if icon else 0)+separation
		if y >= 0 and y < height:
			return index
		y -= height
	return -1

# Labels normally ignore mouse input. Inspect visible descendants of the real GUI
# hit, without changing any control's mouse filter or obscuring another window.
func text_at(node: Node, pos: Vector2) -> Control:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is Control:
		var local: Vector2 = node.get_global_transform_with_canvas().affine_inverse() * pos
		var inside := Rect2(Vector2.ZERO,node.size).has_point(local)
		if node.clip_contents and not inside:
			return null
		if inside and (node is Label or node is Button or node is ItemList):
			return node
	for i in range(node.get_child_count()-1,-1,-1):
		var child := node.get_child(i)
		if child is Control:
			var found := text_at(child,pos)
			if found:
				return found
	if node is Control and node.has_method("context_at") and Rect2(Vector2.ZERO,node.size).has_point(node.get_global_transform_with_canvas().affine_inverse()*pos):
		return node
	return null

static func glyph_at(label: Label, local: Vector2) -> int:
	for i in label.text.length():
		if label.get_character_bounds(i).has_point(local):
			return i
	return -1

func control_matches(control: Control, local: Vector2, binding: Dictionary) -> Array:
	if control is ItemList:
		var row: int = control.get_item_at_position(local,true)
		return resolve_row(control.get_item_text(row),control.get_item_metadata(row)) if row >= 0 else []
	var caption: String = control.text
	if caption.is_empty():
		return []
	if control is OptionButton and control.selected >= 0:
		var row_meta: Variant = control.get_item_metadata(control.selected)
		if row_meta is Dictionary and row_meta.has(BINDING):
			binding = row_meta[BINDING]
	var spans := occurrences(caption)
	if spans.is_empty():
		return []
	var ch := -1
	if control is Label:
		ch = glyph_at(control,local)
	else:
		var distinct := targets(spans,-1,binding)
		if distinct.size() == 1:
			return distinct
		ch = button_glyph(control,local)
	return targets(spans,ch,binding) if ch >= 0 else []

# Buttons use their theme style margins, font and alignment for the text area.
func button_glyph(button: Button, local: Vector2) -> int:
	var style := button.get_theme_stylebox("normal")
	var margin := style.get_offset()
	var available := button.size-style.get_minimum_size()
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.horizontal_alignment = button.alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = button.autowrap_mode
	label.text_overrun_behavior = button.text_overrun_behavior
	label.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	label.add_theme_font_override("font",button.get_theme_font("font"))
	label.add_theme_font_size_override("font_size",button.get_theme_font_size("font_size"))
	if button.icon and button.icon_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		var occupied := button.icon.get_width()+button.get_theme_constant("h_separation")
		available.x -= occupied
		if button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT:
			margin.x += occupied
	label.text = button.text
	button.add_child(label)
	label.size = available
	var index := glyph_at(label,local-margin)
	label.free()
	return index

static func insert_spans(results: Array, caption: String, name: String, entity: Dictionary) -> void:
	if name.is_empty():
		return
	var offset := caption.find(name)
	while offset >= 0:
		results.append({"start":offset,"end":offset+name.length(),"ref":entity})
		offset = caption.find(name,offset+name.length())

func occurrences(caption: String) -> Array:
	var world = game.world
	var spans := []
	var numbered := []
	var i := 0
	while i < caption.length():
		if caption[i] == "#":
			var end := i+1
			while end < caption.length() and caption.unicode_at(end) in range(48,58):
				end += 1
			var id := caption.substr(i+1,end-i-1).to_int()
			var kind := "ship" if world.ships.has(id) else ("person" if world.people.has(id) else ("port" if world.ports.has(id) else ""))
			if not kind.is_empty():
				var number := {"start":i,"end":end,"ref":ref_for(kind,id)}
				numbered.append(number)
				spans.append(number)
			i = end
		else:
			i += 1
	for person: Dictionary in world.people.values():
		insert_spans(spans,caption,person.name,ref_for("person",person.id))
	for port: Dictionary in world.ports.values():
		insert_spans(spans,caption,port.name,ref_for("port",port.id))
	for sys in world.systems.size():
		var region: Dictionary = world.systems[sys]
		insert_spans(spans,caption,region.name,ref_for("system",sys))
		for n in region.planets.size():
			insert_spans(spans,caption,region.planets[n].name,ref_for("planet",n,sys))
	for kind in world.HULLS.size():
		insert_spans(spans,caption,world.HULLS[kind],ref_for("model",kind))
	# A model next to its registry number denotes the individual ship. Likewise
	# a printed person ID disambiguates names in rosters and diagnostic entries.
	for number: Dictionary in numbered:
		var entity: Dictionary = number.ref
		var name := str(world.HULLS[world.ships[entity.id].kind]) if entity.kind == "ship" else entity_name(entity)
		var best := 99
		var chosen := -1
		for span: Dictionary in spans:
			if caption.substr(span.start,span.end-span.start) != name:
				continue
			var near_before: bool = number.end <= span.start
			var lo: int = number.end if near_before else span.end
			var hi: int = span.start if near_before else number.start
			if hi < lo or hi-lo > 4:
				continue
			var gap := caption.substr(lo,hi-lo).strip_edges()
			if gap != "" and gap != "·":
				continue
			var score := (hi-lo)*2 + int(near_before != (entity.kind == "ship")) + (12 if gap == "·" else 0)
			if score < best:
				best = score
				chosen = span.start
		if chosen >= 0:
			for span: Dictionary in spans:
				if span.start == chosen and span.end == chosen+name.length() and (span.ref.kind == entity.kind or (span.ref.kind == "model" and entity.kind == "ship")):
					span.ref = entity
	return spans

func entity_name(ref: Dictionary) -> String:
	var world = game.world
	match ref.kind:
		"person": return world.name_of(ref.id)
		"port": return world.ports.get(ref.id,{}).get("name","")
		"system": return world.systems[ref.id].name
		"planet": return world.systems[ref.system].planets[ref.id].name
		"model": return world.HULLS[ref.id]
		"ship": return "#%d %s" % [ref.id,world.HULLS[world.ships[ref.id].kind]]
	return ""

static func targets(spans: Array, ch: int, preferred: Dictionary) -> Array:
	var out := []
	for span: Dictionary in spans:
		if ch >= 0 and (ch < span.start or ch >= span.end):
			continue
		var nested := false
		for other: Dictionary in spans:
			if other.start <= span.start and other.end >= span.end and (other.start < span.start or other.end > span.end):
				nested = true
				break
		if not nested and not span.ref in out:
			out.append(span.ref)
	if ch >= 0 and preferred in out:
		return [preferred]
	if preferred.get("kind") == "ship" and out.size() == 1 and out[0].kind == "model":
		return [preferred]
	return out

func resolve_row(caption: String, metadata: Variant) -> Array:
	if metadata is Dictionary and metadata.has(BINDING):
		return [metadata[BINDING]]
	return targets(occurrences(caption),-1,{})

func open_matches(matches: Array) -> void:
	if matches.size() > 1:
		var picker := PopupMenu.new()
		for ref: Dictionary in matches:
			var kind: String = {"person":"人物","port":"港口","system":"星系","planet":"行星","ship":"舰船","model":"船型"}[ref.kind]
			picker.add_item("%s · %s #%d" % [kind,entity_name(ref),ref.id])
		picker.index_pressed.connect(func(i): open_matches([matches[i]]))
		present(picker)
		return
	var ref: Dictionary = matches[0]
	match ref.kind:
		"person": game.hud.open_character_menu(ref.id)
		"port": game.hud.open_location_menu(ref.id)
		"system": game.hud.open_location_menu(0,ref.id)
		"planet": game.hud.open_location_menu(0,ref.system,ref.id)
		"ship": game.hud.open_ship_menu(ref.id)
		"star","companion","field","gravity","outlaw":
			var region: Dictionary = game.world.systems[ref.system]
			var label: String = {"star":region.sun.name,"companion":"伴星","field":"小行星矿带","gravity":"恒星引力点","outlaw":"据点"}[ref.kind]
			if ref.kind == "outlaw": label = game.world.Outlaws.groups[region.outlaw_base.group].base_name
			var menu := PopupMenu.new()
			menu.add_separator(label)
			menu.add_item("所属星系　"+region.name,1)
			if ref.system == game.current_system() and not game.world.ride().is_empty():
				menu.add_item("导航至"+label,2)
			menu.id_pressed.connect(func(action):
				if action == 1: game.hud.open_location_menu(0,ref.system)
				elif game.current_system() == ref.system and not game.world.ride().get("layer",true):
					game.select_chart_target({"kind":ref.kind,"name":label,"id":0})
					game.navigate_chart_target())
			present(menu)
		"model":
			var menu := PopupMenu.new()
			var model: Dictionary = game.world.Hulls.MODELS[ref.id]
			menu.add_separator(game.world.HULLS[ref.id])
			menu.add_item("船体 %d　货舱 %d" % [model.hp,game.world.HULL_CARGO[ref.id]])
			menu.set_item_disabled(1,true)
			present(menu)
