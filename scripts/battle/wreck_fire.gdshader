shader_type canvas_item;
render_mode unshaded;

uniform float age = 0.0;
uniform float variant = 0.5;

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	vec4 cells = vec4(dot(i,vec2(51.7,83.1))) + vec4(0.0,51.7,83.1,134.8);
	vec4 h = fract(sin(cells)*15421.28);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
vec4 burst(vec2 p, float t, float radius, float seed) {
	if (t <= 0.0 || t >= 1.65) { return vec4(0.0); }
	float r = radius*(0.14+0.86*(1.0-exp(-4.5*t)));
	vec2 v = p/r;
	float d = length(v);
	if (d > 1.35) { return vec4(0.0); }
	vec2 sample_at = v*3.6+vec2(seed*13.0,-t*1.4);
	float grain = noise(sample_at)*0.64 + noise(sample_at*2.15)*0.36;
	float cloud = 1.0-smoothstep(0.49,0.86,d+(grain-0.5)*0.72);
	float heat = clamp(1.28-d*0.80+grain*0.45-t*1.4,0.0,1.0);
	vec3 color = mix(vec3(0.17,0.19,0.21),vec3(0.47,0.19,0.10),smoothstep(0.08,0.35,heat));
	color = mix(color,vec3(1.0,0.43,0.09),smoothstep(0.4,0.73,heat));
	color = mix(color,vec3(1.0,0.94,0.74),smoothstep(0.75,0.99,heat));
	float glint = exp(-abs(p.y)*120.0/radius-abs(p.x)*5.5/radius)*exp(-t*17.0);
	float halo = exp(-d*d*3.5)*0.24*exp(-t*3.2);
	float alpha = max(halo,cloud) * smoothstep(0.0,0.035,t)*(1.0-smoothstep(0.45,1.65,t));
	color = mix(vec3(0.90,0.35,0.07),color,cloud);
	return vec4(color*alpha+vec3(1.0,0.86,0.60)*glint,max(alpha,glint));
}
void fragment() {
	vec2 p = UV*2.0-1.0;
	float side = variant > 0.5 ? 1.0 : -1.0;
	vec4 a = burst(p-vec2(-0.28,side*0.05),age,0.46,variant);
	vec4 b = burst(p-vec2(0.14,-side*0.08),age-0.16,0.60,variant+1.9);
	vec4 c = burst(p-vec2(0.36,side*0.08),age-0.36,0.32,variant+4.2);
	vec4 result = c+(b+a*(1.0-b.a))*(1.0-c.a);
	COLOR = vec4(result.rgb/max(0.001,result.a),result.a);
}
