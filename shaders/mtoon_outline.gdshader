// Inverted-hull outline pass (set as next_pass of the toon material).
shader_type spatial;
render_mode unshaded, cull_front;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 outline_color : source_color = vec4(0.10, 0.08, 0.10, 1.0);
uniform float outline_width = 0.0012;
uniform float alpha_cutoff = 0.5;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	float a = texture(albedo_tex, UV).a * base_color.a;
	ALBEDO = outline_color.rgb;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
