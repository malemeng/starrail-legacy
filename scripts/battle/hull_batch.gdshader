shader_type canvas_item;
uniform sampler2D armor : filter_nearest, repeat_disable;
uniform sampler2D mapping : filter_nearest, repeat_disable;
varying flat int row;
varying flat vec4 grid_mapping;
varying flat vec4 impact;
varying vec2 surface;
varying vec4 livery;
void vertex() {
	row = INSTANCE_ID;
	grid_mapping = texelFetch(mapping, ivec2(0, row), 0);
	impact = texelFetch(mapping, ivec2(1, row), 0);
	surface = UV;
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	livery = COLOR;
}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a == 0.0) { discard; }
	vec2 grid = clamp(surface * grid_mapping.zw + grid_mapping.xy, vec2(0.0), vec2(0.999));
	ivec2 cell = ivec2(grid * vec2(7.0,5.0));
	float intact = clamp(texelFetch(armor, ivec2(cell.x + 7 * cell.y, row), 0).r * impact.w, 0.0, 1.0);
	float heat = impact.z * (1.0 - smoothstep(0.0,0.14,distance(surface, impact.xy)));
	vec3 scar = mix(vec3(0.11,0.065,0.05),base.rgb,0.35);
	COLOR = vec4(mix(mix(scar,base.rgb,intact),vec3(1.0,0.87,0.64),heat),base.a) * livery;
}
