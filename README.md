# Villa Hojarasca

Juego 3D original de limpieza de hojas en primera persona para **Android** (apaisado, controles táctiles).
Llegas a una finca abandonada en pleno otoño, enterrada bajo decenas de miles de hojas. Recoge, rastrilla,
sopla y aspira; llena bolsas, recíclalas, cobra, mejora tus herramientas y restaura la finca zona a zona
mientras descubres, postal a postal, por qué su dueña se marchó.

- Motor: **Godot 4.5.1** (renderizado *Compatibility* / OpenGL ES 3, ideal para gama media).
- Todo el contenido (modelos, texturas, sonidos, música, iconos) se genera por código: ver `ASSET_CREDITS.md`.

## Qué incluye

- **Sistema de hojas** de ~42.000 hojas: datos compactos, rejilla espacial, física solo para las hojas activas,
  instanciado por GPU por bloques con LOD y distancia de dibujado, y **montones** que crecen en tamaño y altura.
- **Herramientas**: manos (6 niveles), rastrillo, soplador, aspiradora y soplador industrial, con mejoras que se notan.
- **Bolsas** con física: cerrar, coger, lanzar y entregar en contenedores de reciclaje.
- **10 zonas** interconectadas + taller subterráneo secreto, puertas de pago, recompensas al 25/50/75/100 %,
  transformación visual (el césped reverdece, aparecen flores, desaparecen ramas).
- **Economía y mejoras**: 33 mejoras en 7 categorías, multiplicadores de valor, conductos de aspiración automáticos.
- **Diario**: mapa, objetivos, mejoras, colección (12 postales), estadísticas y 34 logros locales.
- **Modos**: Campaña, Zen, Contrarreloj y Nueva partida+.
- **Aspecto**: cielo pintado con nubes, luz cálida y sombras frías, niebla atmosférica, gradación de color,
  sombreado estilizado para todo el atrezo, follaje con viento, césped real que reaparece al limpiar,
  caminos de losas, hojas con 4 siluetas y nervios, árboles de 4 especies y mucha decoración por zona.
- **Vida**: Bellota (una perrita que te acompaña, salta en los montones y se deja acariciar), pájaros,
  motas de luz y luciérnagas, humo de chimenea, farolas y ventanas que se encienden al atardecer.
- **Guías**: indicadores en pantalla hacia el contenedor y la siguiente puerta, aviso de «mejora disponible»,
  contador «+N» al recoger, celebración al completar una zona y radar de las últimas 40 hojas.
- Ciclo amanecer → mañana → tarde → atardecer → crepúsculo, viento, ráfagas, hojas cayendo y llovizna tras completar la campaña.
- Guardado automático con escritura atómica, verificación y copia de seguridad; guardado al pausar/minimizar.
- Calidad gráfica Baja/Media/Alta/Automática (ajusta hojas activas, sombras, resolución y distancia).

## Estructura

```
scripts/autoload/   gestores globales (economía, mejoras, zonas, guardado, audio, haptics, rendimiento…)
scripts/leaves/     LeafManager, LeafSimulationSystem, LeafClusterSystem
scripts/player/     PlayerController, CameraController, BagSystem, InputState
scripts/tools/      HandTool, RakeTool, BlowerTool, VacuumTool, IndustrialBlowerTool, ToolManager
scripts/world/      World, Terrain, WorldBuilder, interactivos (contenedor, puertas, conductos…)
scripts/ui/         UIManager, HUD, TouchInputManager, menús, diario, tienda, ajustes
shaders/            hojas, suelo, césped, cielo, atrezo (prop) y follaje
tools/              generadores de audio/icono y scripts de compilación
tests/              pruebas automáticas de juego y capturas
```

## Compilar el APK

```bash
./tools/build_apk.sh          # debug + release en build/
./tools/build_apk.sh debug    # solo debug
```

El script descarga Godot y sus plantillas Android si faltan, y firma con `apksigner`.
La clave de release se crea en `keys/release.keystore` (no se sube al repositorio: **guárdala**,
la necesitarás para publicar actualizaciones).

## Pruebas

```bash
godot --headless --fixed-fps 60 res://tests/test_runner.tscn   # 72 comprobaciones de juego
godot --headless --fixed-fps 60 res://tests/playtest_bot.tscn  # un bot juega 25 min solo con los controles
                                                               # (BOT_PROFILE=casual, BOT_MINUTES=N, BOT_RAKE=0)
xvfb-run godot --rendering-driver opengl3 res://tests/screenshots.tscn   # capturas de QA visual
# Capturas por área: tests/shots_atmosphere.tscn, shots_props.tscn, shots_ground.tscn, shots_gameplay.tscn
```

## Controles

- Joystick izquierdo: caminar (al máximo hacia delante: correr).
- Arrastrar a la derecha: mirar.
- Botón grande: usar herramienta (con una bolsa en la mano: lanzarla).
- Botón superior: interactuar (mantener para cerrar la bolsa).
- Flecha: saltar. Botón circular: cambiar herramienta (mantener: rueda rápida).

## Investigación: *Leaf It Alone* (referencia de diseño)

Resumen de la investigación hecha el 14-oct-2026 sobre el juego que inspira el concepto. **Solo tomamos ideas generales**:
nada de su nombre, mapa, distribución, interfaz, modelos, texturas, sonidos ni historia.
Nota de método: las páginas se leyeron a través de buscadores (la descarga directa de webs falló en la nube), así que las cifras son
instantáneas y de confianza media; donde las fuentes no coincidían se indica.

### Ficha
- Estudio: **Eternity** (equipo indie de 4 personas, probablemente polaco; no confirmado oficialmente). Motor Unity 6.
- Salida: 30-oct-2025 en Steam (Windows + Steam Deck verificado). **No tiene versión móvil.** 5,99 US$.
- Reseñas: «Extremadamente positivas», ~95-97 % de ~4.400-6.800 reseñas. Duración: **2-3 horas** (una sola finca).
- Requisitos mínimos de PC con GTX 960: la física de las hojas se simula en la GPU y es su principal cuello de botella.
- Actualización 1.1 anunciada para el 30-oct-2026: mapas nuevos, Nueva partida+ y modo personalizado, reasignar controles y optimización.

### Cómo funciona
- **Bucle**: recoges hojas a mano → las metes en bolsas → las tiras al contenedor (o a conductos automáticos) → cobras → compras
  herramientas y mejoras → limpias más rápido. Lo que engancha no es «terminar», sino **ir cada vez más rápido**.
- **Hojas**: cada hoja es un objeto individual con física (el tráiler habla de más de 100.000). Se mueven «como confeti», se forman montones
  y puedes saltar dentro. La transformación del jardín se ve: el progreso es físico, no un número en un menú.
- **Herramientas**:
  - **Mano**: mantener pulsado y barrer con la vista; las mejoras dan más hojas por agarrón y menos espera.
  - **Rastrillo**: arrastra las hojas *hacia ti* para hacer montones; sube de anchura y gana un tirón «pegajoso». Es útil en esquinas y bordes.
  - **Soplador**: rápido en zonas abiertas pero difícil de apuntar, con mejoras de potencia **y** de precisión. Su sonido de motor
    de dos tiempos («po-po-po») se cita como gran fuente de satisfacción.
  - No hay aspiradora de jugador: ese papel lo cumplen tomas de aire fijas.
- **Bolsas** físicas (pequeña, mediana y grande) que se atan y se lanzan; encestarlas desde lejos es un juego en sí.
- **Una finca dividida en ~13 áreas**, cada una con su %. Al 50 % o al 100 % dan premios: abren la siguiente área, dan una habilidad
  (atar bolsas, correr, agacharse), +velocidad o +0,25× al valor de las hojas. Con eso una finca pequeña parece un «metroidvania» suave.
- **Automatización**: 8 tomas de aire rotas que se reparan pagando (de 0 a 25 $) y aspiran solas.
- Extras: 8 fotos ocultas, juguetes con física (balones), 18 logros, un diario con mapa, mejoras y objetivos, y un cuarto secreto como final.

### Qué gusta a los jugadores
1. La escalera de herramientas: cada herramienta nueva hace que la anterior parezca lenta.
2. Ritmo sin «grind»: compras algo cada pocos minutos.
3. Ambiente acogedor y relajante, con progreso visible.
4. Física de las hojas (vuelan, se amontonan, saltar en montones).
5. Sonido: el soplador y el crujido de las hojas.
6. Pequeños descubrimientos: fotos, lanzar bolsas, juguetes.

### Qué critican
1. **Muy corto y un solo mapa** (la queja dominante, incluso en reseñas positivas).
2. **Buscar la última hoja al 99,9 %**: hojas escondidas en superficies grises o atravesando el suelo o paredes. Piden un localizador o
   reiniciar la zona; ellos añadieron un filtro para resaltar las hojas.
3. Rendimiento con muchas hojas en movimiento (sobre todo con el soplador y en montones enormes).
4. Logro de terminar en menos de 40 minutos: choca con el tono relajado.
5. Sin música durante el juego (solo pájaros), sin reasignar controles y el rastrillo flojo al principio.

### Lecciones que aplicamos (a nuestra manera)
- Hojas **individuales, bonitas y legibles** sobre cualquier superficie: colores cálidos y saturados sobre un suelo más apagado, sin
  «manchas» ni montañas de terreno. Los montones son pilas de hojas sueltas.
- Cada herramienta con su papel:
  - mano: precisión;
  - rastrillo: amontonar hacia ti, esquinas;
  - soplador: espacios abiertos, con mejoras de precisión.
  Que la herramienta barata siga siendo útil más adelante.
- **Premios por zona que cambian cómo juegas** (habilidades), mostrados en el HUD y en el mapa.
- **Última hoja resuelta desde el principio**: contador «quedan N», resaltado de las últimas, ayuda para encontrarlas y ninguna hoja
  inalcanzable (recolocar las que caen dentro de objetos).
- Rendimiento por presupuesto: solo se simulan las hojas cercanas o activas, las quietas duermen y la cantidad depende del nivel de calidad.
- Sonido con personalidad (motor del soplador, crujidos) y música opcional y propia.
- Más contenido que su versión 1.0: modos Zen, Contrarreloj y Nueva partida+; el contrarreloj siempre es opcional y con temporizador visible.

### Móvil y juegos parecidos
- *PowerWash Simulator*:
  - «Mostrar suciedad» y lista de partes con %; el «ding» y el destello al completar cada parte son su pilar.
  - El 1 % final también es su queja principal.
  - En móvil: HUD ocultable y un modo de limpiar tocando con el dedo.
- *Leaf Blower Revolution* (inactivo, en móvil): bucle fuerte, pero lo critican por el «grind» creciente. Mejor pocas mejoras con
  precios ajustados a mano que curvas exponenciales.
- Controles táctiles (Apple HIG):
  - joystick flotante a la izquierda y arrastrar para mirar a la derecha;
  - botones de al menos 44 pt con iconos, brillo al pulsar, sonido y vibración;
  - mantener pulsado mejor que tocar repetidamente.
- Vibración:
  - pulsos cortos de 10-20 ms y suaves en eventos frecuentes, nunca un zumbido continuo;
  - en Godot pasar siempre duración y amplitud (por defecto vibra 500 ms);
  - opción para desactivarla.
- Batería y temperatura: 30 FPS por defecto en gama media/baja (con 60 opcional) y bajar FPS en menús. Bajar la calidad poco a poco si el
  móvil se calienta y probar sesiones de más de 15 minutos en un móvil real.

### Fuentes principales
- Steam: https://store.steampowered.com/app/3981100/Leaf_it_Alone/ · reseñas y foros: https://steamcommunity.com/app/3981100/discussions/
- Guías: https://steamcommunity.com/sharedfiles/filedetails/?id=3599824281 · https://steamcommunity.com/sharedfiles/filedetails/?id=3647922909
- PCGamingWiki: https://www.pcgamingwiki.com/wiki/Leaf_it_Alone · MobyGames: https://www.mobygames.com/game/249919/leaf-it-alone/
- Reseñas: https://www.yomiqo.com/en/leaf-it-alone-review/ · https://playwanderer.online/game-reviews/leaf-it-alone ·
  https://lillycorner.com/2025/10/30/leaf-it-alone/ · https://automaton-media.com/articles/newsjp/leaf-it-alone-20251106-364933/
- Devlogs 1.1: https://store.steampowered.com/news/app/3981100/view/668364177007445257 ·
  https://store.steampowered.com/news/app/3981100/view/708903548824322441
- Móvil: https://developer.apple.com/design/human-interface-guidelines/game-controls ·
  https://developer.android.com/develop/ui/views/haptics/haptics-principles · https://developer.android.com/games/optimize/adpf/thermal

## Para la próxima sesión

Opinión del jugador tras probar la 0.2.0 en su móvil:
- le gustan las zonas;
- las hojas deben ser individuales y muchas, sin «montañas», y que se vea cuál agarras;
- el mapa debe ser más grande y bonito, con una casa grande;
- las herramientas deben estar mejor inspiradas.

Prioridades:
1. **(P0, en curso)** Hojas individuales y bonitas, montones hechos de hojas y resaltado de las hojas que vas a agarrar.
2. **(P0, en curso)** Finca nueva más grande alrededor de una casa grande de dos plantas, sin cuadrícula de rectángulos.
3. **(P0, en curso)** Herramientas: modelos nuevos (guantes, rastrillo, soplador de dos tiempos), mano «mantener y barrer», rastrillo que
   amontona hacia ti, soplador tipo confeti y su sonido.
4. **(P1)** Habilidades al completar cada zona: viaje rápido, bolsa que se cierra sola, olfato de Bellota, radar ampliado. Más «Quedan N
   hojas» y que ninguna hoja inalcanzable impida el 100 %.
5. **(P1)** Juguetes con física (balones, calabazas, bolos) y minirretos opcionales.
6. **(P1)** Probar en un móvil real (FPS, temperatura, batería). Modo 30 FPS por defecto en gama baja, vibraciones cortas, opciones de
   comodidad (movimiento de cabeza, sensibilidad) y HUD ocultable.
7. **(P2)** Más contenido para que no sea «corto y de un mapa»: retos cortos, segunda finca y Nueva partida+ con opciones.
8. **Originalidad**: varias de nuestras zonas (garaje, columpios, piscina, laberinto, invernadero, cuarto secreto) y los conductos
   reparables se parecen en concepto a las suyas porque venían en el encargo inicial. Mantener nombres, distribución, historia y aspecto
   propios; no copiar su filtro naranja ni su lista de áreas.
