extends Control

const Pixels = preload("res://art/pixel_art.gd")
const OPTIONS := {
	"face": ["椭圆", "方颌", "窄长", "圆润"],
	"skin": ["浅瓷", "暖杏", "橄榄", "棕褐", "深棕"],
	"cut": ["短发", "侧分", "齐肩", "寸头", "长辫", "无发"],
	"hair": ["墨黑", "深栗", "铜红", "银灰", "金棕", "蓝灰"],
	"eyes": ["平直", "细长", "圆眼", "上挑"],
	"iris": ["灰蓝", "褐色", "青绿", "琥珀", "深灰"],
	"nose": ["短鼻", "直鼻", "宽鼻"],
	"mouth": ["薄唇", "平唇", "丰满"],
	"wear": ["飞行夹克", "商团制服", "舰桥礼服", "工装"],
	"mark": ["无", "眉上疤痕", "颧侧义体", "雀斑"],
}
const GENES := ["face", "skin", "cut", "hair", "eyes", "iris", "nose", "mouth"]

var sprite: Texture2D
var look: Dictionary = {}:
	set(value):
		look = value
		sprite = ImageTexture.create_from_image(Pixels.portrait(look))
		queue_redraw()

static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for key in OPTIONS:
		result[key] = rng.randi_range(0, OPTIONS[key].size() - 1)
	return result

static func inherit(first: Dictionary, second: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result := {"wear": 3, "mark": 0}
	for key in GENES:
		var parent := first if rng.randf() < 0.5 else second
		result[key] = int(parent.get(key, 0))
		if rng.randf() < 0.035:
			var count: int = OPTIONS[key].size()
			result[key] = (result[key] + (1 if rng.randf() < 0.5 else count - 1)) % count
	return result

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite == null:
		sprite = ImageTexture.create_from_image(Pixels.portrait(look))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("142232"))
	var factor := minf(size.x / 64.0, size.y / 72.0)
	var dimensions := Vector2(64, 72) * factor
	if sprite != null:
		draw_texture_rect(sprite, Rect2(((size - dimensions) * 0.5).floor(), dimensions), false)
