shader_type canvas_item;
uniform sampler2D armor_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin;
uniform vec2 mask_extent = vec2(1.0);
uniform float pixel_scale = 1.0;
uniform float flash = 0.0;
uniform vec2 impact_local;
varying vec2 hull_pos;
varying vec4 tint;
void vertex() {
	hull_pos = VERTEX * pixel_scale;
	tint = COLOR;
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 hit_uv = clamp((hull_pos - mask_origin) / mask_extent, vec2(0.0), vec2(0.999));
	float intact = texture(armor_mask, hit_uv).r;
	vec3 wreck = mix(vec3(0.11, 0.065, 0.05), base.rgb, 0.35);
	float heat = flash * (1.0 - smoothstep(0.0, 16.0, distance(hull_pos, impact_local)));
	COLOR = vec4(mix(mix(wreck, base.rgb, intact), vec3(1.0, 0.87, 0.64), heat),base.a) * tint;
}
