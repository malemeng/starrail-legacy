extends RefCounted

const SPANS := {"interceptor":2.3,"fighter":3.1,"support":3.6,"bomber":4.4}

static func formation(wing: Dictionary, heading: float, tone: Color, stroke: Callable) -> void:
	var units: int = wing.get("count_live", wing.count)
	var forward := Vector2.from_angle(wing.get("heading", heading))
	var side := forward.orthogonal()
	var span: float = SPANS.get(wing.role, 3.1)
	for i in units:
		var rank := ceili(i * 0.5)
		var center := Vector2(wing.pos) - forward * rank * 7.0 + side * (rank * (8.0 if i % 2 == 1 else -8.0))
		var nose := center + forward * span
		var rear := center - forward * span * 0.55
		stroke.call(rear - side * span,nose,1.8,tone)
		stroke.call(nose,rear + side * span,1.8,tone)
		if wing.role == "bomber":
			stroke.call(rear - side * span,rear + side * span,1.8,tone)
