# SierraDeGuardia: integración del HUD de conducción

Estado: implementación revisable; validación en Roblox Studio y dispositivos pendiente.
Base: `c1143b4767bd7a3583c015f447314be9df9a7df1` (`main`).
Rama: `coderabbit/integrate-driving-hud`.

## Resultado y condiciones de integración

Se conserva el juego y su arquitectura Rojo. `TacticalHUD.client.luau` sigue siendo el punto de entrada y mantiene escuadrones, compañías, rangos, medicina, radio y misiones. Los nuevos módulos se encuentran bajo rutas ya mapeadas. No se incorporan el proyecto, el bootstrap ni el workflow del ZIP.

La primera imagen guía la distribución: superficies oscuras translúcidas, chat oficial a la izquierda, brújula/ubicación superior, salud y telemetría a la derecha, minimapa con caminos reales y centro libre. En pantallas compactas se colapsan accesos secundarios y chat. La segunda imagen guía la separación entre acciones táctiles y movimiento. Esta adaptación visual todavía requiere comparación dentro del motor; no se presenta una captura simulada como prueba de funcionamiento.

| Condición aprobada | Implementación y evidencia |
|---|---|
| Conservar SierraDeGuardia | Arquitectura y servicios originales; ningún archivo eliminado. Nombre visible/documentado SierraDeGuardia; identificadores internos históricos conservados. |
| Priorizar camioneta | Modo asociado al `DriverSeat` real de un modelo `VehicleCategory=Pickup`; pedales, dirección, freno, salida y cámara. |
| Reutilizar sistemas reales | Telemetría de LogisticsService; salud/armas de MedicalService e InventoryService; paneles existentes de medicina, radio, misiones y escuadrón. |
| Evitar datos inventados | Se muestra `--` o sincronización antes del snapshot. Inventario lógico del servidor; ningún saldo o necesidad ficticia. |
| Respetar medicina/servidor | No se importa el sprint que modificaba WalkSpeed localmente. Conducción valida vida, incapacitación, ocupante y rol; se conserva la inmovilización médica. |
| Corregir módulos/orientación/escalado/ciclo de vida | Dependencias explícitas, reglas compartidas, perfiles sin escala global, ámbitos de limpieza, Start/Stop y cámara reemplazable. |
| Conservar proyecto/workflows | `default.project.json` y `.github/workflows/**` idénticos a la base. Sin publicación automática nueva ni workflow ejecutado para desplegar. |
| Paneles funcionales | Navegación abre los ScreenGui reales; inventario se refresca desde servidor; equipar, logística, tratamientos, radio y objetivos conservan sus contratos. Escape cierra también paneles secundarios. |
| Pruebas y entrega | Arnés nuevo con módulos reales y dobles de APIs, regresiones anteriores, compilación y build local. Fuentes completas, diff y resultados adjuntos. Studio pendiente. |

## Contraste con el diagnóstico técnico

| Defecto verificado | Cambio | Verificación disponible |
|---|---|---|
| Estructura aplanada y rutas incompatibles | Integración en `src/client/hud`; se usa el mapeo existente | Sourcemap y build Rojo |
| Resolver devolvía Instance sin require y errores fuera de pcall | Requiere ModuleScripts propios; GameAdapter consume contratos reales de remotos | Ejecución de módulos completos en arnés |
| Caché negativa de dependencias | ChildAdded para humanoides/paneles; reconciliación del asiento sin cachear ausencias | Personaje y humanoide tardíos; reinicio |
| Brújula sin contexto | HUDView recibe MapConfig y estado de GameAdapter explícitamente | Render ejecutado en arnés |
| E/O invertidos | Heading = atan2(X, -Z); norte fijo, flecha del personaje/vehículo | N/E/S/O y proyección NE |
| POI Vector3 rechazados por type | Marcadores públicos tipados por coordenadas X/Z de LogisticsConfig, sin resolver Vector3 con type | Render/proyección de coordenadas de configuración |
| Animación indexaba UDim2 incorrectamente | Botones de tamaño fijo con respuesta nativa; no se importa la animación defectuosa | Construcción y controles de botones reales del módulo en arnés |
| Relación global 16:9 | Raíz ocupa el área segura; perfiles por tamaño utilizable | 360×640, 667×320, 812×375, 1024×768 y 1920×1080 en dobles |
| Controles reducidos por UIScale | Nuevos controles de 48 px de alto o 64×56 px; sin escala global | Tamaño efectivo y límites geométricos de cada botón de conducción |
| Conexiones, Start y Destroy incompletos | Cleanup; Start/Stop idempotentes; ámbitos de personaje, cámara y conducción; avisos con una cuenta regresiva reemplazable | Cinco respawns, cambios de cámara, doble Start/Stop y reinicio; cero conexiones propias vivas al finalizar |
| Inventario limitado a Tools | Snapshots de armas, medicina, suministros y equipo reales | Munición renderizada desde snapshot; inventario de servicio y descarte de vida anterior |

Las correcciones anteriores de combate móvil se conservan: no se vuelve a introducir disparo por toque global; se mantiene el raycast autoritativo, la recarga, snapshots completos y bloqueo médico. Además, el combate local se oculta/bloquea mientras el personaje está sentado.

## Contrato de conducción

- Ranger1/Ranger2 y su geometría/movimiento siguen siendo los existentes. `Category="Pickup"` es metadata explícita de LogisticsConfig y del modelo emitido por servidor.
- Entrada/salida siguen usando `enter_vehicle` / `exit_vehicle`. Engineer, SquadLeader y Commander conservan permiso; Rifleman no lo adquiere por usar el HUD.
- El canal existente CombatRequest acepta `action="logistics", operation="drive", vehicleId, throttle, steer`. Solo admite un argumento, campos previstos y ejes numéricos finitos en [-1, 1]. No acepta velocidad/posición/combustible del cliente.
- Se envía intención cada 0,2 s. Hay una ventana separada de 12 peticiones de conducción/s, además del límite global existente del remoto. Las interacciones logísticas conservan su límite.
- El servidor comprueba personaje vivo, no incapacitado, ocupante real y rol autorizado. La intención pertenece al Humanoid concreto y caduca a los 0,65 s. Cambiar de ocupante, salir o perder permiso borra la entrada.
- El servidor deja de depender de la replicación de ThrottleFloat/SteerFloat: utiliza el canal explícito para PC y táctil. Conserva StepVehicle, colisiones, PivotTo y consumo existentes.
- Velocidad: **studs/s**. No se transforma en km/h ni se lee AssemblyLinearVelocity de las partes ancladas. El freno pone intención a cero; reversa es una acción separada. El modelo original no simula inercia.
- PC: WASD/flechas; Espacio frena; B entra/sale. Táctil: mantener acelerar/reversa y dirección con dedos independientes; soltar, cancelar o perder foco limpia el estado. Los menús/chat neutralizan la entrada.
- El overlay táctil nativo se oculta únicamente durante conducción y se restaura a su visibilidad anterior al salir. Los botones de combate y la retícula se coordinan con el asiento.
- Cabina alterna la primera persona oficial del jugador; restaura CameraMode al salir. No se afirma una cámara física de cabina ni un seguimiento cinematográfico personalizado.
- El cliente determina el modo desde el asiento actual; un snapshot atrasado nunca convierte a un jugador a pie en conductor. Los snapshots médicos/logísticos incluyen o conservan la identidad del personaje para descartar vidas anteriores.

## Datos y acciones disponibles

| Indicador/panel | Fuente/acción |
|---|---|
| Salud/condición | Humanoid y estado médico real; heridas, sangrado e incapacitación |
| Arma y munición | Snapshot médico/inventario; equipar y recargar por acciones existentes |
| Inventario | Armas, medicinas, Supplies y Equipment del servidor; no se lee Backpack como inventario del juego |
| Vehículo | Nombre, combustible, velocidad, carga, ocupante y permiso del servidor |
| Logística | Entrar/salir, cargar, entregar, repostar y reabastecer; sin Ranger1/depot ficticiamente seleccionados por defecto |
| Radio | Panel y servicio textual existente con permisos, alcance y filtrado |
| Misiones | Panel existente con estado, objetivos y progreso del servidor |
| Organización | Panel existente de escuadrones/compañías/rangos y operaciones existentes |
| Chat | Ventana/entrada de TextChatService y sus restricciones oficiales; fallback de apertura del chat clásico |
| Brújula/mapa | Orientación del personaje/vehículo, caminos de MapConfig, depósito/entrega de LogisticsConfig. D=depósito, L=entrega logística; no es navegación GPS ni muestra posiciones privadas |

**Sin sistema real encontrado:** dinero/economía, hambre, sed, energía/resistencia de sprint, reloj de juego/ciclo horario propio y voz personalizada. No se muestran sus indicadores. Raciones se muestran únicamente como cantidad de inventario; no equivalen a hambre. El chat oficial no concede acceso ni evita restricciones de comunicación de Roblox.

## Archivos completos del cambio

Modificados:

- `README.md`
- `scripts/check-mobile.mjs`
- `src/client/CombatController.client.luau`
- `src/client/LogisticsController.client.luau`
- `src/client/TacticalHUD.client.luau`
- `src/server/services/CombatRequestRules.luau`
- `src/server/services/LogisticsService.luau`
- `src/shared/config/LogisticsConfig.luau`

Creados:

- `docs/hud-verification.md`
- `src/client/hud/Cleanup.luau`
- `src/client/hud/GameAdapter.luau`
- `src/client/hud/HUDController.luau`
- `src/client/hud/HUDView.luau`
- `src/client/hud/VehicleControls.luau`
- `src/server/services/VehicleInputRules.luau`
- `src/shared/HUDRules.luau`
- `tests/hud-runtime.luau`

El ZIP de entrega contiene el proyecto fuente completo, incluidas sus dependencias y archivos originales. El patch contiene el cambio frente a la base; ninguno de los dos requiere reconstruir el juego desde cero.

## Verificación CLI ejecutada

Herramientas ya disponibles: Rojo 7.7.0, Luau 0.743 y StyLua 2.1.0. Sin instalación de runtimes o paquetes nuevos.

| Comprobación | Resultado real |
|---|---|
| `scripts/check-phase2.mjs` | Pasa: versión, destinos y remotos |
| `tests/mobile-runtime.luau` mediante check-mobile | 161 comprobaciones pasan |
| `tests/hud-runtime.luau` mediante check-mobile | 148 comprobaciones pasan |
| Fases 3–11 | Pasan: 21 comprobaciones; 12 grupos; 58; 54; 50; 32; 42; 22; 15, respectivamente |
| Compilación Luau | 59 archivos de src/tests compilan |
| Análisis de tipos sin motor | Reglas/configuraciones/pruebas puras, incluidos HUDRules y VehicleInputRules, pasan |
| StyLua | Archivos Luau modificados/nuevos formateados |
| Rojo build | Genera un .rbxlx local; no carga ni publica en Roblox |
| Diff | Sin errores de whitespace; proyecto/workflows intactos |

El arnés carga el código completo de HUDController, HUDView, GameAdapter, VehicleControls, LogisticsService y sus dependencias. Comprueba intención aceptada/rechazada y movimiento calculado, pero sus dobles de Instance, CFrame, señales, entrada y GUI no ejecutan físicas, SeatWeld, renderizado ni replicación de Roblox. El análisis Luau independiente no incluye todas las definiciones de tipos del motor; no se anuncia análisis completo de los controladores Roblox.

Reproducción desde la raíz, con herramientas en PATH:

```sh
node scripts/check-phase2.mjs
node scripts/check-mobile.mjs
for phase in 3 4 5 6 7 8 9 10 11; do luau "tests/phase${phase}.test.luau"; done
find src tests -name '*.luau' -type f -print0 | xargs -0 -n1 luau-compile >/dev/null
luau-analyze src/shared/HUDRules.luau src/server/services/VehicleInputRules.luau
rojo build default.project.json --output build/sierra-de-guardia-hud.rbxlx
git diff --check
```

`LUAU_BIN` y `ROJO_BIN` permiten usar ejecutables fuera del PATH. El workflow existente ya llama a check-mobile, que ejecuta ambos arneses. No se modifica el workflow.

## Matriz pendiente en Roblox Studio

Todas las filas siguientes están **pendientes**, no aprobadas por los resultados CLI.

1. Abrir el .rbxlx adjunto localmente, o construir/sincronizar con Rojo. No publicar. En Output, comprobar ausencia de errores de arranque, módulos, GUI y remotos.
2. Usar servidor y al menos dos clientes. Con el rol inicial Rifleman, confirmar rechazo al conducir. Asignar roles por el mecanismo autorizado existente para probar Engineer/SquadLeader/Commander; no alterar el cliente para conceder permisos.
3. Entrar en Ranger1/Ranger2, acelerar, girar, frenar, retroceder, chocar, agotar/reponer combustible, cargar/entregar suministros. Verificar ocupante y telemetría entre ambos clientes.
4. Repetir caminar→conducir→caminar, B y salida táctil, cambios rápidos, asiento ocupado, asiento/vehículo destruido y pérdida de combustible/permiso. Comprobar controles nativos, combate y cámara restaurados.
5. Incapacitar, tratar, reanimar, morir y reaparecer durante un pedal mantenido. Repetir varias vidas y rondas: sin movimiento residual, snapshots antiguos, HUD duplicado ni crecimiento de conexiones propias.
6. En emulación y hardware Android: 360×640, 667×375, 812×375, tableta, áreas seguras y rotación; después PC. Medir límites reales de botones, legibilidad y solapamientos con topbar, joystick y chat. Los perfiles CLI no verifican métricas de fuente ni CoreGui.
7. Mantener pedal+dirección, usar dos dedos, soltar fuera, cancelar toque, cambiar de aplicación, abrir chat/menús y recuperar foco. Confirmar neutralización y timeout bajo latencia/pérdida de mensajes.
8. Mirar N/E/S/O en posiciones conocidas; comprobar carreteras y D/L en el minimapa. Verificar centro en personaje/vehículo, no en cámara, y cambio de cámara/orientación.
9. Probar inventario tras disparo/recarga, medicina/reabastecimiento, radio con dos jugadores y restricciones, escuadrones, misiones/rondas y vuelta/cierre de cada panel. Confirmar que acciones siguen siendo validadas por servidor.
10. Probar TextChatService real, permisos de comunicación y chat restringido/no disponible. Verificar posición/tamaño oficiales junto al HUD y restauración de configuración al detenerlo.
11. Medir memoria/FPS y tráfico en hardware real; revisar especialmente el dibujo periódico de caminos y la frecuencia de remotos. No hay mediciones de rendimiento del motor en esta entrega.

No se afirma funcionamiento completo del HUD ni compatibilidad móvil verificada hasta terminar esta matriz.


---

# Rediseño del HUD de mundo abierto (rama `feature/hud-open-world`)

Estado: implementado y verificado por CLI; **Roblox Studio y dispositivos reales siguen pendientes**. Ver la sección "HUD de mundo abierto" del README para el mapa de zonas y fuentes de datos.

## Verificación ejecutada

| Comprobación | Resultado |
|---|---|
| `node scripts/check-phase2.mjs` | Pasa (incluye los módulos nuevos en el sourcemap) |
| `scripts/check-mobile.mjs` | 161 + 168 comprobaciones pasan (el arnés del HUD subió de 148 a 168) |
| Fases 3-11 | Pasan; fase 10: 6341 comprobaciones (layout en 9 tamaños x 2 modos x chat abierto/cerrado) |
| `luau-compile` | 62 archivos compilan |
| `luau-analyze` | Sin errores en `HUDRules`, `HUDLayout`, `VehicleInputRules`, configuraciones y `tests/phase*.test.luau` (los mismos archivos que usa el CI, más los dos módulos de HUD) |
| `rojo build` | Genera `build/sierradeguardia.rbxlx` |

El arnés usa dobles de las APIs de Roblox: no renderiza GUI, no valida fuentes ni replicación.

## Matriz pendiente en Studio (HUD nuevo)

1. **Chat nativo arriba a la izquierda:** comprobar que la ventana nativa de `TextChatService` queda bajo los botones de chat/menú y no los tapa. `ChatWindowConfiguration` solo permite alineación y escala, no desplazamiento en píxeles; si se superpone, hay que reservar ese margen en `HUDLayout.Compute` (`chatY`).
2. Tamaños: 360x640, 667x375, 812x375, tableta, rotación y áreas seguras (la raíz usa `CoreUISafeInsets`). Comprobar que el texto de 12-13 px es legible en Android.
3. Con la camioneta: pedales, dirección, freno, salir y cámara; arma y ranuras se ocultan y vuelven al bajar o reaparecer.
4. Ranuras rápidas: vendaje/botiquín (cuentas reales), equipar fusil/pistola, y que el botón Inventario abra el centro táctil.
5. Disparar y Recargar táctiles junto al joystick y el botón de salto nativos; sin disparo al arrastrar la cámara.
6. Menú izquierdo: Facciones, Inventario, Vehículos y Misiones abren su panel; el botón de menú muestra "cerrar" mientras hay un panel abierto.
7. Rendimiento: el minimapa dibuja ~250 segmentos de camino; solo se reposicionan cuando el jugador se mueve 0,5 studs. Medir FPS/memoria en un Android modesto.
