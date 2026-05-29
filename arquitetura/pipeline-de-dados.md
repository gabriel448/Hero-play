# Pipeline de dados

Listas IPTV reais são caóticas: o mesmo canal aparece em SD/HD/FHD, com tags no
nome, fontes de backup duplicadas, acentos faltando e episódios soltos. Os
pipelines abaixo transformam essa sujeira em estruturas limpas para a UI.

```
texto M3U
   │  ParserM3U.parse
   ▼
List<Canal>  ─────────────┬──────────────────────────┐
   │ tipo == aoVivo       │ tipo == filme (VOD)        │
   ▼                      ▼                            ▼
agruparCanaisAoVivo   agruparPorCategoria(filme)   (na home: conta séries)
   │                      │
   │                      ▼
   │                  Serie.agrupar  ──► filmes puros + List<Serie>
   ▼
categorias com canais agrupados (variantes + fontes)
   │  (opcional)
   ▼
agruparPorQualidade  ──► pseudo-categorias FHD / HD / SD
```

## 1. Qualidade — [utils/qualidade.dart](../lib/utils/qualidade.dart)

Base de quase tudo. Detecta a resolução pelo nome e extrai o **nome-base**.

- `Qualidade { uhd, fhd, hd, sd, desconhecida }` com `rank` (ordenação) e
  `rotulo` (`4K`/`FHD`/`HD`/`SD`/`Padrao`).
- `detectarQualidade(texto)` — regex por faixa, da melhor p/ pior. `\b` evita que
  `HD` case dentro de `FHD`/`UHD`.
- `nomeBase(nome)` — remove tags de qualidade **e codec** (H265, HEVC…) e
  separadores soltos: `"Globo Minas HD"` → `"Globo Minas"`. Números (`ESPN 2`)
  são preservados (canais distintos).
- `nomeFonte(nome)` — remove marcadores de **fonte alternativa** brasileiros:
  asterisco, sufixo ` BR`, dígitos sobrescritos (`²³`). `"Globo SP HD*"` →
  `"Globo SP"`.
- `categoriaBase(grupo)` — `"CANAIS FHD"` → `"CANAIS"` (funde categorias que só
  diferem por qualidade).

## 2. Agrupamento ao vivo — [services/agrupador_canais.dart](../lib/services/agrupador_canais.dart)

`agruparCanaisAoVivo(List<Canal>)` → `Map<categoria, List<Canal>>`, em **dois
passos**, preservando a ordem de aparição:

**Passo 1 — variantes de qualidade.** Agrupa por `(categoriaBase, nomeBase)`. Se
um canal aparece em 2+ resoluções, vira **um** `Canal` agrupado com
`variantes` ordenadas (melhor primeiro), `idGrupo` estável e o logo da melhor
variante que tiver. Canal único passa direto (só re-rotula a categoria fundida).

**Passo 2 — fontes alternativas** (`_agruparFontes`). Funde canais que são
backups do mesmo canal (`"Globo SP"`, `"Globo SP*"`, `"Globo SP 2"`) em um
`Canal` com `fontes` preenchido. A fonte "principal" é a sem asterisco/número,
desempate por nome mais curto. Cada fonte mantém suas próprias variantes de
qualidade.

### Pseudo-categorias por qualidade
`agruparPorQualidade(categoriasAoVivo)` gera categorias virtuais **FHD / HD /
SD**, cada uma listando os canais naquela resolução com a URL da variante exata.
Permite abrir direto numa qualidade sem trocar dentro do player. Categorias
vazias são omitidas; ordem FHD → HD → SD.

## 3. Filmes vs. séries — [models/serie.dart](../lib/models/serie.dart)

VOD entra como `Canal` cru. `Serie.agrupar(List<Canal>)`:

1. Para cada canal, `nomeSerie(nome)` tenta extrair o nome da série reconhecendo
   `SxxExx` (case-insensitive) ou `1x02`. Ex.: `"The Boys S01E02 1080p"` →
   `"The Boys"`.
2. Sem match → é **filme puro**. Com match → vira episódio agrupado sob a série.
3. Episódios são ordenados por temporada e número (`seasonOf`/`episodeOf`).
4. Retorna `AgrupamentoConteudo(filmes, series)`.

`nomeSerie` também **limpa** o nome (tags de idioma/qualidade/ano, pontos e
underscores) para que episódios da mesma série caiam no mesmo balde.

## 4. Onde cada pipeline roda

| Pipeline | Disparado em | Cacheado? |
|---|---|---|
| `ParserM3U.parse` | Importação (`IptvProvider`) | Resultado salvo no `ListaM3U` (Hive) |
| `agruparCanaisAoVivo` | `TelaInicial._atualizarCache` | Sim, por id de lista |
| `agruparPorCategoria(filme)` | `TelaInicial._atualizarCache` | Sim, por id de lista |
| `Serie.agrupar` | Telas de filmes/séries (`compute`) | Em estado de tela |
| `agruparPorQualidade` | Sob demanda (menu de qualidade) | Não |

Trabalho pesado (agregação VOD, parse de XMLTV) roda em **isolate** via
`compute()` para não travar a UI thread.

## Normalização de nomes — visão consolidada

Várias funções "limpam" nomes, cada uma para um fim:

| Função | Onde | Para quê |
|---|---|---|
| `nomeBase` | qualidade.dart | Agrupar variantes de qualidade |
| `nomeFonte` | qualidade.dart | Agrupar fontes de backup |
| `categoriaBase` | qualidade.dart | Fundir categorias por qualidade |
| `Serie.nomeSerie` | serie.dart | Reconhecer/limpar nome de série |
| `TmdbService._prepararQuery` | tmdb_service.dart | Montar query de busca TMDB |
| `_normalizar` (telas VOD) | tela_filmes.dart | Match sem acento (ex.: "lançamentos") |

São intencionalmente separadas — cada uma remove um conjunto diferente de ruído.