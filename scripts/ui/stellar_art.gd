extends RefCounted

const Celestial = preload("res://celestial.gd")
const SKY_SIZE := Vector2i(256, 144)
const Surface = preload("res://scripts/ui/stellar_surface.gdshader")


var last_seed := -1
var background: Texture2D
var terrain: ImageTexture

func sky(region: Dictionary) -> Texture2D:
	var seed_value: int = region.get("sky_seed", hash(region.name))
	if last_seed == seed_value and background != null:
		return background
	last_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var profile := Celestial.profile(region)
	var shade := Color(profile.sky[0])
	var cloud := Color(profile.sky[1])
	var highlight := Color(profile.sky[2])
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = rng.randf_range(0.014,0.027)
	noise.fractal_octaves = 4
	var grains := noise.get_image(SKY_SIZE.x,SKY_SIZE.y,false,false,false).get_data()
	var axis := Vector2.from_angle(rng.randf_range(0, TAU))
	var center := Vector2(rng.randf_range(68,190),rng.randf_range(30,113))
	var radius := rng.randf_range(36,76)
	var palette := PackedColorArray()
	for i in range(64):
		var k := i / 63.0
		palette.append(shade.lerp(cloud, k * 1.28) if k < 0.72 else cloud.lerp(highlight, (k-0.72)*1.95))
	var img := Image.create(SKY_SIZE.x, SKY_SIZE.y, false, Image.FORMAT_RGB8)
	var shape: String = profile.shape
	for y in range(SKY_SIZE.y):
		for x in range(SKY_SIZE.x):
			var grain := grains[y*SKY_SIZE.x+x] / 255.0
			var delta := Vector2(x,y) - center
			var band := absf(delta.dot(axis) + (grain-0.5)*50.0)
			var density := grain * 0.32
			match shape:
				"lane": density += maxf(0,1.0-band/47.0) * (grain+0.24)
				"shell": density += maxf(0,1.0-absf(delta.length()-radius+(grain-0.5)*50.0)/28.0) * (grain+0.22)
				"rift": density += maxf(0,1.0-absf(band-19)/26) * (grain+0.28)
				"cloud": density += maxf(0,0.98-delta.length()/172.0) * grain * 1.82
				_: density *= 0.75
			img.set_pixel(x,y,palette[clampi(roundi(density*63),0,63)])
	var cluster := Vector2(rng.randf_range(0,SKY_SIZE.x),rng.randf_range(0,SKY_SIZE.y))
	for i in range(rng.randi_range(260,460)):
		var p := Vector2i(rng.randi_range(1,SKY_SIZE.x-2),rng.randi_range(1,SKY_SIZE.y-2))
		if i % 4 == 0:
			p = Vector2i(cluster + Vector2(rng.randfn(0,23),rng.randfn(0,12)))
			if p.x < 1 or p.y < 1 or p.x >= SKY_SIZE.x-1 or p.y >= SKY_SIZE.y-1:
				continue
		var light := Color("f5dec1") if i%7 == 0 else Color("c6e4f1")
		img.set_pixelv(p,img.get_pixelv(p).lerp(light, rng.randf_range(0.19,0.9)))
		if i%67 == 0:
			for ray: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.RIGHT,Vector2i.LEFT]:
				img.set_pixelv(p+ray,img.get_pixelv(p+ray).lerp(light,0.27))
	background = ImageTexture.create_from_image(img)
	return background

func material_for(body: Dictionary, star: bool) -> ShaderMaterial:
	if terrain == null:
		var source := FastNoiseLite.new()
		source.seed = 4932
		source.frequency = 0.042
		source.fractal_octaves = 4
		terrain = ImageTexture.create_from_image(source.get_seamless_image(256,256))
	var rng := RandomNumberGenerator.new()
	rng.seed = body.get("surface_seed",hash([body.pos,body.type]))
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.set_shader_parameter("terrain",terrain)
	material.set_shader_parameter("hue",Color(Celestial.STARS[body.type][1] if star else Celestial.PLANETS[body.type][1]))
	var kind := 0 if star else (2 if body.type >= 20 else (3 if body.type in [3,4,16,17] else 1))
	material.set_shader_parameter("kind",kind)
	material.set_shader_parameter("spin",float(body.get("spin",0.0)))
	material.set_shader_parameter("rings",not star and body.get("rings",false))
	material.set_shader_parameter("tilt",rng.randf_range(-0.6,0.6))
	material.set_shader_parameter("offset",Vector2(rng.randf_range(0,5),rng.randf_range(0,5)))
	return material
