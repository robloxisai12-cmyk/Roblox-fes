# Sierra de Guardia

Simulador táctico cooperativo original ambientado en una región ficticia de la sierra mexicana. Escuadrones coordinan patrullas, logística y objetivos en un mundo amplio generado por código, con ritmo deliberado y decisiones de combate server-authoritative. La ambientación es propia: no replica mapas, nombres, armas, marcas ni assets de otros juegos.

## Fases

1. **Base técnica:** Rojo 7.7.0 fijado, estructura server/client/shared y arranques mínimos. Entrega: proyecto compilable desde archivos.
2. **Jugadores y datos:** sesiones de servidor con valores predeterminados, snapshots de solo lectura y limpieza al salir. No se usa persistencia en esta fase.
3. **Escuadrones y mando:** compañías, escuadrones, rangos y roles con permisos del servidor. Entrega: organización funcional.
4. **Mundo generado:** disposición procedural determinista y constructor server-side de terreno, pueblo, caminos, vegetación y spawns. Entrega: primer mapa jugable construido por código.
5. **Inventario y combate:** equipo, munición, disparo, retroceso y daño calculados en servidor. Entrega: combate básico validado.
6. **Heridas y medicina:** estados de lesión, tratamiento y límites para el rol médico. Entrega: recuperación que requiere cooperación.
7. **Logística y vehículos:** suministros, reabastecimiento y vehículos ligeros con autoridad del servidor. Entrega: movilidad y sostenimiento iniciales.
8. **Radio:** canales de escuadrón y mando con permisos y alcance definidos. Entrega: comunicación de equipo.
9. **Objetivos y partidas:** captura, fases de misión y condiciones de victoria. Entrega: ciclo de partida completo.
10. **Interfaz y controles:** HUD, interacción táctil y controles para PC. Entrega: flujos utilizables en ambos formatos.
11. **Pruebas y rendimiento:** pruebas de exploits de cliente, carga, red y dispositivos móviles. Entrega: criterios de aceptación y ajustes antes de distribuir.

## Estructura prevista

```text
src/
	client/                 # Arranque y controladores de entrada/interfaz
	server/
		services/             # Servicios autoritativos
	shared/
		config/               # Defaults compartidos, no autoridad del servidor
scripts/
	check-phase2.mjs        # Comprobación reproducible del sourcemap y remoto
tests/
	phase3.test.luau        # Pruebas Luau del registry, permisos y payloads
	phase4.test.luau        # Pruebas Luau de semilla y layout del mapa
```

Los módulos de servidor se mapean bajo `ServerScriptService.Server`; los compartidos, bajo `ReplicatedStorage.Shared`; y el cliente, bajo `StarterPlayer.StarterPlayerScripts.Client`. Las carpetas futuras se crearán al implementar cada fase.

## Servicios principales previstos

- **Servidor:** PlayerDataService, CompanyService, SquadService, RankService y RankRules; luego MapBuilderService, InventoryService, CombatService, WoundService, MedicalService, LogisticsService, VehicleService, RadioService, ObjectiveService y MatchService.
- **Cliente:** InputController, HUDController y CameraController. Envían intenciones; nunca deciden daño, munición, inventario ni posiciones válidas.
- **Compartido:** constantes y defaults públicos. Los campos sensibles y permisos se crean y conservan en el servidor.

## Fase 1: requisitos y comandos

No necesitas Roblox Studio para generar el proyecto. La compilación de Fase 1 se puede comprobar completamente desde el Codespace. La prueba en ejecución con sincronización en vivo es opcional y sí requiere Studio con el plugin Rojo.

```sh
mkdir -p /tmp/aftman
curl -fsSL https://github.com/LPGhatguy/aftman/releases/download/v0.3.0/aftman-0.3.0-linux-x86_64.zip -o /tmp/aftman/aftman.zip
unzip -oq /tmp/aftman/aftman.zip -d /tmp/aftman
/tmp/aftman/aftman self-install
export PATH="$HOME/.aftman/bin:$PATH"
aftman install
rojo --version
mkdir -p build
rojo build default.project.json --output build/sierradeargueria.rbxlx
```

La compilación genera el lugar en `build/`. Si más adelante tienes acceso a Studio, `rojo serve default.project.json` permite probar la sincronización desde el plugin. No se publica nada.

## Fase 2: jugadores y datos de sesión

`PlayerDataService` crea sesiones al entrar, también recoge jugadores que ya estuvieran conectados al iniciar el servicio y elimina los datos al salir. `GetSession` devuelve una copia defensiva; no hay una API cliente para cambiar rango, rol, inventario o permisos. Los datos viven solo en memoria y todavía no usan DataStore.

Comprueba la versión y el mapeo de módulos con:

```sh
node scripts/check-phase2.mjs
rojo build default.project.json --output build/sierradeargueria.rbxlx
```

La comprobación de Node valida versión, destinos del sourcemap y el único remoto permitido de la Fase 3; no sustituye una prueba de ejecución en Roblox Studio.

## Fase 3: escuadrones, compañías y rangos

`SquadService` expone solo `SquadRequest`, un `RemoteFunction` con acciones `list`, `create`, `join`, `leave`, `disband` y `setRole`. El servidor obtiene identidad y permisos del `Player` y la sesión; rechaza campos extra, roles no asignables, IDs mal formados y solicitudes excedidas por rate limit. Los IDs recibidos se resuelven contra el registry del servidor y no conceden autoridad por sí mismos.

Los rangos (`Recruit`, `Private`, `Corporal`, `Sergeant`, `Commander`) y permisos están en módulos exclusivos de `ServerScriptService`. Los roles de miembro son fusilero (`Rifleman`), médico (`Medic`) e ingeniero (`Engineer`); el creador recibe líder de escuadrón (`SquadLeader`) y el rango Commander obtiene el rol Commander. Compañías, límite de ocho escuadrones por compañía y ocho miembros por escuadrón están configurados en `OrganizationConfig`. No hay persistencia.

Para repetir la suite del registry con Luau 0.743 en Linux x86_64:

```sh
mkdir -p /tmp/luau
curl -fsSL https://github.com/luau-lang/luau/releases/download/0.743/luau-ubuntu.zip -o /tmp/luau/luau.zip
unzip -oq /tmp/luau/luau.zip -d /tmp/luau
/tmp/luau/luau tests/phase3.test.luau
node scripts/check-phase2.mjs
rojo build default.project.json --output build/sierradeargueria.rbxlx
```

La suite prueba permisos, duplicados, límites de compañía y miembros, transferencia del liderazgo, disolución y solicitudes inválidas. La capa que depende del motor Roblox requiere además prueba en Studio; este proyecto no publica automáticamente.

## Fase 4: mapa procedural

`MapConfig` contiene la semilla `4202026`, dimensiones de 1280 x 1280 studs, alturas, densidad vegetal, caminos, distribución del pueblo y posiciones de aparición. `MapLayoutGenerator` valida esos datos y produce colinas, caminos, casas y árboles usando un PRNG determinista. `MapGenerationService` consume el layout en el servidor y construye terreno Roblox nativo, tramos de camino, piezas para el pueblo, vegetación ligera y `SpawnLocation` dentro de una zona marcada como segura. Genera al arrancar una vez; no se regenera con cada jugador. No usa modelos ni assets externos.

El mapa cubre **1280 x 1280 studs** (1.638.400 studs cuadrados), con 20 colinas y montañas, 3 caminos conectados, 8 construcciones, 122 árboles y 4 puntos de aparición con la semilla actual. El cálculo da aproximadamente **563 instancias**: 88 segmentos de camino, 96 instancias de casas (11 piezas y una carpeta por casa), 244 instancias de vegetación y carpetas/spawns. La base de Terrain abarca aproximadamente 409.600 celdas de 4 studs (4 capas verticales), antes de sumar el volumen de las colinas. Es un presupuesto geométrico, no una medición de memoria o FPS. El aspecto, las colisiones del motor, el terreno y el comportamiento de spawns deben verificarse dentro de Roblox Studio. La zona de aparición queda marcada para sistemas futuros; todavía no existe lógica de combate que aplique protección dentro de ella.

En Linux x86_64, con Rojo 7.7.0 y el runner Luau 0.743 instalado en `/tmp/luau`:

```sh
/tmp/luau/luau tests/phase3.test.luau
/tmp/luau/luau tests/phase4.test.luau
/tmp/luau/luau-analyze src/server/services/MapLayoutGenerator.luau src/shared/config/MapConfig.luau
node scripts/check-phase2.mjs
rojo build default.project.json --output build/sierradeargueria.rbxlx
```

Los tests de layout comprueban reproducibilidad por semilla, cambio con otra semilla, presupuesto del terreno, límites, pendiente/continuidad de caminos, separación de edificios/árboles y superficie/obstáculos de spawns con geometría calculada. El build crea el archivo `.rbxlx`, pero no ejecuta el script de Roblox ni valida visualmente el mundo. En Studio se debe comprobar `Workspace.SierraDeGuardiaMap`, la superficie física de `SpawnLocation` y el resultado visual/colisiones de Terrain; estas verificaciones no se simulan en la suite Luau.