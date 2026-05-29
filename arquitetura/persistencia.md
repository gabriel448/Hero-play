# Persistência

Toda a persistência local usa **Hive** (NoSQL chave-valor) através de uma fachada
única: [`services/armazenamento.dart`](../lib/services/armazenamento.dart).
Nenhuma outra parte do código fala com o Hive diretamente.

## Inicialização

`Armazenamento.inicializar()` é chamado **uma vez** no [`main.dart`](../lib/main.dart),
antes de `runApp`. Abre todas as boxes:

```dart
await Hive.initFlutter();
_boxListas      = await Hive.openBox('listas');
_boxFavoritos   = await Hive.openBox('favoritos');
// ... e assim por diante
```

## Boxes

| Box | Constante | Conteúdo | Chave do registro |
|---|---|---|---|
| `listas` | `_nomeBoxListas` | `ListaM3U` (com canais parseados) | `lista.id` (= `fonte`) |
| `favoritos` | `_nomeBoxFavoritos` | `Canal` favoritado | `canal.id` |
| `historico` | `_nomeBoxHistorico` | `CanalAssistido` | `canal.id` (máx. 50, FIFO) |
| `progressos` | `_nomeBoxProgressos` | `ProgressoCanal` ("continuar assistindo") | `canal.url` |
| `preferencias` | `_nomeBoxPreferencias` | idioma, ordenações, auto-qualidade, lista ativa | chaves fixas |
| `qualidades` | `_nomeBoxQualidades` | URL da variante preferida | `idGrupo` do canal |
| `categorias_personalizadas` | `_nomeBoxCategorias` | `CategoriaPersonalizada` | `cat.id` |
| `epg` | `_nomeBoxEpg` | grade XMLTV parseada + data | `idLista` |
| `minha_lista` | `_nomeBoxMinhaLista` | lista de chaves de "minha lista" | chave fixa `'keys'` |

## Detalhes por box

### `listas`
Guarda os `Canal`s **já parseados** dentro do `ListaM3U` — evita reparsear o M3U
toda vez. Ordenadas por `atualizadaEm` decrescente ao carregar.

### `historico`
Limitado a `_limiteHistorico = 50`. Ao exceder, `registrarVisualizacao` apaga os
mais antigos (ordena por `ultimaVistaEm` ascendente e remove o excedente).

### `preferencias` — chaves fixas
`idioma`, `auto_qualidade`, `ordem_categorias` (`popularidade`/`az`),
`ordem_canais` (`padrao`/`az`), `lista_ativa_id`. A lista ativa é restaurada no
boot por `IptvProvider._restaurarListaAtiva` (cai na primeira lista se o id
salvo sumiu).

### `epg`
Salvo como `{ atualizadoEm: ISO8601, canais: { tvgId: [programas...] } }`. O
parse do XMLTV roda em isolate; aqui guarda-se só o resultado já estruturado.

### `minha_lista`
Um único registro (chave `'keys'`) com uma `List<String>`. Cada chave é
`c:{url}` (filme/`Canal`) ou `s:{nome}` (série inteira). A resolução de chave →
objeto acontece no `IptvProvider` / telas VOD via um mapa `_todosPorChave`.

## Serialização

Sem code generation (sem `TypeAdapter`). Cada model expõe `toMap()` /
`fromMap()` com `Map<String, dynamic>` simples. Ver [modelos.md](modelos.md#convenção-de-serialização)
para a convenção de retrocompatibilidade (campos opcionais omitidos quando
`null`, lidos com `as T?`).

**Implicação prática:** adicionar um campo novo a um model **não quebra** dados
salvos por versões antigas — o campo simplesmente vem `null`. Foi assim que
`Canal.duracaoSegundos` foi adicionado sem migração.

## Onde fica fisicamente

Hive grava no diretório de documentos do app (resolvido por `path_provider` /
`Hive.initFlutter`). Android: armazenamento interno do app. Windows: pasta de
dados do usuário. Desinstalar o app limpa tudo.