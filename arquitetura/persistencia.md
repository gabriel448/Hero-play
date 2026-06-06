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

Há **dois grupos** de boxes: **globais** (compartilhadas entre perfis) e **por
perfil** (a biblioteca pessoal — abertas com sufixo `__<idPerfil>` e re-apontadas
em `Armazenamento.ativarPerfil`, ver [perfis](#perfis-quem-está-assistindo)).

| Box | Escopo | Conteúdo | Chave do registro |
|---|---|---|---|
| `listas` | global | `ListaM3U` (com canais parseados) | `lista.id` (= `fonte`) |
| `epg` | global | grade XMLTV parseada + data | `idLista` |
| `perfis` | global | `Perfil` (definição: nome, ícone, config) | `perfil.id` (uuid) |
| `preferencias` | global | `pulou_login`, `lista_ativa_id`, `perfil_ativo_id` | chaves fixas |
| `favoritos__<id>` | por perfil | `Canal` favoritado | `canal.id` |
| `historico__<id>` | por perfil | `CanalAssistido` | `canal.id` (máx. 50, FIFO) |
| `progressos__<id>` | por perfil | `ProgressoCanal` ("continuar assistindo") | `canal.url` |
| `qualidades__<id>` | por perfil | URL da variante preferida | `idGrupo` do canal |
| `categorias_personalizadas__<id>` | por perfil | `CategoriaPersonalizada` | `cat.id` |
| `minha_lista__<id>` | por perfil | lista de chaves de "minha lista" | chave fixa `'keys'` |

## Perfis ("quem está assistindo")

As boxes da **biblioteca pessoal** ficam null até um perfil ser ativado — antes
disso (na `TelaPerfis`) as leituras retornam vazio. `Armazenamento.ativarPerfil(id)`
abre `favoritos__<id>`, `historico__<id>`, etc. e persiste `perfil_ativo_id`.
`removerPerfil`/`limparPerfis` apagam as boxes do(s) perfil(is) do disco.

**Migração:** ao criar o **primeiro** perfil, `migrarLegadoParaPerfil` copia a
biblioteca antiga (boxes sem sufixo, de versões pré-perfis) para as boxes do novo
perfil e apaga as antigas — nenhum dado é perdido na atualização.

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