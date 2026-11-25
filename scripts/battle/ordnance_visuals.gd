extends RefCounted

# Local-space strokes (x1, y1, x2, y2) are shared by close-up and fleet rendering.
const GLYPHS := {
	"flare": [Color("ffc97b"), 1.8, [Vector4(-4,0,4,0),Vector4(0,-3,0,3)]],
	"canister": [Color("ffae77"), 2.2, [Vector4(-5,-2,4,-2),Vector4(-5,2,4,2),Vector4(4,-2,4,2)]],
	"mote": [Color("adeaff"), 1.5, [Vector4(-3,0,0,-3),Vector4(0,-3,3,0),Vector4(3,0,0,3),Vector4(0,3,-3,0)]],
	"screen": [Color("8ffde2"), 1.8, [Vector4(-3,-4,2,-2),Vector4(2,-2,2,2),Vector4(2,2,-3,4)]],
	"constructor": [Color("c1e5a0"), 1.8, [Vector4(-4,-3,4,0),Vector4(4,0,-4,3),Vector4(-4,-3,-4,3)]],
	"terminator": [Color("ec94ba"), 2.0, [Vector4(-6,-3,5,0),Vector4(-6,3,5,0),Vector4(-3,0,5,0)]]
}

static func draw_shot(kind: String, pos: Vector2, velocity: Vector2, draw_segment: Callable) -> void:
	var glyph: Array = GLYPHS[kind]
	var pose := Transform2D(velocity.angle(), pos)
	for line: Vector4 in glyph[2]:
		draw_segment.call(pose * Vector2(line.x,line.y), pose * Vector2(line.z,line.w), glyph[1], glyph[0])
