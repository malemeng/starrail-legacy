shader_type canvas_item;
render_mode unshaded, blend_add;

varying flat float travel;

void vertex() {
	travel = INSTANCE_CUSTOM.x;
}

void fragment() {
	// Repeating parcels move from the port to the widening, cooling plume tip.
	float x = UV.x;
	float spread = mix(0.10, 0.49, x);
	float swirl = sin(x * 14.0 - travel * TAU) * 0.05 * x;
	float lateral = abs(UV.y - 0.5 + swirl);
	float jet = 1.0 - smoothstep(spread * 0.12, spread, lateral);
	float parcels = 0.54 + 0.46 * sin((x * 3.0 - travel) * TAU + lateral * 11.0);
	float tail = 1.0 - smoothstep(0.12, 1.0, x);
	vec3 tint = mix(vec3(0.84, 1.0, 0.99), vec3(0.32, 0.78, 0.94), x);
	COLOR = vec4(tint, jet * tail * mix(1.0, parcels, smoothstep(0.0, 0.45, x)) * 0.88);
}
