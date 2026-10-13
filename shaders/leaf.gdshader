shader_type spatial;
// Hojas instanciadas (MultiMesh). Opacas, sin transparencias: baratas en GPUs móviles.
// INSTANCE_CUSTOM: x = escala, y = fase, z = factor de elevación sobre el montón, w = forma.
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap;

uniform sampler2D pile_tex : filter_linear, repeat_disable;
uniform vec4 grid_rect;
uniform float pile_max = 1.25;

void vertex() {
	float s = INSTANCE_CUSTOM.x;
	VERTEX.x *= mix(0.7, 1.25, INSTANCE_CUSTOM.w);
	float tip = length(VERTEX.xz) * 6.0;
	VERTEX *= s;
	VERTEX.y += sin(TIME * 2.4 + INSTANCE_CUSTOM.y * 40.0) * 0.006 * tip * s;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 uv = (origin.xz - grid_rect.xy) * grid_rect.zw;
	float lift = textureLod(pile_tex, uv, 0.0).g * pile_max * INSTANCE_CUSTOM.z;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * vec3(0.0, lift, 0.0);
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		c *= 0.82;
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
