extends RefCounted

const Industry = preload("res://scripts/economy/industry.gd")
const Art = preload("res://presentation.gd")
const SHEET = preload("res://scripts/ui/icons/cargo_atlas.png")
const CELLS := ["ore","alloy","fuel","food_med","hull_parts","water","luxury","silicon","ice","gas_h2","energy","wafer","electronics","ordnance","engine_parts","scrap","cash","company_share","station_share","treaty"]
static var cache := {}

static func texture(kind: String, id: int = 0) -> AtlasTexture:
	var item: String = Industry.RULES.wares[id].id if kind == "ware" and id >= 0 and id < Industry.WARES.size() else kind
	if cache.has(item):
		return cache[item]
	var slot := CELLS.find(item)
	if slot < 0:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = SHEET
	icon.region = Rect2((slot % 4)*32,(slot / 4)*32,32,32)
	icon.filter_clip = true
	cache[item] = icon
	return icon

static func show_icon(parent: Control, kind: String, id: int, pixels: int) -> TextureRect:
	var image := Art.contained(parent,texture(kind,id),Vector2(pixels,pixels))
	image.name = "CargoIcon%d" % id
	image.set_meta("asset_kind",kind)
	image.set_meta("asset_id",id)
	return image
