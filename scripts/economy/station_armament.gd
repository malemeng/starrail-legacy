extends RefCounted

const Hulls = preload("res://hull_catalog.gd")
const Economy = preload("res://economy.gd")
const Industry = preload("res://scripts/economy/industry.gd")
const Mounts = preload("res://data/economy/station_mounts.json")
const Art = preload("res://scripts/ui/station_art.gd")
const MODULE_KEYS := ["mine","refinery","yard","defense","habitat","solar","chemical","electronics","components","recycler"]
static var outlines: Dictionary = {}

## Use ship fitting profiles so mount families, weapon IDs, magazines and OP retain
## their normal meanings. Module indices follow the station designer: core, then build order.
static func profile(site: Dictionary, index: int) -> int:
	if index == 0:
		return Hulls.kind_for_reference("astral")
	match int(site.modules[index - 1]):
		Industry.Module.DEFENSE: return Hulls.kind_for_reference("mora")
		Industry.Module.YARD: return Hulls.kind_for_reference("heron")
		Industry.Module.SOLAR, Industry.Module.ELECTRONICS, Industry.Module.CHEMICAL: return Hulls.kind_for_reference("sunder")
	return Hulls.kind_for_reference("enforcer")

## Bearings are authored on opaque deck pixels of each 80×80 module sprite.
## The renderer, turret training and projectile creation share these exact offsets.
static func mount_offsets(part: Dictionary) -> PackedVector2Array:
	var key: String = "core" if int(part.kind) < 0 else MODULE_KEYS[int(part.kind)]
	var points := PackedVector2Array()
	for pixel in Mounts.data[key]:
		points.append(((Vector2(pixel[0],pixel[1])+Vector2(0.5,0.5))/80.0-Vector2(0.5,0.5))*Vector2(part.size))
	return points

static func module_outline(part: Dictionary) -> PackedVector2Array:
	if not outlines.has(part.kind):
		var mask := Art.module_image(part.kind,Color.WHITE)
		var vertices := PackedVector2Array()
		for y in mask.get_height():
			var left := mask.get_width()
			var right := -1
			for x in mask.get_width():
				if mask.get_pixel(x,y).a >= 0.5:
					left = mini(left,x)
					right = x
			if right >= 0:
				for edge in [left,right+1]:
					for height in [y,y+1]:
						vertices.append(Vector2(edge,height)/Vector2(mask.get_size())-Vector2(0.5,0.5))
		var hull := Geometry2D.convex_hull(vertices)
		hull.remove_at(hull.size()-1)
		outlines[part.kind] = hull
	return Transform2D(0.0,part.size,0.0,Vector2.ZERO) * PackedVector2Array(outlines[part.kind])

static func label(world, site: Dictionary, index: int) -> String:
	return "指挥核心" if index == 0 else "%d号%s" % [index,world.MODULES[site.modules[index-1]]]

static func fitting(site: Dictionary, index: int) -> Hulls.Fitting:
	var kind := profile(site,index)
	var fit := Hulls.stock_fitting(kind)
	if index == 0:
		fit.wings.assign(["thunder_wing","thunder_wing","wasp_wing","wasp_wing","claw_wing","dagger_wing"])
	elif site.modules[index-1] == Industry.Module.YARD:
		fit.wings.assign(["broadsword_wing","talon_wing","dagger_wing"])
	elif site.modules[index-1] == Industry.Module.DEFENSE:
		fit.wings.assign(["talon_wing","wasp_wing","broadsword_wing"])
	var weapons: Dictionary = site.get("module_armaments",{}).get(index,{})
	for slot in fit.weapons.size():
		var id: String = Hulls.slot_spec(kind,slot).id
		if weapons.get(id) is String and Hulls.weapon_compatible(kind,slot,weapons[id]):
			fit.weapons[slot] = weapons[id]
	return fit if Hulls.fitting_cost(kind,fit) >= 0 else Hulls.stock_fitting(kind)

static func valid_module(site: Dictionary, index: int) -> bool:
	return not site.is_empty() and not site.get("landing_only",false) and site.build == 0 and index >= 0 and index <= site.modules.size()

static func inspect(world, site: Dictionary, index: int = -1, slot: int = -1) -> Dictionary:
	if not valid_module(site,0):
		return {"ok":false,"reason":"本站尚无可用的模块武备。"}
	var info := {"ok":true,"port":site.id,"modules":[]}
	for i in site.modules.size()+1:
		var k := profile(site,i)
		var fit := fitting(site,i)
		var aircraft := 0
		for id in fit.wings:
			aircraft += int(Hulls.wing_spec(id).count)
		info.modules.append({"module":i,"name":label(world,site,i),"shield":Hulls.capacity({"kind":k,"fit":fit}),"slots":fit.weapons.size(),"wings":fit.wings.duplicate(),"aircraft":aircraft})
	if index == -1:
		return info
	if not valid_module(site,index):
		return {"ok":false,"reason":"无此已建成模块。"}
	var kind := profile(site,index)
	var fit := fitting(site,index)
	info.module = index
	info.mounts = []
	info.op = Hulls.COMBAT[kind].op
	info.used_op = Hulls.fitting_cost(kind,fit)
	for i in fit.weapons.size():
		var mount := Hulls.slot_spec(kind,i)
		info.mounts.append({"slot":i,"id":mount.id,"family":mount.family,"size":mount.size,"builtin":mount.builtin,"weapon":fit.weapons[i]})
	if slot >= 0 and slot < fit.weapons.size():
		info.offers = Economy.station_weapons(world,site).filter(func(key): return Hulls.weapon_compatible(kind,slot,key))
		if not Hulls.slot_spec(kind,slot).builtin and fit.weapons[slot] != "":
			info.offers.append("")
	return info

static func quote(world, site: Dictionary, index: int, slot: int, weapon: String) -> Dictionary:
	if not valid_module(site,index) or not world.Dividends.can_manage(world,site) or world.active().loc != site.id:
		return {"ok":false,"reason":"须在所管理的空间站内进行换装。"}
	if site.has("assault"):
		return {"ok":false,"reason":"交战期间不能更换模块武器。"}
	return Economy.weapon_refit_quote(world,site,profile(site,index),fitting(site,index),slot,weapon,false,int(world.active().wallet))

static func refit(world, site: Dictionary, index: int, slot: int, weapon: String, expected: Variant = null) -> Dictionary:
	var offer := quote(world,site,index,slot,weapon)
	if not offer.ok:
		return offer
	if expected != null and expected != offer.current:
		return {"ok":false,"reason":"原武器已变更，请重新查看挂点。"}
	if weapon != "" and not Industry.consume(site,Economy.weapon_materials(weapon)):
		return {"ok":false,"reason":"本站制造材料不足。"}
	world.credit(world.player,-int(offer.net))
	world.Treasury.post(world,site,int(offer.net),"站防模块换装")
	var fit: Dictionary = site.get_or_add("module_armaments",{}).get_or_add(index,{})
	fit[Hulls.slot_spec(profile(site,index),slot).id] = weapon
	return {"ok":true,"port":site.id,"module":index,"slot":slot,"weapon":weapon,"net":offer.net}
