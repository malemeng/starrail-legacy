extends VBoxContainer

var title_label: Label
var meter: ProgressBar
var details: Label
var factors: Label
var fill := StyleBoxFlat.new()

func setup(game, pass_score: int) -> void:
	var heading = game.hbox(self)
	title_label = game.title(heading,"",16,game.INK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.title(heading,"%d 分可签" % pass_score,13,game.DIM)
	meter = ProgressBar.new()
	meter.name = "ConsentMeter"
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.custom_minimum_size.y = 12
	var track := StyleBoxFlat.new()
	track.bg_color = Color("263849")
	meter.add_theme_stylebox_override("background",track)
	meter.add_theme_stylebox_override("fill",fill)
	add_child(meter)
	var threshold := ColorRect.new()
	threshold.color = Color("f2e9d6")
	threshold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_child(threshold)
	threshold.anchor_left = pass_score / meter.max_value
	threshold.anchor_right = threshold.anchor_left
	threshold.anchor_bottom = 1.0
	threshold.offset_right = 2.0
	details = game.title(self,"",14,game.INK,true)
	factors = game.title(self,"",13,game.DIM,true)

func present(preview: Dictionary) -> void:
	meter.value = preview.score
	fill.bg_color = Color("70cbaa") if preview.accepted else (Color("e4ae66") if preview.score >= 30 else Color("d47d72"))
	title_label.text = "同意度　%d / 100　%s" % [preview.score,preview.label]
	details.text = preview.reason
	var distinct := PackedStringArray()
	for factor: String in preview.get("factors",[]):
		if not factor.is_empty() and factor != details.text and factor not in distinct:
			distinct.append(factor)
	factors.text = "　·　".join(distinct)
	factors.visible = not factors.text.is_empty()
