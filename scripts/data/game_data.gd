class_name GameData
## Datos de diseño del juego: zonas, puertas, mejoras, logros, objetivos y coleccionables.
## Todo el contenido es original de Villa Hojarasca.

const GAME_TITLE := "Villa Hojarasca"

# Límites del mapa (metros). La rejilla de hojas cubre también el taller secreto (al este).
const GRID_ORIGIN := Vector2(-62.0, -64.0)
const GRID_SIZE_M := Vector2(160.0, 132.0)
const CELL := 0.5

const START_POS := Vector3(0.0, 1.0, 60.0)

# Zonas: rect = Rect2(x, z, ancho, fondo).
const ZONES := [
	{"id": "entrada", "name": "Entrada", "rect": Rect2(-20, 40, 40, 24), "leaves": 2600, "value": 0.8, "color": Color(0.93, 0.62, 0.25)},
	{"id": "jardin_delantero", "name": "Jardín delantero", "rect": Rect2(-20, 10, 40, 30), "leaves": 3600, "value": 1.4, "color": Color(0.85, 0.45, 0.2)},
	{"id": "patio_principal", "name": "Patio principal", "rect": Rect2(-20, -25, 40, 35), "leaves": 4200, "value": 3.0, "color": Color(0.8, 0.35, 0.22)},
	{"id": "garaje", "name": "Garaje", "rect": Rect2(20, 10, 40, 30), "leaves": 3600, "value": 2.0, "color": Color(0.7, 0.5, 0.3)},
	{"id": "zona_infantil", "name": "Zona infantil", "rect": Rect2(-60, 10, 40, 30), "leaves": 4000, "value": 2.0, "color": Color(0.95, 0.75, 0.3)},
	{"id": "huerto", "name": "Huerto", "rect": Rect2(-60, -25, 40, 35), "leaves": 4200, "value": 4.0, "color": Color(0.6, 0.55, 0.25)},
	{"id": "jardin_trasero", "name": "Jardín trasero", "rect": Rect2(-20, -62, 40, 37), "leaves": 5600, "value": 6.0, "color": Color(0.75, 0.3, 0.2)},
	{"id": "piscina", "name": "Piscina", "rect": Rect2(20, -25, 40, 35), "leaves": 4800, "value": 5.0, "color": Color(0.45, 0.6, 0.7)},
	{"id": "laberinto", "name": "Laberinto vegetal", "rect": Rect2(-60, -62, 40, 37), "leaves": 4400, "value": 8.0, "color": Color(0.4, 0.55, 0.3)},
	{"id": "invernadero", "name": "Invernadero", "rect": Rect2(20, -62, 40, 37), "leaves": 4200, "value": 10.0, "color": Color(0.55, 0.7, 0.55)},
	{"id": "taller_secreto", "name": "Taller subterráneo", "rect": Rect2(70, -44, 22, 18), "leaves": 700, "value": 12.0, "color": Color(0.5, 0.4, 0.35), "secret": true},
]

# Puertas entre zonas. "axis" = dirección de la valla ("x": valla paralela al eje X).
const GATES := [
	{"id": "g_delantero", "pos": Vector2(0, 40), "axis": "x", "a": "entrada", "b": "jardin_delantero", "cost": 150, "req": "entrada", "pct": 40.0},
	{"id": "g_infantil", "pos": Vector2(-20, 25), "axis": "z", "a": "jardin_delantero", "b": "zona_infantil", "cost": 700, "req": "jardin_delantero", "pct": 50.0},
	{"id": "g_garaje", "pos": Vector2(20, 25), "axis": "z", "a": "jardin_delantero", "b": "garaje", "cost": 700, "req": "jardin_delantero", "pct": 50.0},
	{"id": "g_patio", "pos": Vector2(0, 10), "axis": "x", "a": "jardin_delantero", "b": "patio_principal", "cost": 4000, "req": "jardin_delantero", "pct": 65.0},
	{"id": "g_huerto", "pos": Vector2(-20, -5), "axis": "z", "a": "patio_principal", "b": "huerto", "cost": 9000, "req": "patio_principal", "pct": 50.0},
	{"id": "g_piscina", "pos": Vector2(20, -5), "axis": "z", "a": "patio_principal", "b": "piscina", "cost": 9000, "req": "patio_principal", "pct": 50.0},
	{"id": "g_trasero", "pos": Vector2(16, -25), "axis": "x", "a": "patio_principal", "b": "jardin_trasero", "cost": 18000, "req": "patio_principal", "pct": 75.0},
	{"id": "g_laberinto", "pos": Vector2(-38, -25), "axis": "x", "a": "huerto", "b": "laberinto", "cost": 30000, "req": "huerto", "pct": 60.0},
	{"id": "g_invernadero", "pos": Vector2(40, -25), "axis": "x", "a": "piscina", "b": "invernadero", "cost": 35000, "req": "piscina", "pct": 60.0},
	# Atajos: se abren solos cuando ambas zonas están desbloqueadas.
	{"id": "s_infantil_huerto", "pos": Vector2(-40, 10), "axis": "x", "a": "zona_infantil", "b": "huerto", "cost": 0, "auto": true},
	{"id": "s_garaje_piscina", "pos": Vector2(40, 10), "axis": "x", "a": "garaje", "b": "piscina", "cost": 0, "auto": true},
	{"id": "s_trasero_oeste", "pos": Vector2(-16, -25), "axis": "x", "a": "patio_principal", "b": "jardin_trasero", "cost": 0, "auto": true},
	{"id": "s_trasero_laberinto", "pos": Vector2(-20, -44), "axis": "z", "a": "jardin_trasero", "b": "laberinto", "cost": 0, "auto": true},
	{"id": "s_trasero_invernadero", "pos": Vector2(20, -44), "axis": "z", "a": "jardin_trasero", "b": "invernadero", "cost": 0, "auto": true},
]

# Recompensas por porcentaje de limpieza (se aplican a cada zona).
const ZONE_REWARDS := {
	25: {"type": "money", "mult": 0.15, "text": "Bonificación de limpieza"},
	50: {"type": "value", "amount": 0.05, "text": "+5 % valor de las hojas"},
	75: {"type": "speed", "amount": 0.03, "text": "+3 % velocidad al caminar"},
	100: {"type": "value", "amount": 0.10, "text": "+10 % valor de las hojas · Zona restaurada"},
}

const CATEGORIES := [
	{"id": "hands", "name": "MANOS"},
	{"id": "bag", "name": "BOLSA"},
	{"id": "rake", "name": "RASTRILLO"},
	{"id": "blower", "name": "SOPLADOR"},
	{"id": "vacuum", "name": "ASPIRADORA"},
	{"id": "player", "name": "PERSONAJE"},
	{"id": "auto", "name": "AUTOMATIZACIÓN"},
]

# Mejoras. costs[n] = precio para pasar del nivel n al n+1. values tiene un valor más que costs.
const UPGRADES := {
	"hand": {"cat": "hands", "name": "Manos expertas", "desc": "Más hojas por puñado. Nivel 5: mantener para recoger sin parar. Nivel 6: radio doble.",
		"costs": [25, 120, 350, 700, 1600], "values": [2, 4, 7, 12, 12, 12], "fmt": "hand"},
	"bag_capacity": {"cat": "bag", "name": "Bolsas grandes", "desc": "Cuántas hojas caben en cada bolsa.",
		"costs": [80, 300, 1000, 3000, 8000], "values": [50, 100, 250, 500, 750, 1000], "fmt": "%d hojas"},
	"bag_close": {"cat": "bag", "name": "Nudo rápido", "desc": "Cierra las bolsas en menos tiempo.",
		"costs": [120, 900, 3500], "values": [1.2, 0.7, 0.35, 0.05], "fmt": "%.1f s"},
	"bag_throw": {"cat": "bag", "name": "Brazo lanzador", "desc": "Lanza las bolsas más lejos.",
		"costs": [100, 700, 3000, 8000], "values": [8.0, 11.0, 14.5, 18.5, 23.0], "fmt": "fuerza %.0f"},
	"bag_carry": {"cat": "bag", "name": "Espalda fuerte", "desc": "Camina más rápido cargando bolsas.",
		"costs": [150, 1200, 5000], "values": [0.7, 0.82, 0.92, 1.0], "fmt": "pct"},
	"leaf_value": {"cat": "bag", "name": "Compost premium", "desc": "Multiplica el dinero que recibes por cada hoja.",
		"costs": [350, 1800, 7000, 25000, 80000], "values": [1.0, 1.15, 1.25, 1.5, 2.0, 3.0], "fmt": "x%.2f"},
	"tool_rake": {"cat": "rake", "name": "Rastrillo", "desc": "Arrastra muchas hojas a la vez y crea montones.",
		"costs": [250], "values": [0, 1], "fmt": "tool"},
	"rake_width": {"cat": "rake", "name": "Cabezal ancho", "desc": "Zona de barrido más ancha.", "requires": "tool_rake",
		"costs": [300, 900, 2500, 7000], "values": [1.8, 2.4, 3.0, 3.6, 4.2], "fmt": "%.1f m"},
	"rake_capacity": {"cat": "rake", "name": "Púas resistentes", "desc": "Cuántas hojas puede arrastrar a la vez.", "requires": "tool_rake",
		"costs": [400, 1200, 3500, 9000], "values": [60, 140, 300, 600, 1100], "fmt": "%d hojas"},
	"rake_speed": {"cat": "rake", "name": "Barrido ágil", "desc": "Barre y camina más rápido con el rastrillo.", "requires": "tool_rake",
		"costs": [250, 1500, 5000], "values": [1.0, 1.15, 1.3, 1.5], "fmt": "x%.2f"},
	"rake_grip": {"cat": "rake", "name": "Adherencia", "desc": "Menos hojas se escapan entre las púas.", "requires": "tool_rake",
		"costs": [350, 1800, 6000], "values": [0.88, 0.93, 0.97, 1.0], "fmt": "pct"},
	"rake_reach": {"cat": "rake", "name": "Mango largo", "desc": "Alcance del rastrillo.", "requires": "tool_rake",
		"costs": [300, 1400, 4500], "values": [1.6, 1.9, 2.2, 2.6], "fmt": "%.1f m"},
	"tool_blower": {"cat": "blower", "name": "Soplador", "desc": "Un cono de aire que levanta y arrastra hojas.", "requires_zone": "jardin_delantero",
		"costs": [2500], "values": [0, 1], "fmt": "tool"},
	"blower_power": {"cat": "blower", "name": "Turbina", "desc": "Más fuerza de empuje.", "requires": "tool_blower",
		"costs": [1500, 4000, 10000, 25000], "values": [7.0, 10.0, 14.0, 19.0, 26.0], "fmt": "%.0f N"},
	"blower_range": {"cat": "blower", "name": "Boquilla larga", "desc": "Mayor distancia de soplado.", "requires": "tool_blower",
		"costs": [1200, 3500, 9000], "values": [4.5, 6.0, 8.0, 10.5], "fmt": "%.1f m"},
	"blower_width": {"cat": "blower", "name": "Difusor", "desc": "Cono de aire más ancho.", "requires": "tool_blower",
		"costs": [1000, 3000, 8000], "values": [16.0, 22.0, 29.0, 36.0], "fmt": "%.0f°"},
	"blower_stability": {"cat": "blower", "name": "Estabilizador", "desc": "Chorro más uniforme y controlado.", "requires": "tool_blower",
		"costs": [900, 2500, 7000], "values": [0.5, 0.7, 0.85, 1.0], "fmt": "pct"},
	"tool_industrial": {"cat": "blower", "name": "Soplador industrial", "desc": "Mueve cientos de hojas de golpe.", "requires_zone": "jardin_trasero",
		"costs": [70000], "values": [0, 1], "fmt": "tool"},
	"industrial_power": {"cat": "blower", "name": "Turbina doble", "desc": "Potencia del soplador industrial.", "requires": "tool_industrial",
		"costs": [40000, 90000], "values": [1.0, 1.4, 1.9], "fmt": "x%.1f"},
	"tool_vacuum": {"cat": "vacuum", "name": "Aspiradora de hojas", "desc": "Absorbe hojas y las mete directamente en la bolsa.", "requires_zone": "patio_principal",
		"costs": [15000], "values": [0, 1], "fmt": "tool"},
	"vacuum_radius": {"cat": "vacuum", "name": "Boca ancha", "desc": "Radio de succión.", "requires": "tool_vacuum",
		"costs": [6000, 15000, 35000], "values": [1.6, 2.2, 3.0, 4.0], "fmt": "%.1f m"},
	"vacuum_power": {"cat": "vacuum", "name": "Motor potente", "desc": "Las hojas llegan antes a la boquilla.", "requires": "tool_vacuum",
		"costs": [5000, 12000, 30000], "values": [5.0, 8.0, 12.0, 17.0], "fmt": "%.0f m/s"},
	"vacuum_capacity": {"cat": "vacuum", "name": "Tubo reforzado", "desc": "Hojas en vuelo simultáneas hacia la boquilla.", "requires": "tool_vacuum",
		"costs": [7000, 18000, 40000], "values": [40, 90, 180, 320], "fmt": "%d"},
	"vacuum_speed": {"cat": "vacuum", "name": "Caudal", "desc": "Hojas absorbidas por segundo.", "requires": "tool_vacuum",
		"costs": [6000, 16000, 38000], "values": [50, 110, 220, 400], "fmt": "%d/s"},
	"move_speed": {"cat": "player", "name": "Botas cómodas", "desc": "Velocidad al caminar.",
		"costs": [200, 1000, 4000, 12000], "values": [4.2, 4.7, 5.2, 5.8, 6.5], "fmt": "%.1f m/s"},
	"sprint": {"cat": "player", "name": "Zancada", "desc": "Velocidad al correr (joystick al máximo).",
		"costs": [300, 1500, 6000], "values": [1.4, 1.6, 1.8, 2.0], "fmt": "x%.1f"},
	"stamina": {"cat": "player", "name": "Resistencia", "desc": "Cuánto tiempo puedes correr.",
		"costs": [250, 1200, 5000], "values": [4.0, 7.0, 12.0, 999.0], "fmt": "stamina"},
	"jump": {"cat": "player", "name": "Salto", "desc": "Salta más alto (ideal para montones).",
		"costs": [150, 900, 4000], "values": [4.6, 5.4, 6.3, 7.4], "fmt": "%.1f"},
	"interact_speed": {"cat": "player", "name": "Manos rápidas", "desc": "Velocidad de interacción y de recogida.",
		"costs": [400, 2500, 8000], "values": [1.0, 1.25, 1.5, 2.0], "fmt": "x%.2f"},
	"duct_radius": {"cat": "auto", "name": "Conductos: alcance", "desc": "Radio de succión de los conductos reparados.",
		"costs": [3000, 9000, 25000], "values": [3.5, 5.0, 6.5, 8.0], "fmt": "%.1f m"},
	"duct_rate": {"cat": "auto", "name": "Conductos: caudal", "desc": "Hojas por segundo de cada conducto.",
		"costs": [3500, 10000, 28000], "values": [10, 20, 40, 80], "fmt": "%d/s"},
	"robot": {"cat": "auto", "name": "Robot Brizna", "desc": "Un robot que barre hojas despacio por la zona donde lo dejes.", "requires_flag": "robot_found",
		"costs": [20000], "values": [0, 1], "fmt": "tool"},
	"robot_speed": {"cat": "auto", "name": "Brizna turbo", "desc": "El robot recoge más rápido.", "requires": "robot",
		"costs": [20000, 50000], "values": [1.0, 1.6, 2.4], "fmt": "x%.1f"},
}

# Herramientas: orden de la rueda rápida.
const TOOLS := [
	{"id": "hand", "name": "Manos", "unlock": ""},
	{"id": "rake", "name": "Rastrillo", "unlock": "tool_rake"},
	{"id": "blower", "name": "Soplador", "unlock": "tool_blower"},
	{"id": "vacuum", "name": "Aspiradora", "unlock": "tool_vacuum"},
	{"id": "industrial", "name": "Soplador industrial", "unlock": "tool_industrial"},
]

# Conductos de aspiración averiados (automatización).
const DUCTS := [
	{"id": "d_patio", "zone": "patio_principal", "pos": Vector2(-8, 4), "cost": 2500},
	{"id": "d_garaje", "zone": "garaje", "pos": Vector2(28, 16), "cost": 2000},
	{"id": "d_infantil", "zone": "zona_infantil", "pos": Vector2(-28, 36), "cost": 2000},
	{"id": "d_huerto", "zone": "huerto", "pos": Vector2(-28, -18), "cost": 4000},
	{"id": "d_piscina", "zone": "piscina", "pos": Vector2(26, -20), "cost": 5000},
	{"id": "d_trasero", "zone": "jardin_trasero", "pos": Vector2(-10, -32), "cost": 8000},
	{"id": "d_laberinto", "zone": "laberinto", "pos": Vector2(-22, -59), "cost": 12000},
	{"id": "d_invernadero", "zone": "invernadero", "pos": Vector2(56, -30), "cost": 14000},
]

# Coleccionables: postales de Clementina a su robot Brizna.
const POSTCARDS := [
	{"id": "p01", "zone": "entrada", "pos": Vector2(5.5, 59.0), "title": "Me voy unos días",
		"text": "Querido Brizna: me voy unos días a buscar el Arce de Cobre. Riega los geranios y no dejes que las hojas se acumulen. Vuelvo el martes.\n— C."},
	{"id": "p02", "zone": "jardin_delantero", "pos": Vector2(-13.4, 28.2), "title": "Árboles que susurran",
		"text": "Querido Brizna: el martes se ha alargado. En las Islas Brumosas los árboles susurran. Literalmente. Uno me ha pedido la hora."},
	{"id": "p03", "zone": "garaje", "pos": Vector2(35.0, 31.0), "title": "El bidón azul",
		"text": "Brizna: me cuentan que se derramó el Tónico Otoñal. ¿Es verdad que los árboles no paran de soltar hojas? No toques el bidón azul. Ni lo huelas."},
	{"id": "p04", "zone": "zona_infantil", "pos": Vector2(-48.0, 16.0), "title": "Cien otoños",
		"text": "Querido Brizna: un guía jura que el Arce de Cobre florece una vez cada cien otoños. Le he dicho que tengo paciencia. Poca, pero tengo."},
	{"id": "p05", "zone": "huerto", "pos": Vector2(-25.5, 5.5), "title": "El buzón calabaza",
		"text": "Brizna: si el cartero no puede pasar por la entrada, que deje las postales en el buzón del huerto. Sí, el que tiene forma de calabaza."},
	{"id": "p06", "zone": "patio_principal", "pos": Vector2(7.0, -11.0), "title": "La cascada al revés",
		"text": "Querido Brizna: he visto una cascada que sube en lugar de bajar. Me acordé de ti cuando te atascaste en la escalera del sótano."},
	{"id": "p07", "zone": "piscina", "pos": Vector2(46.0, -9.0), "title": "Sobre la piscina",
		"text": "Brizna: la piscina no era para guardar hojas. Pero entiendo que alguien tenía que hacerlo."},
	{"id": "p08", "zone": "jardin_trasero", "pos": Vector2(2.0, -44.0), "title": "¡Lo encontré!",
		"text": "Querido Brizna: ¡el Arce de Cobre existe! Sus hojas no caen: se posan. Me llevo una semilla para curar los árboles de casa."},
	{"id": "p09", "zone": "laberinto", "pos": Vector2(-40.0, -44.0), "title": "Instrucciones del laberinto",
		"text": "Brizna: el laberinto lo diseñé yo, así que si te pierdes es culpa tuya. Pista: siempre a la izquierda, salvo cuando no."},
	{"id": "p10", "zone": "invernadero", "pos": Vector2(38.0, -44.4), "title": "Hablarle bajito",
		"text": "Querido Brizna: planta la semilla en la maceta grande del invernadero. Hablarle bajito ayuda. Cantarle, no."},
	{"id": "p11", "zone": "taller_secreto", "pos": Vector2(84.0, -38.0), "title": "El rastrillo de cobre",
		"text": "Brizna: dejé mi rastrillo de cobre en el taller de abajo. Si alguien restaura la casa, que se lo quede. Se lo habrá ganado."},
	{"id": "p12", "zone": "taller_secreto", "pos": Vector2(76.0, -30.0), "title": "Vuelvo en primavera",
		"text": "Querido Brizna: vuelvo a casa en primavera. Si la finca está limpia, prometo no inventar más tónicos. Probablemente.\n— Clementina"},
]

# Notas de historia ambiental (se leen al interactuar).
const NOTES := [
	{"id": "n_taller", "pos": Vector3(-12.0, 1.1, 48.4), "title": "Tablón del taller",
		"text": "TAREAS DE BRIZNA (escritas por Clementina)\n1. Barrer.\n2. Barrer otra vez.\n3. NO abrir el bidón azul.\n4. Si vuelven a caer hojas, ver punto 1."},
	{"id": "n_cartero", "pos": Vector3(4.2, 1.2, 61.2), "title": "Aviso del cartero",
		"text": "Aviso: no se puede entregar el correo. Motivo: hojas hasta la rodilla. Segundo motivo: un robot me persiguió con una escoba. Muy educado, eso sí."},
]

const ACHIEVEMENTS := [
	{"id": "first_leaf", "name": "Primer puñado", "desc": "Recoge tu primera hoja."},
	{"id": "first_bag", "name": "Bolsa a bolsa", "desc": "Entrega tu primera bolsa."},
	{"id": "leaves_1k", "name": "Mil hojas", "desc": "Recoge 1.000 hojas."},
	{"id": "leaves_10k", "name": "Diez mil", "desc": "Recoge 10.000 hojas."},
	{"id": "leaves_30k", "name": "Alfombra otoñal", "desc": "Recoge 30.000 hojas."},
	{"id": "got_rake", "name": "Púas nuevas", "desc": "Consigue el rastrillo."},
	{"id": "got_blower", "name": "Huracán de bolsillo", "desc": "Consigue el soplador."},
	{"id": "got_vacuum", "name": "Sin dejar rastro", "desc": "Consigue la aspiradora."},
	{"id": "got_industrial", "name": "Fuerza de la naturaleza", "desc": "Consigue el soplador industrial."},
	{"id": "pile_200", "name": "Montoncito", "desc": "Crea un montón de 200 hojas."},
	{"id": "pile_500", "name": "Montañero", "desc": "Crea un montón de 500 hojas."},
	{"id": "pile_jump", "name": "¡Al montón!", "desc": "Salta sobre un montón grande."},
	{"id": "long_throw", "name": "Canasta", "desc": "Lanza una bolsa al contenedor desde 8 m o más."},
	{"id": "zone_100", "name": "Impecable", "desc": "Deja una zona al 100 %."},
	{"id": "zones_5", "name": "Media finca", "desc": "Completa 5 zonas al 100 %."},
	{"id": "zones_10", "name": "Villa restaurada", "desc": "Completa las 10 zonas principales."},
	{"id": "money_10k", "name": "Ahorrador", "desc": "Gana 10.000 $ en total."},
	{"id": "money_100k", "name": "Magnate del compost", "desc": "Gana 100.000 $ en total."},
	{"id": "upgrades_10", "name": "Manitas", "desc": "Compra 10 mejoras."},
	{"id": "upgrades_40", "name": "Taller completo", "desc": "Compra 40 mejoras."},
	{"id": "duct", "name": "Fontanero de hojas", "desc": "Repara un conducto de aspiración."},
	{"id": "postcard_1", "name": "Correo atrasado", "desc": "Encuentra tu primera postal."},
	{"id": "postcards_12", "name": "Coleccionista", "desc": "Encuentra las 12 postales."},
	{"id": "bags_50", "name": "Logística verde", "desc": "Usa 50 bolsas."},
	{"id": "blown_5k", "name": "Viento a favor", "desc": "Sopla 5.000 hojas."},
	{"id": "vacuumed_5k", "name": "Glotona", "desc": "Aspira 5.000 hojas."},
	{"id": "no_blower_zone", "name": "A la antigua", "desc": "Completa una zona sin usar el soplador."},
	{"id": "all_tools", "name": "Caja de herramientas", "desc": "Usa todas las herramientas."},
	{"id": "secret", "name": "Bajo tierra", "desc": "Descubre el taller subterráneo."},
	{"id": "play_hour", "name": "Solo un poco más", "desc": "Juega durante una hora."},
	{"id": "pet_dog", "name": "¿Quién es una buena perrita?", "desc": "Acaricia a Bellota."},
	{"id": "pet_dog_25", "name": "Uña y carne", "desc": "Acaricia a Bellota 25 veces."},
	{"id": "dog_find", "name": "Olfato fino", "desc": "Recoge una postal que Bellota haya olfateado."},
	{"id": "dog_pile", "name": "¡Bellota, no!", "desc": "Mira cómo Bellota se lanza a un montón de hojas."},
]

# Objetivos secundarios con recompensa.
const OBJECTIVES := [
	{"id": "o_collect_200", "name": "Recoge 200 hojas", "stat": "leaves_collected", "target": 200, "reward": 60},
	{"id": "o_bags_5", "name": "Entrega 5 bolsas", "stat": "bags_delivered", "target": 5, "reward": 120},
	{"id": "o_collect_1k", "name": "Recoge 1.000 hojas", "stat": "leaves_collected", "target": 1000, "reward": 250},
	{"id": "o_buy_5", "name": "Compra 5 mejoras", "stat": "upgrades_bought", "target": 5, "reward": 200},
	{"id": "o_pile_150", "name": "Rastrilla un montón de 150 hojas", "stat": "max_pile", "target": 150, "reward": 250},
	{"id": "o_pile_500", "name": "Crea un montón de 500 hojas", "stat": "max_pile", "target": 500, "reward": 600},
	{"id": "o_long_throw", "name": "Lanza una bolsa al contenedor desde lejos", "stat": "long_throws", "target": 1, "reward": 400},
	{"id": "o_zone_100", "name": "Completa una zona al 100 %", "stat": "zones_completed", "target": 1, "reward": 500},
	{"id": "o_no_blower", "name": "Limpia una zona sin usar el soplador", "stat": "zones_no_blower", "target": 1, "reward": 800},
	{"id": "o_collect_10k", "name": "Recoge 10.000 hojas", "stat": "leaves_collected", "target": 10000, "reward": 3000},
	{"id": "o_blow_2k", "name": "Sopla 2.000 hojas", "stat": "leaves_blown", "target": 2000, "reward": 1500},
	{"id": "o_ducts", "name": "Repara todos los conductos", "stat": "ducts_repaired", "target": 8, "reward": 8000},
	{"id": "o_all_tools", "name": "Usa todas las herramientas", "stat": "tools_used", "target": 5, "reward": 5000},
	{"id": "o_postcards", "name": "Encuentra todas las postales", "stat": "postcards", "target": 12, "reward": 12000},
	{"id": "o_zones_10", "name": "Restaura toda la finca", "stat": "zones_completed", "target": 10, "reward": 50000},
]

# Bellota, la perrita compañera (diseño original de Villa Hojarasca).
const COMPANION := {
	"name": "Bellota",
	"follow_dist": 2.6,        # distancia cómoda detrás/al lado del jugador (m)
	"start_follow": 4.6,       # a partir de aquí echa a andar tras el jugador
	"teleport_dist": 24.0,     # si se queda muy atrás, aparece junto al jugador (fuera de cámara)
	"walk_speed": 2.4,
	"run_speed": 7.2,
	"pile_min_height": 0.4,    # altura mínima (m) de un montón para lanzarse dentro
	"pile_search": 11.0,       # radio de búsqueda de montones alrededor del jugador
	"pile_cooldown": [40.0, 80.0],
	"sniff_radius": 13.0,      # olfatea postales escondidas a esta distancia del jugador
	"sniff_cooldown": 75.0,
	"pet_cooldown": 0.9,
}

# Guías del HUD (marcadores en pantalla).
const GUIDES := {
	"bin_hide_dist": 2.6,
	"gate_hide_dist": 3.2,
	"loose_bag_dist": 28.0,
	"upgrade_toast_cooldown": 150.0,
}

static func zone_by_id(id: String) -> Dictionary:
	for z in ZONES:
		if z["id"] == id:
			return z
	return {}


static func zone_index(id: String) -> int:
	for i in ZONES.size():
		if ZONES[i]["id"] == id:
			return i
	return -1


static func gate_by_id(id: String) -> Dictionary:
	for g in GATES:
		if g["id"] == id:
			return g
	return {}
