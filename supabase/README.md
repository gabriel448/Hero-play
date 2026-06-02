# Contas e sincronizacao de listas (Supabase)

Backend de contas do Hero Play. O Supabase guarda **apenas as definicoes**
das listas de cada usuario (nome + URL da M3U + URL do EPG). Os canais
parseados continuam **locais** no app (cache Hive) — o banco fica minusculo.

```
[ Site: login.html + painel.html ]  --\
   (supabase-js, no navegador)         \
                                        >-- [ Supabase: Auth + tabela `listas` + RLS ]
[ App Flutter / TV ]  -------------------/
   login -> puxa definicoes -> parse local -> Hive (cache dos canais)
```

## Passo a passo do setup

1. **Crie o projeto** em <https://supabase.com> (plano free serve).
2. **Rode o schema:** Dashboard > *SQL Editor* > *New query* > cole o conteudo
   de [`schema.sql`](schema.sql) > *Run*. Isso cria a tabela `listas`, os
   indices, as policies de **RLS** e o trigger de `updated_at`.
3. **Auth (MVP):** Dashboard > *Authentication* > *Providers* > **Email** ligado.
   - Para o login funcionar **na hora** (sem confirmar email), em
     *Authentication > Sign In / Providers > Email* desligue
     **"Confirm email"**. Da pra reativar depois, quando formos cuidar de
     seguranca a serio.
4. **Pegue as chaves publicas:** Dashboard > *Project Settings* > *API*:
   - `Project URL`
   - `anon public` key
5. **Configure o site:** cole essas duas no arquivo
   [`../website/supabase-config.js`](../website/supabase-config.js).

## Sobre a `anon key` (importante)

A `anon key` **e publica por design** — pode ir no front-end e no Git sem
problema. Quem protege os dados e o **RLS** (passo 2), nao o segredo da chave.
Por isso o RLS nao e opcional, nem no MVP. A chave que **nunca** pode vazar e a
`service_role` — nao use ela no site nem no app.

## Tabela `listas`

| coluna       | tipo          | nota                                  |
|--------------|---------------|---------------------------------------|
| `id`         | uuid          | PK                                    |
| `user_id`    | uuid          | FK -> `auth.users`, preenchido no app |
| `nome`       | text          | nome amigavel da lista                |
| `fonte_url`  | text          | URL da M3U                            |
| `epg_url`    | text (nulo)   | URL do XMLTV/EPG                      |
| `ordem`      | int           | ordem de exibicao                     |
| `created_at` | timestamptz   |                                       |
| `updated_at` | timestamptz   | atualizado por trigger                |

## Proximos passos (app Flutter)

- Pacote `supabase_flutter`.
- `services/servico_conta.dart` — auth + CRUD das definicoes.
- Provider de conta seguindo o padrao do projeto (grava -> recarrega ->
  `notifyListeners()`).
- No login: puxa as definicoes -> `IptvProvider.importarPorUrl(...)` para cada
  uma (parse local, como ja faz hoje) -> Hive vira cache.
