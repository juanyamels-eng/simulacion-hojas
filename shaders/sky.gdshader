shader_type sky;
// Cielo estilizado de Villa Hojarasca: degradado suave cénit → horizonte, bruma cálida del lado del sol,
// disco solar con halo, nubes pintadas que derivan con el viento y suelo lejano brumoso.
// Barato para móviles: sin bucles; las nubes (3 lecturas de textura) solo se dibujan en el fondo,
// nunca en el cubemap de radiancia (que se regenera solo cuando cambian la luz o los parámetros).

uniform vec3 zenith_color : source_color = vec3(0.28, 0.5, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.98, 0.86, 0.7);
uniform vec3 ground_color : source_color = vec3(0.45, 0.43, 0.32);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.82, 0.58);
uniform float sun_size = 0.03;
uniform float sun_glow = 1.0;
uniform float horizon_glow = 0.45;
uniform float gradient_curve = 3.0;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_shade : source_color = vec3(0.66, 0.7, 0.82);
uniform float cloud_cover = 0.52;
uniform float cloud_softness = 0.2;
uniform float cloud_alpha = 0.9;
uniform float cloud_detail = 1.0;       // 0 en calidad Baja: una lectura menos por píxel de cielo
uniform vec2 cloud_offset = vec2(0.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float sky_energy = 1.0;

void sky() {
	vec3 d = EYEDIR;
	vec3 s = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float h = d.y;
	float up = clamp(h, 0.0, 1.0);
	float sd = max(dot(d, s), 0.0);
	// Horizonte cálido del lado del sol y pálido (azulado o rosado) del lado contrario.
	float side = dot(d.xz, s.xz) / (length(d.xz) * length(s.xz) + 0.0001) * 0.5 + 0.5;
	vec3 pale = mix(zenith_color, horizon_color, 0.35) * 0.6 + vec3(0.35);
	vec3 hor = mix(pale, horizon_color, smoothstep(0.05, 0.95, side));
	// Degradado principal: banda del horizonte baja, cénit profundo.
	vec3 col = mix(hor, zenith_color, 1.0 - pow(1.0 - up, gradient_curve));
	// Bruma cálida: más intensa cerca del horizonte y del lado del sol.
	float haze = exp(-up * 7.0);
	col += sun_tint * horizon_glow * haze * side * side;
	// Halo del sol (ancho y suave + núcleo concentrado).
	col += sun_tint * (pow(sd, 5.0) * 0.18 + pow(sd, 60.0) * 0.55) * sun_glow;
	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(cos(sun_size), cos(sun_size * 0.75), sd);
		col = mix(col, sun_tint * 5.0, disk * step(-0.02, s.y));
		if (h > 0.0 && cloud_alpha > 0.001) {
			// Capa plana de nubes proyectada sobre el cielo.
			vec2 uv = d.xz / (h + 0.14) * 0.2 + cloud_offset;
			float n = texture(cloud_noise, uv).r;
			if (cloud_detail > 0.5) {
				n = n * 0.72 + texture(cloud_noise, uv * 2.6 + vec2(0.37, 0.71)).r * 0.28;
			}
			float dens = smoothstep(cloud_cover, cloud_cover + cloud_softness, n);
			// Iluminación barata: comparar con la densidad desplazada hacia el sol.
			vec2 to_sun = s.xz / (length(s.xz) + 0.0001);
			float ns = texture(cloud_noise, uv + to_sun * 0.035).r;
			float lit = clamp(0.62 + (n - ns) * 5.0, 0.0, 1.0);
			vec3 cc = mix(cloud_shade, cloud_lit, lit);
			// Bordes plateados a contraluz y tinte del sol cerca del horizonte.
			cc += sun_tint * pow(sd, 8.0) * (1.0 - dens * 0.6) * 0.9;
			cc = mix(cc, cc * sun_tint * 1.15, haze * 0.6);
			float fade = smoothstep(0.0, 0.22, h);
			col = mix(col, cc, dens * fade * cloud_alpha);
		}
	}
	// Bajo el horizonte: bruma que se funde con el campo lejano.
	if (h < 0.0) {
		col = mix(col, ground_color, smoothstep(0.0, -0.35, h));
	}
	// sky_energy solo aclara el fondo visible; la luz ambiente (cubemap) no cambia.
	COLOR = AT_CUBEMAP_PASS ? col : col * sky_energy;
}
