# Vitrine de cenários do PerfScope

**Idiomas:** [English](README.md) · [Español](README.es.md) · [Português](README.pt.md)

Um app de vitrine profissional e categorizado que exercita cada capacidade do
PerfScope contra a superfície de API real — sem mocks, sem fakes. Cada cenário
é uma tela dedicada que explica o que o PerfScope captura, mostra o código de
uso exato na tela (correto para copiar e colar) e renderiza resultados ao vivo
de eventos reais do motor.

## Pontos de entrada

### Recomendado: modo profile com PerfScope habilitado

```bash
flutter run --profile -t lib/main_profile.dart
```

`main_profile.dart` chama `bootstrapPerfScope()` de `perf_bootstrap.dart`, que
inicializa o motor com `PerfScopeConfig(printWarnings: true)`, registra um
`MemorySink` compartilhado, abre a sessão nomeada `'showcase'` e anexa
`PerfScopeNavigatorObserver()` para que rotas nomeadas se tornem nomes de tela.

Executar em builds de debug em vez disso imprime exatamente uma linha de aviso:

```text
[PerfScope] Running in DEBUG mode: performance measurements are NOT representative of real-world behavior. Use `flutter run --profile` for trustworthy numbers.
```

Os números de frame medidos em modo debug carregam asserções e sobrecarga JIT;
trate-os como direcionais apenas.

### Linha de base segura para release (vitrine degradada)

```bash
flutter run -t lib/main.dart
```

`main.dart` não contém import do PerfScope nem inicialização. O app ainda
funciona: cada tela de cenário detecta o motor desabilitado e substitui sua
área de ação por um aviso explícito ("PerfScope is disabled in this entry
point...") em vez de quebrar ou mostrar silenciosamente resultados vazios. A
tela inicial mostra um banner de status equivalente. Use este ponto de entrada
para verificar que os builds de release permanecem limpos.

## Cenários

| Categoria | Cenário | Rota | API exercitada | O que observar |
| --- | --- | --- | --- | --- |
| Frames | Linha de base de navegação fluida | `/frames/smooth-navigation` | `PerfScopeNavigatorObserver` | ScreenEvents com nomes de rota; zero anomalias |
| Frames | Jank da thread de UI | `/frames/ui-thread-jank` | nenhuma (detecção passiva) | Anomalias de frames slow/severe, provável gargalo UI |
| Frames | Pressão de raster | `/frames/raster-pressure` | nenhuma (detecção passiva) | Anomalias ligadas a raster; raster_ms dominando |
| Frames | Lista de scroll longa | `/frames/long-scroll-list` | nenhuma (detecção passiva) | Contagem crescente de frames slow sob um nome de tela |
| Tracing | Trace síncrono | `/tracing/sync-trace` | `PerfScope.trace`, `recentTraces` | Registros CompletedTrace com metadados anexados |
| Tracing | Trace assíncrono: operação longa | `/tracing/async-trace-long-operation` | `PerfScope.traceAsync`, `anomalies` | LongTraceAnomaly escalada contra `longTraceThreshold` |
| Context | Spans de interação | `/context/interaction-spans` | `startInteraction`, `interaction` | Pares start/end com durações; marcadores rápidos |
| Context | Sobrescrita de contexto de tela | `/context/screen-context` | `screen()`, `setMetadata` | ScreenEvent com motivo `manual`; fusão de metadados |
| Sessions & reports | Relatório de sessão | `/sessions/session-report` | `startSession`, `stopSession`, `formatReportText` | Caixa de relatório de texto completo na tela |
| Sessions & reports | Console de eventos ao vivo | `/sessions/live-event-console` | `events`, `MemorySink` | Hierarquia de eventos selada crua, colorida por severidade |
| AI & export | Visualizador de contexto de IA | `/ai-export/ai-context-viewer` | `report.toAiContext()` | Bloco PERFSCOPE_SESSION otimizado em tokens |
| AI & export | Exportação JSON de sessão | `/ai-export/session-json-viewer` | `exportCurrentSessionAsJson` | JSON determinístico schema-v1 |
| AI & export | Comparação antes / depois | `/ai-export/before-after-compare` | `compareSessions`, `formatSessionComparison` | Deltas com sinal; avisos de amostra pequena esperados |

Os loops de trabalho são adaptativos ao dispositivo: primeiro medem um lote de
teste e escalam para a duração alvo, nunca fixando contagens de iterações.

## Snippets de uso por categoria

Fragmentos reais — o mesmo código que cada tela exibe.

### Frames

```dart
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/products': (_) => const ProductsScreen()},
);
// Named routes become PerfScope screen names automatically.
```

As receitas de jank não precisam de API alguma: trabalho síncrono dentro de
`build` ou decorações de pintura caras estouram o orçamento e o PerfScope
classifica os frames por conta própria (`UiBoundFrameAnomaly`,
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

### Sessões e relatórios

```dart
PerfScope.startSession('release-check'); // auto-finalizes previous
await runWorkload();
final report = await PerfScope.stopSession();
print(formatReportText(report)); // reports have NO toText()

PerfScope.events.listen((PerformanceEvent event) {
  if (event is AnomalyEvent) debugPrint(event.anomaly.severity.name);
});
```

### IA e exportação

```dart
Clipboard.setData(ClipboardData(text: report.toAiContext()));
final json = PerfScope.exportCurrentSessionAsJson();

final comparison = PerfScope.compareSessions(beforeReport, afterReport);
print(formatSessionComparison(comparison)); // negative delta = improvement
```

## Estrutura do projeto

```text
lib/
  main.dart                  ponto de entrada seguro para release (sem PerfScope)
  main_profile.dart          ponto de entrada de profile: bootstrap + navigator observer
  perf_bootstrap.dart        MemorySink compartilhado + helpers de inicialização/desligamento
  app/
    showcase_app.dart        casca MaterialApp e rotas nomeadas
    scenario.dart            modelo Scenario, categorias, catálogo
    scenario_card.dart       cartão da lista inicial por cenário
    scenario_scaffold.dart   scaffold de detalhe compartilhado (resumo/capturas/código)
    code_block.dart          contêiner de snippet monoespaçado selecionável
    busy_work.dart           helper adaptativo de spin de CPU compartilhado por cenários
  scenarios/
    frames/                  linha de base de navegação + três receitas de jank
    tracing/                 traces síncronos e traces assíncronos longos
    context/                 spans de interação e contexto de tela manual
    sessions/                relatórios de sessão e console de eventos ao vivo
    ai_export/               contexto de IA, exportação JSON, comparação antes/depois
```

## Testes de ponta a ponta

`integration_test/perfscope_e2e_test.dart` conduz este app pelos tiles da tela
inicial (chaves `menu-tile<route>`) através de um motor real com um `MemorySink`
injetado, verificando a detecção de anomalias de frames, o ciclo de vida de
sessões, o parsing de ida e volta de JSON e a atribuição de telas por rotas
nomeadas.
