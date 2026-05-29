# Serviços

Em [`lib/services/`](../lib/services/). Toda a lógica de I/O, parsing, controle
de player e integração externa. Recebem dependências por construtor (testáveis)
e não conhecem widgets.

## Entrada de dados (listas)

### `CarregadorLista` — [carregador_lista.dart](../lib/services/carregador_lista.dart)
Obtém o **texto bruto** de uma lista, por URL (HTTP) ou arquivo local. Não
parseia nada — essa separação permite testar o parser sem rede.

- `baixarDeUrl(url)` — `http.get` com timeout de 30s; mensagens de erro
  específicas (status HTTP, sem internet, URL inválida).
- `lerDeArquivo(caminho)`.
- Decodificação **tolerante**: tenta UTF-8, cai para latin1 se inválido (listas
  IPTV BR às vezes vêm em latin1).
- Erros viram `CarregamentoListaException`.

### `ParserM3U` — [parser_m3u.dart](../lib/services/parser_m3u.dart)
Converte o texto M3U Extended em `List<Canal>`.

Pontos-chave:
- **Detecção de formato incompatível antes de parsear.** Se o conteúdo for um
  manifesto HLS (`#EXT-X-TARGETDURATION`…) ou um XMLTV (`<?xml`, `<tv`), lança
  `FormatoNaoSuportadoException('hls' | 'epg')` — a UI mostra orientação
  específica em vez de erro genérico.
- Lê pares `#EXTINF` + linha de URL. De cada `#EXTINF` extrai: `tvg-logo`,
  `group-title`, `tvg-id`, o nome (após a vírgula) e a **duração** (número logo
  após `#EXTINF:`; `-1`/`0` viram `null`).
- **Classificação `aoVivo` vs `filme`**: extensão de vídeo na URL (`.mp4`,
  `.mkv`, `.avi`…) ou palavra-chave no grupo (`filme`, `serie`, `vod`…).
- Parsing resiliente: linhas malformadas individuais são ignoradas.

## Players de vídeo

Dois **singletons** baseados em `media_kit` (libmpv). O padrão singleton existe
para evitar o bug de **vazamento de superfície EGL no Windows** — criar um
`Player`/`VideoController` novo a cada vídeo causa `"Failed to create EGL
surface"` após algumas aberturas.

### `PlayerAoVivo` — [player_ao_vivo.dart](../lib/services/player_ao_vivo.dart)
Player reutilizável para **canais ao vivo** em tela cheia. Propriedades mpv
ajustadas: `cache=no`, readahead curto, `network-timeout=5`; no Android,
`hwdec=mediacodec-copy` (evita falhas de Surface quando o EPG roda em background).

Diferença do VOD: um canal ao vivo pode ser **transferido para o mini player**
ao minimizar. Nesse caso `liberarSeAtual(player)` solta o singleton — o player
passa a pertencer ao mini player e o próximo canal cria uma instância nova.

### `PlayerVod` — [player_vod.dart](../lib/services/player_vod.dart)
Player único para **filmes e episódios**. VOD nunca usa mini player (só ao vivo
minimiza), então uma instância basta. Readahead maior (10s) que o ao vivo.

> O **estado** do mini player (posição, tamanho, mudo) fica em
> `MiniPlayerProvider` — ver [estado.md](estado.md). Os singletons aqui só
> gerenciam o **handle nativo** do libmpv.

## EPG (guia de programação)

### `CarregadorEpg` / `ParserEpg` / `ServicoEpg`
- `CarregadorEpg` baixa o XMLTV (pode ter 30MB+).
- `ParserEpg` transforma o XMLTV em `Map<tvgId, List<Programa>>`.
- `ServicoEpg` ([servico_epg.dart](../lib/services/servico_epg.dart)) **orquestra**:
  download → parse **em isolate** (`compute(_parseIsolate, …)`) → cache em
  memória + persistência no Hive. É também `ChangeNotifier` para a UI reagir ao
  estado de carregamento.

Garantias do `ServicoEpg`:
- **Cache em memória** por id de lista (`_grades`) — evita reparsear o XMLTV
  toda vez que um canal abre.
- **Carregamento preguiçoso do disco** (`carregarDoDisco`, idempotente).
- **Deduplicação de downloads** (`_baixando`) — abrir vários canais em sequência
  não dispara downloads paralelos da mesma grade.
- Lookups: `programaAtual`, `agenda`, `agendaCurta`, `programasPara`.

## Metadados externos

### `TmdbService` — [tmdb_service.dart](../lib/services/tmdb_service.dart)
Busca poster (carrosséis de série), sinopse, ano e elenco no TMDB **através de um
proxy** (a chave de API fica server-side — ver [build-e-deploy.md](build-e-deploy.md)).

- Dois caches em memória independentes (`_cachePoster`, `_cacheInfo`) — cada
  consulta é feita uma vez por sessão.
- `_prepararQuery` limpa o nome IPTV antes de consultar (remove `4K`, `1080p`,
  `LEG`, `DUB`, anos entre parênteses, pontos/underscores) — caso contrário a
  busca no TMDB falha.
- **Ranking de match** por prioridade: exato → começa com → contém → todas as
  palavras → primeiro resultado (mais popular). Cobre nomes sujos de IPTV.
- Tudo é best-effort: sem proxy configurado ou em erro de rede, retorna vazio e
  o app segue funcionando.

## Persistência

### `Armazenamento` — [armazenamento.dart](../lib/services/armazenamento.dart)
Fachada única sobre o Hive. Abre todas as boxes em `inicializar()` (chamado uma
vez no `main`). Toda leitura/escrita de disco passa por aqui. Detalhe das boxes e
chaves em [persistencia.md](persistencia.md).