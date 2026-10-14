shader_type spatial;
// Hojas instanciadas (MultiMesh). Opacas, sin transparencias ni recortes: baratas en GPUs móviles.
// Cada hoja es una hoja de verdad: la silueta está en la malla (LeafMeshes, 5 especies con la misma
// topología) y el shader la curva (bordes enrollados, pliegue en V por el nervio, punta arqueada), la
// apoya en el terreno o en el montón (inclinada según su superficie y al azar dentro de él), la agita
// con el viento y la colorea (dos tonos, borde oscuro nítido, nervios claros, motas).
//
// Datos por instancia:
//   transform  posición (y = suelo + 1,5 cm) y giro. Base sin inclinar = en reposo; inclinada = en el
//              aire; escala 1,2 = volando hacia la mano/aspiradora (se ilumina y no se apoya en el montón).
//   COLOR.rgb  color de la hoja (× tinte del vértice).  COLOR.a (malla): 0 nervio → 1 borde.
//   INSTANCE_CUSTOM  x = tamaño, y = semilla, z = profundidad en el montón (0 fondo → 1 superficie),
//                    w = (especie + variación de anchura · 0,96) / 5.
// Montones: pile_tex.g (altura) reparte las hojas por todo el volumen del montón: altura = H · z.
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap;

uniform sampler2D pile_tex : filter_linear, repeat_disable;
uniform sampler2D site_tex : filter_nearest, repeat_disable;   // rg = pendiente del terreno, b = zona + 1
uniform sampler2D vein_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 grid_rect;          // origen x, z; 1 / tamaño x, z (m)
uniform vec2 grid_cells;         // celdas de la rejilla (ancho, fondo)
uniform float cell_size = 0.5;
uniform float pile_max = 1.25;
uniform float leaf_size = 0.32;
uniform vec2 wind = vec2(0.0);
uniform vec4 highlight = vec4(0.0);      // xyz centro, w radio (0 = apagado)
uniform float reveal = 0.0;              // Ajustes → «Resaltar hojas»
// Últimas hojas de hasta 4 zonas casi limpias: índice de zona + 1 (0 = nada) y brillo de cada una.
// (Sin arrays de float: en el renderizador Compatibility desordenan el bloque de uniformes.)
uniform vec4 glow_zones = vec4(0.0);
uniform vec4 glow_amount = vec4(0.0);
uniform vec2 far_boost = vec2(26.0, 80.0);   // a lo lejos las hojas crecen algo: no desaparecen entre píxeles

const float WIDTH[5] = float[](0.5, 0.27, 0.4, 0.13, 0.46);

varying vec3 v_centre;
varying vec3 v_edge;
varying vec2 v_vein;
varying vec4 v_fx;       // x = resaltado de la mano, y = brillo de zona, z = volando a la mano, w = motas

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float sp = INSTANCE_CUSTOM.w * 5.0 + 0.002;
	float species = min(floor(sp), 4.0);
	float vari = fract(sp);
	float seed = INSTANCE_CUSTOM.y;
	vec2 p = VERTEX.xz;
	if (species > 3.5) {
		p = CUSTOM0.zw;
	} else if (species > 2.5) {
		p = CUSTOM0.xy;
	} else if (species > 1.5) {
		p = UV2;
	} else if (species > 0.5) {
		p = UV;
	}
	vec2 pc = clamp(p, vec2(-0.59), vec2(0.59));
	vec2 tile = vec2(mod(species, 3.0), floor(species / 3.0 + 0.01));
	v_vein = (tile + vec2(pc.x + 0.6, 0.6 - pc.y) / 1.2) * vec2(1.0 / 3.0, 0.5);
	float W = WIDTH[int(species)];
	p.x *= mix(0.86, 1.14, vari);

	float h1 = hash11(seed * 97.0 + 1.0);
	float h2 = hash11(seed * 57.0 + 7.0);
	float h3 = hash11(seed * 131.0 + 3.0);
	float h4 = hash11(seed * 211.0 + 5.0);
	float h5 = hash11(seed * 313.0 + 11.0);
	float h6 = hash11(seed * 419.0 + 13.0);
	float h7 = hash11(seed * 523.0 + 17.0);

	// Estado: en reposo (base sin inclinar), en el aire (inclinada) o volando a la mano (escala 1,2).
	float sc = length(MODEL_MATRIX[0].xyz);
	float sucked = step(1.08, sc);
	float air = max(smoothstep(0.985, 0.9, MODEL_MATRIX[1].y / sc), sucked);
	float rest = 1.0 - air;

	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 uv = (origin.xz - grid_rect.xy) * grid_rect.zw;
	float H = textureLod(pile_tex, uv, 0.0).g * pile_max;
	float depth = INSTANCE_CUSTOM.z;
	float heap = smoothstep(0.02, 0.22, H);
	vec4 site = texelFetch(site_tex, ivec2(clamp(uv, vec2(0.0), vec2(0.9999)) * grid_cells), 0);

	// Viento: ráfagas que recorren el césped en la dirección del viento (las hojas enterradas no se mueven).
	float wl = length(wind);
	vec2 wd = wl > 0.001 ? wind / wl : vec2(1.0, 0.0);
	float gust = smoothstep(0.45, 1.0, sin(dot(origin.xz, wd) * 0.42 - TIME * 1.6) * 0.5 + 0.5);
	float breeze = min(wl, 1.5) * (0.25 + 0.75 * gust) * rest * (1.0 - heap * (1.0 - depth));

	// Forma: bordes enrollados (algunas hojas secas mucho), pliegue en V por el nervio y punta arqueada.
	float cup = 0.06 + 0.22 * h1 + step(0.86, h1) * 0.35 + air * 0.25;
	float fold = 0.05 + 0.16 * h2;
	float bow = 0.03 + 0.22 * h3;
	float tip = max(p.y, 0.0);
	float wave = sin(TIME * (2.3 + 8.0 * air + 3.0 * breeze) + seed * 40.0 + p.y * (2.0 + 2.0 * air));
	float flap = mix((wave * 0.5 + 0.5) * (0.01 + 0.12 * breeze), wave * 0.22, air);
	float h = cup * p.x * p.x / W + fold * abs(p.x) + bow * p.y * p.y + flap * tip;
	float dhx = 2.0 * cup * p.x / W + fold * sign(p.x);
	float dhy = 2.0 * bow * p.y + flap * step(0.0, p.y);
	// Resaltado de la mano: las hojas que vas a coger crecen un poco, se levantan y brillan.
	float hl = 0.0;
	if (highlight.w > 0.0) {
		float d = length(origin.xz - highlight.xz);
		hl = (1.0 - smoothstep(highlight.w * 0.85, highlight.w, d)) * step(abs(origin.y - highlight.y), 1.8) * (1.0 - sucked);
	}
	// Últimas hojas de una zona casi limpia: flotan sobre la hierba y laten.
	float zg = 0.0;
	if (glow_amount.x + glow_amount.y + glow_amount.z + glow_amount.w > 0.0) {
		float zid = floor(site.b * 255.0 + 0.5);
		if (zid > 0.5) {
			zg = dot(step(abs(glow_zones - vec4(zid)), vec4(0.5)), glow_amount) * rest;
		}
	}
	float s = INSTANCE_CUSTOM.x * leaf_size * (1.0 + 0.18 * hl + 0.35 * zg);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	s *= 1.0 + 0.6 * smoothstep(far_boost.x, far_boost.y, distance(cam, origin));
	vec3 v = vec3(p.x, h, -p.y) * s;
	vec3 n = vec3(-dhx, 1.0, dhy);

	// En el aire: voltereta continua (además del giro que da la física).
	if (air > 0.01) {
		float t = TIME * (2.6 + 4.0 * h5) + seed * 30.0;
		float ax = sin(t) * 1.1 * air;
		float az = cos(t * 0.71 + seed * 11.0) * 0.8 * air;
		mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(ax), sin(ax)), vec3(0.0, -sin(ax), cos(ax)));
		mat3 rz = mat3(vec3(cos(az), sin(az), 0.0), vec3(-sin(az), cos(az), 0.0), vec3(0.0, 0.0, 1.0));
		mat3 r = rz * rx;
		v = r * v;
		n = r * n;
	}

	// En reposo: apoyada en el terreno (su pendiente) o en el montón (su superficie + inclinación al azar).
	float lift = H * depth * (1.0 - sucked);
	if (rest > 0.01) {
		vec2 slope = (site.rg - 0.5) * 4.0;
		vec2 jit = vec2(h5 - 0.5, h6 - 0.5);
		vec2 tilt = jit * 0.14;
		if (H > 0.004) {
			vec2 e = 1.0 / grid_cells;
			float gx = textureLod(pile_tex, uv + vec2(e.x, 0.0), 0.0).g - textureLod(pile_tex, uv - vec2(e.x, 0.0), 0.0).g;
			float gz = textureLod(pile_tex, uv + vec2(0.0, e.y), 0.0).g - textureLod(pile_tex, uv - vec2(0.0, e.y), 0.0).g;
			slope += vec2(gx, gz) * (pile_max / (2.0 * cell_size)) * depth;
			tilt = mix(tilt, jit * 1.7, heap);
		}
		vec3 nw = normalize(vec3(tilt.x - slope.x, 1.0, tilt.y - slope.y));
		vec3 nl = normalize(transpose(mat3(MODEL_MATRIX)) * nw);
		vec3 X = normalize(vec3(1.0, 0.0, 0.0) - nl * nl.x);
		vec3 Z = cross(X, nl);
		v = mix(v, X * v.x + nl * v.y + Z * v.z, rest);
		n = mix(n, X * n.x + nl * n.y + Z * n.z, rest);
		// Inclinada sobre su centro: se sube lo justo para que el borde bajo no atraviese el suelo.
		lift += (length(tilt) * 0.5 * s + 0.002 + 0.012 * h7) * rest;
	}

	lift += hl * (0.05 + 0.02 * sin(TIME * 8.0 + seed * 40.0));
	lift += zg * (0.08 + 0.03 * sin(TIME * 3.0 + seed * 20.0));
	lift += reveal * 0.02 * rest;
	VERTEX = v + transpose(mat3(MODEL_MATRIX)) * vec3(0.0, lift, 0.0) / (sc * sc);
	NORMAL = normalize(n);

	// Color: dos tonos por hoja (centro soleado o aún verdoso, borde más oscuro y rojizo).
	vec3 base = COLOR.rgb;
	float lum = dot(base, vec3(0.3, 0.55, 0.15));
	vec3 sunny = base * vec3(1.06, 1.14, 0.78) + vec3(0.05, 0.04, 0.0);
	vec3 greenish = vec3(0.42, 0.55, 0.12) * (0.55 + lum);
	vec3 centre = mix(base, sunny, step(h4, 0.5) * 0.5);
	centre = mix(centre, greenish, step(0.94, h4) * 0.45);
	vec3 edge = base * mix(vec3(0.86, 0.66, 0.56), vec3(0.6, 0.34, 0.24), h3);
	// Oscurecimiento por contacto: las hojas del fondo del montón quedan en una sombra cálida (pardo
	// rojizo, no gris ni oliva) y las que tocan el suelo, algo más oscuras en el centro.
	float k = heap * (1.0 - depth) * rest;
	vec3 ao = mix(vec3(1.0), vec3(0.6, 0.44, 0.36), k);
	v_centre = centre * ao;
	v_edge = edge * ao;
	v_fx = vec4(hl, zg, sucked, step(0.84, h6) * step(species, 1.5));
}

void fragment() {
	vec2 vt = texture(vein_tex, v_vein).rg;
	float e = COLOR.a;
	vec3 c = mix(v_centre, v_edge, smoothstep(0.35, 1.0, e));
	// Borde nítido algo más oscuro: separa hojas iguales que se solapan.
	float rim = smoothstep(0.84, 0.97, e);
	c *= 1.0 - 0.3 * rim;
	c *= 0.86 + 0.28 * vt.g;
	// Motas oscuras en algunas hojas de arce y roble.
	c *= 1.0 - v_fx.w * smoothstep(0.66, 0.72, vt.g) * 0.6;
	// Nervios más claros y dorados.
	c = mix(c, c * vec3(1.22, 1.16, 0.8) + vec3(0.05, 0.035, 0.0), vt.r * 0.7);
	if (!FRONT_FACING) {
		// Envés: más pálido y mate (y con la misma iluminación que el haz).
		NORMAL = -NORMAL;
		c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))), 0.3) * 0.84;
	}
	vec3 em = vec3(0.0);
	// Resaltado de la mano: brillo cálido con el borde muy luminoso (se ve en sol y en sombra).
	float hl = v_fx.x;
	c = mix(c, c * 1.2 + vec3(0.06, 0.03, 0.0), hl);
	em += (c * 0.2 + vec3(1.0, 0.5, 0.1) * (0.18 + 1.4 * rim)) * hl;
	// Últimas hojas de la zona: latido anaranjado con contorno dorado.
	float zg = v_fx.y * (0.7 + 0.3 * sin(TIME * 4.0));
	em += (vec3(1.0, 0.42, 0.04) * 0.7 + vec3(1.0, 0.85, 0.3) * rim * 1.6) * zg;
	// Volando a la mano: un poco de brillo para seguirlas con la vista.
	em += c * v_fx.z * 0.35;
	// «Resaltar hojas»: tinte saturado y contorno luminoso que destacan sobre cualquier suelo.
	if (reveal > 0.5) {
		float g = dot(c, vec3(0.3, 0.5, 0.2));
		c = clamp(mix(vec3(g), c, 1.6) * 1.15, 0.0, 1.0);
		em += vec3(1.0, 0.36, 0.02) * 0.28 + vec3(1.0, 0.9, 0.25) * rim * 1.1;
	}
	ALBEDO = c;
	EMISSION = em;
	// Translucidez: el sol a contraluz atraviesa la hoja.
	BACKLIGHT = c * 0.45;
	ROUGHNESS = 0.78;
}
