extends Control

const Hulls = preload("res://hull_catalog.gd")
const WingVisuals = preload("res://scripts/battle/wing_visuals.gd")

const ROLE_LABELS := {
	"fighter": "制空联队",
	"bomber": "轰炸联队",
	"interceptor": "截击联队",
	"support": "支援联队",
}

const ROLE_COLORS := {
	"fighter": Color("63d2e4"),
	"bomber": Color("e9b977"),
	"interceptor": Color("5cd69a"),
	"support": Color("baa1ff"),
}

var wing_spec_data: Dictionary = {}

func configure(wing_id: String) -> void:
	wing_spec_data = Hulls.wing_spec(wing_id)
	custom_minimum_size = Vector2(0, 108)
	queue_redraw()

func _draw() -> void:
	if wing_spec_data.is_empty() or minf(size.x, size.y) <= 24.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0d1d29"))
	var gap := 18.0
	var x := fposmod(size.x * 0.5, gap)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("#182f3e"))
		x += gap
	var y := fposmod(size.y * 0.5, gap)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#182f3e"))
		y += gap
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("#264557"), false, 1.0)

	var role := str(wing_spec_data.get("role", "fighter"))
	var tone: Color = ROLE_COLORS.get(role, Color("63d2e4"))
	var count := int(wing_spec_data.get("count", 1))
	var scale_factor := clampf(minf(size.x, size.y) / 48.0, 1.35, 2.4)
	var center := Vector2(size.x * 0.62, size.y * 0.52)
	var pseudo_wing := {
		"pos": Vector2.ZERO,
		"role": role,
		"count": count,
		"heading": 0.0,
	}
	WingVisuals.formation(pseudo_wing, 0.0, tone, func(a: Vector2, b: Vector2, width: float, col: Color):
		draw_line(center + a * scale_factor, center + b * scale_factor, col, maxf(1.6, width * 1.15), true))

	var font := get_theme_default_font()
	var label: String = ROLE_LABELS.get(role, "舰载联队")
	draw_string(font, Vector2(9, 18), "%s · %d 架编队" % [label, count], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tone)
	var airframe := str(wing_spec_data.get("airframe", ""))
	if not airframe.is_empty():
		draw_string(font, Vector2(9, size.y - 7), airframe, HORIZONTAL_ALIGNMENT_LEFT, size.x - 18.0, 11, Color("#8ca7b3"))
