shader_type canvas_item;
render_mode unshaded, blend_add;

varying flat vec4 shield;
varying vec4 tint;
varying float angle;
uniform float pulse_time;

void vertex() {
	shield = INSTANCE_CUSTOM;
	tint = COLOR;
	angle = (UV.x - 0.5) * TAU * shield.x;
	float radius = mix(0.72, 1.012, UV.y);
	VERTEX = vec2(cos(angle), sin(angle)) * radius;
}

void fragment() {
	float radius = mix(0.72, 1.012, UV.y);
	float edge = smoothstep(0.72, 0.985, radius) * (1.0 - smoothstep(0.985, 1.012, radius));
	float end_fade = shield.x > 0.999 ? 1.0 : smoothstep(0.0, 0.06, PI * shield.x - abs(angle));
	float stress = 1.0 + 0.17 * shield.w * sin(angle * 18.0 + pulse_time);
	float hit_angle = (shield.y - 0.5) * TAU;
	float separation = abs(mod(angle - hit_angle + PI, TAU) - PI);
	float distance_from_hit = length(vec2(separation, 1.0 - radius));
	float age = 1.0 - shield.z;
	float wave = 1.0 - smoothstep(0.025, 0.12, abs(distance_from_hit - 0.03 - age * 0.82));
	float center = 1.0 - smoothstep(0.0, 0.30, distance_from_hit);
	float flash = shield.z * (wave + center * 0.65);
	float alpha = clamp((edge * 0.56 * stress + flash) * end_fade, 0.0, 1.0);
	COLOR = vec4(mix(tint.rgb, vec3(0.89, 0.98, 1.0), clamp(flash, 0.0, 1.0)), alpha);
}
