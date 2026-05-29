# Visão geral

## O que é o app

Hero Play é um **leitor de listas IPTV M3U**. O usuário importa uma lista
(por URL ou arquivo), e o app organiza o conteúdo em três eixos — **canais ao
vivo**, **filmes** e **séries** — com player integrado, favoritos, histórico,
continuar assistindo, EPG (guia de programação) e metadados do TMDB.

Tudo é **local-first**: não há backend próprio de contas ou conteúdo. O único
serviço externo é um proxy serverless do TMDB (só para metadados). As listas,
favoritos e progresso ficam no dispositivo (Hive).

## Princípios de arquitetura

1. **Local-first.** O estado de verdade vive no dispositivo. A rede é usada para
   baixar a lista M3U, o XMLTV (EPG) e metadados TMDB — nada disso é obrigatório
   para o app funcionar.
2. **Camadas com dependência unidirecional.** `models ← services ← state ← UI`.
   A UI nunca fala direto com I/O; sempre passa pelo `state`.
3. **Parsing pesado fora da UI thread.** M3U e XMLTV podem ter dezenas de MB.
   Operações caras rodam em isolate via `compute()`.
4. **Responsivo por form factor, não por plataforma.** Um único código serve
   phone / tablet / desktop. A decisão de layout é centralizada em
   [`utils/layout.dart`](../lib/utils/layout.dart).
5. **Tolerância a sujeira.** Listas IPTV reais são caóticas (nomes com tags de
   qualidade, acentos faltando, duplicatas). Os pipelines normalizam e agrupam
   defensivamente — ver [pipeline-de-dados.md](pipeline-de-dados.md).

## Stack

| Camada | Tecnologia |
|---|---|
| Framework | Flutter (Dart SDK `^3.12.0`) |
| Estado | `provider` (`ChangeNotifier`) |
| Persistência | `hive` + `hive_flutter` (NoSQL local) |
| Player de vídeo | `media_kit` (libmpv) — HLS, MPEG-TS, RTSP, codecs exóticos |
| Rede | `http` |
| Metadados | TMDB via proxy serverless (Vercel + Node.js) |
| Fontes | `google_fonts` (Manrope) |
| Config | `flutter_dotenv` (`.env`) |

**Por que libmpv e não ExoPlayer/video_player?** Streams IPTV ao vivo usam
formatos e codecs que os players nativos frequentemente recusam. libmpv (o motor
do mpv) reproduz praticamente tudo, o que é essencial aqui.

## Fluxo de dados de alto nível

```
┌─────────────┐   importa     ┌──────────────┐   parse     ┌──────────┐
│   Usuário   │ ────────────► │ CarregadorM3U│ ──────────► │ ParserM3U│
└─────────────┘  URL/arquivo  └──────────────┘   texto     └────┬─────┘
                                                                 │ List<Canal>
                                                                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          IptvProvider (state)                          │
│  • mantém listas, favoritos, histórico, progresso, "minha lista"       │
│  • persiste tudo via Armazenamento (Hive)                              │
│  • expõe getters reativos + ações para a UI                            │
└───────────────┬────────────────────────────────────────────┬─────────┘
                │ notifyListeners()                            │
                ▼                                              ▼
┌──────────────────────────┐                    ┌──────────────────────────┐
│  Telas (screens/)        │  agrupamento p/ UI │  Serviços auxiliares      │
│  • TelaInicial (home)    │ ◄───────────────►  │  • agrupador_canais       │
│  • TelaCanais/Filmes/... │   (ao vivo / VOD)  │  • Serie.agrupar (séries) │
│  • TelaPlayer            │                    │  • ServicoEpg / TmdbService│
└──────────────────────────┘                    └──────────────────────────┘
```

### Caminho de uma importação

1. Usuário cola URL ou escolhe arquivo em `TelaImportar`.
2. `IptvProvider.importarPorUrl/Arquivo` chama `CarregadorLista` (download/leitura).
3. `ParserM3U.parse` transforma o texto em `List<Canal>` (detecta e rejeita
   formatos incompatíveis — HLS manifest, XMLTV).
4. A lista vira um `ListaM3U`, é salva no Hive e marcada como ativa.
5. Se houver `epgUrl`, dispara download do EPG **em background** (não bloqueia).
6. `notifyListeners()` → a home reconstrói com o novo conteúdo.

### Caminho de exibição (home → carrosséis)

- **Ao vivo:** `agruparCanaisAoVivo()` funde variantes de qualidade e fontes
  alternativas do mesmo canal.
- **Filmes/Séries:** `ListaM3U.agruparPorCategoria(filme)` separa por grupo, e
  `Serie.agrupar()` reconhece episódios (`S01E02`, `1x02`) e os agrupa em séries.
- O resultado é **cacheado** por id de lista na `TelaInicial` para não reprocessar
  a cada rebuild.

## Onde começar a ler o código

1. [`lib/main.dart`](../lib/main.dart) — ordem de inicialização.
2. [`lib/state/iptv_provider.dart`](../lib/state/iptv_provider.dart) — o coração.
3. [`lib/services/parser_m3u.dart`](../lib/services/parser_m3u.dart) — entrada de dados.
4. [`lib/screens/tela_inicial.dart`](../lib/screens/tela_inicial.dart) — montagem da UI.

Continue em [camadas.md](camadas.md).