# Camadas

O app segue quatro camadas com **dependência unidirecional**. Uma camada só
conhece as que estão abaixo dela — nunca as de cima.

```
┌─────────────────────────────────────────────────────────┐
│  UI            screens/  ·  widgets/  ·  theme/  ·  utils/ │  ← Flutter widgets
├─────────────────────────────────────────────────────────┤
│  STATE         state/  (ChangeNotifier providers)          │  ← estado + ações
├─────────────────────────────────────────────────────────┤
│  SERVICES      services/  (I/O, parse, players, externos)  │  ← efeitos colaterais
├─────────────────────────────────────────────────────────┤
│  MODELS        models/  (estruturas de dados puras)        │  ← sem dependências
└─────────────────────────────────────────────────────────┘
```

## 1. Models (`lib/models/`)

Estruturas de dados puras. **Sem** dependência de Flutter, Hive ou rede. Cada
modelo sabe se (de)serializar via `toMap()` / `fromMap()` (usado pelo Hive) e
pode ter lógica de domínio leve (ex.: `Serie.agrupar`, `Programa.ehAtual`).

Regra: um model nunca importa de `services`, `state` ou `screens`.

Detalhe em [modelos.md](modelos.md).

## 2. Services (`lib/services/`)

Onde mora todo **efeito colateral**: baixar arquivos, ler disco, parsear texto,
controlar o player nativo, falar com APIs externas, persistir no Hive.

Características:
- Recebem dependências por construtor (injetáveis → testáveis).
- Não conhecem widgets nem `BuildContext`.
- Operações caras usam `compute()` (isolate) para não travar a UI.

Os players ao vivo/VOD são **singletons** (`PlayerAoVivo.instancia`) para evitar
vazamento de superfícies EGL no Windows ao recriar `Player` a cada canal.

Detalhe em [servicos.md](servicos.md).

## 3. State (`lib/state/`)

`ChangeNotifier`s registrados no topo da árvore (`MultiProvider` em
[`main.dart`](../lib/main.dart)). Mantêm o estado em memória, orquestram os
services e chamam `notifyListeners()` quando algo muda.

| Provider | Responsabilidade |
|---|---|
| `IptvProvider` | Listas, favoritos, histórico, progresso, "minha lista", busca, lista ativa |
| `MiniPlayerProvider` | Estado do mini player flutuante (canal, player, posição, tamanho) |
| `PreferenciasProvider` | Idioma, ordenações, auto-qualidade |
| `ServicoEpg` | É service **e** `ChangeNotifier` — a UI escuta o estado de carregamento do EPG |

A UI lê com `context.watch<T>()` (reativo) ou `context.read<T>()` (one-shot, em
callbacks). Detalhe em [estado.md](estado.md).

## 4. UI (`lib/screens/`, `lib/widgets/`, `lib/theme/`, `lib/utils/`)

- **screens/** — telas completas que viram rotas (`MaterialPageRoute`).
- **widgets/** — componentes reutilizáveis (mini player overlay, item de canal,
  painel EPG, skeleton de loading).
- **theme/** — tokens de design (`AppColors`, `AppSpacing`, `AppRadius`) e o
  `ThemeData`. Decisões registradas em [`DESIGN.md`](../DESIGN.md).
- **utils/** — helpers transversais: `layout.dart` (form factor / responsividade),
  `qualidade.dart` (detecção de resolução), `nav_keys.dart` (navigator key raiz),
  `popularidade_categorias.dart`, `smooth_scroll.dart`.

A UI **não faz I/O direto**. Para importar uma lista, ela chama
`provider.importarPorUrl(...)` — quem baixa e parseia é o service por trás.

Detalhe em [ui-e-navegacao.md](ui-e-navegacao.md).

## Regras de dependência (resumo)

| Camada | Pode importar de | Nunca importa de |
|---|---|---|
| models | (nada interno) | services, state, screens, widgets |
| services | models | state, screens, widgets |
| state | models, services | screens, widgets |
| UI | models, services (tipos), state, utils, theme | — |

> Exceção pragmática: alguns providers que controlam vídeo (`MiniPlayerProvider`)
> importam tipos de `media_kit` diretamente, porque encapsulam o handle do player.