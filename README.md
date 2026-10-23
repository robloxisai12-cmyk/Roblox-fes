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
11. **Pruebas y rendimiento:** reglas puras, comprobaciones de integración estática y ajustes conservadores; carga, red y dispositivos quedan pendientes de Roblox Studio.

## Estructura prevista

```text
src/
	client/                 # Arranque y controladores de entrada/interfaz
	server/
		services/             # Servicios autoritativos
	shared/
		config/               # Defaults compartidos, no autoridad del servidor
scripts/
	check-phase2.mjs        # Comprobación reproducible del sourcemap y remotos
tests/
	phase3.test.luau        # Pruebas Luau del registry, permisos y payloads
	phase4.test.luau        # Pruebas Luau de semilla y layout del mapa
	phase5.test.luau        # Pruebas puras de inventario y reglas de combate
	phase6.test.luau        # Pruebas puras de heridas, tratamiento e incapacitación
	phase7.test.luau        # Pruebas puras de logística, combustible y vehículos
	phase8.test.luau        # Pruebas puras de canales, mensajes, alcance y límites
	phase9.test.luau        # Pruebas puras de partidas, objetivos, tiempos y reinicio
	phase10.test.luau       # Pruebas puras de escalado y presentación del HUD
	phase11.test.luau       # Pruebas de integración para validadores y configuraciones puras
```

Los módulos de servidor se mapean bajo `ServerScriptService.Server`; los compartidos, bajo `ReplicatedStorage.Shared`; y el cliente, bajo `StarterPlayer.StarterPlayerScripts.Client`. Las carpetas futuras se crearán al implementar cada fase.

## Servicios principales previstos

- **Servidor:** PlayerDataService, CompanyService, SquadService, RankService y RankRules; MapGenerationService, InventoryService, CombatService, MedicalService, LogisticsService, RadioService y MatchService.
- **Cliente:** CombatController, MedicalController, LogisticsController, RadioController, MissionController y TacticalHUD. Envían intenciones; nunca deciden daño, munición, inventario, canales autorizados, progreso ni posiciones válidas.
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
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

La compilación genera el lugar en `build/`. Si más adelante tienes acceso a Studio, `rojo serve default.project.json` permite probar la sincronización desde el plugin. No se publica nada.

## Fase 2: jugadores y datos de sesión

`PlayerDataService` crea sesiones al entrar, también recoge jugadores que ya estuvieran conectados al iniciar el servicio y elimina los datos al salir. `GetSession` devuelve una copia defensiva; no hay una API cliente para cambiar rango, rol, inventario o permisos. Los datos viven solo en memoria y todavía no usan DataStore.

Comprueba la versión y el mapeo de módulos con:

```sh
node scripts/check-phase2.mjs
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

La comprobación de Node valida versión, destinos del sourcemap y los remotos declarados para las fases implementadas; no sustituye una prueba de ejecución en Roblox Studio.

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
rojo build default.project.json --output build/sierradeguardia.rbxlx
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
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

Los tests de layout comprueban reproducibilidad por semilla, cambio con otra semilla, presupuesto del terreno, límites, pendiente/continuidad de caminos, separación de edificios/árboles y superficie/obstáculos de spawns con geometría calculada. El build crea el archivo `.rbxlx`, pero no ejecuta el script de Roblox ni valida visualmente el mundo. En Studio se debe comprobar `Workspace.SierraDeGuardiaMap`, la superficie física de `SpawnLocation` y el resultado visual/colisiones de Terrain; estas verificaciones no se simulan en la suite Luau.

## Fase 5: inventario y combate

`InventoryConfig` define el equipo permitido (`Rifle` y `Sidearm`), cargadores y reservas iniciales, cadencia, daño, alcance, duración de recarga y retroceso. `InventoryService` crea un inventario independiente al entrar el jugador, devuelve copias defensivas, solo equipa IDs de configuración y elimina inventario y conexiones al salir. El estado permanece en memoria; no se usa DataStore.

`CombatService` recibe las intenciones por el único remoto nuevo, `CombatRequest` (`RemoteEvent`); `SquadRequest` permanece sin cambios. El cliente solicita `shoot` con una dirección unitaria de cámara, `reload` o `equip`. El servidor valida forma y frecuencia, verifica personaje vivo, arma equipada, cargador, cadencia y dirección, consume una bala y realiza un raycast desde la cabeza del atacante con el alcance configurado. El primer impacto es decisivo: un obstáculo bloquea el tiro, la ausencia de impacto es un fallo, y solo un modelo distinto con `Humanoid` vivo y `HumanoidRootPart` puede recibir daño; el servidor calcula el daño y llama una vez a `TakeDamage`. Disparos fuera de cadencia, payloads inválidos, falta de munición o atacante muerto se rechazan sin cambiar munición/cadencia. Los fallos válidos al disparar (sin impacto, obstáculo u objetivo no válido) sí consumen una bala, pero no aplican daño. No se confía en daño, punto de impacto, objetivo ni raycast del cliente.

Las recargas se limitan al cargador y reserva configurados, se impiden mientras otra recarga está pendiente y se invalidan al morir, reaparecer o abandonar el jugador. El servidor completa el temporizador y la transferencia. En la entrega de esta fase, el controlador mínimo usaba clic/toque para disparar, `R`/botón táctil para recargar y `1`/`2` (o botones táctiles) para elegir arma; aplicaba retroceso de cámara solo tras un disparo aceptado. El HUD de munición se agregó en la Fase 10. La zona segura del mapa todavía no bloquea daño.

La suite de fase 5 prueba las reglas puras y no requiere APIs Roblox:

```sh
/tmp/luau/luau tests/phase3.test.luau
/tmp/luau/luau tests/phase4.test.luau
/tmp/luau/luau tests/phase5.test.luau
/tmp/luau/luau-analyze src/shared/config/InventoryConfig.luau src/server/services/InventoryRules.luau src/server/services/CombatRequestRules.luau src/server/services/CombatRules.luau
node scripts/check-phase2.mjs
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

El análisis estático del comando cubre los módulos Luau puros. El `luau-analyze` independiente no incluye definiciones de tipos del motor Roblox, por lo que no valida los servicios y controladores que usan APIs de Studio. La fase está implementada, pero **no se considera validada completamente hasta probarla en Roblox Studio**. El runner Luau 0.743 y `luau-analyze` deben estar en `/tmp/luau` (el README de Fase 3 describe cómo instalar el paquete oficial en Linux x86_64). En Studio falta comprobar el arranque real y los remotos, cadencia/recarga durante juego, apuntado con cámara, raycast en obstáculos, daño a personajes y NPC válidos, muerte/reaparición y controles táctiles; no se han simulado APIs del motor ni se declara prueba de Studio.

## Fase 6: heridas y medicina

`MedicalService` conserva un estado autoritativo por personaje con salud acotada, heridas, gravedad, sangrado e incapacitación temporal. `MedicalRules` mantiene las reglas puras y valida la configuración compartida de `MedicalConfig`. El daño de armas pasa por `MedicalService.ApplyDamage`; no se instala una conexión `HealthChanged` que replique o duplique el daño nativo. Al alcanzar daño letal, el servidor mantiene al Humanoid en 1 de salud, bloquea movimiento y marca `SierraIncapacitated`; el sangrado se procesa en una tarea por personaje solo mientras haya sangrado o incapacitación, y al vencer el plazo el servidor establece la muerte.

El inventario existente ahora incluye consumibles médicos junto a las armas, en vez de mantener una bolsa paralela. Cada jugador comienza con tres vendajes, un botiquín y un kit de emergencia. El vendaje trata heridas leves y el botiquín puede curar hasta 35 puntos y tratar heridas hasta gravedad severa, sin superar `Humanoid.MaxHealth`. El kit de emergencia reanima a un aliado incapacitado con 35 de salud después de cuatro segundos. El médico debe tener el rol `Medic` para tratar a otros jugadores; cualquier jugador puede tratarse a sí mismo. Los objetos se reservan durante la acción, se consumen solo al completar un tratamiento válido y la reserva se libera al cancelar o interrumpir la acción. Se cancela por muerte, cambio de personaje, salida del alcance o pérdida de disponibilidad del estado. Las solicitudes se validan mediante `CombatRequest` con rate limit y comprobaciones de rol, inventario, vida, objetivo y distancia en el servidor.

`MedicalController` añade un panel compacto sin assets externos, botones táctiles y accesos de teclado (`3`, `4`, `H`) para vendaje, botiquín y ayuda a un aliado cercano; también muestra salud, heridas, sangrado e inventario disponible. La interfaz solo envía solicitudes y presenta el estado recibido. No se implementó daño ambiental ni curación fuera del combate porque no hay otros sistemas de daño/curación en las fases existentes. El inventario y los estados médicos son de sesión y se reinician al salir o reaparecer; no hay persistencia.

Archivos añadidos: `src/shared/config/MedicalConfig.luau`, `src/server/services/MedicalRules.luau`, `src/server/services/MedicalService.luau`, `src/client/MedicalController.client.luau` y `tests/phase6.test.luau`. Integración: `InventoryRules`, `InventoryService`, `CombatRequestRules`, `CombatService`, `Bootstrap.server.luau` y `scripts/check-phase2.mjs`; `default.project.json` conserva el remoto `CombatRequest`, reutilizado para acciones y estados médicos.

Validación automatizada ejecutada en Codespaces:

```sh
/tmp/luau/luau tests/phase3.test.luau
/tmp/luau/luau tests/phase4.test.luau
/tmp/luau/luau tests/phase5.test.luau
/tmp/luau/luau tests/phase6.test.luau
/tmp/luau/luau-analyze src/shared/config/MedicalConfig.luau src/server/services/MedicalRules.luau src/server/services/InventoryRules.luau src/server/services/CombatRequestRules.luau
node scripts/check-phase2.mjs
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

Las pruebas de reglas de Fase 3, 4, 5 y 6 pasaron en esta ejecución: 21 comprobaciones, 12 grupos, 58 comprobaciones y 54 comprobaciones, respectivamente. El análisis estático de los módulos puros terminó sin errores; la comprobación de sourcemap/remotos confirmó Rojo 7.7.0 y el build del lugar finalizó correctamente. Esto no ejecuta los servicios del motor Roblox. La prueba en Studio sigue pendiente para verificar ciclo de vida real de personajes y NPCs, muerte/respawn, colisiones/daño de Humanoid, restauración de movimiento, interacción entre clientes, interrupción de tratamientos, botones táctiles y presentación del HUD en tamaños de pantalla distintos.

## Fase 7: logística y vehículos

`LogisticsService` construye vehículos terrestres sencillos y marcadores de depósito/entrega con piezas nativas de Roblox, sin modelos ni assets externos. Los vehículos tienen asiento, entrada/salida, velocidad de avance y reversa, giro, combustible y capacidad de carga. El servidor valida el rol autorizado (`Engineer`, `SquadLeader` o `Commander`), ocupación, distancia, estado del personaje, obstáculos, combustible y frecuencia de solicitudes; la velocidad y el consumo se calculan allí. El depósito `SierraDepot` y la entrega `ValleyDelivery`, vehículos, recursos, stocks, capacidades y temporizadores están definidos en `LogisticsConfig`. El reabastecimiento por tiempo no excede el máximo configurado.

La carga se lleva en el estado del vehículo y solo puede cargarse desde un depósito cercano y entregarse en un punto autorizado cercano. La entrega parcial conserva en el vehículo lo que exceda la capacidad del destino. El repostaje consume stock del depósito y limita el tanque a su capacidad. `InventoryService` aplica munición, artículos médicos y raciones a los inventarios existentes; no existe un inventario paralelo. La munición se agrega a las reservas de armas existentes y se respetan capacidades. `CombatRequest` existente transporta solicitudes y estados logísticos; no se agregó otro remoto. `LogisticsController` presenta vehículo, combustible, carga, puntos, inventario y botones de interacción para PC y móvil; el servidor vuelve a validar cada acción.

Archivos nuevos: `src/shared/config/LogisticsConfig.luau`, `src/server/services/LogisticsRules.luau`, `src/server/services/VehicleRules.luau`, `src/server/services/LogisticsService.luau`, `src/client/LogisticsController.client.luau` y `tests/phase7.test.luau`. Archivos integrados/modificados: `src/server/services/InventoryRules.luau`, `src/server/services/InventoryService.luau`, `src/server/services/CombatRequestRules.luau`, `src/server/services/CombatService.luau`, `src/server/Bootstrap.server.luau` y `scripts/check-phase2.mjs`. `default.project.json` conserva los remotos previos y Rojo mapea la configuración, servicios y controlador nuevos.

Comprobaciones ejecutadas en Codespaces:

```sh
/tmp/luau/luau tests/phase3.test.luau
/tmp/luau/luau tests/phase4.test.luau
/tmp/luau/luau tests/phase5.test.luau
/tmp/luau/luau tests/phase6.test.luau
/tmp/luau/luau tests/phase7.test.luau
find src tests -type f -name '*.luau' -print0 | xargs -0 -n1 /tmp/luau/luau-compile >/dev/null
/tmp/luau/luau-analyze src/shared/config/LogisticsConfig.luau src/server/services/LogisticsRules.luau src/server/services/VehicleRules.luau src/server/services/InventoryRules.luau src/server/services/CombatRequestRules.luau
node scripts/check-phase2.mjs
git diff --check
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

En la validación de fases 3–7 pasaron 21 comprobaciones, 12 grupos, 58, 54 y 50 comprobaciones, respectivamente. El análisis se limita a módulos puros; el build de Rojo no ejecuta servicios del motor Roblox. Para las fases anteriores, Roblox Studio aún debe validar la conducción, colisiones, spawns y controles táctiles. No se ha publicado el juego ni se han creado commits o pushes.

## Fase 8: radio y comunicaciones tácticas

`RadioConfig` configura el canal general, el alcance de cada tipo de canal, el límite de bytes por mensaje y los límites de solicitudes/transmisiones. Cada escuadrón registrado obtiene su canal dinámico `squad/<id>`; `SquadService` expone una lectura del registry existente y el servidor solo lo ofrece a los miembros actuales. El canal `general` está disponible para jugadores con radio. Los mensajes solo llegan a jugadores conectados, equipados con radio, autorizados para el canal y dentro del alcance. La señal mostrada se calcula en el servidor según la distancia al enlace autorizado más cercano, con pérdida lineal hasta el límite configurado.

El radio se asigna como equipo `FieldRadio` dentro del estado del `InventoryService` existente; no se crea un inventario ni un objeto/herramienta paralelo. `RadioService` recibe `RadioRequest`, valida la forma y el tamaño del mensaje, resuelve el canal desde la selección guardada por el servidor, aplica límites de frecuencia, comprueba inventario, pertenencia al escuadrón, personaje y distancias, y obtiene el nombre del remitente de la sesión del servidor (no del payload del cliente). El contenido se filtra con `TextService` antes de transmitirse; si el filtrado falla, no se difunde el mensaje. No se almacena historial y un mensaje no se reproduce a jugadores que entren después. El panel `RadioController` permite cambiar entre canales autorizados, leer mensajes, transmitir con botón o Enter y ver señal/alcance en PC y móvil; el estado de señal se actualiza periódicamente. No usa assets externos.

Archivos nuevos: `src/shared/config/RadioConfig.luau`, `src/server/services/RadioRules.luau`, `src/server/services/RadioService.luau`, `src/client/RadioController.client.luau` y `tests/phase8.test.luau`. Integración: `InventoryConfig`, `InventoryRules`, `InventoryService`, `SquadService`, `Bootstrap.server.luau`, `default.project.json` y `scripts/check-phase2.mjs`. `RadioRequest` es el único remoto nuevo para esta fase; `SquadRequest` y `CombatRequest` siguen dedicados a sus sistemas anteriores.

La suite de fase 8 comprueba reglas puras (configuración, validación estricta de solicitudes, longitud, canal de escuadrón, alcance, señal, rate limit y equipo en el inventario). Comandos ejecutados:

```sh
/tmp/luau/luau tests/phase3.test.luau
/tmp/luau/luau tests/phase4.test.luau
/tmp/luau/luau tests/phase5.test.luau
/tmp/luau/luau tests/phase6.test.luau
/tmp/luau/luau tests/phase7.test.luau
/tmp/luau/luau tests/phase8.test.luau
find src tests -type f -name '*.luau' -print0 | xargs -0 -n1 /tmp/luau/luau-compile >/dev/null
/tmp/luau/luau-analyze src/shared/config/InventoryConfig.luau src/shared/config/RadioConfig.luau src/server/services/InventoryRules.luau src/server/services/RadioRules.luau tests/phase8.test.luau
node scripts/check-phase2.mjs
git diff --check
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

En esta entrega pasaron las pruebas de fases 3–8: 21 comprobaciones, 12 grupos, 58, 54, 50 y 32 comprobaciones, respectivamente; todos los archivos Luau pasaron `luau-compile`, el análisis de módulos puros terminó sin errores, el verificador confirmó los tres remotos y el sourcemap, `git diff --check` pasó y el build de Rojo se completó. Roblox Studio sigue siendo necesario para verificar arranque real de servicios/remotos, filtrado de texto en entorno Roblox, entrega entre jugadores, cambios de escuadrón durante una sesión, alcance físico, interfaz táctil y legibilidad en distintos dispositivos. No se afirma que la radio haya sido probada en una partida real.

## Fase 9: objetivos y partidas

`MissionConfig` establece las fases configurables (`waiting`, `preparation`, `active`, `victory`, `defeat`, `ended`), cantidad mínima de jugadores, duraciones, frecuencia de actualización y objetivos secuenciales. La configuración inicial inicia preparación con un jugador, da 15 segundos antes de jugar y limita la partida a 900 segundos. Los jugadores conectados inician una cuenta atrás; si abandonan durante la preparación, esta se cancela. Una partida sin jugadores o que agota su tiempo termina en derrota. Victoria y derrota se muestran durante el tiempo configurado, pasan a limpieza y luego reinician progreso y contribuyentes para la siguiente ronda.

La misión configurada primero requiere asegurar el valle: el servidor cuenta presencia de personajes vivos y no incapacitados dentro de la zona, y el progreso cooperativo aumenta según cuántos jugadores contribuyen (hasta el límite configurado). La posición se toma del personaje replicado y el progreso descarta desplazamientos observados que excedan los límites configurados de movimiento horizontal/vertical; la tolerancia se expresa como velocidad adicional para que no permita el mismo salto de distancia en cada frame. Después se requiere llevar dos unidades de suministros médicos a `ValleyDelivery`. Ese objetivo solo avanza por entregas reales aceptadas por `LogisticsService`; el servicio registra los cambios de stock validados al completar la entrega de carga del vehículo. Las unidades entregadas durante la ronda se consumen al terminarla para que el stock no bloquee rondas posteriores. No se aceptan solicitudes de progreso del cliente. Las ubicaciones se configuran en coordenadas X/Z dentro del mapa actual; al arrancar, el servidor genera marcadores y proyecta las zonas sobre la superficie del mapa.

La integración usa `SquadService` para mostrar los escuadrones que contribuyen a asegurar la zona; el progreso requiere personajes sanos de combate y excluye incapacitados según el estado médico existente, permitiendo que una reanimación médica vuelva a habilitar su contribución. La entrega utiliza las comprobaciones actuales de carga, conductor, vehículo, combustible y punto logístico. `RadioService` remite avisos de mando de la misión a jugadores que tienen el radio existente. `MissionRequest` solo permite pedir una copia de estado: ningún mensaje de cliente inicia la partida, concede progreso ni completa objetivos. Un único `Heartbeat` realiza avances y transiciones; `Start` es idempotente, `Stop` desconecta listeners y elimina marcadores/estado.

`MissionController` muestra el ciclo de partida, tiempo restante, objetivos secuenciales, progreso y número de contribuidores en una interfaz adaptable a pantallas de PC y móvil. No hay un sistema de bandos/enemigos en las fases actuales; por eso la misión implementada es cooperativa y el objetivo de zona se basa en presencia, no en combate contra una fuerza opositora. Las métricas de contribución capturan participantes distintos durante la ronda, no son estadísticas persistentes.

Archivos nuevos: `src/shared/config/MissionConfig.luau`, `src/server/services/MatchRules.luau`, `src/server/services/MatchService.luau`, `src/client/MissionController.client.luau` y `tests/phase9.test.luau`. Integración: `LogisticsService` registra cantidades de entrega confirmadas; `RadioService` y `RadioController` manejan avisos de misión; `Bootstrap.server.luau` inicia MatchService después del mapa, logística y radio; `default.project.json` define el remoto `MissionRequest`; `scripts/check-phase2.mjs` verifica el mapeo y los cuatro remotos.

Pruebas ejecutadas para esta fase:

```sh
/tmp/luau/luau tests/phase3.test.luau
/tmp/luau/luau tests/phase4.test.luau
/tmp/luau/luau tests/phase5.test.luau
/tmp/luau/luau tests/phase6.test.luau
/tmp/luau/luau tests/phase7.test.luau
/tmp/luau/luau tests/phase8.test.luau
/tmp/luau/luau tests/phase9.test.luau
/tmp/luau/luau-analyze src/shared/config/MissionConfig.luau src/server/services/MatchRules.luau tests/phase9.test.luau
find src tests -type f -name '*.luau' -print0 | xargs -0 -n1 /tmp/luau/luau-compile >/dev/null
node scripts/check-phase2.mjs
git diff --check
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

La suite de fase 9 comprueba configuración, solicitudes de solo lectura, preparación/cancelación, inicio, progreso cooperativo, entregas confirmadas, victoria/derrota por salida o tiempo, plausibilidad de movimiento y limpieza/reinicio. En la validación de Fase 11 pasaron las suites de fases 3–9: 21 comprobaciones, 12 grupos, 58, 54, 50, 32 y 42 comprobaciones, respectivamente. Todos los archivos Luau pasaron `luau-compile`; el análisis de reglas puras terminó sin errores; `check-phase2.mjs` confirmó el sourcemap, el orden de arranque y los cuatro remotos; `git diff --check` pasó y el build solicitado de Rojo se completó. El análisis puro no incluye APIs de Roblox y ni los tests ni el build prueban ejecución en motor. Queda pendiente validar en Roblox Studio el orden real de arranque, `Heartbeat`, colocación de zonas sobre Terrain, ciclo completo con varios clientes, detección de movimiento, reanimación, conductor/carga/entrega de vehículos, avisos de radio y legibilidad móvil. No se afirma que esta fase funcione en una partida real.

## Fase 10: interfaz y controles

`TacticalHUD.client.luau` agrega un HUD nativo compacto con salud, heridas, sangrado, munición, arma y estado del personaje; su menú táctico agrupa inventario/armas, escuadrón, medicina, radio, objetivos y logística. Las ventanas de Medicina, Radio, Misión y Logística existentes se abren de una en una desde el menú, evitando que sus paneles se superpongan entre sí. El panel de escuadrón consulta `SquadRequest` para presentar miembros, rango, rol y estado del personaje, y envía solicitudes de crear/unirse/salir al servicio existente; el servidor conserva la autorización.

Las acciones de tratamiento siguen usando `CombatRequest`, el equipo se consulta desde el snapshot médico de servidor y los cambios de arma siguen sujetos a `CombatService`. Las vistas de radio y misión siguen usando sus remotos existentes. `MedicalService.GetStatus` solo expone al cliente una copia de lectura de munición/equipo y estado médico; `SquadService` añade datos de presentación de los miembros al resultado de listado. No hay lógica cliente que conceda munición, tratamiento, canal, rango, progreso o resultados de partida. Se usan instancias nativas de Roblox, sin imágenes, fuentes ni assets externos.

En PC, `Tab` abre/cierra el menú y `Escape` lo cierra; los controles anteriores conservan `R`, `1/2`, `3/4`, `H`, `Enter` en radio y los atajos logísticos. En móvil, el botón de menú y los botones `Activated` permiten navegación táctil; las reglas puras fijan áreas de toque de 48 px y calculan límites adaptables. El menú es desplazable y sus dimensiones se limitan al viewport; el HUD permanece compacto y las vistas de servicio solo se muestran al seleccionarlas.

Archivos añadidos: `src/client/TacticalHUD.client.luau`, `src/shared/config/TacticalUIRules.luau` y `tests/phase10.test.luau`. Archivos existentes integrados/modificados: `src/client/LogisticsController.client.luau`, `src/client/MedicalController.client.luau`, `src/client/RadioController.client.luau`, `src/client/MissionController.client.luau`, `src/server/services/MedicalService.luau`, `src/server/services/SquadService.luau`, `scripts/check-phase2.mjs` y `README.md`. No fue necesario modificar `default.project.json`: su ruta de cliente ya incluye el controlador nuevo.

La prueba pura de fase 10 cubre perfiles compactos/expandidos, límites de tamaño del panel, objetivo táctil, condición médica y formato de munición. Las pruebas Luau y el build de Rojo no verifican Roblox GUI, entrada táctil real, lectura de controles móviles ni llamadas de remotos en el motor. Deben validarse en Studio el encaje y legibilidad con resoluciones/orientaciones distintas, los controles simultáneos con el joystick y el botón de salto, el estado al reaparecer, navegación entre ventanas, teclado/entrada de radio, listas de escuadrón con varios jugadores y la actualización real del HUD tras disparos/recargas/tratamientos. No se afirma que la interfaz haya sido probada dentro del motor.

Validación local ejecutada:

```sh
for phase in 3 4 5 6 7 8 9 10; do /tmp/luau/luau "tests/phase${phase}.test.luau"; done
find src tests -type f -name '*.luau' -print0 | xargs -0 -n1 /tmp/luau/luau-compile
node scripts/check-phase2.mjs
git diff --check
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

En esta ejecución pasaron las fases 3–10: 21 comprobaciones, 12 grupos, 58, 54, 50, 32, 41 y 14 comprobaciones, respectivamente. Todos los archivos Luau compilaron; el verificador confirmó los módulos/remotos mapeados, `git diff --check` no reportó errores y Rojo 7.7.0 generó `build/sierradeguardia.rbxlx`. Estas comprobaciones no sustituyen la validación en Studio descrita arriba.

## Fase 11: pruebas, rendimiento y preparación

Se amplió `scripts/check-phase2.mjs` para comprobar también que los servicios aparezcan en el orden de arranque esperado: generación del mapa, datos de jugador, escuadrón, inventario, medicina, logística, combate, radio y partida. La prueba nueva `tests/phase11.test.luau` verifica reglas puras de todas las fases disponibles en este checkout, incluidos rechazos de peticiones cliente mal formadas, configuración del mapa y compatibilidad de inventario/medicina. Las fases 1 y 2 no tienen suites Luau independientes: se verifican mediante el check del proyecto y el build.

Hallazgos corregidos durante la auditoría:

- `RadioService` ahora conserva y desconecta la conexión de `RadioRequest` en `Stop`, y vacía estado temporal de radio.
- La plausibilidad de movimiento del objetivo ya no concede una distancia fija adicional en cada muestra: el margen se calcula proporcionalmente al tiempo transcurrido. La suite de fase 9 incluye un caso que rechaza pequeños teletransportes repetidos.
- Si falla la construcción de instancias del mapa, se elimina el Folder generado y se restablece el estado local para permitir reintento. Los árboles conservan tronco y copa dentro de `Vegetacion`, sin crear un Folder por árbol.
- Se ajustó el tipado de reglas/pruebas para aceptar la configuración de roles de solo lectura y modelar explícitamente inventarios/stock mutables; las expectativas de prueba no se eliminaron.

La prueba de fase 4 estima 563 instancias para la configuración actual (409600 celdas base de Terrain y 122 árboles); eliminar el Folder individual por árbol reduce unas 122 instancias. Es una estimación de la regla de layout, no un perfil de memoria, tiempo de carga ni FPS medido en el motor. El servidor valida peticiones, identidades, estado de partida, rangos/roles, solicitudes por ventana, inventario, tratamiento, radio y objetivos mediante reglas/servicios; el cliente expresa intenciones y recibe snapshots. La compilación no mide latencia ni carga concurrente.

Validación ejecutada en esta revisión:

```sh
for phase in 3 4 5 6 7 8 9 10 11; do /tmp/luau/luau "tests/phase${phase}.test.luau" || exit 1; done
find src tests -type f -name '*.luau' -print0 | xargs -0 -n1 /tmp/luau/luau-compile >/dev/null
/tmp/luau/luau-analyze src/server/services/CombatRequestRules.luau src/server/services/CombatRules.luau src/server/services/InventoryRules.luau src/server/services/LogisticsRules.luau src/server/services/MapLayoutGenerator.luau src/server/services/MatchRules.luau src/server/services/MedicalRules.luau src/server/services/RadioRules.luau src/server/services/RankRules.luau src/server/services/SquadRegistry.luau src/server/services/SquadRequestRules.luau src/server/services/VehicleRules.luau src/shared/config/*.luau tests/phase*.test.luau
node scripts/check-phase2.mjs
git diff --check
rojo build default.project.json --output build/sierradeguardia.rbxlx
```

Resultado real: todas las suites 3–11 pasaron (21, 12 grupos, 58, 54, 50, 32, 42, 14 y 15 comprobaciones, respectivamente); todos los archivos Luau compilaron; `luau-analyze` finalizó sin errores para los módulos de reglas, mapa, registro y pruebas que no dependen de APIs Roblox; el verificador de proyecto confirmó destinos, remotos y orden de arranque; `git diff --check` pasó; Rojo generó `build/sierradeguardia.rbxlx`. No se pudo hacer análisis de tipos completo para controladores/servicios que dependen de `game`, instancias y tipos del motor, porque el analizador Luau independiente no incluye definiciones de Roblox. Estas verificaciones no demuestran ejecución real.

Limitaciones y riesgos pendientes: no se ejecutó Roblox Studio ni pruebas de carga/red/multijugador/dispositivos. El movimiento se calcula desde posiciones replicadas: el margen ahora está limitado por tiempo, pero puede requerir ajuste ante latencia y correcciones de red legítimas. Si falla la construcción del mapa después de modificar `Terrain`, se elimina el mapa de instancias y se restablece el estado local, pero no se revierte el Terrain ya escrito. La generación de layout fue validada con reglas puras, no se midieron tiempos de construcción. Datos de sesión siguen siendo solo memoria, según las fases anteriores.

### Lista manual para Roblox Studio

1. Desde la raíz del repositorio, ejecutar `rojo build default.project.json --output build/sierradeguardia.rbxlx` y abrir `build/sierradeguardia.rbxlx` en Roblox Studio (`File > Open from File`), o ejecutar `rojo serve default.project.json` y conectar el plugin Rojo a `localhost:34872`.
2. En Studio, abrir `View > Output`; iniciar una sesión con `Test > Start` usando un servidor y al menos dos clientes. Confirmar que no haya errores y que mapa, remotos y servicios arranquen una sola vez.
3. En servidor y clientes, probar entrada/salida, muerte, reaparición y fin/reinicio de ronda; verificar limpieza de sesiones, límites de solicitudes y estado del HUD.
4. Verificar combate, recarga, daño, heridas, sangrado, tratamiento y reanimación con jugador autorizado/no autorizado; alterar peticiones desde cliente y confirmar que no concedan daño, munición ni tratamientos.
5. Verificar escuadrones y rangos, cambios de rol, radio entre canales/escuadrones, filtrado de mensajes, objetivos cooperativos y entrega logística validada; confirmar que peticiones directas del cliente no completen objetivos.
6. Repetir con PC y emulación móvil en varios tamaños y orientaciones. Probar `Tab`, `Escape`, `R`, `1/2`, `3/4`, `H`, `Enter`, controles táctiles junto al joystick/salto, desplazamiento y cambio entre paneles; comprobar que la vista del juego no quede bloqueada.
7. Con MicroProfiler/estadísticas de Studio, medir arranque del mapa, instancias, memoria, FPS y tráfico con más jugadores y en hardware móvil; observar correcciones de movimiento bajo latencia y buscar conexiones/eventos duplicados tras varias rondas.

No se afirma que fases 1–11 estén completamente funcionales en Roblox hasta completar estas pruebas manuales. No se hizo commit, push ni publicación.