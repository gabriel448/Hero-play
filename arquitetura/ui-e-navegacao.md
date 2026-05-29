# UI e navegação

## Responsividade por form factor

A decisão de layout é centralizada em [`utils/layout.dart`](../lib/utils/layout.dart),
não espalhada por checagens de `Platform` na UI. Fonte única de verdade:

```dart
enum FormFactor { phone, tablet, desktop }

FormFactor formFactor(BuildContext context) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return desktop;
  if (MediaQuery.sizeOf(context).shortestSide >= 600) return tablet;
  return phone;
}
```

Helpers: `isPhone`, `isTablet` (tablet **e** desktop — ambos wide-screen),
`isDesktop`. Mais: `posterColumns(context)` (3/4/6), `channelSidebarWidth`,
`tabletBody` (centraliza e limita largura), constantes de largura de sidebar.

**Regra de ouro:** desktop ≈ tablet em estrutura; o que muda é largura, tamanho
de item e a presença de player embutido vs. mini player flutuante.

## Bootstrap e roteamento inicial

[`app.dart`](../lib/app.dart) monta o `MaterialApp` (tema dark forçado,
`navigatorKey: rootNavigatorKey`) e decide a home:

```dart
final temIdioma = context.watch<PreferenciasProvider>().idiomaDefinido;
home: !temIdioma ? const TelaOnboarding() : const TelaInicial();
builder: (context, child) => MiniPlayerOverlay(child: child!), // overlay global
```

O `MiniPlayerOverlay` envolve **toda** a árvore via `MaterialApp.builder`, então
o mini player vive fora de qualquer `Navigator`. Por isso existe o
`rootNavigatorKey` ([nav_keys.dart](../lib/utils/nav_keys.dart)): dá ao mini
player acesso ao Navigator certo para empilhar telas (ex.: botão "expandir").

A navegação é **imperativa** com `Navigator.push(MaterialPageRoute(...))` — não
há router declarativo.

## Telas (`lib/screens/`)

| Tela | Papel |
|---|---|
| `TelaOnboarding` | Escolha de idioma na primeira abertura |
| `TelaInicial` | Home: hub entre Canais / Filmes / Séries + gerenciar/config |
| `TelaCanais` | Canais ao vivo (3 layouts: phone, tablet, desktop) |
| `TelaFilmes` / `TelaSeries` | Carrosséis VOD por categoria (`TipoVod`) |
| `TelaConteudo` / `TelaCategoria` | Drill-down de categoria |
| `TelaDetalhes` | Detalhe de filme/série (sinopse TMDB, episódios, "minha lista") |
| `TelaPlayer` | Player em tela cheia (ao vivo e VOD) |
| `TelaFavoritos` / `TelaHistorico` | Listas persistidas |
| `TelaImportar` / `TelaGerenciarListas` | Gestão de listas M3U |
| `TelaConfiguracoes` | Idioma, ordenações, EPG |
| `TelaCategoriaPersonalizada` | Categorias criadas pelo usuário |

### `TelaInicial` — cache de agrupamento
A home processa os canais da lista ativa em estruturas prontas para a UI
(`agruparCanaisAoVivo`, `agruparPorCategoria(filme)`, contagem de séries) e
**cacheia por id de lista** (`_idListaCacheada`) para não reprocessar a cada
rebuild. Só recomputa quando a lista ativa muda.

### `TelaCanais` — três layouts
A mesma tela renderiza um de três layouts conforme o form factor:

- **Phone** (`_ListaCategorias`): lista de categorias → empilha a lista de canais.
- **Tablet landscape / Desktop**: layout de **colunas** (sidebar de categorias +
  painel de canais + player embutido fixo no desktop).
- **Tablet portrait**: usa o mini player flutuante.

**Padrão `canaisOverride`:** em vez de criar rotas novas para sub-listas
("Favoritos", "Todos", uma categoria personalizada), a sidebar passa uma lista de
canais já pronta (`canaisOverride`) ao mesmo painel. `null` = usa a categoria
selecionada normal. Reduz drasticamente o número de telas.

## Mini player vs. player embutido

Há **três** modos de "continuar vendo enquanto navega", escolhidos por form factor:

| Form factor | Mecanismo | Onde |
|---|---|---|
| Phone / tablet portrait | Mini player flutuante (arrastável) | [mini_player_overlay.dart](../lib/widgets/mini_player_overlay.dart) |
| Desktop | Player embutido fixo dentro de `TelaCanais` | [player_embutido_desktop.dart](../lib/widgets/player_embutido_desktop.dart) |
| Tablet landscape | Coluna de player no layout de 3 colunas | dentro de `TelaCanais` |

O **estado** (canal atual, posição, tamanho, mudo) fica em `MiniPlayerProvider`;
o **handle nativo** do vídeo vem dos singletons `PlayerAoVivo`/`PlayerVod` — ver
[estado.md](estado.md) e [servicos.md](servicos.md).

## Widgets reutilizáveis (`lib/widgets/`)

| Widget | Papel |
|---|---|
| `MiniPlayerOverlay` | Stack global que sobrepõe o mini player à árvore |
| `PlayerEmbutidoDesktop` | Player fixo na coluna direita do desktop |
| `ItemCanal` | Linha/card de canal reutilizável |
| `SeletorCategoria` | Seletor de categoria |
| `PainelEpg` / `ModalProgramacao` | UI do guia de programação |
| `DialogoEditarLista` | Modal de edição de lista |
| `Skeleton` | Placeholders de carregamento |

## Tema

[`theme/app_theme.dart`](../lib/theme/app_theme.dart) define tokens
(`AppColors`, `AppSpacing`, `AppRadius`) e o `ThemeData`. **Dark mode forçado**
(decisão de produto — usuário no sofá, sala escura). Paleta: off-blacks tintados
de morno + um accent vermelho. Fonte Manrope via `google_fonts`. Racional
completo em [`DESIGN.md`](../DESIGN.md) e [`PRODUCT.md`](../PRODUCT.md).