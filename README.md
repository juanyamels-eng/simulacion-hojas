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
