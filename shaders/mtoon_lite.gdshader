// Lightweight MToon-style cel shader (base + shade colour, soft terminator, subtle rim).
// Unshaded on purpose: the light direction is a fixed camera-relative uniform, so it looks the same in any scene.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D shade_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.78, 0.74, 0.80, 1.0);
uniform bool use_shade_tex = false;
uniform float shading_shift = -0.05;
uniform float shading_toony = 0.9;
uniform float alpha_cutoff = 0.5;
uniform float rim_strength = 0.12;
uniform vec3 light_dir_view = vec3(-0.35, 0.55, 0.75);

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 base = tex.rgb * base_color.rgb;
	vec3 shade = use_shade_tex ? texture(shade_tex, UV).rgb * shade_color.rgb : base * shade_color.rgb;

	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float ndl = dot(n, normalize(light_dir_view));
	float width = max(1.0 - shading_toony, 0.02);
	float lit = smoothstep(-width, width, ndl + shading_shift);
	vec3 col = mix(shade, base, lit);

	float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
	col += vec3(rim * rim_strength * lit);

	ALBEDO = col;
	ALPHA = tex.a * base_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
