# CLAUDE.md

Orientações para o Claude Code (e qualquer dev) ao trabalhar neste repositório.

## ⛔ REGRA ABSOLUTA — toda mudança vale para as 3 plataformas

**Toda alteração deve funcionar e ser verificada em CELULAR, TABLET e DESKTOP**
(Android phone, Android/tablet e Windows). Sem exceções.

- O app é **um único código Dart compartilhado**; o layout decide por
  `formFactor(context)` / `isPhone`/`isTablet`/`isDesktop`
  ([utils/layout.dart](lib/utils/layout.dart)). Uma mudança na lógica entra nos
  três automaticamente — mas a UI **não**: cada layout (phone, tablet, desktop)
  precisa receber a feature.
- **Proibido** entregar um efeito/feature só em um form factor (ex.: animar uma
  lista só no phone e deixar o sidebar do tablet/desktop sem). Se um layout não
  puder ter exatamente o mesmo, faça o equivalente — e diga explicitamente o que
  ficou diferente e por quê.
- Telas de canais ao vivo têm layouts distintos por device (lista no phone,
  sidebar+painel no tablet/desktop, 3 colunas no desktop). Ao mexer nelas,
  cubra **todos** os caminhos em [tela_canais.dart](lib/screens/tela_canais.dart).
- Ao concluir, **buildar e testar nos 3** quando possível (APK no aparelho +
  Windows via cmake — ver "Cuidados de release"). Nunca assuma que "como é
  compartilhado, já está nos três" sem conferir o layout de cada um.

## ⛔ REGRA ABSOLUTA — não remover botões/funcionalidades sem perguntar

**Nunca remova um botão, opção ou funcionalidade existente sem antes perguntar
ao usuário de forma clara.** Mesmo que pareça redundante ou que "atrapalhe" a
mudança pedida, pergunte primeiro e explique o porquê — a decisão é do usuário.
Ao alterar telas (especialmente o player), preserve as opções já existentes
(ex.: minimizar/fullscreen, CC/legendas, volume, copiar URL) a menos que o
usuário autorize remover.

## ⛔ REGRA ABSOLUTA — conformidade com as lojas (app = player neutro)

**O app distribuído nas lojas (Google Play, App Store, Samsung, LG, Roku) tem
que ser um PLAYER NEUTRO "traga sua própria lista". Todo o comércio/revenda fica
no WEB, nunca no app.** Se qualquer mudança violar isso, **PARE e avise o usuário
antes de prosseguir** — explique o que fere a conformidade e ofereça a alternativa
neutra. A loja julga o APP e a ficha da loja, não o backend/painel.

**Regras que o app NÃO pode violar:**
- **Abre vazio / na tela de login.** Com conta nova (sem lista, sem ativação) o
  revisor tem que ver um player inócuo — **nada de canais/conteúdo embutido**.
- **Sem venda no app:** nada de comprar conteúdo, link de pagamento externo, ou
  "insira o código do revendedor". Ativação é só uma **flag silenciosa** da nuvem.
- **Conta inativa = estado neutro** ("nenhuma lista configurada — fale com seu
  provedor"), **sem** botão de pagar / CTA de compra.
- **Sem palavra "IPTV", "canais/filmes grátis", "lista de canais"** em nome,
  descrição, screenshots ou strings visíveis. Posicionar como reprodutor de
  mídia / M3U / playlist.
- **Nenhuma playlist de exemplo com canais reais** embutida no binário.
- **Recursos de revendedor (gerar link de convite, ver/gerenciar listas de
  clientes, créditos, ativação) são WEB-only** — nunca entram no app submetido.
- Manter o que as lojas **exigem**: política de privacidade, termos e **exclusão
  de conta** (já implementados).

**Trilho duplo de distribuição:** (1) lojas = app neutro; (2) **APK direto no
site + painel web** = onde a revenda realmente roda. Apple é a mais rígida (pode
rejeitar "IPTV player"); Samsung/LG/Roku aceitam players "traga sua lista" sem
conteúdo/venda embutidos.

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
│   ├── lista_remota.dart  # Definição de lista na nuvem (id, nome, fonte_url, epg_url)
│   └── perfil.dart        # Perfil de uso (id, nome, ícone, idioma, config) — local + nuvem
├── services/
│   └── servico_conta.dart # Auth Supabase + CRUD de listas (Edge Function) e perfis (tabela)
├── state/
│   ├── conta_provider.dart  # Estado de autenticação; IptvProvider usa ServicoConta opcional
│   └── perfil_provider.dart # Perfis (até 3), perfil ativo da sessão, CRUD, sync nuvem
├── screens/
│   ├── tela_login.dart         # Login / cadastro + "continuar sem conta"
│   ├── tela_importando_listas.dart  # Tela de progresso na 1ª sync pós-login
│   └── tela_perfis.dart        # "Quem está assistindo?" — gate de perfil (1ª tela)
├── widgets/
│   ├── animado_entrada.dart    # Widget de animação de entrada reutilizável
│   └── avatar_perfil.dart      # Avatar Lottie do perfil (assets/avatars/*.json)
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

## Animação e ferramentas (MCP / skills) — SEMPRE

### ⛔ REGRA ABSOLUTA — toda animação a 60 fps

**Toda animação (app Flutter E site) deve rodar a 60 fps.** O caminho para isso
é animar apenas o que o **compositor (GPU)** resolve, sem reflow/repaint por frame:

- **Anime só `transform` (translate/scale/rotate) e `opacity`.** Esses ficam numa
  camada de GPU e não disparam layout. **Evite animar propriedades de layout** —
  `width`/`height`/`top`/`left`/`margin`/`padding` no **web**; no Flutter, evite
  rebuildar/relayoutar a subárvore por frame.
- **Web (anime.js):** já roda em `requestAnimationFrame` (vsync). Use `transform`
  + `opacity`; adicione `will-change: transform, opacity` (e `backface-visibility:
  hidden`) nos elementos animados para promovê-los a camada GPU. Se for inevitável
  animar layout (ex.: `height` num modal pequeno), mantenha curto, em subárvore
  pequena, e ligue `will-change` só durante a animação (e limpe ao terminar).
- **Flutter:** prefira `AnimatedBuilder`/`Transform`/`Opacity`/`FadeTransition`/
  `SlideTransition`; mantenha o `builder` leve (sem trabalho pesado por frame) e
  anime só a parte que muda (use `child:` para não reconstruir o resto). O app
  renderiza no refresh do device (60/120 Hz) — não bloqueie a UI thread (trabalho
  pesado vai pra `compute()`/isolate).
- **Não** introduza jank: nada de animar `box-shadow`/`filter`/cores em listas
  grandes, nem `setState` por frame em árvores caras. Confira que a animação está
  suave (sem travos) antes de concluir.

Ao trabalhar com **animação** ou **qualquer feature de Flutter**, use sempre,
sem precisar ser solicitado:

- **Servidores MCP** quando ajudarem: `context7` para a doc oficial do Flutter
  (`/websites/flutter_dev`) e de pacotes antes de implementar; `dart` para
  análise/erros/inspeção de pacotes. Consulte a doc para validar a abordagem em
  vez de confiar só na memória.
- **Skills de animação** disponíveis como referência de princípios (timeline,
  stagger, easing, física de mola). As skills do repositório são voltadas a
  web/React — traduza os conceitos para o Flutter (`AnimationController`,
  `AnimatedBuilder`, `Interval`, `Tween`, `repeat(reverse:)`, overlays em
  coordenadas globais).
- **Padrão de animação do app:** a entrada de perfil
  ([tela_inicial.dart](lib/screens/tela_inicial.dart)) e a abertura de seção
  ([widgets/abertura_secao.dart](lib/widgets/abertura_secao.dart)) são a base.
  Transições entre telas usam 3 estágios assíncronos (origem → centro com pulso
  enquanto carrega → posição final) com overlay em coordenadas globais e
  `Listenable.merge` de múltiplos controllers. Reutilize `AberturaSecao` +
  `TituloSecao` para novas seções com carregamento.

## Comandos

```bash
flutter pub get
flutter analyze                 # lints (flutter_lints)
flutter run                     # dev
flutter run --release -d <id>   # instala release num aparelho
flutter build apk --release     # APK assinado com keystore de release
flutter build windows --release # Windows (build direto)
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
- **Build Windows — gotcha do `cpp_client_wrapper`:** sem o Modo Desenvolvedor
  do Windows, os `.cc` em `windows/flutter/ephemeral/cpp_client_wrapper/` ficam
  faltando/quebrados e o `flutter build windows` falha com
  `C1083: ... .cc: No such file or directory`.
  **Workaround (ORDEM IMPORTA):** copiar os fontes reais ANTES e só então rodar
  o `flutter build windows` — com os `.cc` presentes ele passa direto E
  recompila o Dart (`app.so` fresco):
  ```powershell
  Copy-Item "C:\src\flutter\bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper\*" `
    "windows\flutter\ephemeral\cpp_client_wrapper\" -Recurse -Force
  flutter build windows --release
  ```
  ⚠️ **NÃO** rodar `flutter build windows` primeiro: ele aborta no compile do
  C++ **antes** do `flutter assemble`, e um `cmake --build` posterior reaproveita
  o `app.so` ANTIGO → o desktop sai com Dart desatualizado (bug ja visto).
  Conferir sempre a data de `build\windows\x64\runner\Release\data\app.so`.
  Saída: `build\windows\x64\runner\Release\` (pasta portátil com `iptv_app.exe`).

## Ao adicionar uma feature

1. Modelo de dados novo? → `models/` com `toMap/fromMap`.
2. I/O ou integração? → `services/` (injetável por construtor).
3. Estado/ação? → método no provider apropriado (`IptvProvider` na maioria dos
   casos) + `notifyListeners()`.
4. UI? → `screens/` ou `widgets/`, consumindo o provider com `watch`/`read`.
   **Cubra os 3 layouts** (phone, tablet, desktop) — ver REGRA ABSOLUTA no topo.
5. `flutter analyze` limpo antes de concluir.
6. **Buildar/testar nos 3**: APK no aparelho **e** Windows (ver "Cuidados de
   release"). Não basta buildar só o APK toda vez — o desktop fica defasado.

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

### Regras extras para o sistema de perfis

- Máximo de **3 perfis** por conta/aparelho (`Perfil.maxPerfis`) — limite por
  causa do bloqueio de acesso múltiplo simultâneo às listas, que são
  **compartilhadas** entre todos os perfis.
- A **biblioteca pessoal** (favoritos, histórico, progresso, "minha lista",
  categorias, qualidades) é **por perfil**: o `Armazenamento` abre boxes com
  sufixo `__<idPerfil>` em `ativarPerfil`. Antes de um perfil ser ativo essas
  boxes ficam null e as leituras retornam vazio.
- As **preferências por perfil** (idioma, auto-qualidade, ordenações) vivem no
  `Perfil`; leia/grave sempre via `PreferenciasProvider` (que delega ao perfil
  ativo) — não acesse a box `preferencias` para isso.
- Trocar de perfil = `PerfilProvider.selecionar(p)` (aponta as boxes) **e**
  `IptvProvider.recarregarDadosDoPerfil()` (recarrega a memória). A `TelaPerfis`
  já orquestra os dois; não duplique.
- Perfis sincronizam só a **definição** (nome/ícone/config) na tabela `perfis`
  do Supabase — direto na tabela (sem segredos, protegido por RLS), diferente de
  `listas`. A biblioteca pessoal **nunca** sobe ao banco.
- Avatares são Lottie em `assets/avatars/*.json`, gerados por
  `tool/gerar_avatares.py`. Para adicionar um, gere o JSON e inclua a chave em
  `avataresDisponiveis` ([widgets/avatar_perfil.dart](lib/widgets/avatar_perfil.dart)).
- Ao fazer schema novo no Supabase, rode `supabase db push` (ou cole `schema.sql`
  no SQL Editor) — a tabela `perfis` precisa existir no projeto remoto.