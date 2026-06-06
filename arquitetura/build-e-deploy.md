# Build e deploy

## Versionamento

Fonte única: `version` no [`pubspec.yaml`](../pubspec.yaml) (formato
`semver+build`, ex.: `1.3.0+3`). O `versionName`/`versionCode` do Android e o
nome do instalador Windows derivam dela. O `build_installer.ps1` lê a versão
direto do pubspec.

## Android (APK)

### Assinatura — **crítico para updates**
O app é assinado com um **keystore de release dedicado** (não a debug key). Isso
é o que permite que um APK novo **atualize** o app instalado em vez de instalar
um app separado — o Android identifica o "dono" do app pela chave de assinatura.

| Arquivo | Papel | Versionado? |
|---|---|---|
| `android/app/hero_play_release.jks` | Keystore de release | **Não** (`.gitignore`) |
| `android/key.properties` | Credenciais + alias + caminho | **Não** (`.gitignore`) |
| `android/app/build.gradle.kts` | Lê `key.properties` e configura o signing | Sim |

> ⚠️ **Guardar o `.jks` em local seguro.** Perdê-lo significa não conseguir mais
> atualizar o app nos aparelhos sem desinstalar/reinstalar do zero.

O `build.gradle.kts` carrega `key.properties` se existir; senão, cai para a debug
key (mantém `flutter run` funcionando sem o keystore).

### Build
```bash
flutter build apk --release
# Saída: build/app/outputs/flutter-apk/app-release.apk
```
Para instalar direto num aparelho conectado: `flutter run --release -d <id>`.

## Windows (instalador)

### Build + instalador em um passo
Requer [Inno Setup](https://jrsoftware.org/isinfo.php) instalado.
```powershell
.\build_installer.ps1
# Saída: installer_output/Hero_Play_Setup_<versão>.exe
```
O script: lê a versão do pubspec → localiza o `ISCC.exe` (registro + caminhos
comuns) → `flutter build windows --release` → compila o
[`installer.iss`](../installer.iss).

### Updates in-place no Windows
O [`installer.iss`](../installer.iss) define um `AppId` fixo
(`{{B3F2A1C0-IPTV-PLAYER-SOUSA-0001}}`). Esse GUID estável é o que faz o
instalador **atualizar por cima** da versão anterior em vez de criar uma segunda
instalação. Nome do app: "Hero Play"; instala em `{autopf}\Hero Play`.

> ⚠️ Bug recorrente do ambiente: os `.cc` de `windows/flutter/ephemeral/cpp_client_wrapper`
> somem quando o symlink quebra (sem Developer Mode). Fix: copiar de
> `C:\src\flutter\bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper\*.cc`.
> Precisa refazer após `flutter clean`.

## Releases no GitHub

Repositório: `gabriel448/Hero-play` (o remote `IPTV` foi movido para lá).

Fluxo de release de uma versão:
1. `git commit` + `git tag vX.Y.Z` + `git push origin main --tags`.
2. Build do APK (com keystore) e do instalador Windows.
3. Renomear/copiar artefatos para o padrão de nome:
   - `Hero_Play_Setup_X.Y.Z.exe`
   - `Hero_Play_vX.Y.Z.apk`
4. Substituir assets no release (`gh release delete-asset` + `gh release upload`).

Comandos `gh` usados:
```bash
gh release list --repo gabriel448/Hero-play
gh release view vX.Y.Z --repo gabriel448/Hero-play --json assets
gh release upload vX.Y.Z <arquivos> --repo gabriel448/Hero-play
```

## API proxy (TMDB)

Pasta [`API/`](../API/) — proxy serverless Node.js, deploy no **Vercel**.

- Propósito: injetar a `TMDB_API_KEY` **server-side** para a chave nunca ficar
  no app. O app só conhece a URL do proxy (`TMDB_PROXY_URL` no `.env`).
- [`API/api/tmdb.js`](../API/api/tmdb.js): recebe `?p=<endpoint>&...`, anexa a
  api_key e repassa para `https://api.themoviedb.org`.
- Variável de ambiente no projeto Vercel da API: `TMDB_API_KEY`.
- `API/vercel.json`: `{ "version": 2 }`.

Sem o proxy configurado, o `TmdbService` retorna vazio e o app funciona normal
(sem sinopse/poster TMDB).

## Supabase (contas e sincronização)

### Estrutura

```
supabase/
├── config.toml            # Configuração do projeto Supabase CLI (local dev)
├── schema.sql             # DDL das tabelas `listas` e `perfis` + RLS + grants
├── .env                   # ENCRYPTION_KEY (AES-256-CBC) — NÃO versionado
├── functions/
│   └── iptv/              # Edge Function Deno — CRUD de listas com cifragem Xtream
└── templates/
    ├── mfa-ativado.html   # Email enviado quando MFA é ativado
    └── senha-alterada.html # Email enviado quando senha é alterada
```

### Edge Function `iptv`

Roda no Deno (runtime Supabase). Responsável por:
- **Cifragem:** extrai `username=` / `password=` da URL Xtream e cifra com
  AES-256-CBC usando `ENCRYPTION_KEY` do `supabase/.env`.
- **Escrita:** grava `fonte_url` sanitizada (sem credenciais) + `credenciais_enc`
  (cifradas) na tabela.
- **Leitura:** descriptografa `credenciais_enc` e reconstrói a URL completa
  antes de retornar ao app.

Deploy:
```bash
supabase functions deploy iptv --project-ref <ref>
```

### Configuração local

Preencher `supabase/.env` com:
```env
ENCRYPTION_KEY=<chave-hex-64-chars>
```

### Variáveis no app Flutter

No `.env` da raiz:
```env
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_ANON_KEY=<anon-key-publica>
```
Sem essas variáveis, o app roda em modo local-only (login não aparece).

### Schema

```sql
CREATE TABLE listas (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nome          TEXT NOT NULL,
  fonte_url     TEXT NOT NULL,       -- URL sanitizada (sem credenciais)
  credenciais_enc TEXT,              -- credenciais Xtream cifradas (AES-256-CBC)
  epg_url       TEXT,
  criado_em     TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, fonte_url)         -- chave do upsert
);
-- RLS: só o dono lê/escreve
ALTER TABLE listas ENABLE ROW LEVEL SECURITY;
```

### Tabela `perfis` (perfis de uso)

```sql
CREATE TABLE perfis (
  id               UUID PRIMARY KEY,        -- gerado no cliente (casa local↔nuvem)
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nome             TEXT NOT NULL,
  icone            TEXT NOT NULL DEFAULT 'ember',
  idioma           TEXT,                    -- BCP-47; null = padrão
  auto_qualidade   BOOLEAN NOT NULL DEFAULT false,
  ordem_categorias TEXT NOT NULL DEFAULT 'popularidade',
  ordem_canais     TEXT NOT NULL DEFAULT 'padrao',
  criado_em        TIMESTAMPTZ DEFAULT now()
);
-- RLS owner-only. Acessada DIRETO pelo app (sem Edge Function): perfis não têm
-- segredos a cifrar. Só a definição sobe — a biblioteca pessoal fica no Hive.
```

Rodar `supabase db push` (ou colar `schema.sql` no SQL Editor) para criar a
tabela no projeto remoto.

## Site (landing page + painel)

[`website/`](../website/) — páginas estáticas, deploy no Vercel. O
[`vercel.json`](../vercel.json) da raiz aponta `outputDirectory: website`.

| Arquivo | Papel |
|---|---|
| `index.html` | Landing page pública |
| `login.html` | Login / cadastro + MFA (autenticação Supabase client-side) |
| `painel.html` | Painel do usuário: gerenciar listas, configurações de conta, MFA |
| `supabase-config.js` | URL + anon key do Supabase (pública por design — protegida por RLS) |
| `assets/auth.css` | Estilos compartilhados de `login.html` e `painel.html` |

Os links de download na seção "Download" apontam para os assets do release no
GitHub — **precisam ser atualizados a cada nova versão**.

## Configuração local (.env)

```env
TMDB_PROXY_URL=https://sua-api.vercel.app
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_ANON_KEY=<anon-key-publica>
```
Carregado em runtime por `flutter_dotenv`; declarado como asset no `pubspec.yaml`.
Sem `SUPABASE_URL`/`SUPABASE_ANON_KEY`, o app roda em modo local-only.

## Resumo dos "gotchas"

| Item | Cuidado |
|---|---|
| Keystore Android | Guardar `.jks`; sem ele não há update |
| Primeiro update pós-keystore | O aparelho precisa desinstalar a versão antiga (assinatura mudou) uma única vez |
| `AppId` do Inno Setup | Não mudar — é o que permite update in-place no Windows |
| `cpp_client_wrapper` | Recopiar `.cc` após `flutter clean` no Windows |
| Links do site | Atualizar a cada release com nome de arquivo novo |
| Remote git | É `gabriel448/Hero-play` (não `IPTV`) |
| `supabase/.env` | Guardar `ENCRYPTION_KEY` junto com o keystore — sem ela não dá para descriptografar listas Xtream |
| Edge Function | Fazer `supabase functions deploy iptv` após mudanças em `supabase/functions/iptv/` |