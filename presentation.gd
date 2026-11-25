extends RefCounted

const Pixels = preload("res://art/pixel_art.gd")
const Hulls = preload("res://hull_catalog.gd")
const SHIP_TEXT := [
	"短轴轻艇。老式翼形散热片很好修，舱位有限，但适合独立飞行员摸清一条新航线。",
	"箱式散货船。宽腹货架适合装矿石和整箱合金；发动机推得动满载的货，却追不上轻快的船。",
	"双叉护卫舰。装甲保护主机和炮座，更适合给货船护航，或者亲自闯过一条被封锁的航道。",
	"前伸式破岩钳挖得比轻艇快；别指望它载满矿石时还能甩掉追兵。",
	"双臂能切开普通飞船捞不到的残骸结构，适合一次多跑几个回收点。",
	"前甲与炮座可以承受长时间对射。更重的船体吃油，也更挑泊位。",
	"采掘梁和传送带都塞进腹舱，能吃下一整片富矿，不必来回卸货。",
	"硬面装甲背后是两组重炮；修理、补给和找到可停靠的船坞都要提前安排。",
	"把多艘小货船才能运完的货装进同一艘船。需要主力舰船坞，单舰火力不适合打硬仗。",
]
const PORT_TEXT := [
	"吊臂把碎岩从一艘艘满载的货船里掏出来。码头上的人只关心你能运走多少。",
	"熔炉震得地板发颤。管道里的金属嘶嘶作响，空气里有一股烧热的铁和润滑油味。",
	"远处传来船体铆接的沉响。比起一艘漂亮的新船，老船长们更在乎下次能不能把它修好。",
	"泊位灯在瞭望窗上投下一道红线。每艘船靠港前都要先报识别码。",
]

static func ship(model: int) -> Texture2D:
	return Pixels.ship_texture(model, Color(Hulls.MODELS[model].paint))

static func hull_description(model: int) -> String:
	if model < SHIP_TEXT.size():
		return SHIP_TEXT[model]
	var spec: Dictionary = Hulls.MODELS[model]
	return "%s。最低船员 %d，采掘 %d，推进倍率 %.2f。" % [spec.role,Hulls.crew_limits(model).x,spec.mine,spec.speed]

static func face(look: Dictionary) -> Texture2D:
	return Pixels.portrait_texture(look)

static func fill(texture: Texture2D, target: Control) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return picture

static func contained(parent: Control, texture: Texture2D, dimensions: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.custom_minimum_size = dimensions
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture

static func fade(target: Control, from: Color, to: Color, vertical: bool = false) -> void:
	var shades := Gradient.new()
	shades.colors = PackedColorArray([from, to])
	var gradient := GradientTexture2D.new()
	gradient.gradient = shades
	gradient.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var picture := TextureRect.new()
	picture.texture = gradient
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
