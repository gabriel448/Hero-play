# CLAUDE.md

Orientações para o Claude Code (e qualquer dev) ao trabalhar neste repositório.

## O que é

**Hero Play** — player IPTV multiplataforma em Flutter (Android, Windows, tablet)
que lê listas M3U e organiza o conteúdo em canais ao vivo, filmes e séries.
Local-first: o único serviço externo é um proxy do TMDB (só metadados).

## Documentação de arquitetura

Antes de mexer em algo não trivial, leia a pasta [`arquitetura/`](arquitetura/):

- [`arquitetura/README.md`](arquitetura/README.md) — índice
- [`visao-geral.md`](arquitetura/visao-geral.md) — princípios, stack, fluxo de dados
- [`camadas.md`](arquitetura/camadas.md) — camadas e regras de dependência
- [`modelos.md`](arquitetura/modelos.md) · [`servicos.md`](arquitetura/servicos.md) · [`estado.md`](arquitetura/estado.md) · [`ui-e-navegacao.md`](arquitetura/ui-e-navegacao.md)
- [`pipeline-de-dados.md`](arquitetura/pipeline-de-dados.md) — parse → agrupamento → qualidade → séries
- [`persistencia.md`](arquitetura/persistencia.md) — Hive
- [`build-e-deploy.md`](arquitetura/build-e-deploy.md) — build, assinatura, releases, API, site

Design e produto: [`DESIGN.md`](DESIGN.md), [`PRODUCT.md`](PRODUCT.md).

## Estrutura

```
lib/
├── main.dart      # Bootstrap: Hive → MediaKit → dotenv → providers → runApp
├── app.dart       # MaterialApp, tema, onboarding vs. home
├── models/        # Dados puros (toMap/fromMap, sem Flutter)
├── services/      # I/O, parse, players, EPG, TMDB, Hive
├── state/         # ChangeNotifier providers (IptvProvider é o central)
├── screens/       # Telas (rotas)
├── widgets/       # Componentes reutilizáveis
├── theme/         # Tokens de design + ThemeData (dark forçado)
└── utils/         # layout (responsividade), qualidade, nav_keys
API/               # Proxy TMDB serverless (Vercel)
website/           # Landing page (Vercel)
```

## Convenções do código

- **Idioma:** todo o código, comentários e identificadores são em **português**
  (sem acentos nos identificadores; comentários podem ter acento). Mantenha esse
  padrão — ex.: `IptvProvider`, `armazenamento`, `canaisFiltrados`.
- **Camadas com dependência unidirecional:** `models ← services ← state ← UI`.
  A UI **nunca** faz I/O direto — sempre via um provider. Um model nunca importa
  de `services`/`state`/`screens`.
- **Estado:** `provider` + `ChangeNotifier`. Padrão de ação: grava no
  `Armazenamento` → recarrega do disco para a memória → `notifyListeners()`.
- **Persistência:** sempre via `Armazenamento` (fachada do Hive). Models usam
  `toMap/fromMap` simples (sem TypeAdapter). Campos opcionais omitidos quando
  `null` e lidos com `as T?` → schema retrocompatível, sem migração.
- **Responsividade:** decida layout por `formFactor(context)` de
  [`utils/layout.dart`](lib/utils/layout.dart) (`isPhone`/`isTablet`/`isDesktop`),
  **não** por checagem de `Platform` espalhada na UI.
- **Trabalho pesado fora da UI thread:** parse de M3U/XMLTV e agregação VOD usam
  `compute()` (isolate).
- **Players:** use os singletons `PlayerAoVivo`/`PlayerVod` — nunca crie
  `Player`/`VideoController` novos por vídeo (vaza superfície EGL no Windows).

## Comandos

```bash
flutter pub get
flutter analyze                 # lints (flutter_lints)
flutter run                     # dev
flutter run --release -d <id>   # instala release num aparelho
flutter build apk --release     # APK assinado com keystore de release
.\build_installer.ps1           # Windows: build + instalador Inno Setup
```

Sempre rodar `flutter analyze` após mudanças. Não há suíte de testes relevante
(`test/widget_test.dart` é o template padrão).

## Cuidados de release (ver build-e-deploy.md)

- **Keystore Android** (`android/app/hero_play_release.jks`) e `key.properties`
  **não** são versionados. Sem o `.jks` não há como atualizar o app instalado.
- **`AppId` do Inno Setup** não pode mudar — é o que permite update in-place no
  Windows.
- Remote git: **`gabriel448/Hero-play`** (não `IPTV`).
- Links de download no `website/` apontam para os assets do release no GitHub;
  atualizar a cada versão nova.
- Versão é fonte única no `pubspec.yaml`.

## Ao adicionar uma feature

1. Modelo de dados novo? → `models/` com `toMap/fromMap`.
2. I/O ou integração? → `services/` (injetável por construtor).
3. Estado/ação? → método no provider apropriado (`IptvProvider` na maioria dos
   casos) + `notifyListeners()`.
4. UI? → `screens/` ou `widgets/`, consumindo o provider com `watch`/`read`.
5. `flutter analyze` limpo antes de concluir.