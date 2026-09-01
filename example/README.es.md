# Escaparate de escenarios de PerfScope

**Idiomas:** [English](README.md) · [Español](README.es.md) · [Português](README.pt.md)

Una app de escaparate profesional y categorizada que ejercita cada capacidad
de PerfScope contra la superficie de API real — sin mocks, sin fakes. Cada
escenario es una pantalla dedicada que explica qué captura PerfScope, muestra
el código de uso exacto en pantalla (correcto para copiar y pegar) y renderiza
resultados en vivo de eventos reales del motor.

## Puntos de entrada

### Recomendado: modo profile con PerfScope habilitado

```bash
flutter run --profile -t lib/main_profile.dart
```

`main_profile.dart` llama a `bootstrapPerfScope()` desde
`perf_bootstrap.dart`, que inicializa el motor con
`PerfScopeConfig(printWarnings: true)`, registra un `MemorySink` compartido,
abre la sesión nombrada `'showcase'` y adjunta `PerfScopeNavigatorObserver()`
para que las rutas nombradas se conviertan en nombres de pantalla.

Ejecutar en compilaciones de debug en su lugar imprime exactamente una línea
de advertencia:

```text
[PerfScope] Running in DEBUG mode: performance measurements are NOT representative of real-world behavior. Use `flutter run --profile` for trustworthy numbers.
```

Los números de frame medidos en modo debug llevan aserciones y sobrecarga JIT;
trátalos como direccionales únicamente.

### Línea base segura para release (escaparate degradado)

```bash
flutter run -t lib/main.dart
```

`main.dart` no contiene ningún import de PerfScope ni inicialización. La app
aún funciona: cada pantalla de escenario detecta el motor deshabilitado y
reemplaza su área de acción con un aviso explícito ("PerfScope is disabled in
this entry point...") en lugar de crashear o mostrar silenciosamente
resultados vacíos. La pantalla de inicio muestra un banner de estado
equivalente. Usa este punto de entrada para verificar que las compilaciones de
release sigan limpias.

## Escenarios

| Categoría | Escenario | Ruta | API ejercitada | Qué observar |
| --- | --- | --- | --- | --- |
| Frames | Línea base de navegación fluida | `/frames/smooth-navigation` | `PerfScopeNavigatorObserver` | ScreenEvents con nombres de ruta; cero anomalías |
| Frames | Jank del hilo UI | `/frames/ui-thread-jank` | ninguna (detección pasiva) | Anomalías de frames slow/severe, cuello de botella probable UI |
| Frames | Presión de raster | `/frames/raster-pressure` | ninguna (detección pasiva) | Anomalías ligadas a raster; raster_ms dominando |
| Frames | Lista de scroll larga | `/frames/long-scroll-list` | ninguna (detección pasiva) | Conteo creciente de frames slow bajo un nombre de pantalla |
| Tracing | Trace síncrono | `/tracing/sync-trace` | `PerfScope.trace`, `recentTraces` | Registros CompletedTrace con metadatos adjuntos |
| Tracing | Trace asíncrono: operación larga | `/tracing/async-trace-long-operation` | `PerfScope.traceAsync`, `anomalies` | LongTraceAnomaly escalada contra `longTraceThreshold` |
| Context | Spans de interacción | `/context/interaction-spans` | `startInteraction`, `interaction` | Pares start/end con duraciones; marcadores rápidos |
| Context | Sobrescritura de contexto de pantalla | `/context/screen-context` | `screen()`, `setMetadata` | ScreenEvent con razón `manual`; fusión de metadatos |
| Sessions & reports | Informe de sesión | `/sessions/session-report` | `startSession`, `stopSession`, `formatReportText` | Caja de informe de texto completo en pantalla |
| Sessions & reports | Consola de eventos en vivo | `/sessions/live-event-console` | `events`, `MemorySink` | Jerarquía de eventos sellada cruda, coloreada por severidad |
| AI & export | Visor de contexto IA | `/ai-export/ai-context-viewer` | `report.toAiContext()` | Bloque PERFSCOPE_SESSION optimizado en tokens |
| AI & export | Exportación JSON de sesión | `/ai-export/session-json-viewer` | `exportCurrentSessionAsJson` | JSON determinista schema-v1 |
| AI & export | Comparación antes / después | `/ai-export/before-after-compare` | `compareSessions`, `formatSessionComparison` | Deltas con signo; se esperan advertencias de muestra pequeña |

Los bucles de trabajo son adaptativos al dispositivo: primero miden un lote de
prueba y escalan a la duración objetivo, nunca fijan conteos de iteraciones.

## Snippets de uso por categoría

Fragmentos reales — el mismo código que muestra cada pantalla.

### Frames

```dart
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/products': (_) => const ProductsScreen()},
);
// Named routes become PerfScope screen names automatically.
```

Las recetas de jank no necesitan API alguna: el trabajo síncrono dentro de
`build` o las decoraciones de pintura costosas revientan el presupuesto y
PerfScope clasifica los frames por su cuenta (`UiBoundFrameAnomaly`,
`RasterBoundFrameAnomaly`).

### Tracing

```dart
final prices = PerfScope.trace('calculate_prices', () => computePrices(cart));
await PerfScope.traceAsync('load_products', () async {
  await api.loadProducts(); // > longTraceThreshold raises LongTraceAnomaly
});
print(PerfScope.recentTraces.length);
```

### Context

```dart
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end();
PerfScope.interaction('add_to_cart'); // quick marker

PerfScope.screen('checkout', metadata: {'step': 'payment'}); // manual override
PerfScope.setMetadata('cart_items', 3);
```

### Sesiones e informes

```dart
PerfScope.startSession('release-check'); // auto-finalizes previous
await runWorkload();
final report = await PerfScope.stopSession();
print(formatReportText(report)); // reports have NO toText()

PerfScope.events.listen((PerformanceEvent event) {
  if (event is AnomalyEvent) debugPrint(event.anomaly.severity.name);
});
```

### IA y exportación

```dart
Clipboard.setData(ClipboardData(text: report.toAiContext()));
final json = PerfScope.exportCurrentSessionAsJson();

final comparison = PerfScope.compareSessions(beforeReport, afterReport);
print(formatSessionComparison(comparison)); // negative delta = improvement
```

## Estructura del proyecto

```text
lib/
  main.dart                  punto de entrada seguro para release (sin PerfScope)
  main_profile.dart          punto de entrada de profile: bootstrap + navigator observer
  perf_bootstrap.dart        MemorySink compartido + helpers de inicialización/apagado
  app/
    showcase_app.dart        carcasa MaterialApp y rutas nombradas
    scenario.dart            modelo Scenario, categorías, catálogo
    scenario_card.dart       tarjeta de lista de inicio por escenario
    scenario_scaffold.dart   scaffold de detalle compartido (resumen/capturas/código)
    code_block.dart          contenedor de snippet monoespaciado seleccionable
    busy_work.dart           helper adaptativo de spin de CPU compartido por escenarios
  scenarios/
    frames/                  línea base de navegación + tres recetas de jank
    tracing/                 traces síncronos y traces asíncronos largos
    context/                 spans de interacción y contexto de pantalla manual
    sessions/                informes de sesión y consola de eventos en vivo
    ai_export/               contexto IA, exportación JSON, comparación antes/después
```

## Tests de extremo a extremo

`integration_test/perfscope_e2e_test.dart` conduce esta app por sus tiles de
inicio (claves `menu-tile<route>`) a través de un motor real con un
`MemorySink` inyectado, verificando la detección de anomalías de frames, el
ciclo de vida de sesiones, el parsing de ida y vuelta de JSON y la atribución
de pantallas por rutas nombradas.
