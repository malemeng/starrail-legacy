extends Node2D

const Art = preload("res://art/weapon_mounts.gd")
var groups: Array[MultiMeshInstance2D] = []
var counts := PackedInt32Array()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Art.SIZE
	for family in Art.PATTERNS.size():
		var batch := MultiMeshInstance2D.new()
		batch.texture = Art.texture(family)
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		batch.multimesh.use_colors = true
		batch.multimesh.mesh = quad
		add_child(batch)
		groups.append(batch)
	counts.resize(groups.size())

func begin(capacity: int) -> void:
	counts.fill(0)
	for group in groups:
		if group.multimesh.instance_count < capacity:
			group.multimesh.instance_count = nearest_po2(maxi(capacity,8))

func add_mount(transform: Transform2D, mount: Dictionary, id: String, angle: float, recoil: float, disabled: bool) -> void:
	var style := Art.profile(id)
	var family: int = style.family
	var mesh := groups[family].multimesh
	var index := counts[family]
	# QuadMesh UVs run bottom-up in canvas coordinates. Match draw_texture_rect.
	mesh.set_instance_transform_2d(index,transform*Art.pose(mount,style,angle,recoil)*Transform2D.FLIP_Y)
	mesh.set_instance_color(index,Art.tint(disabled,recoil))
	counts[family] = index+1

func finish() -> void:
	for family in groups.size(): groups[family].multimesh.visible_instance_count = counts[family]
