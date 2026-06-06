# Gerenciamento de estado

Usa `provider` com `ChangeNotifier`. Os providers são registrados no topo da
árvore em [`main.dart`](../lib/main.dart) via `MultiProvider`, **depois** de
inicializar Hive e MediaKit (a ordem importa — o `IptvProvider` já lê o disco no
construtor/`inicializar`).

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider<IptvProvider>.value(value: provider),
    ChangeNotifierProvider<PerfilProvider>.value(value: perfis),
    ChangeNotifierProvider<PreferenciasProvider>.value(value: preferencias),
    ChangeNotifierProvider<ServicoEpg>.value(value: servicoEpg),
    Provider<TmdbService>.value(value: tmdb),          // sem notify — stateless
    ChangeNotifierProvider<MiniPlayerProvider>(create: (_) => MiniPlayerProvider()),
    ChangeNotifierProvider<ContaProvider>(create: (_) => ContaProvider(servicoConta)),
  ],
  child: const IptvApp(),
)
```

`servicoConta` é `null` se as credenciais Supabase não estiverem no `.env`; nesse
caso `ContaProvider.disponivel == false` e a tela de login nunca aparece.

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
  `_executarComLoading` (seta `carregando`/`erro` e notifica). Quando logado,
  cada ação de lista também chama o `ServicoConta` equivalente (best-effort).
- **Sincronização:** `sincronizarDoSupabase()` — busca definições na nuvem e
  importa as que não existem localmente. `primeiraSync` fica `true` durante
  esse processo para o `app.dart` exibir `TelaImportandoListas`. `limparListasLocais()`
  apaga o cache Hive no logout (evita mistura de contas).
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

## `ContaProvider` — [conta_provider.dart](../lib/state/conta_provider.dart)

Expõe o estado de autenticação para a UI e delega ações ao `ServicoConta`.

- `disponivel` — `true` quando as credenciais Supabase estão no `.env`.
- `estaLogado`, `email` — derivados da sessão atual.
- `entrar`, `criarConta`, `sair` — delegam ao `ServicoConta`.
- Escuta `ServicoConta.mudancasAuth` (stream) e chama `notifyListeners()` a cada
  mudança de sessão — assim o `app.dart` reage ao login/logout sem polling.

O `app.dart` usa `ContaProvider` + `PreferenciasProvider` + `PerfilProvider`
para decidir a tela raiz: `precisaLogin = disponivel && !logado && !pulouLogin`,
depois `!perfilConfirmado` → `TelaPerfis`.

## `PerfilProvider` — [perfil_provider.dart](../lib/state/perfil_provider.dart)

Gerencia os perfis (estilo "quem está assistindo"). Cada conta/aparelho tem até
`Perfil.maxPerfis` (3) perfis — limite por causa do bloqueio de acesso múltiplo
simultâneo às listas, que são **compartilhadas** entre perfis.

- `perfis`, `perfilAtivo`, `podeAdicionar`.
- `perfilConfirmado` — flag de **sessão** (começa `false` a cada abertura); o
  `app.dart` mostra `TelaPerfis` enquanto for `false`.
- `selecionar(p)` — aponta as boxes do Hive para o perfil (`Armazenamento.ativarPerfil`)
  e marca `perfilConfirmado`. A `TelaPerfis` então chama
  `IptvProvider.recarregarDadosDoPerfil()` para trocar a biblioteca em memória.
- `criar` (o 1º perfil herda preferências legadas e **migra** a biblioteca antiga),
  `editar`, `remover` (apaga as boxes do perfil), `trocarPerfil` (volta ao seletor).
- `atualizarConfigAtivo(...)` — usado pelo `PreferenciasProvider` para gravar a
  config no perfil ativo.
- `sincronizarDoSupabase` / `limparLocais` — espelham/limpam as **definições** de
  perfil na nuvem (best-effort). A biblioteca pessoal nunca sobe ao banco.

## `PreferenciasProvider` — [preferencias_provider.dart](../lib/state/preferencias_provider.dart)

Superfície única de leitura/escrita das preferências. As que são **por perfil**
(idioma, ajuste automático de qualidade, ordenações) ficam no `Perfil` ativo e são
lidas/gravadas via `PerfilProvider` — este provider escuta o `PerfilProvider` e
re-emite `notifyListeners` quando o perfil (ou sua config) muda, mantendo as telas
existentes funcionando sem saberem de perfis:
- `idioma`/`idiomaEfetivo`, `autoQualidade`, `ordemCategorias`/`ordemCanais` →
  delegam ao perfil ativo.
- `pulouLogin` (bool) — global ao aparelho, persistido via `Armazenamento`.

## `ServicoEpg` como provider

É service e `ChangeNotifier` ao mesmo tempo — registrado no `MultiProvider` para
que widgets de EPG (painel, modal de programação) reajam ao estado de
carregamento (`estaCarregando`, `temEpg`). Ver [servicos.md](servicos.md).