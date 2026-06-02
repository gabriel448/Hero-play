# CLAUDE.md

Orientações para o Claude Code (e qualquer dev) ao trabalhar neste repositório.

## O que é

**Hero Play** — player IPTV multiplataforma em Flutter (Android, Windows, tablet)
que lê listas M3U e organiza o conteúdo em canais ao vivo, filmes e séries.

**Local-first com sincronização opcional via Supabase.** O app funciona 100%
offline — o único serviço externo obrigatório é um proxy serverless do TMDB
(só metadados). Opcionalmente, o usuário cria uma conta (email/senha) e as
*definições* de lista (nome, URL M3U, URL EPG) ficam na nuvem e sincronizam
entre dispositivos. Os canais parseados nunca sobem ao banco — o app baixa e
faz o parse localmente, mantendo o Hive como cache.

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
├── main.dart          # Bootstrap: Hive → MediaKit → dotenv → Supabase? → providers → runApp
├── app.dart           # MaterialApp, gate: onboarding → login → sync → home
├── models/
│   └── lista_remota.dart  # Definição de lista na nuvem (id, nome, fonte_url, epg_url)
├── services/
│   └── servico_conta.dart # Auth Supabase + CRUD de listas via Edge Function
├── state/
│   └── conta_provider.dart # Estado de autenticação; IptvProvider usa ServicoConta opcional
├── screens/
│   ├── tela_login.dart         # Login / cadastro + "continuar sem conta"
│   └── tela_importando_listas.dart  # Tela de progresso na 1ª sync pós-login
├── widgets/
│   └── animado_entrada.dart    # Widget de animação de entrada reutilizável
├── services/      # I/O, parse, players, EPG, TMDB, Hive
├── state/         # ChangeNotifier providers (IptvProvider é o central)
├── screens/       # Demais telas (rotas)
├── widgets/       # Componentes reutilizáveis
├── theme/         # Tokens de design + ThemeData (dark forçado)
└── utils/         # layout (responsividade), qualidade, nav_keys
API/               # Proxy TMDB serverless (Vercel)
supabase/          # Edge Function (iptv/) + schema.sql + config.toml
website/           # Landing page + login.html + painel.html (Vercel)
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
  Quando logado, ações de lista também são espelhadas no Supabase via
  `ServicoConta` (best-effort — falha de rede não quebra o fluxo local).
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

# Supabase (requer Supabase CLI)
supabase functions serve iptv   # Edge Function local
supabase db push                # aplica schema.sql no projeto remoto
```

Para rodar com conta habilitada, preencha `SUPABASE_URL` e `SUPABASE_ANON_KEY`
no `.env`. Sem esses valores o app usa modo local-only (login não aparece).

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
- **`supabase/.env`** (`ENCRYPTION_KEY` para cifrar credenciais Xtream) **não**
  é versionado. Guardar junto com o keystore.
- A Edge Function `supabase/functions/iptv/` precisa ser deployed no projeto
  Supabase remoto: `supabase functions deploy iptv`.

## Ao adicionar uma feature

1. Modelo de dados novo? → `models/` com `toMap/fromMap`.
2. I/O ou integração? → `services/` (injetável por construtor).
3. Estado/ação? → método no provider apropriado (`IptvProvider` na maioria dos
   casos) + `notifyListeners()`.
4. UI? → `screens/` ou `widgets/`, consumindo o provider com `watch`/`read`.
5. `flutter analyze` limpo antes de concluir.

### Regras extras para o sistema de contas

- `ServicoConta` é opcional: sempre verifique `conta != null && conta.estaLogado`
  antes de chamar qualquer método de nuvem.
- Ações de lista no `IptvProvider` espelham no Supabase de forma best-effort —
  nunca lance exceção de rede para o usuário por causa da sincronização.
- `ContaProvider` controla o gate de login no `app.dart`; não repita essa lógica
  em telas individuais.
- O banco Supabase **nunca** guarda canais — só a definição (nome/url/epg).
  Se precisar de dados de canal persistidos, use o Hive.
- Credenciais Xtream (username/password na querystring) são cifradas pela Edge
  Function `iptv` antes de gravar; o app recebe a URL reconstituída na leitura.
  Nunca escreva direto na tabela `listas` — sempre use `ServicoConta`.