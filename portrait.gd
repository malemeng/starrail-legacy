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
		sprite = Pixels.portrait_texture(look)
		queue_redraw()

static func for_actor(world, actor: Dictionary) -> Dictionary:
	var result: Dictionary = actor.look.duplicate()
	var flag := int(actor.get("flag",-1))
	var faction: Dictionary = world.factions.get(flag,{})
	var day := int(actor.get("death_day",world.day))
	var days_old := maxi(0,day-int(actor.birth))
	var years := floori(days_old / 360.0)
	result.actor_id = int(actor.id)
	result.age_band = 2 if years >= 65 else (1 if years >= 50 else 0)
	result.stress_tier = clampi(int(actor.get("stress",0))/100,0,3)
	result.wounded = int(actor.get("injured_until",-1)) >= day
	result.low_health = float(actor.get("health",1.0)) <= 0.35 or days_old >= int(actor.get("lifespan",9999999))-360
	result.regalia = actor.get("noble",false) and faction.get("leader",0) == actor.id
	var culture := str(actor.get("culture",""))
	var house := str(actor.get("house",""))
	result.crest = (hash([culture,house]) & 63) | 1 if not culture.is_empty() or not house.is_empty() else -1
	if not faction.is_empty():
		result.uniform_style = int(faction.get("style",0))
		result.uniform = flag if flag >= 0 and flag < 8 else posmod(int(faction.get("regime",0))+2*result.uniform_style,8)
		result.uniform_color = str(faction.get("color",Pixels.COAT_TRIM[result.uniform]))
	return result

static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for key in OPTIONS:
		result[key] = rng.randi_range(0, OPTIONS[key].size() - 1)
	return result

static func random_look_for_gender(rng: RandomNumberGenerator, gender: int) -> Dictionary:
	var result := random_look(rng)
	if gender == 1:
		result.face = [0, 2, 3][rng.randi_range(0, 2)]
		result.cut = [1, 2, 4, 2, 4][rng.randi_range(0, 4)]
		result.mouth = [1, 2, 2][rng.randi_range(0, 2)]
	else:
		result.face = [0, 1, 2][rng.randi_range(0, 2)]
		result.cut = [0, 1, 3, 5, 0][rng.randi_range(0, 4)]
		result.mouth = [0, 1][rng.randi_range(0, 1)]
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
		sprite = Pixels.portrait_texture(look)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("142232"))
	if sprite != null:
		var source_size := sprite.get_size()
		var factor := minf(size.x / source_size.x, size.y / source_size.y)
		var dimensions := source_size * factor
		draw_texture_rect(sprite, Rect2(((size - dimensions) * 0.5).floor(), dimensions), false)
