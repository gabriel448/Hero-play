# Gerenciamento de estado

Usa `provider` com `ChangeNotifier`. Os providers são registrados no topo da
árvore em [`main.dart`](../lib/main.dart) via `MultiProvider`, **depois** de
inicializar Hive e MediaKit (a ordem importa — o `IptvProvider` já lê o disco no
construtor/`inicializar`).

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider<IptvProvider>.value(value: provider),
    ChangeNotifierProvider<PreferenciasProvider>.value(value: preferencias),
    ChangeNotifierProvider<ServicoEpg>.value(value: servicoEpg),
    Provider<TmdbService>.value(value: tmdb),          // sem notify — stateless
    ChangeNotifierProvider<MiniPlayerProvider>(create: (_) => MiniPlayerProvider()),
  ],
  child: const IptvApp(),
)
```

## Como a UI consome

| Chamada | Quando usar |
|---|---|
| `context.watch<T>()` | Dentro de `build` — reconstrói quando o provider notifica |
| `context.read<T>()` | Em callbacks (`onPressed`, `initState`) — leitura one-shot |
| `Consumer<T>` / `Selector<T>` | Rebuild localizado de um trecho da árvore |

## `IptvProvider` — [iptv_provider.dart](../lib/state/iptv_provider.dart)

O provider central. Mantém praticamente todo o estado do domínio e orquestra os
services (`Armazenamento`, `CarregadorLista`, `ParserM3U`, `ServicoEpg`).

**Estado que expõe** (getters reativos):
`listas`, `favoritos`, `historico`, `progressos`, `categoriasPersonalizadas`,
`minhaListaChaves`, `listaAtiva`, `busca`, `carregando`, `erro`,
`formatoNaoSuportado`, `canalSelecionadoDesktop`, `canaisFiltrados`.

**Grupos de ações:**
- **Importação:** `importarPorUrl`, `importarPorArquivo`, `atualizarLista`,
  `atualizarUrlLista`, `renomearLista`, `removerLista`. Todas passam por
  `_executarComLoading` (seta `carregando`/`erro` e notifica).
- **Lista ativa:** `selecionarLista`, `ativarLista` (persiste qual abre no
  startup), `_restaurarListaAtiva` (no boot).
- **EPG:** `atualizarEpgUrl` + `_baixarEpgEmBackground` (dispara download que
  **não bloqueia** e silencia erros — EPG nunca quebra o fluxo principal).
- **Favoritos / Histórico / Progresso:** `alternarFavorito`, `ehFavorito`,
  `registrarVisualizacao`, `salvarProgresso`, `obterProgresso`.
- **Minha lista:** `alternarMinhaLista`, `ehMinhaLista`. Chave normalizada:
  `c:{url}` para `Canal`, `s:{nome}` para `Serie` — séries entram inteiras.
- **Categorias personalizadas:** criar/remover/adicionar/remover canal.
- **Qualidade preferida:** lembra a variante escolhida por canal agrupado.

**Padrão recorrente:** ação → grava no `Armazenamento` → **recarrega** a lista
do disco para o campo em memória → `notifyListeners()`. Isso mantém memória e
disco sempre coerentes.

```dart
Future<void> alternarFavorito(Canal canal) async {
  if (ehFavorito(canal)) {
    await _armazenamento.removerFavorito(canal.id);
  } else {
    await _armazenamento.adicionarFavorito(canal);
  }
  _favoritos = _armazenamento.carregarFavoritos(); // recarrega do disco
  notifyListeners();
}
```

## `MiniPlayerProvider` — [mini_player_provider.dart](../lib/state/mini_player_provider.dart)

Estado do **mini player flutuante** (desktop/tablet). Diferente dos outros, ele
segura o **handle do player** (`Player`, `VideoController`) além do estado de UI
(posição arrastável, largura redimensionável, mudo, ações visíveis).

Fluxo de transferência de player:
- `iniciar(canal, player, controller)` — recebe um player já aberto vindo da
  `TelaPlayer` (minimizar).
- `reivindicar()` — devolve `(canal, player, controller)` para a `TelaPlayer`
  retomar em tela cheia (expandir), sem dispor o player.
- `iniciarComSingleton(canal)` — reabre o stream usando `PlayerAoVivo.instancia`
  (caso de rotação landscape→portrait no tablet).
- `_fecharPlayer()` — `stop().whenComplete(dispose)`; se o player veio do
  singleton, chama `liberarSeAtual` antes (evita handle descartado).

Geometria do mini player desktop é derivada de uma largura única
(`larguraDesktop`, clampada 220–800px): altura do vídeo é 16:9, barra de botões
é proporcional.

## `PreferenciasProvider` — [preferencias_provider.dart](../lib/state/preferencias_provider.dart)

Preferências do usuário, persistidas via `Armazenamento`:
- `idioma` (`IdiomaApp?`) — `null` dispara o onboarding. `idiomaDefinido` e
  `idiomaEfetivo` (cai em português).
- `autoQualidade` (bool).
- `ordemCategorias` (`OrdemCategorias`: popularidade | A-Z) e `ordemCanais`
  (`OrdemCanais`: padrão | A-Z) — ordenação das listas ao vivo.

`IptvApp` escuta `idiomaDefinido` para decidir entre `TelaOnboarding` e
`TelaInicial`.

## `ServicoEpg` como provider

É service e `ChangeNotifier` ao mesmo tempo — registrado no `MultiProvider` para
que widgets de EPG (painel, modal de programação) reajam ao estado de
carregamento (`estaCarregando`, `temEpg`). Ver [servicos.md](servicos.md).