extends Node2D

const Hulls = preload("res://hull_catalog.gd")
const Pixels = preload("res://art/pixel_art.gd")
const Surface = preload("res://scripts/battle/wreck_hull.gdshader")
const Fire = preload("res://scripts/battle/wreck_fire.gdshader")
const COOL_TIME := 3.4

var age := COOL_TIME
var bounds: Rect2
var texture: Texture2D
var fire: Node2D
var directions := PackedVector2Array()
var size_factor: float
var variant: float

func configure(record: Dictionary, kind: int, burning: bool) -> void:
	var model: Dictionary = Hulls.MODELS[kind]
	texture = Pixels.ship_texture(kind,Color(model.paint).lerp(record.tint,0.38))
	var extent := texture.get_size()*float(model.sprite_scale)
	var top_left := -Vector2(model.sprite_center)*float(model.sprite_scale)
	bounds = Rect2(top_left-extent*0.2,extent*1.4)
	position = record.pos
	rotation = record.heading
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	age = 0.0 if burning else COOL_TIME
	variant = float(posmod(hash(record.source_id),997))/997.0
	var surface := ShaderMaterial.new()
	surface.shader = Surface
	surface.set_shader_parameter("hull_art",texture)
	surface.set_shader_parameter("aspect",extent.x/extent.y)
	surface.set_shader_parameter("variant",variant)
	surface.set_shader_parameter("age",age)
	material = surface
	if burning:
		size_factor = clampf(maxf(extent.x,extent.y)*0.50,13.0,108.0)
		fire = Node2D.new()
		add_child(fire)
		var cloud := ShaderMaterial.new()
		cloud.shader = Fire
		cloud.set_shader_parameter("variant",variant)
		fire.material = cloud
		fire.draw.connect(func(): fire.draw_texture_rect(texture,Rect2(-Vector2.ONE*size_factor,Vector2.ONE*size_factor*2.0),false))
		var sparks := Node2D.new()
		fire.add_child(sparks)
		var rng := RandomNumberGenerator.new()
		rng.seed = record.source_id
		for i in 10+int(model.size)*3:
			directions.append(Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(0.36,1.1))
		sparks.draw.connect(draw_sparks.bind(sparks))
	queue_redraw()

func draw_sparks(canvas: Node2D) -> void:
	for i in directions.size():
		var t := age-float(i%3)*0.14
		if t < 0.0 or t >= 1.55: continue
		var dir := directions[i]
		var origin := Vector2((float(i%3)-1.0)*0.25*size_factor,0)
		var tip := origin+dir*size_factor*(1.0-exp(-t*1.7))*1.2
		var fade := 1.0-smoothstep(0.15,1.55,t)
		var tail := dir*maxf(1.0,size_factor*0.14)*fade
		canvas.draw_line(tip-tail,tip,Color(0.91,0.42,0.15,fade*0.8),1.4,true)
		canvas.draw_circle(tip,0.9,Color(1.0,0.88,0.60,fade))

func advance(delta: float) -> void:
	if age >= COOL_TIME: return
	age = minf(COOL_TIME,age+delta)
	material.set_shader_parameter("age",age)
	if is_instance_valid(fire):
		if age >= 2.04:
			fire.hide()
			fire.queue_free()
			fire = null
		else:
			fire.material.set_shader_parameter("age",age)
			fire.get_child(0).queue_redraw()

func _draw() -> void:
	if texture: draw_texture_rect(texture,bounds,false)
