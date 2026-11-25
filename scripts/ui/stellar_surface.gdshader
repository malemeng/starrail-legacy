shader_type canvas_item;
render_mode unshaded;

uniform sampler2D terrain : repeat_enable, filter_linear;
uniform vec4 hue : source_color;
uniform vec2 offset;
uniform int kind;
uniform bool rings;
uniform float tilt;
uniform float spin;
uniform vec2 sunward = vec2(-0.78,-0.62);

void fragment() {
	vec2 p = (UV - 0.5) * 3.3;
	float r = length(p);
	float rim = clamp(fwidth(r), 0.00004, 0.035);
	float disk = 1.0 - smoothstep(1.0-rim, 1.0+rim, r);
	float z = sqrt(max(0.0,1.0-r*r));
	float longitude = (atan(p.x, max(z,0.0001))-spin)/TAU;
	float latitude = asin(clamp(p.y,-1.0,1.0))/PI;
	vec2 ground = vec2(longitude,latitude);
	float broad = texture(terrain, ground*vec2(3.0,1.5)+offset).r;
	float fine = texture(terrain, ground*vec2(15.0,7.5)+offset).r;
	float detail = texture(terrain, ground*vec2(72.0,36.0)+offset).r;
	float grain = broad*0.58 + fine*0.29 + detail*0.13;
	vec3 color;
	float alpha;
	if (kind == 0) {
		float daylight = sqrt(max(0.0, 1.0-r*r));
		float heat = clamp(daylight*0.51 + grain*0.83,0.0,1.0);
		color = mix(hue.rgb*0.72, mix(hue.rgb,vec3(1.0),0.83),heat);
		float altitude = clamp((r-1.0)/0.12,0.0,1.0);
		float corona = (1.0-altitude)*(1.0-altitude)*(0.36+grain*0.44);
		color = mix(hue.rgb,color,disk);
		alpha = mix(corona,1.0,disk);
	} else {
		float light = max(0.0, dot(vec3(p,z),normalize(vec3(sunward,0.72))));
		vec3 pigment = hue.rgb;
		if (kind == 2) {
			pigment *= 0.94 + 0.16*sin(p.y*27.0+4.0*broad+p.x*1.6) + (fine-0.5)*0.16;
		} else {
			if (kind == 3) {
				pigment = mix(vec3(0.12,0.29,0.48),pigment,smoothstep(0.45,0.50,broad));
			}
			pigment *= 0.65+grain*0.7;
		}
		color = mix(vec3(0.027,0.044,0.079),pigment,clamp(light*1.04+0.085,0.0,1.0));
		color += hue.rgb*pow(r,16.0)*light*0.36;
		alpha = disk;
		if (rings) {
			vec2 ring = mat2(vec2(cos(tilt),sin(tilt)),vec2(-sin(tilt),cos(tilt))) * p;
			float distance_to_center = length(vec2(ring.x,ring.y*3.7));
			float aa = clamp(fwidth(distance_to_center),0.0001,0.04);
			float band = smoothstep(1.17-aa,1.17+aa,distance_to_center)*(1.0-smoothstep(1.57-aa,1.57+aa,distance_to_center));
			band *= smoothstep(0.012,0.030,abs(distance_to_center-1.42));
			if (ring.y > 0.0 || r > 1.0) {
				color = mix(color,mix(hue.rgb,vec3(0.89,0.78,0.63),0.6)*(0.78+0.16*sin(distance_to_center*95.0)),band);
				alpha = max(alpha,band);
			}
		}
	}
	COLOR = vec4(color,alpha);
}
