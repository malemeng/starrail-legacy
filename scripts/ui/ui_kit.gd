extends RefCounted

const CYAN := Color("63d2e4")
const GOLD := Color("e9b977")
const INK := Color("dce5e8")
const DIM := Color("849daf")
const OK := Color("5cd69a")
const WARN := Color("eab308")
const DANGER := Color("ef6461")

const CARD_BG := Color(0.0588, 0.1059, 0.1686, 0.92)
const CARD_BORDER := Color(0.1804, 0.3059, 0.4157, 0.85)
const SUBCARD_BG := Color(0.0392, 0.0745, 0.1255, 0.90)

## Persistent UI state across panel refreshes (scroll positions, fold states, choice selections).
static var folded: Dictionary = {}
static var choices: Dictionary = {}
static var scroll_pos: Dictionary = {}

static func tone_color(tone: String) -> Color:
	match tone:
		"gold": return GOLD
		"ok", "green": return OK
		"warn", "amber": return WARN
		"danger", "red": return DANGER
		"dim": return DIM
		_: return CYAN

static func _card_style(accent: Color = Color.TRANSPARENT, bg: Color = CARD_BG) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = accent if accent.a > 0.0 else CARD_BORDER
	box.border_width_left = 3 if accent.a > 0.0 else 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.content_margin_left = 12.0
	box.content_margin_top = 9.0
	box.content_margin_right = 12.0
	box.content_margin_bottom = 9.0
	box.corner_radius_top_left = 7
	box.corner_radius_top_right = 7
	box.corner_radius_bottom_right = 7
	box.corner_radius_bottom_left = 7
	return box

## Glassmorphic card container with optional left accent stripe.
static func card(parent: Node, accent: Color = Color.TRANSPARENT, sub: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _card_style(accent, SUBCARD_BG if sub else CARD_BG))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box

## Collapsible accordion section that remembers its open/closed state by key.
static func section(parent: Node, key: String, title_text: String, badge_text: String = "", default_open: bool = true) -> VBoxContainer:
	var is_open: bool = folded.get(key, default_open)
	var wrap := card(parent, CYAN if is_open else Color.TRANSPARENT)
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(header)
	var toggle := Button.new()
	toggle.flat = true
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = ("%s  %s" % ["▾" if is_open else "▸", title_text])
	toggle.add_theme_color_override("font_color", GOLD if is_open else INK)
	toggle.add_theme_font_size_override("font_size", 15)
	header.add_child(toggle)
	if not badge_text.is_empty():
		badge(header, badge_text, "info" if is_open else "dim")
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	content.visible = is_open
	wrap.add_child(content)
	toggle.pressed.connect(func():
		var next := not content.visible
		folded[key] = next
		content.visible = next
		toggle.text = ("%s  %s" % ["▾" if next else "▸", title_text])
		toggle.add_theme_color_override("font_color", GOLD if next else INK))
	return content

## Semantic pill badge.
static func badge(parent: Node, text: String, tone: String = "info") -> Label:
	var col := tone_color(tone)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(col.r, col.g, col.b, 0.16)
	box.border_color = Color(col.r, col.g, col.b, 0.55)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.content_margin_left = 7.0
	box.content_margin_top = 2.0
	box.content_margin_right = 7.0
	box.content_margin_bottom = 2.0
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 4
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_stylebox_override("normal", box)
	parent.add_child(lbl)
	return lbl

## Aligned 2- or 3-column key-value grid for stats and telemetry.
static func kv_grid(parent: Node, pairs: Array, columns: int = 2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for entry in pairs:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var k := Label.new()
		k.text = str(entry[0])
		k.add_theme_font_size_override("font_size", 13)
		k.add_theme_color_override("font_color", DIM)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(k)
		var v := Label.new()
		v.text = str(entry[1])
		v.add_theme_font_size_override("font_size", 13)
		v.add_theme_color_override("font_color", tone_color(str(entry[2])) if entry.size() > 2 else INK)
		cell.add_child(v)
	return grid

## Compact progress meter with inline label and value readout.
static func meter(parent: Node, label_text: String, value: float, max_value: float, tone: String = "info", suffix: String = "") -> ProgressBar:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 58
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", DIM)
	row.add_child(lbl)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(1.0, max_value)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = tone_color(tone)
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_right = 4
	fill.corner_radius_bottom_left = 4
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var val := Label.new()
	val.text = suffix if not suffix.is_empty() else ("%d / %d" % [roundi(value), roundi(max_value)])
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", INK)
	row.add_child(val)
	return bar

static func _variant_style(variant: String, hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	var border := CYAN
	var bg := Color(0.086, 0.184, 0.267, 0.96)
	match variant:
		"primary":
			border = GOLD if not hover else Color("ffd38f")
			bg = Color(0.188, 0.153, 0.082, 0.95) if not hover else Color(0.255, 0.204, 0.106, 1.0)
		"danger":
			border = DANGER if not hover else Color("ff8c89")
			bg = Color(0.216, 0.075, 0.082, 0.95) if not hover else Color(0.302, 0.098, 0.110, 1.0)
		"ghost":
			border = Color(0.165, 0.282, 0.380, 0.6) if not hover else CYAN
			bg = Color(0.039, 0.074, 0.125, 0.55) if not hover else Color(0.086, 0.169, 0.251, 0.85)
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.content_margin_left = 12.0
	box.content_margin_top = 6.0
	box.content_margin_right = 12.0
	box.content_margin_bottom = 6.0
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_right = 6
	box.corner_radius_bottom_left = 6
	return box

## Action button with semantic variant and automatic disabled_reason tooltip.
static func action_button(parent: Node, caption: String, action: Callable, variant: String = "default", enabled: bool = true, disabled_reason: String = "", expanded: bool = false) -> Button:
	var btn := Button.new()
	btn.text = caption
	btn.disabled = not enabled
	if expanded:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variant in ["primary", "danger", "ghost"]:
		btn.add_theme_stylebox_override("normal", _variant_style(variant, false))
		btn.add_theme_stylebox_override("hover", _variant_style(variant, true))
		if variant == "primary":
			btn.add_theme_color_override("font_color", GOLD)
		elif variant == "danger":
			btn.add_theme_color_override("font_color", Color("ffb3b0"))
	if not enabled and not disabled_reason.is_empty():
		btn.tooltip_text = "不可用：" + disabled_reason
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn

## Persistent OptionButton that remembers selection index across refreshes.
static func remembered_choice(parent: Node, key: String, items: Array, default_idx: int = 0) -> OptionButton:
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(str(item))
	var saved := int(choices.get(key, default_idx))
	if items.size() > 0:
		opt.select(clampi(saved, 0, items.size() - 1))
	opt.item_selected.connect(func(idx: int): choices[key] = idx)
	parent.add_child(opt)
	return opt
