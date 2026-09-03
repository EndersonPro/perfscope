# PerfScope

[![pub package](https://img.shields.io/pub/v/perfscope.svg)](https://pub.dev/packages/perfscope) [![pub points](https://img.shields.io/pub/points/perfscope.svg)](https://pub.dev/packages/perfscope/score) [![likes](https://img.shields.io/pub/likes/perfscope.svg)](https://pub.dev/packages/perfscope/score) [![CI](https://github.com/EndersonPro/perfscope/actions/workflows/ci.yml/badge.svg)](https://github.com/EndersonPro/perfscope/actions/workflows/ci.yml) [![codecov](https://codecov.io/gh/EndersonPro/perfscope/graph/badge.svg)](https://codecov.io/gh/EndersonPro/perfscope) [![License: MIT](https://img.shields.io/github/license/EndersonPro/perfscope.svg)](https://github.com/EndersonPro/perfscope/blob/main/LICENSE) [![Dart](https://img.shields.io/badge/dart-%5E3.5.0-blue.svg)] [![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.24.0-blue.svg)]

**Observabilidade de desempenho local para Flutter.**

- Sem nuvem.
- Sem backend.
- Sem dependência do DevTools.

**Idiomas:** [English](README.md) · [Español](README.es.md) · [Português](README.pt.md)

O PerfScope detecta anomalias de frames, rastreia telas e interações, registra
sessões, compara regressões contra linhas de base e gera relatórios de
desempenho prontos para IA — inteiramente no dispositivo e dentro do processo.

## Por que PerfScope

O DevTools responde "o que aconteceu NESTA sessão conectada?". O PerfScope
responde "como meu app se comporta durante o uso REAL, em dispositivos reais,
ao longo do tempo?" — sem conexão com um desktop:

* **Monitoramento de frames sempre ativo** via
  `SchedulerBinding.addTimingsCallback`, classificado em níveis de severidade
  com uma heurística de provável gargalo.
* **Sessões** que você controla: auto-iniciadas, nomeadas, interrompidas,
  comparadas.
* **Artefatos compartilháveis**: JSON determinístico (schema v1), relatórios
  de texto formatado, tabelas de comparação antes/depois.
* **Saída pronta para IA**: um bloco de contexto otimizado em tokens que você
  pode colar diretamente em uma conversa com um LLM para depurar uma regressão
  de jank.

O PerfScope observa; nunca transmite. Veja [Privacidade](#privacidade).

## Instalação

```bash
flutter pub add --dev perfscope
```

O PerfScope é uma *dependência de desenvolvimento*: é instrumentação que você
executa enquanto desenvolve e analisa o desempenho, não algo que seus usuários
de produção precisam.

## Configuração em 30 segundos

```dart
import 'package:flutter/material.dart';
import 'package:perfscope/perfscope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PerfScope.initialize();
  runApp(const MyApp());
}
```

É isso. Uma sessão inicia automaticamente (`autoStartSession` padrão é `true`),
os frames são classificados conforme chegam, as anomalias são impressas no
console e `await PerfScope.stopSession()` retorna o `PerformanceReport`
completo.

> **Aviso — Somente modo Profile para números confiáveis.**
> Builds de debug carregam asserções e sobrecarga JIT: os tempos de frame
> medidos com `flutter run` (debug) NÃO são representativos do comportamento
> real.
> O PerfScope imprime exatamente um aviso quando inicializado em modo debug:
>
> ```
> [PerfScope] Running in DEBUG mode: performance measurements are NOT
> representative of real-world behavior. Use `flutter run --profile` for
> trustworthy numbers.
> ```
>
> Sempre meça com `flutter run --profile`.

### Configuração estrita somente-profile (recomendada)

O app de exemplo demonstra a disposição mais limpa: os pontos de entrada de
release nunca importam o PerfScope, de modo que o código de observabilidade é
completamente removido dos builds de release. Três arquivos:

```dart
// lib/main.dart — PONTO DE ENTRADA DE RELEASE. Sem import do PerfScope.
import 'app/showcase_app.dart';

void main() => runShowcaseApp();
```

```dart
// lib/main_profile.dart — PONTO DE ENTRADA DE PROFILE. O PerfScope é
// inicializado apenas aqui.
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
// lib/perf_bootstrap.dart — apenas fiação do motor: MemorySink compartilhado,
// PerfScope.initialize(config:, sinks:), abertura/fechamento de sessão nomeada.
```

Execute com:

```bash
flutter run --profile -t lib/main_profile.dart
```

Se seu app também precisar funcionar em builds de debug, inicialize atrás de
uma verificação de modo:
`if (kDebugMode || kProfileMode) PerfScope.initialize();`.

## Vitrine de cenários

O pacote `example/` é um app de vitrine categorizada: cada capacidade do
PerfScope tem uma tela dedicada que explica o que é capturado, exibe o código
de uso exato na tela e renderiza resultados ao vivo de eventos reais do motor —
receitas de jank de frames, tracing, contexto de tela/interação, sessões e
relatórios, console de eventos ao vivo, contexto de IA, exportação JSON e
comparação antes/depois. Ele também demonstra a degradação elegante quando o
PerfScope não está inicializado.

Veja [example/README.md](example/README.md) para instruções de execução, o
mapa cenário-para-API e os snippets de código por categoria.

## Monitoramento de frames

O PerfScope assina o stream de tempos de frame do Flutter uma vez, por início
do motor. Cada frame concluído torna-se um `FrameSample` imutável (durações de
build / raster / total, sobrecarga de vsync) enriquecido com a tela e a
interação atuais, e então é classificado contra o orçamento de frame efetivo:

| Duração total vs orçamento | Nível   |
|----------------------------|---------|
| <= orçamento               | normal  |
| > orçamento                | warning |
| > orçamento x 1.5          | slow    |
| > orçamento x 3            | severe  |

O orçamento padrão é 60 Hz (`targetFrameRate`) e pode ser sobrescrito ou
resolvido pela detecção de taxa de atualização. Os limiares são configuráveis
via `PerformanceThresholds(warningMultiplier:, slowMultiplier:,
severeMultiplier:)`.

A contabilidade por frame é O(1): contadores, somas acumuladas e uma posição de
ring buffer (veja [Sobrecarga de desempenho](#sobrecarga-de-desempenho)). O
cálculo de percentis é adiado para o momento da captura.

## Anomalias

Somente frames slow/severe se tornam anomalias — frames de nível warning
permanecem eventos. Cinco tipos de anomalia vêm prontos:

| Tipo                       | Elevado quando                                                |
|----------------------------|---------------------------------------------------------------|
| `SlowFrameAnomaly`         | frame slow/severe, não foi possível inferir o gargalo           |
| `UiBoundFrameAnomaly`      | o trabalho da thread de UI domina (build >= 2x raster)         |
| `RasterBoundFrameAnomaly`  | o trabalho da thread de raster domina (raster >= 2x build)     |
| `MixedFrameAnomaly`        | Ambas as fases contribuem de forma comparável                   |
| `LongTraceAnomaly`         | Um trace manual excedeu `longTraceThreshold`                    |

Mapeamento de severidade (contrato documentado):

* Anomalias de frame: `slow` -> **high**, `severe` -> **critical**. Frames de
  nível warning nunca chegam à criação de anomalias.
* Anomalias de trace longo escalam com o limiar configurado (padrão 50 ms):
  >= 2x limiar -> **high**, >= 5x -> **critical**, caso contrário **medium**.

O gargalo é uma HEURÍSTICA derivada apenas das formas dos tempos de frame.
Indica a fase *provável* — nunca a causa comprovada. Anomalias recentes são
acessíveis via `PerfScope.anomalies`, e os frames ao redor de cada anomalia de
frame via `PerfScope.contextWindowFor(anomalyId)`.

## Navegação

Anexe o observer e as telas se nomeiam a partir das rotas:

```dart
MaterialApp(
  navigatorObservers: [PerfScopeNavigatorObserver()],
  routes: {'/checkout': (_) => const CheckoutScreen()},
)
```

* Rotas nomeadas tornam-se nomes de tela; frames, anomalias, traces e resumos
  de relatório se atribuem à tela visível.
* Apps sem Navigator podem sobrescrever manualmente:
  `PerfScope.screen('checkout');`.
* Rotas sem nome reportam `'unknown'`. Dê nomes às rotas importantes.

## Interações

Dois estilos complementares:

**Marcador rápido** — uma linha para fluxos tipo tap. O marcador é atribuído ao
próximo lote de frames observado; nada mais a fechar:

```dart
PerfScope.interaction('add_to_cart');
```

**Span** — para fluxos que sobrevivem a um único frame. Retorna um handle;
chame `end()` exatamente uma vez (fechamentos fora de ordem são suportados):

```dart
final handle = PerfScope.startInteraction('checkout');
await pay();
handle.end();
```

Spans aninham: cada `InteractionEvent` carrega o id do span ativo mais interno
como pai, de modo que um `tap_pay` dentro de `checkout` permanece atribuível.
O aninhamento é limitado em 16 níveis (starts descontrolados são bugs do
chamador; starts mais profundos retornam um handle inerte). Frames renderizados
enquanto um span está aberto são atribuídos a ele — correlação temporal, não
causalidade.

## Tracing

Meça o tempo de qualquer operação e alimente tanto o registro da sessão quanto
o Timeline:

```dart
final prices = PerfScope.trace('calculate_prices', () =>
    computePrices(items));

final user = await PerfScope.traceAsync('fetch_user', () => api.getUser());
```

Contrato de exceções: se `body` lançar, o PerfScope registra o trace como
falho (`didThrow`, duração incluída) e então relança o erro ORIGINAL e o stack
trace intactos. Metadados passados via `metadata:` são validados e embutidos
no evento resultante. Traces que excedem `longTraceThreshold` (padrão 50 ms)
elevam uma `LongTraceAnomaly`.

Integração com Timeline: traces síncronos emitem `Timeline.startSync` /
`finishSync`; traces assíncronos emitem spans `TimelineTask` (o SDK não tem
`startSync` assíncrono). Falhas de adaptador são engolidas — problemas de
Timeline nunca podem quebrar o fluxo do app. Traces recentes:
`PerfScope.recentTraces`.

## Sessões

Uma sessão é uma janela de observação gravada. Por padrão, uma inicia
automaticamente em `initialize()`.

```dart
final session = PerfScope.startSession('release-check'); // auto-finaliza qualquer sessão aberta
// ... exercite o app ...
final report = await PerfScope.stopSession(); // PerformanceReport completo
```

* O início duplo é seguro: abrir uma nova sessão auto-finaliza a anterior
  (seu relatório permanece acessível via relatório anexado).
* Chamadas consecutivas a `stopSession()` lançam — não há nada aberto.
* `PerfScope.currentSession` e `PerfScope.lastReport` respondem passivamente;
  nunca lançam.

## Logs

Quatro estilos via `PerfScopeConfig(logStyle:)`: `silent`, `compact`, `pretty`,
`json`. As amostras abaixo são a saída exata do renderizador.

**compact** — uma linha por anomalia/aviso:

```text
PERF ProductList | UI 27.4ms | Raster 4.8ms | Total 33.1ms | Budget 16.7ms | HIGH ui-bound
PERF TRACE calculate_prices | 127.0ms | HIGH
```

**pretty** (padrão) — cartões com caixas desenhadas:

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

**json** — envelopes NDJSON, parseáveis por máquina:

```json
{"schema_version":1,"type":"performance_anomaly","anomaly_type":"ui_bound_frame","event_id":"evt_1","session_id":"ses_1","timestamp":"2026-01-01T00:00:00.000Z","screen":"ProductList","interaction_id":"int_1","frame":{"build_ms":27.4,"raster_ms":4.8,"total_ms":33.1,"budget_ms":16.67},"severity":"high","probable_bottleneck":"ui"}
```

**silent** — sem saída.

Eventos crus ignoram o logging inteiramente via stream broadcast
`PerfScope.events` e sinks injetáveis.

## Relatórios

Parar uma sessão renderiza uma caixa de resumo de largura fixa (layout idêntico
via `TextExporter` ou `formatReportText`):

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

Os relatórios classificam telas e interações de forma determinística (contagem
de anomalias, depois p95, depois nome) e listam as piores anomalias primeiro.

## Exportação JSON

JSON determinístico de uma linha, schema versão 1:

```dart
final json = PerfScope.exportCurrentSessionAsJson();

// Depois de stopSession() não há mais sessão ABERTA; a exportação cai para o
// relatório anexado da última sessão finalizada em vez de retornar null,
// então a exportação pós-stop simplesmente funciona.
final report = await PerfScope.stopSession();
final stopped = PerfScope.exportCurrentSessionAsJson();
```

Garantia de ida e volta — tudo o que o writer emite, o parser lê de volta:

```dart
final parsed = SessionParser().parseString(json);
expect(parsed.session.id, originalId); // em testes
```

Os destinos são preocupações do host; o PerfScope inclui três seams:

* `CallbackExporter(onJson:)` — você decide para onde os bytes vão.
* `InMemoryExporter` — armazena strings JSON para testes/telas de debug.
* `TextExporter` — caixa de resumo legível por humanos.

## Contexto de IA

Uma chamada transforma um relatório em contexto pronto para LLM
(`report.toAiContext()` ou `buildAiContextText(report)`):

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

A saída é otimizada em tokens, com limite rígido e nunca inventa dados que não
possui. Envie pelo CLI: `dart run perfscope:perfscope ai-context
session.json > context.txt`.

Prompt recomendado para acompanhar:

```text
You are a senior Flutter performance engineer. Below is a PerfScope session
summary captured on-device in profile mode. Identify the most probable root
causes, rank them by user impact (p95/worst frames, anomaly density), and
propose concrete code-level fixes. Treat probable_bottleneck values as
heuristics derived from frame timing shapes, not proven causes; recommend
timeline tracing where certainty is needed.

<paste context.txt here>
```

## Comparações antes/depois

Comparação pura, sem motor, de dois relatórios quaisquer:

```dart
final comparison = PerfScope.compareSessions(baselineReport, candidateReport);
print(formatSessionComparison(comparison));
```

Ou direto de arquivos:

```bash
dart run perfscope:perfscope compare baseline.json candidate.json
```

Os deltas de métricas são reportados por rótulo (frames, p50/p95/p99, pior
frame, anomalias, ...) de modo que regressões aparecem como porcentagens com
sinal em vez de intuições.

## CLI

Ferramentas offline sobre arquivos de sessão exportados:

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

Verifique seu ambiente (saída real; versões variam por máquina):

```text
$ dart run perfscope:perfscope doctor
ok   Flutter detected (3.44.1)
ok   Dart detected (3.12.1)
ok   pubspec.yaml found
ok   Project detected (perfscope)

Recommended performance mode:
  flutter run --profile
```

## Privacidade

O PerfScope NÃO coleta NADA e NÃO transmite NADA. Não há código de rede no
pacote — nem telemetria, nem relatório de erros, nem "estatísticas de uso
anônimas". Explicitamente, o PerfScope nunca toca:

* identificadores de dispositivo ou IDs de publicidade,
* identificadores de usuário ou dados de conta,
* conteúdos de tela, texto digitado ou imagens renderizadas,
* crash logs ou stack traces das SUAS exceções (apenas as falhas de traces do
  próprio PerfScope são registradas, localmente),
* nenhuma pipeline de análise ou telemetria.

Tudo vive em memória limitada dentro do processo até VOCÊ exportar pelo seu
próprio canal escolhido. Os ids de correlação (`ses_1`, `anm_2`, `trc_3`) são
apenas números de sequência locais — úteis dentro de um processo, sem
significado fora dele.

## Sobrecarga de desempenho

Contabilidade honesta:

* O trabalho por frame é classificação mais enfileiramento APENAS: algumas
  comparações de inteiros, atualizações de contadores e uma escrita de posição
  em um ring buffer pré-alocado. Sem alocação por frame, sem ordenação, sem
  construção de strings.
* Os percentis ordenam uma janela limitada (padrão 10.000 amostras) apenas
  quando ocorre uma captura/exportação — nunca no caminho do frame.
* Números absolutos variam por dispositivo; não confie nos benchmarks de
  ninguém, incluindo estes docs. Execute você mesmo:

```bash
dart run benchmark/frame_classification_benchmark.dart
dart run benchmark/ring_buffer_benchmark.dart
dart run benchmark/anomaly_creation_benchmark.dart
dart run benchmark/statistics_benchmark.dart
dart run benchmark/serialization_benchmark.dart
```

Cada um imprime a mediana em ns/op e ops/seg sobre lotes cronometrados após o
warmup.

## Suporte de plataformas

| Capacidade                             | Android | iOS | macOS | Windows | Linux | Web |
|----------------------------------------|---------|-----|-------|---------|-------|-----|
| Monitoramento de frames (`FrameTiming`) | sim     | sim | sim   | sim     | sim   | ?   |
| Tracing / interações manuais           | sim     | sim | sim   | sim     | sim   | sim |
| Sessões, relatórios, JSON, CLI          | sim     | sim | sim   | sim     | sim   | sim |

A detecção de taxa de atualização depende da plataforma: onde o SO não revela a
taxa real de atualização da tela, o PerfScope cai para o orçamento configurado
e informa isso no ambiente da sessão (`frameBudgetSource`).

A coluna web para monitoramento de frames é um `?` honesto: o comportamento de
`addTimingsCallback` na web não é documentado upstream, então o PerfScope não
faz nenhuma afirmação que não possa verificar. Todo o resto é Dart puro e
funciona em qualquer lugar onde Dart roda.

## Arquitetura

Uma olhada em `lib/src`:

```
core/          fiação do motor, config, abstração de clock, geradores de id
frames/        FrameSample, classificador, orçamentos, fonte de frames do Flutter
anomalies/     modelos de anomalia, detector, janelas de contexto de frames
buffers/       RingBuffer — a única estrutura mutável do caminho quente
context/       rastreador de tela, rastreador de interações, store de metadados
events/        a hierarquia de eventos tipada (frame/screen/interaction/trace/anomaly/lifecycle)
sessions/      ciclo de vida de sessões e agregados
reporting/     estatísticas, resumos de tela/interação, construtor de relatórios, comparações
serialization/ schema v1, serializador, parser (ida e volta segura)
exporters/     exporters de callback / em memória / texto
logging/       escritor de logs + renderizadores silent/compact/pretty/json
navigation/    observer de navigator
traces/        rastreamento de traces manuais, adaptadores de Timeline
sinks/         sinks de eventos de console/json/memória
ai/            construtores de contexto de IA
cli/           interface de linha de comando offline
testing/       fakes e fixtures de teste
```

Dependências: Flutter SDK e `args` (parsing de CLI). Nada mais.

## Limitações

* **FrameTiming não pode nomear funções culpadas.** O motor vê durações por
  fase, não amostras de stack. `probableBottleneck` é uma heurística sobre
  formas de tempos; atribuir culpa a widgets específicos requer tracing de
  Timeline (que o PerfScope facilita, mas não falsifica).
* **Os percentis vêm de uma janela deslizante limitada**
  (`maxStatisticSamples`, padrão 10.000). Sessões longas descrevem seu passado
  recente, não sua história completa; contadores e somas permanecem exatos o
  tempo todo.
* **Rotas sem nome reportam `'unknown'`.** Dê nomes às suas rotas.
* **O monitoramento de frames na web não é verificado.** O comportamento de
  `addTimingsCallback` na web não é documentado upstream; trate a coluna web
  acima como desconhecida, não como quebrada.
* **Os ids de correlação são locais ao processo** — nunca os use como chaves
  de banco de dados.

## Roadmap

* **v0.2** — direção de ponte em runtime: expor sessões/streams ao vivo para
  ferramentas externas (integração estilo MCP) para que agentes e dashboards
  possam consultar o PerfScope enquanto o app roda.
* Mais tarde — métricas adicionais além de frames/traces: CPU, memória, pressão
  de GC, atividade de isolates. Cada uma chega apenas com um mecanismo de
  coleta honesto e documentado.

## Contribuindo

Issues e PRs são bem-vindos — veja [CONTRIBUTING.md](CONTRIBUTING.md) para
configuração, gates de qualidade e expectativas.

## Licença

[MIT](LICENSE)
