-- ============================================================================
-- Hero Play — SCHEMA do PROJETO DE TV + PAINEL DE REVENDA (limpo).
--
-- Rode ESTE arquivo no projeto Supabase NOVO (TV + painel), NÃO o `schema.sql`
-- (aquele é o do app MOBILE/DESKTOP e traz tabelas que NÃO existem aqui:
-- `listas`, `perfis`, `biblioteca`, `codigos_ativacao`, `contas_ativacao`,
-- além do login/e-mail do cliente final e do sync de favoritos/continuar
-- assistindo — nada disso é da TV, que é local-first e sem conta/PII).
--
-- Aqui só entra o que TV e painel COMPARTILHAM:
--   revendedores → clientes → dispositivos → playlists (↔ dispositivo_playlists)
--   + creditos_transacoes + codigos_ativacao_tv + as RPCs de crédito.
--
-- Identidade/segurança:
--   - App de TV: SEM login. Identifica-se por MAC+Key; fala só com a Edge
--     Function `ativacao` (service role). Nunca toca em auth.users nem em crédito.
--   - Painel: o REVENDEDOR loga (auth.users). `revendedores.id` = auth.users(id).
--   - Ninguém (anon/authenticated) acessa as tabelas direto — só as Edge
--     Functions via service role. RLS ligado + GRANT só p/ service_role.
--
-- Ordem importa (FKs): revendedores → clientes → dispositivos → playlists →
--   dispositivo_playlists → creditos_transacoes → codigos_ativacao_tv → RPCs.
-- ============================================================================
create extension if not exists pgcrypto;

grant usage on schema public to authenticated;

-- ── OPERADOR DO PAINEL (revendedores) ───────────────────────────────────────
-- Hierarquia admin → master → reseller. Cada nível cria/distribui crédito ao de
-- baixo; o reseller CONSOME crédito ao ativar um device. Contas TOP-DOWN (sem
-- signup público): quem está acima cria o login via `painel` (auth.admin.createUser).
-- Login é por USUÁRIO (sem e-mail). O Supabase Auth exige e-mail, então guardamos
-- um e-mail SINTÉTICO em auth.users (`<usuario>@u.heroplaytv.com`, nunca enviado —
-- contas são auto-confirmadas) e o `usuario` legível aqui. `email` fica só de
-- legado (contas antigas/admin com e-mail real).
create table if not exists public.revendedores (
  id                uuid primary key references auth.users(id) on delete cascade,
  nome              text,
  usuario           text,                              -- nome de login (único)
  email             text,                              -- legado/opcional (admin com e-mail real)
  papel             text not null default 'reseller',   -- admin | master | reseller
  criado_por        uuid references public.revendedores(id) on delete set null,
  saldo_creditos    int not null default 0,
  ativo             boolean not null default true,
  codigo_indicacao  text,                              -- código do link de indicação (único)
  criado_em         timestamptz not null default now()
);
alter table public.revendedores add column if not exists usuario text;
create unique index if not exists idx_revendedores_usuario on public.revendedores(lower(usuario));
create unique index if not exists idx_revendedores_codigo on public.revendedores(codigo_indicacao);
alter table public.revendedores enable row level security;
revoke all on public.revendedores from anon, authenticated;
grant all on public.revendedores to service_role;

-- ── CLIENTE (dono das playlists e dispositivos) ─────────────────────────────
-- revendedor_id NULL = self-serve (ativação independente, sem revenda).
create table if not exists public.clientes (
  id            uuid primary key default gen_random_uuid(),
  revendedor_id uuid references public.revendedores(id) on delete set null,
  nome          text,
  criado_em     timestamptz not null default now()
);
create index if not exists idx_clientes_revendedor on public.clientes(revendedor_id);
alter table public.clientes enable row level security;
revoke all on public.clientes from anon, authenticated;
grant all on public.clientes to service_role;

-- ── DISPOSITIVO (MAC + Key) ─────────────────────────────────────────────────
-- A Key (mostrada na TV) é o segredo do aparelho: liga o device na 1ª gravação e
-- protege leituras/trocas. `modelo` = plataforma real (webos|tizen|roku|androidtv).
create table if not exists public.dispositivos (
  id              uuid primary key default gen_random_uuid(),
  mac             text unique not null,
  device_key      text not null,
  modelo          text,                              -- webos|tizen|roku|androidtv|web
  cliente_id      uuid references public.clientes(id) on delete set null,
  status          text not null default 'trial',     -- sem_lista|trial|ativo|expirado|banido
  trial_expira_em timestamptz,
  expira_em       timestamptz,
  ativado_por     text,                              -- qr|codigo|admin|reseller
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index if not exists idx_dispositivos_cliente on public.dispositivos(cliente_id);
alter table public.dispositivos enable row level security;
revoke all on public.dispositivos from anon, authenticated;
grant all on public.dispositivos to service_role;

-- ── PLAYLIST do cliente (URL/EPG CIFRADOS pela Edge Function) ───────────────
create table if not exists public.playlists (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid references public.clientes(id) on delete cascade,
  nome          text,
  tipo          text,                                -- xtream|m3u
  url_cifrada   text not null,
  epg_cifrada   text,
  pin           text,                                -- senha da playlist no device (opcional)
  free_dns      boolean not null default false,      -- domínio parceiro → ativação sem crédito
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists idx_playlists_cliente on public.playlists(cliente_id);
alter table public.playlists enable row level security;
revoke all on public.playlists from anon, authenticated;
grant all on public.playlists to service_role;

-- ── VÍNCULO dispositivo ↔ playlist (N↔N) ────────────────────────────────────
-- `selecionada` = playlist ATIVA naquele dispositivo (uma por device).
create table if not exists public.dispositivo_playlists (
  dispositivo_id uuid not null references public.dispositivos(id) on delete cascade,
  playlist_id    uuid not null references public.playlists(id)    on delete cascade,
  selecionada    boolean not null default false,
  criado_em      timestamptz not null default now(),
  primary key (dispositivo_id, playlist_id)
);
create index if not exists idx_dp_dispositivo on public.dispositivo_playlists(dispositivo_id);
create index if not exists idx_dp_playlist    on public.dispositivo_playlists(playlist_id);
alter table public.dispositivo_playlists enable row level security;
revoke all on public.dispositivo_playlists from anon, authenticated;
grant all on public.dispositivo_playlists to service_role;

-- ── EXTRATO DE CRÉDITOS (uma linha por movimento) ───────────────────────────
-- tipo = adicionado|consumido|transferido_saida|transferido_entrada.
create table if not exists public.creditos_transacoes (
  id            uuid primary key default gen_random_uuid(),
  revendedor_id uuid not null references public.revendedores(id) on delete cascade,
  tipo          text not null,
  quantidade    int  not null,               -- +entra / -sai (do ponto de vista do dono)
  saldo_apos    int,
  por           uuid references public.revendedores(id) on delete set null,
  nota          text,
  criado_em     timestamptz not null default now()
);
create index if not exists idx_creditos_rev on public.creditos_transacoes(revendedor_id, criado_em desc);
alter table public.creditos_transacoes enable row level security;
revoke all on public.creditos_transacoes from anon, authenticated;
grant all on public.creditos_transacoes to service_role;

-- ── CÓDIGOS DE ATIVAÇÃO do TV (dev/revendedor gera; cliente usa em "ativar") ─
-- dias = null → vitalício.
create table if not exists public.codigos_ativacao_tv (
  codigo        text primary key,
  dias          int,
  usado         boolean not null default false,
  usado_por_mac text,
  nota          text,
  criado_em     timestamptz not null default now()
);
alter table public.codigos_ativacao_tv enable row level security;
revoke all on public.codigos_ativacao_tv from anon, authenticated;
grant all on public.codigos_ativacao_tv to service_role;

-- ═══════════════════════════════════════════════════════════════════════════
--  RPCs de CRÉDITO — transacionais (evitam o double-spend).
--  O débito é um único UPDATE com guarda `saldo >= qtd`, que serializa no lock
--  da linha → impossível gastar 2× em requisições simultâneas.
-- ═══════════════════════════════════════════════════════════════════════════

-- Transfere créditos entre revendedores (débito + crédito + 2 lançamentos), atômico.
create or replace function public.rpc_transferir_creditos(
  p_de uuid, p_para uuid, p_qtd int, p_por uuid,
  p_nota_saida text, p_nota_entrada text
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saldo_de   int;
  v_saldo_para int;
begin
  if p_qtd is null or p_qtd <= 0 then raise exception 'QTD_INVALIDA'; end if;

  update revendedores set saldo_creditos = saldo_creditos - p_qtd
    where id = p_de and saldo_creditos >= p_qtd
    returning saldo_creditos into v_saldo_de;
  if not found then raise exception 'SALDO_INSUFICIENTE'; end if;

  update revendedores set saldo_creditos = saldo_creditos + p_qtd
    where id = p_para
    returning saldo_creditos into v_saldo_para;
  if not found then raise exception 'DESTINO_INVALIDO'; end if;

  insert into creditos_transacoes (revendedor_id, tipo, quantidade, saldo_apos, por, nota) values
    (p_de,   'transferido_saida',   -p_qtd, v_saldo_de,   p_por, p_nota_saida),
    (p_para, 'transferido_entrada',  p_qtd, v_saldo_para, p_por, p_nota_entrada);

  return v_saldo_de;
end $$;

-- Ativa um dispositivo consumindo 1 crédito, atômico. Device já 'ativo' NÃO cobra.
create or replace function public.rpc_ativar_dispositivo(
  p_dispositivo_id uuid, p_cliente_id uuid, p_rev uuid, p_mac text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ja_ativo boolean;
  v_saldo    int;
begin
  select (status = 'ativo') into v_ja_ativo from dispositivos where id = p_dispositivo_id for update;
  if not found then raise exception 'DEVICE_INEXISTENTE'; end if;

  if not v_ja_ativo then
    update revendedores set saldo_creditos = saldo_creditos - 1
      where id = p_rev and saldo_creditos >= 1
      returning saldo_creditos into v_saldo;
    if not found then raise exception 'SALDO_INSUFICIENTE'; end if;

    insert into creditos_transacoes (revendedor_id, tipo, quantidade, saldo_apos, por, nota)
      values (p_rev, 'consumido', -1, v_saldo, p_rev, 'Ativação do dispositivo ' || coalesce(p_mac, ''));
  else
    select saldo_creditos into v_saldo from revendedores where id = p_rev;
  end if;

  update dispositivos
     set cliente_id = p_cliente_id, status = 'ativo', ativado_por = 'reseller', atualizado_em = now()
   where id = p_dispositivo_id;

  return json_build_object('cobrado', not v_ja_ativo, 'saldo', v_saldo);
end $$;

revoke all on function public.rpc_transferir_creditos(uuid, uuid, int, uuid, text, text) from anon, authenticated;
revoke all on function public.rpc_ativar_dispositivo(uuid, uuid, uuid, text) from anon, authenticated;
grant execute on function public.rpc_transferir_creditos(uuid, uuid, int, uuid, text, text) to service_role;
grant execute on function public.rpc_ativar_dispositivo(uuid, uuid, uuid, text) to service_role;

notify pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════════════════
--  BOOTSTRAP do 1º admin. O login é por USUÁRIO → o e-mail no Auth é SINTÉTICO.
--    1) Authentication → Add user:
--         E-mail: admin@u.heroplaytv.com   (sintético; escolha o usuário "admin")
--         Senha:  <sua senha>              (marque Auto Confirm User)
--    2) Rode (usuario = 'admin' casa com o e-mail acima):
--
--  insert into public.revendedores (id, nome, usuario, papel, saldo_creditos, codigo_indicacao)
--  select id, 'Admin', 'admin', 'admin', 100000, 'ADMIN001'
--    from auth.users where email = 'admin@u.heroplaytv.com'
--  on conflict (id) do update set papel = 'admin', usuario = 'admin';
--
--  → No painel, logue com usuário "admin" e a senha escolhida.
-- ════════════════════════════════════════════════════════════════════════════