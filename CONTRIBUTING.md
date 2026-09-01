# Contribuyendo a PerfScope

Gracias por ayudar a mejorar PerfScope. Este documento cubre la configuración,
los gates de calidad que cada cambio debe pasar y lo que los revisores esperan.

## Configuración

Requisitos:

* Flutter SDK (canal stable). El paquete apunta a `sdk: ^3.5.0` y
  `flutter: >=3.24.0`.

```bash
git clone <tu-url-de-fork>
cd perfscope
flutter pub get
cd example && flutter pub get && cd ..
```

## Comandos cotidianos

```bash
# Tests unitarios (la suite completa debe seguir en verde)
flutter test

# Formato (CI lo exige exactamente)
dart format --output=none --set-exit-if-changed .
dart format .            # aplicar correcciones localmente

# Análisis estático (cero issues es la barra)
flutter analyze
(cd example && flutter analyze)

# Los docs de API deben compilar sin advertencias que tú introduzcas
dart doc

# Gate de publicabilidad (debe pasar; sin placeholders en pubspec)
dart pub publish --dry-run
```

### Benchmarks

Los cambios sensibles al rendimiento deben venir con números antes/después de
la suite de benchmarks:

```bash
dart run benchmark/frame_classification_benchmark.dart
dart run benchmark/ring_buffer_benchmark.dart
dart run benchmark/anomaly_creation_benchmark.dart
dart run benchmark/statistics_benchmark.dart
dart run benchmark/serialization_benchmark.dart
```

Los números son específicos de cada máquina — repórtalos como deltas
relativos de tu propia máquina, nunca como afirmaciones absolutas para el
README.

## Expectativas de pull request

* **Commits por unidad de trabajo.** Cada commit es una unidad revisable que
  compila y pasa tests por sí sola. Los tests y la documentación viajan con el
  código que cubren, no en un commit separado de "arreglar tests".
* **Tests incluidos.** Cada cambio de comportamiento o arreglo de bug incluye
  un test que falla sin él. Los arreglos de bugs fijan el bug primero.
* **Docs actualizados.** Los cambios de API pública actualizan los snippets
  del README y los comentarios de doc en el mismo PR. Las muestras de código
  del README deben compilar contra firmas reales.
* **Sin dependencias nuevas sin justificación.** El conjunto de dependencias
  es deliberadamente mínimo (Flutter SDK + `args`). Cualquier dependencia
  nueva necesita una justificación por escrito en la descripción del PR que
  cubra por qué no se puede evitar y qué cuesta (tamaño, cadena de suministro,
  alcance de plataformas).
* **Issue primero.** Abre un issue (o comenta en uno existente) describiendo
  el problema antes de refactors grandes o features nuevas. Los arreglos
  pequeños y obvios pueden adelantarse — enlaza el issue de todas formas
  cuando exista uno.

## Guía de alcance

PerfScope es observabilidad solo-local. Los rechazos son casi seguros para:

* cualquier cosa que agregue acceso a red, telemetría o analítica,
* features de sincronización en la nube (las apps host son dueñas del
  transporte),
* trabajo pesado por frame en la ruta caliente (clasificar + encolar solo),
* métricas especulativas sin un mecanismo de recolección honesto y documentado.

## Reportando bugs

Incluye: versión de Flutter (`flutter --version`), plataforma, una
reproducción mínima y — cuando sea relevante — un archivo JSON de sesión
exportado. Sanea cualquier metadato que hayas adjuntado mediante
`PerfScope.setMetadata`; los archivos de sesión contienen exactamente lo que
tu app puso allí.
