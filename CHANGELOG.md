# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - Lanzamiento inicial

Observabilidad de rendimiento local para Flutter: detección de anomalías de
frames en el dispositivo, sesiones, informes, comparaciones y contexto listo
para IA. Sin nube, sin backend, sin dependencia de DevTools.

### Motor core

- Monitoreo de frames mediante `SchedulerBinding.addTimingsCallback` con
  clasificación O(1) por frame en niveles normal / warning / slow / severe
  contra un presupuesto de frame configurable (default 60 Hz; resolución de
  frecuencia de refresco con procedencia de fallback documentada).
- Heurística de cuello de botella probable por frame slow (UI / raster / mixed
  / unknown) derivada de las formas de tiempos build-vs-raster.
- Contención de fallos: las excepciones dentro de PerfScope se enrutan al
  escritor de logs y nunca se propagan a la aplicación host.
- `Clock` inyectable, inicio de motor fire-and-forget, initialize idempotente,
  dispose amigable con hot-restart.

### Anomalías

- Cinco tipos de anomalía: `SlowFrameAnomaly`, `UiBoundFrameAnomaly`,
  `RasterBoundFrameAnomaly`, `MixedFrameAnomaly` y `LongTraceAnomaly`.
- Contrato de severidad: los frames slow mapean a high, los severe a critical;
  los frames de nivel warning nunca se convierten en anomalías. Los traces
  largos escalan a 2x/5x del umbral configurado (default 50 ms).
- Ventanas de contexto de frames acotadas alrededor de cada anomalía de frame
  (`contextFramesBefore` / `contextFramesAfter`).

### Atribución de contexto

- Seguimiento de pantallas mediante `PerfScopeNavigatorObserver` o
  sobrescritura manual `PerfScope.screen()`; las rutas sin nombre se
  normalizan a `'unknown'`.
- Interacciones: marcadores rápidos de un solo uso más spans anidables con
  enlace de id de padre y guarda de profundidad; cierres de span fuera de
  orden soportados.
- Store de metadatos validado con copia defensiva.

### Trazado manual

- `PerfScope.trace` / `traceAsync` con semántica de fallo
  registra-primero-relanza-sin-tocar e integración con Timeline (spans
  síncronos mediante `Timeline.startSync`, asíncronos mediante `TimelineTask`),
  ambos protegidos contra fallos de adaptador.

### Sesiones, informes, comparaciones

- Sesiones auto-iniciadas o manuales; el doble inicio auto-finaliza la sesión
  anterior; la detención explícita devuelve un `PerformanceReport` completo y
  lo adjunta a la sesión finalizada para exportación posterior.
- Estadísticas de sesión: contadores/sumas/peor frame exactos más percentiles
  de rango más cercano sobre una ventana deslizante acotada
  (`maxStatisticSamples`, default 10,000).
- Resúmenes por pantalla y por interacción con clasificación determinista;
  lista top-10 de peores anomalías.
- `SessionComparator` puro antes/después con tablas de comparación
  formateadas.

### Exportación y serialización

- Schema JSON determinista v1 con garantía de ida y vuelta del parser; las
  exportaciones funcionan a mitad de sesión (instantánea mínima) y después de
  detener (fallback al informe adjunto).
- Seams de exportación: `CallbackExporter`, `InMemoryExporter`,
  `TextExporter`.

### Logging

- Cuatro estilos de salida (`silent`, `compact`, `pretty`, `json`/NDJSON) con
  renderers deterministas cubiertos por snapshot tests; stream de eventos
  crudos (`PerfScope.events`) y sinks inyectables junto al logging.

### Integración IA

- Constructores de contexto IA optimizados en tokens (`buildAiContextText`,
  `buildAiContextJson`) que omiten datos ausentes en lugar de inventarlos.

### Herramientas

- CLI offline (`dart run perfscope:perfscope`) con comandos `analyze`,
  `report`, `compare`, `ai-context` y `doctor` y códigos de salida estables.
- Suite de benchmarks bajo `benchmark/` cubriendo clasificación, rendimiento
  de ring buffer, creación de anomalías, estadísticas y serialización.
- App de demostración bajo `example/` demostrando la configuración estricta
  solo-profile.
