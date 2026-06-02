-- ============================================================================
-- Hero Play — schema de contas e listas (MVP)
--
-- Rode este SQL no Supabase em: Dashboard > SQL Editor > New query > Run.
-- A autenticacao (email/senha) e gerenciada pelo proprio Supabase Auth,
-- entao aqui so criamos a tabela que guarda as DEFINICOES das listas de
-- cada usuario (nome + URL da M3U + URL do EPG). Os canais NAO ficam aqui:
-- o app baixa e faz o parse da M3U localmente e mantem em cache (Hive).
-- ============================================================================

-- Tabela: cada linha e uma lista pertencente a um usuario.
create table if not exists public.listas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  nome       text not null,
  fonte_url  text not null,           -- URL da lista M3U
  epg_url    text,                    -- URL do XMLTV/EPG (opcional)
  ordem      int  not null default 0, -- ordem de exibicao escolhida pelo usuario
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Busca rapida das listas de um usuario.
create index if not exists listas_user_id_idx on public.listas (user_id);

-- Cada usuario nao pode ter a mesma URL de lista duas vezes. Serve tambem
-- de chave para o app sincronizar (upsert por user_id + fonte_url).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'listas_user_fonte_unica'
  ) then
    alter table public.listas
      add constraint listas_user_fonte_unica unique (user_id, fonte_url);
  end if;
end $$;

-- ============================================================================
-- Row Level Security (RLS) — ESSENCIAL.
-- Sem isto, qualquer pessoa com a anon key le/escreve as listas de todos.
-- Com isto, cada usuario so enxerga e mexe nas PROPRIAS linhas.
-- ============================================================================
alter table public.listas enable row level security;

drop policy if exists "listas_select_proprias" on public.listas;
create policy "listas_select_proprias" on public.listas
  for select using (auth.uid() = user_id);

drop policy if exists "listas_insert_proprias" on public.listas;
create policy "listas_insert_proprias" on public.listas
  for insert with check (auth.uid() = user_id);

drop policy if exists "listas_update_proprias" on public.listas;
create policy "listas_update_proprias" on public.listas
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "listas_delete_proprias" on public.listas;
create policy "listas_delete_proprias" on public.listas
  for delete using (auth.uid() = user_id);

-- ============================================================================
-- Colunas para separar credenciais Xtream da URL da lista.
-- Migracao segura: ADD COLUMN IF NOT EXISTS nao quebra instancias ja rodando.
-- As listas existentes ficam com xtream_user/pass NULL (URLs diretas sem creds).
-- ============================================================================
alter table public.listas
  add column if not exists server_url  text,           -- origem do servidor Xtream
  add column if not exists xtream_user text,           -- usuario cifrado (AES-256-CBC, base64)
  add column if not exists xtream_pass text;           -- senha   cifrada (AES-256-CBC, base64)

-- ============================================================================
-- Privilegios de tabela (GRANT).
-- O RLS decide QUAIS linhas o usuario ve; mas o Postgres ainda exige GRANT
-- para o papel poder acessar a tabela. Sem isto da:
--   "permission denied for table listas".
-- Concedemos APENAS ao papel `authenticated` (usuario logado). O papel `anon`
-- nao precisa de acesso: a Edge Function valida o JWT antes de qualquer query,
-- entao requisicoes nao autenticadas nunca chegam aqui.
-- ============================================================================
revoke select, insert, update, delete on public.listas from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.listas to authenticated;

-- Recarrega o cache da API (PostgREST) apos mudancas de schema/privilegios.
notify pgrst, 'reload schema';

-- ============================================================================
-- Mantem updated_at sempre atualizado em UPDATEs.
-- ============================================================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists listas_set_updated_at on public.listas;
create trigger listas_set_updated_at
  before update on public.listas
  for each row execute function public.set_updated_at();
