extends Node2D

const Wreck = preload("res://scripts/battle/wreck_visual.gd")
const RESOLUTION := 1.5
var live: Array[Node2D] = []
var target: SubViewport
var printed := 0

func setup(half_size: Vector2) -> void:
	if DisplayServer.get_name() == "headless": return
	target = SubViewport.new()
	target.disable_3d = true
	target.transparent_bg = true
	target.size = Vector2i((half_size*2.0*RESOLUTION).ceil())
	add_child(target)
	target.canvas_transform = Transform2D(0.0,Vector2.ONE*RESOLUTION,0,half_size*RESOLUTION)
	var surface := Sprite2D.new()
	surface.centered = false
	surface.position = -half_size
	surface.scale = Vector2.ONE/RESOLUTION
	surface.texture = target.get_texture()
	add_child(surface)
	reset()

func reset() -> void:
	for view in live:
		remove_child(view)
		view.queue_free()
	live.clear()
	printed = 0
	if target:
		release_prints()
		target.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		target.render_target_update_mode = SubViewport.UPDATE_ONCE

func add_wreck(_id: int, record: Dictionary) -> void:
	var view := Wreck.new()
	view.configure(record,Wreck.Hulls.kind_for_id(record.hull_id),true)
	add_child(view)
	live.append(view)

func advance(delta: float) -> void:
	for i in range(live.size()-1,-1,-1):
		var view = live[i]
		view.advance(delta)
		if view.age < Wreck.COOL_TIME: continue
		live.remove_at(i)
		remove_child(view)
		printed += 1
		if not target:
			view.queue_free()
			continue
		# Stamp cooled hulls once. The whole history then costs one canvas sprite.
		target.add_child(view)
		target.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not RenderingServer.frame_post_draw.is_connected(release_prints):
			RenderingServer.frame_post_draw.connect(release_prints,CONNECT_ONE_SHOT)

func release_prints() -> void:
	for view in target.get_children():
		target.remove_child(view)
		view.queue_free()
	if target.render_target_clear_mode != SubViewport.CLEAR_MODE_ONCE:
		target.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
