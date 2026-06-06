# Modelos de dados

Todos em [`lib/models/`](../lib/models/). Estruturas puras com `toMap()` /
`fromMap()` para persistência no Hive.

## `Canal` — [canal.dart](../lib/models/canal.dart)

A unidade central. Representa **qualquer** item de uma lista M3U: um canal ao
vivo, um filme, ou um episódio de série (séries são montadas a partir de canais).

| Campo | Tipo | Descrição |
|---|---|---|
| `nome` | `String` | Nome de exibição (ex.: `"Globo HD"`, `"Avatar (2009)"`) |
| `url` | `String` | URL do stream |
| `logoUrl` | `String?` | Logo/poster (`tvg-logo` da M3U) |
| `grupo` | `String` | Categoria (`group-title`); default `"Sem categoria"` |
| `tvgId` | `String?` | Id EPG (`tvg-id`) — liga ao `Programa` do XMLTV |
| `tipo` | `TipoCanal` | `aoVivo` ou `filme` (VOD) |
| `variantes` | `List<Canal>` | Variantes de qualidade do mesmo canal (SD/HD/FHD) |
| `idGrupo` | `String?` | Id estável de canal agrupado (não muda ao trocar qualidade) |
| `fontes` | `List<Canal>` | Fontes alternativas (streams de backup do mesmo canal) |
| `duracaoSegundos` | `int?` | Duração extraída do `#EXTINF` (usado para ordenar filmes) |

Getters importantes:
- `id` → `idGrupo ?? url` (identidade estável).
- `agrupado` → tem 2+ variantes de qualidade.
- `temFontes` → tem fontes alternativas.

**Classificação `aoVivo` vs `filme`** é feita no parser por: extensão de vídeo na
URL (`.mp4`, `.mkv`…) **ou** palavra-chave no `group-title` (`filme`, `serie`,
`vod`…). Ver [servicos.md](servicos.md).

## `Serie` — [serie.dart](../lib/models/serie.dart)

Agrupa episódios (que são `Canal`s) sob um nome de série. **Não é persistida
diretamente** — é derivada em runtime a partir dos canais VOD.

| Campo | Tipo |
|---|---|
| `nome` | `String` |
| `logoUrl` | `String?` |
| `grupo` | `String` |
| `episodios` | `List<Canal>` (ordenados por temporada/episódio) |

Lógica de domínio (estática):
- `nomeSerie(nomeCanal)` — extrai o nome da série de `"The Boys S01E02"` →
  `"The Boys"`. Reconhece `SxxExx` e `1x02`. Retorna `null` se não for episódio.
- `seasonOf` / `episodeOf` / `episodeLabel` — extraem temporada/episódio.
- `agrupar(List<Canal>)` → `AgrupamentoConteudo(filmes, series)`: separa filmes
  puros de séries e monta os objetos `Serie`.
- `totalEpisodios`, `totalTemporadas`.

Esse é o coração da separação filme/série — ver [pipeline-de-dados.md](pipeline-de-dados.md).

## `ListaM3U` — [lista_m3u.dart](../lib/models/lista_m3u.dart)

Uma lista importada inteira. Guarda os canais **já parseados** para não
reparsear o M3U a cada abertura.

| Campo | Tipo |
|---|---|
| `nome` | `String` (escolhido pelo usuário) |
| `fonte` | `String` (URL ou caminho — também é o `id`) |
| `origem` | `OrigemLista` (`url` ou `arquivo`) |
| `canais` | `List<Canal>` |
| `atualizadaEm` | `DateTime` |
| `epgUrl` | `String?` (XMLTV opcional) |

Getters de conveniência: `canaisAoVivo`, `filmes`, `grupos`,
`agruparPorCategoria(tipo)`, `totalCanais`. `id == fonte` (uma fonte é única).

`copyWith` existe mas **não consegue setar campos opcionais para null** (usa
`?? this.x`) — por isso `atualizarEpgUrl` instancia o objeto diretamente quando
precisa remover o EPG.

## `Programa` — [programa.dart](../lib/models/programa.dart)

Um programa da grade EPG (vem do XMLTV `<programme>`).

| Campo | Tipo |
|---|---|
| `tvgId` | `String` (liga ao `Canal.tvgId`) |
| `inicio` / `fim` | `DateTime` (UTC após parse) |
| `titulo` | `String` |
| `descricao` | `String?` |

Métodos: `ehAtual([agora])`, `ehFuturo([agora])`, `duracao`.

## Modelos de apoio

| Modelo | Arquivo | Papel |
|---|---|---|
| `CanalAssistido` | [canal_assistido.dart](../lib/models/canal_assistido.dart) | Entrada de histórico: `Canal` + `ultimaVistaEm` |
| `ProgressoCanal` | [progresso_canal.dart](../lib/models/progresso_canal.dart) | "Continuar assistindo": `url`, `posicaoSeg`, `duracaoSeg`, `fracao` |
| `CategoriaPersonalizada` | [categoria_personalizada.dart](../lib/models/categoria_personalizada.dart) | Categoria criada pelo usuário: `id`, `nome`, `canais` |
| `IdiomaApp` | [idioma_app.dart](../lib/models/idioma_app.dart) | Idioma (código BCP-47 + rótulo) |
| `Perfil` | [perfil.dart](../lib/models/perfil.dart) | Perfil de uso: `id` (uuid), `nome`, `icone`, e config própria (`idioma`, `autoQualidade`, ordenações). `toMap/fromMap` (Hive) + `toCloudMap/fromCloudMap` (Supabase). Ordenações guardadas como String crua para não depender de `state` |

## Convenção de serialização

Todos usam `Map<String, dynamic>` simples (sem code generation do Hive). Vantagem:
fácil de evoluir o schema sem migrações de TypeAdapter. Campos opcionais são
omitidos do mapa quando `null` e lidos com `as T?` na volta — o que torna a
leitura de dados antigos **retrocompatível** (campos novos viram `null`).

Exemplo (`Canal`):
```dart
Map<String, dynamic> toMap() => {
      'nome': nome, 'url': url, /* ... */
      if (duracaoSegundos != null) 'duracaoSegundos': duracaoSegundos,
    };

factory Canal.fromMap(Map map) => Canal(
      nome: map['nome'] as String? ?? 'Sem nome',
      duracaoSegundos: map['duracaoSegundos'] as int?, // null em listas antigas
      /* ... */
    );
```