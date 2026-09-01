# PerfScope

**Observabilidad de rendimiento local para Flutter.**

- Sin nube.
- Sin backend.
- Sin dependencia de DevTools.

**Idiomas:** [English](README.md) · [Español](README.es.md) · [Português](README.pt.md)

PerfScope detecta anomalías de frames, rastrea pantallas e interacciones,
registra sesiones, compara regresiones contra líneas base y genera informes de
rendimiento listos para IA — todo en el dispositivo y dentro del proceso.

## Por qué PerfScope

DevTools responde "¿qué pasó en ESTA sesión conectada?". PerfScope responde
"¿cómo se comporta mi app durante el uso REAL, en dispositivos reales, a lo
largo del tiempo?" — sin conexión a un escritorio:

* **Monitoreo de frames siempre activo** mediante
  `SchedulerBinding.addTimingsCallback`, clasificado en niveles de severidad
  con una heurística de probable cuello de botella.
* **Sesiones** que controlas: auto-iniciadas, nombradas, detenidas, comparadas.
* **Artefactos compartibles**: JSON determinista (schema v1), informes de
  texto formateado, tablas de comparación antes/después.
* **Salida lista para IA**: un bloque de contexto optimizado en tokens que
  puedes pegar directamente en una conversación con un LLM para depurar una
  regresión de jank.

PerfScope observa; nunca transmite. Ver [Privacidad](#privacidad).

## Instalación

```bash
flutter pub add --dev perfscope
```

PerfScope es una *dependencia de desarrollo*: es instrumentación que ejecutas
mientras desarrollas y perfilas, no algo que tus usuarios de producción
necesiten.

## Configuración en 30 segundos

```dart
import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PerfScope.initialize();
  runApp(const MyApp());
}
```

Eso es todo. Una sesión se inicia automáticamente (`autoStartSession` por
defecto es `true`), los frames se clasifican a medida que llegan, las
anomalías se imprimen en la consola y `await PerfScope.stopSession()` devuelve
el `PerformanceReport` completo.

> **Advertencia — Solo modo Profile para números confiables.**
> Las compilaciones de debug llevan aserciones y sobrecarga JIT: los tiempos
> de frame medidos con `flutter run` (debug) NO son representativos del
> comportamiento real.
> PerfScope imprime exactamente una advertencia cuando se inicializa en modo
> debug:
>
> ```
> [PerfScope] Running in DEBUG mode: performance measurements are NOT
> representative of real-world behavior. Use `flutter run --profile` for
> trustworthy numbers.
> ```
>
> Siempre mide con `flutter run --profile`.

### Configuración estricta solo-profile (recomendada)

La app de ejemplo demuestra la disposición más limpia: los puntos de entrada
de release nunca importan PerfScope, de modo que el código de observabilidad
se elimina por completo de las compilaciones de release. Tres archivos:

```dart
// lib/main.dart — PUNTO DE ENTRADA DE RELEASE. Sin import de PerfScope.
import 'app/showcase_app.dart';

void main() => runShowcaseApp();
```

```dart
// lib/main_profile.dart — PUNTO DE ENTRADA DE PROFILE. PerfScope se
// inicializa solo aquí.
import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

import 'app/showcase_app.dart';
import 'perf_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  bootstrapPerfScope();
  runShowcaseApp(observers: <NavigatorObserver>[PerfScopeNavigatorObserver()]);
}
```

```dart
// lib/perf_bootstrap.dart — solo cableado del motor: MemorySink compartido,
// PerfScope.initialize(config:, sinks:), apertura/cierre de sesión nombrada.
```

Ejecútala con:

```bash
flutter run --profile -t lib/main_profile.dart
```

Si tu app también debe funcionar en compilaciones de debug, inicializa detrás
de una comprobación de modo:
`if (kDebugMode || kProfileMode) PerfScope.initialize();`.

## Escaparate de escenarios

El paquete `example/` es una app de escaparate categorizada: cada capacidad de
PerfScope tiene una pantalla dedicada que explica qué captura, muestra el
código de uso exacto en pantalla y renderiza resultados en vivo de eventos
reales del motor — recetas de jank de frames, trazado, contexto de
pantalla/interacción, sesiones e informes, consola de eventos en vivo,
contexto IA, exportación JSON y comparación antes/después. También demuestra
la degradación elegante cuando PerfScope no está inicializado.

Ver [example/README.md](example/README.md) para instrucciones de ejecución, el
mapa escenario-a-API y los snippets de código por categoría.

## Monitoreo de frames

PerfScope se suscribe al stream de tiempos de frame de Flutter una vez, por
inicio del motor. Cada frame completado se convierte en un `FrameSample`
inmutable (duraciones de build / raster / total, sobrecarga de vsync)
enriquecido con la pantalla y la interacción actuales, y luego se clasifica
contra el presupuesto de frame efectivo:

| Duración total vs presupuesto | Nivel   |
|-------------------------------|---------|
| <= presupuesto                | normal  |
| > presupuesto                 | warning |
| > presupuesto x 1.5           | slow    |
| > presupuesto x 3             | severe  |

El presupuesto por defecto es 60 Hz (`targetFrameRate`) y se puede sobrescribir
o resolver desde la detección de frecuencia de refresco. Los umbrales son
configurables mediante
`PerformanceThresholds(warningMultiplier:, slowMultiplier:, severeMultiplier:)`.

La contabilidad por frame es O(1): contadores, sumas acumuladas y una ranura de
ring buffer (ver [Sobrecarga de rendimiento](#sobrecarga-de-rendimiento)). El
cálculo de percentiles se difiere al momento de la instantánea.

## Anomalías

Solo los frames slow/severe se convierten en anomalías — los frames de nivel
warning siguen siendo eventos. Cinco tipos de anomalía vienen incluidos:

| Tipo                       | Se eleva cuando                                              |
|----------------------------|--------------------------------------------------------------|
| `SlowFrameAnomaly`         | frame slow/severe, no se pudo inferir el cuello de botella    |
| `UiBoundFrameAnomaly`      | el trabajo del hilo UI domina (build >= 2x raster)           |
| `RasterBoundFrameAnomaly`  | el trabajo del hilo raster domina (raster >= 2x build)       |
| `MixedFrameAnomaly`        | Ambas fases contribuyen de forma comparable                   |
| `LongTraceAnomaly`         | Un trace manual superó `longTraceThreshold`                   |

Mapeo de severidad (contrato documentado):

* Anomalías de frame: `slow` -> **high**, `severe` -> **critical**. Los frames
  de nivel warning nunca llegan a la creación de anomalías.
* Anomalías de trace largo escalan con el umbral configurado (default 50 ms):
  >= 2x umbral -> **high**, >= 5x -> **critical**, en otro caso **medium**.

El cuello de botella es una HEURÍSTICA derivada únicamente de las formas de los
tiempos de frame. Indica la fase *probable* — nunca la causa probada. Las
anomalías recientes son alcanzables mediante `PerfScope.anomalies`, los frames
alrededor de cada anomalía de frame mediante
`PerfScope.contextWindowFor(anomalyId)`.

## Navegación

Adjunta el observer y las pantallas se nombran a sí mismas desde las rutas:

```dart
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/checkout': (_) => const CheckoutScreen()},
)
```

* Las rutas nombradas se convierten en nombres de pantalla; los frames, las
  anomalías, los traces y los resúmenes de informe se atribuyen a la pantalla
  visible.
* Las apps sin Navigator pueden sobrescribir manualmente:
  `PerfScope.screen('checkout');`.
* Las rutas sin nombre reportan `'unknown'`. Da nombres a las rutas
  importantes.

## Interacciones

Dos estilos complementarios:

**Marcador rápido** — una línea para flujos tipo tap. El marcador se atribuye
al siguiente lote de frames observado; nada más que cerrar:

```dart
PerfScope.interaction('add_to_cart');
```

**Span** — para flujos que sobreviven a un solo frame. Devuelve un handle;
llama a `end()` exactamente una vez (se soportan cierres fuera de orden):

```dart
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end();
```

Los spans se anidan: cada `InteractionEvent` lleva el id del span activo más
interno como padre, de modo que un `tap_pay` dentro de `checkout` sigue siendo
atribuible. El anidamiento está protegido en 16 niveles (los starts sin control
son bugs del llamador; los starts más profundos devuelven un handle inerte).
Los frames renderizados mientras un span está abierto se atribuyen a él —
correlación temporal, no causalidad.

## Trazado

Mide el tiempo de cualquier operación y alimenta tanto el registro de sesión
como el Timeline:

```dart
final prices = PerfScope.trace('calculate_prices', () =>
    computePrices(items));

final user = await PerfScope.traceAsync('fetch_user', () => api.getUser());
```

Contrato de excepciones: si `body` lanza, PerfScope registra el trace como
fallido (`didThrow`, duración incluida) y luego relanza el error ORIGINAL y el
stack trace sin tocar. Los metadatos pasados mediante `metadata:` se validan y
se incrustan en el evento resultante. Los traces que superan
`longTraceThreshold` (default 50 ms) elevan una `LongTraceAnomaly`.

Integración con Timeline: los traces síncronos emiten
`Timeline.startSync` / `finishSync`; los traces asíncronos emiten spans
`TimelineTask` (el SDK no tiene `startSync` asíncrono). Los fallos de adaptador
se tragan — los problemas del Timeline nunca pueden romper el flujo de la app.
Traces recientes: `PerfScope.recentTraces`.

## Sesiones

Una sesión es una ventana de observación grabada. Por defecto una se inicia
automáticamente en `initialize()`.

```dart
final session = PerfScope.startSession('release-check'); // auto-finaliza cualquier sesión abierta
// ... ejercita la app ...
final report = await PerfScope.stopSession(); // PerformanceReport completo
```

* El doble inicio es seguro: abrir una sesión nueva auto-finaliza la anterior
  (su informe sigue siendo alcanzable mediante su informe adjunto).
* Las llamadas consecutivas a `stopSession()` lanzan — no hay nada abierto.
* `PerfScope.currentSession` y `PerfScope.lastReport` responden pasivamente;
  nunca lanzan.

## Logs

Cuatro estilos mediante `PerfScopeConfig(logStyle:)`: `silent`, `compact`,
`pretty`, `json`. Las muestras siguientes son la salida exacta del renderer.

**compact** — una línea por anomalía/advertencia:

```text
PERF ProductList | UI 27.4ms | Raster 4.8ms | Total 33.1ms | Budget 16.7ms | HIGH ui-bound
PERF TRACE calculate_prices | 127.0ms | HIGH
```

**pretty** (default) — tarjetas con cajas dibujadas:

```text
╭──────────────────────────────────────────────────────────╮
│ PerfScope — Performance anomaly                          │
├──────────────────────────────────────────────────────────┤
│ Screen        ProductList                                │
│ Interaction   product_list_scroll                        │
│                                                          │
│ Build         27.400 ms                                  │
│ Raster         4.800 ms                                  │
│ Total         33.100 ms                                  │
│ Budget        16.667 ms                                  │
│                                                          │
│ Severity      HIGH                                       │
│ Type          UiBoundFrame                               │
│ Probable      UI                                         │
╰──────────────────────────────────────────────────────────╯
```

**json** — sobres NDJSON, parseables por máquina:

```json
{"schema_version":1,"type":"performance_anomaly","anomaly_type":"ui_bound_frame","event_id":"evt_1","session_id":"ses_1","timestamp":"2026-01-01T00:00:00.000Z","screen":"ProductList","interaction_id":"int_1","frame":{"build_ms":27.4,"raster_ms":4.8,"total_ms":33.1,"budget_ms":16.67},"severity":"high","probable_bottleneck":"ui"}
```

**silent** — sin salida.

Los eventos crudos omiten el registro por completo a través del stream
broadcast `PerfScope.events` y de los sinks inyectables.

## Informes

Detener una sesión renderiza una caja de resumen de ancho fijo (diseño
idéntico mediante `TextExporter` o `formatReportText`):

```text
╭──────────────────────────────────────────────────────────╮
│ PerfScope — Session Summary                              │
├──────────────────────────────────────────────────────────┤
│ Session                    ses_7                         │
│ Duration                  1m 00s                         │
│ Frames                       400                         │
│ Slow frames                    1                         │
│ Severe frames                  0                         │
│ Slow-frame rate            0.25%                         │
│ Worst frame              32.2 ms                         │
│                                                          │
│ p50                      10.0 ms                         │
│ p90                      13.4 ms                         │
│ p95                      14.1 ms                         │
│ p99                      15.0 ms                         │
╰──────────────────────────────────────────────────────────╯
```

Los informes clasifican pantallas e interacciones de forma determinista
(conteo de anomalías, luego p95, luego nombre) y listan las peores anomalías
primero.

## Exportación JSON

JSON determinista de una sola línea, schema versión 1:

```dart
final json = PerfScope.exportCurrentSessionAsJson();

// Después de stopSession() ya no hay sesión ABIERTA; la exportación cae al
// informe adjunto de la última sesión finalizada en lugar de devolver null,
// de modo que la exportación post-stop simplemente funciona.
final report = await PerfScope.stopSession();
final stopped = PerfScope.exportCurrentSessionAsJson();
```

Garantía de ida y vuelta — todo lo que el writer emite, el parser lo lee:

```dart
final parsed = SessionParser().parseString(json);
expect(parsed.session.id, originalId); // en tests
```

Los destinos son preocupaciones del host; PerfScope incluye tres seams:

* `CallbackExporter(onJson:)` — tú decides adónde van los bytes.
* `InMemoryExporter` — almacena strings JSON para tests/pantallas de debug.
* `TextExporter` — caja de resumen legible por humanos.

## Contexto IA

Una llamada convierte un informe en contexto listo para LLM
(`report.toAiContext()` o `buildAiContextText(report)`):

```text
PERFSCOPE_SESSION

name: checkout-performance
duration: 4m 32s
frames: 18421
slow_frames: 37
slow_frame_rate: 0.20%

p50_ms: 7.1
p95_ms: 14.4
p99_ms: 28.7
worst_frame_ms: 71.3

TOP_ISSUES:

1:
screen: ProductList
anomalies: 12
worst_frame_ms: 46
p95_ms: 29
probable_bottleneck: UI
```

La salida está optimizada en tokens, con tope duro y nunca inventa datos que no
tiene. Envíala por el CLI: `dart run perfscope:perfscope ai-context
session.json > context.txt`.

Prompt recomendado para acompañarla:

```text
You are a senior Flutter performance engineer. Below is a PerfScope session
summary captured on-device in profile mode. Identify the most probable root
causes, rank them by user impact (p95/worst frames, anomaly density), and
propose concrete code-level fixes. Treat probable_bottleneck values as
heuristics derived from frame timing shapes, not proven causes; recommend
timeline tracing where certainty is needed.

<paste context.txt here>
```

## Comparaciones antes/después

Comparación pura, sin motor, de dos informes cualesquiera:

```dart
final comparison = PerfScope.compareSessions(baselineReport, candidateReport);
print(formatSessionComparison(comparison));
```

O directamente desde archivos:

```bash
dart run perfscope:perfscope compare baseline.json candidate.json
```

Los deltas de métricas se reportan por etiqueta (frames, p50/p95/p99, peor
frame, anomalías, ...) de modo que las regresiones aparecen como porcentajes
con signo en lugar de corazonadas.

## CLI

Herramientas offline sobre archivos de sesión exportados:

```text
Usage: dart run perfscope:perfscope <command> [arguments]

Commands:
  analyze <session.json>       Compact session summary
  report <session.json>        Full formatted session report
  compare <before> <after>     Before/after comparison table
  ai-context <session.json>    AI-ready context (for shell redirection)
  doctor                       Environment checks

Exit codes:
  0 success   1 usage error   2 unreadable file
  3 invalid session file   4 doctor found missing requirements
```

Comprueba tu entorno (salida real; las versiones varían según la máquina):

```text
$ dart run perfscope:perfscope doctor
ok   Flutter detected (3.44.1)
ok   Dart detected (3.12.1)
ok   pubspec.yaml found
ok   Project detected (perfscope)

Recommended performance mode:
  flutter run --profile
```

## Privacidad

PerfScope NO recopila NADA y NO transmite NADA. No hay código de red en el
paquete — ni telemetría, ni reporte de errores, ni "estadísticas de uso
anónimas". Explícitamente, PerfScope nunca toca:

* identificadores de dispositivo o IDs de publicidad,
* identificadores de usuario o datos de cuenta,
* contenidos de pantalla, texto ingresado o imágenes renderizadas,
* crash logs o stack traces de TUS excepciones (solo se registran los fallos
  de los traces del propio PerfScope, localmente),
* ninguna pipeline de analítica o telemetría.

Todo vive en memoria acotada dentro del proceso hasta que TÚ lo exportas por
tu propio canal elegido. Los ids de correlación (`ses_1`, `anm_2`, `trc_3`)
son solo números de secuencia locales — útiles dentro de un proceso, sin
significado fuera de él.

## Sobrecarga de rendimiento

Contabilidad honesta:

* El trabajo por frame es clasificación más encolado SOLO: unas pocas
  comparaciones de enteros, actualizaciones de contadores y una escritura de
  ranura en un ring buffer preasignado. Sin asignación por frame, sin
  ordenamiento, sin construcción de strings.
* Los percentiles ordenan una ventana acotada (default 10,000 muestras) solo
  cuando ocurre una instantánea/exportación — nunca en la ruta del frame.
* Los números absolutos varían según el dispositivo; no confíes en los
  benchmarks de nadie, incluidos estos docs. Ejecútalos tú mismo:

```bash
dart run benchmark/frame_classification_benchmark.dart
dart run benchmark/ring_buffer_benchmark.dart
dart run benchmark/anomaly_creation_benchmark.dart
dart run benchmark/statistics_benchmark.dart
dart run benchmark/serialization_benchmark.dart
```

Cada uno imprime la mediana en ns/op y ops/seg sobre lotes cronometrados
después del warmup.

## Soporte de plataformas

| Capacidad                             | Android | iOS | macOS | Windows | Linux | Web |
|---------------------------------------|---------|-----|-------|---------|-------|-----|
| Monitoreo de frames (`FrameTiming`)   | sí      | sí  | sí    | sí      | sí    | ?   |
| Trazado / interacciones manuales      | sí      | sí  | sí    | sí      | sí    | sí  |
| Sesiones, informes, JSON, CLI         | sí      | sí  | sí    | sí      | sí    | sí  |

La detección de frecuencia de refresco depende de la plataforma: donde el SO
no revela la frecuencia real de refresco de la pantalla, PerfScope cae al
presupuesto configurado y lo indica en el entorno de la sesión
(`frameBudgetSource`).

La columna web para el monitoreo de frames es un `?` honesto: el
comportamiento de `addTimingsCallback` en web no está documentado upstream, así
que PerfScope no hace ninguna afirmación que no pueda verificar. Todo lo demás
es Dart puro y funciona en cualquier lugar donde Dart se ejecute.

## Arquitectura

Una mirada a `lib/src`:

```
core/          cableado del motor, config, abstracción de reloj, generadores de id
frames/        FrameSample, clasificador, presupuestos, fuente de frames de Flutter
anomalies/     modelos de anomalía, detector, ventanas de contexto de frames
buffers/       RingBuffer — la única estructura mutable de la ruta caliente
context/       rastreador de pantalla, rastreador de interacciones, store de metadatos
events/        la jerarquía de eventos tipada (frame/screen/interaction/trace/anomaly/lifecycle)
sessions/      ciclo de vida de sesiones y agregados
reporting/     estadísticas, resúmenes de pantalla/interacción, constructor de informes, comparaciones
serialization/ schema v1, serializador, parser (seguro de ida y vuelta)
exporters/     exporters de callback / en memoria / texto
logging/       escritor de logs + renderers silent/compact/pretty/json
navigation/    observer de navigator
traces/        seguimiento de traces manuales, adaptadores de Timeline
sinks/         sinks de eventos de consola/json/memoria
ai/            constructores de contexto IA
cli/           interfaz de línea de comandos offline
testing/       fakes y fixtures de test
```

Dependencias: Flutter SDK y `args` (parsing de CLI). Nada más.

## Limitaciones

* **FrameTiming no puede nombrar funciones culpables.** El motor ve duraciones
  por fase, no muestras de stack. `probableBottleneck` es una heurística sobre
  formas de tiempos; atribuir culpa a widgets específicos requiere trazado de
  Timeline (que PerfScope facilita, pero no falsifica).
* **Los percentiles provienen de una ventana deslizante acotada**
  (`maxStatisticSamples`, default 10,000). Las sesiones largas describen su
  pasado reciente, no su historia completa; los contadores y sumas siguen
  siendo exactos en todo momento.
* **Las rutas sin nombre reportan `'unknown'`.** Nombra tus rutas.
* **El monitoreo de frames en web no está verificado.** El comportamiento de
  `addTimingsCallback` en web no está documentado upstream; trata la columna
  web de arriba como desconocida, no como rota.
* **Los ids de correlación son locales al proceso** — nunca los uses como
  claves de base de datos.

## Roadmap

* **v0.2** — dirección de puente en runtime: exponer sesiones/streams en vivo
  a herramientas externas (integración estilo MCP) para que agentes y
  dashboards puedan consultar PerfScope mientras la app se ejecuta.
* Más adelante — métricas adicionales más allá de frames/traces: CPU, memoria,
  presión de GC, actividad de isolates. Cada una aterriza solo con un
  mecanismo de recolección honesto y documentado.

## Contribuciones

Issues y PRs bienvenidos — ver [CONTRIBUTING.md](CONTRIBUTING.md) para setup,
gates de calidad y expectativas.

## Licencia

[MIT](LICENSE)
