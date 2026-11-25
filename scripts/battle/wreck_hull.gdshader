shader_type canvas_item;
render_mode unshaded;

uniform sampler2D hull_art : source_color, filter_nearest, repeat_disable;
uniform float age = 5.0;
uniform float variant = 0.5;
uniform float aspect = 1.0;

// The three plates share the same torn edges. Inverse-map each plate to
// the original ship artwork so even an asymmetric bow keeps its markings.
float cut(vec2 uv, float side) {
	float row = floor(uv.y * 26.0);
	return mix(0.32, 0.69, side) + (uv.y-0.5)*mix(0.17,-0.21,side)
		+ 0.024*sin(row*0.74 + variant*15.0 + side*2.5)
		+ 0.013*sin(row*2.11 + side + variant*7.0);
}
vec4 plate(vec2 at, float index, float spread) {
	float side = index-1.0;
	vec2 pivot = vec2(0.5+0.31*side,0.5);
	float angle = spread * (side * (0.10 + 0.13*variant) + 0.035);
	vec2 shift = vec2(side*0.072, (side*0.047+side*side*(variant-0.5)*0.08));
	vec2 v = (at - pivot - spread*shift)*vec2(aspect,1.0);
	float c = cos(angle), s = sin(angle);
	vec2 uv = pivot + vec2(c*v.x+s*v.y,-s*v.x+c*v.y)/vec2(aspect,1.0);
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) { return vec4(0.0); }
	float left = uv.x-cut(uv,0.0), right = uv.x-cut(uv,1.0);
	float edge = index < 0.5 ? -left : (index > 1.5 ? right : min(left,-right));
	if (edge < 0.0) { return vec4(0.0); }
	vec4 base = texture(hull_art,uv);
	float charred = smoothstep(0.04,1.10,age);
	float lum = dot(base.rgb,vec3(0.25,0.61,0.14));
	float rib = fract(uv.y*32.0+variant) < 0.22 ? 1.0 : 0.0;
	float tear = 1.0-smoothstep(0.002,0.047,edge);
	vec3 cold = mix(vec3(0.08,0.095,0.108)+lum*vec3(0.52,0.50,0.47),
		vec3(0.09,0.073,0.065)+rib*vec3(0.16,0.14,0.11),tear);
	float heat = (1.0-smoothstep(0.002,0.022,edge)) * smoothstep(0.0,0.14,age)
		* exp(-max(age-0.38,0.0)*1.35) * (0.6+0.4*sin(uv.y*67.0+variant*13.0));
	return vec4(mix(base.rgb,cold,charred)+vec3(1.0,0.38,0.055)*heat,base.a);
}
void fragment() {
	vec2 at = (UV-0.5)*1.4+0.5;
	float spread = smoothstep(0.08,1.72,age);
	vec4 color = plate(at,0.0,spread);
	vec4 middle = plate(at,1.0,spread);
	vec4 bow = plate(at,2.0,spread);
	color = mix(color,middle,middle.a);
	COLOR = mix(color,bow,bow.a);
}
