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

-- "Para onde foi" cada movimento, em COLUNA. Antes so existia na `nota`, texto
-- livre: dava para ler numa linha, nao para filtrar nem juntar na visao do
-- admin de todos os revendedores. As RPCs abaixo preenchem as tres.
alter table public.creditos_transacoes add column if not exists dispositivo_id uuid references public.dispositivos(id) on delete set null;
alter table public.creditos_transacoes add column if not exists plano text;
alter table public.creditos_transacoes add column if not exists contraparte_id uuid references public.revendedores(id) on delete set null;
create index if not exists idx_creditos_criado on public.creditos_transacoes(criado_em desc);

-- Backfill das ativacoes ANTIGAS, lendo a nota "Ativação do dispositivo
-- AA:BB:.. (ano)". Idempotente: so toca linha com a coluna ainda nula. Casa o
-- aparelho por IGUALDADE do MAC extraido (e nao `like '%mac%'`, que varreria
-- todos os aparelhos para cada linha). Transferencias antigas ficam sem
-- contraparte — a nota delas ("Para X") continua sendo o que se le.
update public.creditos_transacoes
   set plano = substring(nota from '\(([a-z]+)\)$')
 where tipo = 'consumido' and plano is null and nota ~ '\([a-z]+\)$';
update public.creditos_transacoes t
   set dispositivo_id = d.id
  from public.dispositivos d
 where t.tipo = 'consumido' and t.dispositivo_id is null
   and d.mac = substring(t.nota from 'dispositivo ([0-9A-Fa-f:]+) \(');

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

-- ── SUPORTE (tickets) ───────────────────────────────────────────────────────
-- Um ticket é aberto por um revendedor; o ADMIN vê TODOS e responde/encerra. As
-- mensagens (thread) ficam em ticket_mensagens. status: aberto|respondido|fechado.
create table if not exists public.tickets (
  id            uuid primary key default gen_random_uuid(),
  revendedor_id uuid not null references public.revendedores(id) on delete cascade,
  assunto       text not null,
  status        text not null default 'aberto',      -- aberto | respondido | fechado
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists idx_tickets_rev on public.tickets(revendedor_id, atualizado_em desc);
create index if not exists idx_tickets_status on public.tickets(status, atualizado_em desc);
alter table public.tickets enable row level security;
revoke all on public.tickets from anon, authenticated;
grant all on public.tickets to service_role;

create table if not exists public.ticket_mensagens (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets(id) on delete cascade,
  autor_id   uuid references public.revendedores(id) on delete set null,
  do_admin   boolean not null default false,           -- true = resposta do suporte/admin
  corpo      text not null,
  criado_em  timestamptz not null default now()
);
create index if not exists idx_ticket_msg on public.ticket_mensagens(ticket_id, criado_em);
alter table public.ticket_mensagens enable row level security;
revoke all on public.ticket_mensagens from anon, authenticated;
grant all on public.ticket_mensagens to service_role;

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
  v_admin      boolean;
  v_saldo_de   int;
  v_saldo_para int;
begin
  if p_qtd is null or p_qtd <= 0 then raise exception 'QTD_INVALIDA'; end if;

  -- ADMIN tem credito INFINITO: ele e a fonte, nao um estoque. Nao debita nem
  -- lanca saida no extrato dele — so credita quem recebe. O papel e lido AQUI
  -- (e nao vem do cliente) pra ninguem se declarar admin pela requisicao.
  select (papel = 'admin') into v_admin from revendedores where id = p_de;
  if v_admin is null then raise exception 'ORIGEM_INVALIDA'; end if;

  if not v_admin then
    update revendedores set saldo_creditos = saldo_creditos - p_qtd
      where id = p_de and saldo_creditos >= p_qtd
      returning saldo_creditos into v_saldo_de;
    if not found then raise exception 'SALDO_INSUFICIENTE'; end if;
  end if;

  update revendedores set saldo_creditos = saldo_creditos + p_qtd
    where id = p_para
    returning saldo_creditos into v_saldo_para;
  if not found then raise exception 'DESTINO_INVALIDO'; end if;

  -- `contraparte_id` = o outro lado da transferencia, para o historico do admin
  -- dizer "para quem" sem depender do texto da nota.
  if not v_admin then
    insert into creditos_transacoes (revendedor_id, tipo, quantidade, saldo_apos, por, nota, contraparte_id)
      values (p_de, 'transferido_saida', -p_qtd, v_saldo_de, p_por, p_nota_saida, p_para);
  end if;
  insert into creditos_transacoes (revendedor_id, tipo, quantidade, saldo_apos, por, nota, contraparte_id)
    values (p_para, 'transferido_entrada', p_qtd, v_saldo_para, p_por, p_nota_entrada, p_de);

  return v_saldo_de;   -- NULL p/ admin: o painel nao mostra saldo dele
end $$;

-- ── PLANO da ativacao (1 ano / vitalicia) ────────────────────────────────────
-- `plano` guarda o que foi VENDIDO ('ano' | 'vitalicia'; 'semestre' ja previsto
-- p/ quando for oferecido) e `expira_em` a data em que a assinatura morre —
-- NULL = vitalicia. Quem le a validade e a Edge Function `ativacao`: passou da
-- data, o device vira 'expirado' e para de receber a lista.
alter table public.dispositivos add column if not exists plano text;
create index if not exists idx_disp_expira on public.dispositivos(expira_em)
  where expira_em is not null;

-- Ativa/RENOVA um dispositivo consumindo 1 crédito, atômico.
--
-- ⚠️ A assinatura da funcao MUDOU (ganhou plano/meses/renovar). No Postgres uma
-- assinatura nova cria uma SOBRECARGA em vez de substituir — por isso o drop da
-- versao de 4 argumentos, senao a antiga continuaria existindo e ativando sem
-- validade nenhuma.
drop function if exists public.rpc_ativar_dispositivo(uuid, uuid, uuid, text);

create or replace function public.rpc_ativar_dispositivo(
  p_dispositivo_id uuid, p_cliente_id uuid, p_rev uuid, p_mac text,
  p_plano text,            -- 'ano' | 'vitalicia' | 'semestre'
  p_meses int,             -- NULL = vitalicia (sem data de expiracao)
  p_renovar boolean default false
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin    boolean;
  v_status   text;
  v_exp      timestamptz;
  v_vigente  boolean;      -- ativo E dentro da validade
  v_cobra    boolean;
  v_base     timestamptz;
  v_nova     timestamptz;
  v_saldo    int;
begin
  select status, expira_em into v_status, v_exp
    from dispositivos where id = p_dispositivo_id for update;
  if not found then raise exception 'DEVICE_INEXISTENTE'; end if;

  -- ADMIN ativa/renova de graca (credito infinito). Papel lido do banco.
  select (papel = 'admin') into v_admin from revendedores where id = p_rev;

  -- "Ja ativo" tem que considerar a VALIDADE: um device com status 'ativo' e
  -- expira_em no passado esta expirado, e re-ativar tem que cobrar de novo.
  v_vigente := (v_status = 'ativo' and (v_exp is null or v_exp > now()));
  -- Renovacao sempre cobra (e o que o revendedor esta vendendo de novo).
  -- Vincular de novo um device VIGENTE nao cobra — protege o duplo-clique.
  v_cobra := (p_renovar or not v_vigente) and not coalesce(v_admin, false);

  if v_cobra then
    update revendedores set saldo_creditos = saldo_creditos - 1
      where id = p_rev and saldo_creditos >= 1
      returning saldo_creditos into v_saldo;
    if not found then raise exception 'SALDO_INSUFICIENTE'; end if;

    -- A nota continua (e o que o extrato do revendedor mostra), mas o aparelho e
    -- o plano agora vao tambem em COLUNA, para o historico do admin filtrar.
    insert into creditos_transacoes (revendedor_id, tipo, quantidade, saldo_apos, por, nota, dispositivo_id, plano)
      values (p_rev, 'consumido', -1, v_saldo,  p_rev,
              (case when p_renovar then 'Renovação' else 'Ativação' end)
              || ' do dispositivo ' || coalesce(p_mac, '')
              || ' (' || coalesce(p_plano, '?') || ')',
              p_dispositivo_id, p_plano);
  elsif not coalesce(v_admin, false) then
    select saldo_creditos into v_saldo from revendedores where id = p_rev;
  end if;   -- admin: v_saldo fica NULL (o painel nao mostra saldo dele)

  if p_meses is null then
    v_nova := null;                                  -- vitalicia
  else
    -- Renovar ANTES de vencer SOMA ao que resta (o cliente nao perde os dias
    -- que ja pagou). Vencido, conta a partir de agora.
    v_base := case when v_exp is not null and v_exp > now() then v_exp else now() end;
    v_nova := v_base + (p_meses || ' months')::interval;
  end if;

  update dispositivos
     set cliente_id   = coalesce(p_cliente_id, cliente_id),   -- renovar nao troca de cliente
         status       = 'ativo',
         plano        = p_plano,
         expira_em    = v_nova,
         ativado_por  = 'reseller',
         atualizado_em = now()
   where id = p_dispositivo_id;

  return json_build_object('cobrado', v_cobra, 'saldo', v_saldo, 'expira_em', v_nova);
end $$;

revoke all on function public.rpc_transferir_creditos(uuid, uuid, int, uuid, text, text) from anon, authenticated;
revoke all on function public.rpc_ativar_dispositivo(uuid, uuid, uuid, text, text, int, boolean) from anon, authenticated;
grant execute on function public.rpc_transferir_creditos(uuid, uuid, int, uuid, text, text) to service_role;
grant execute on function public.rpc_ativar_dispositivo(uuid, uuid, uuid, text, text, int, boolean) to service_role;

-- ── TICKETS: topico pre-definido ──────────────────────────────────────────────
-- O revendedor nao escreve mais o assunto: escolhe entre Financeiro/Tecnico/
-- Login e so descreve o problema. O `assunto` continua sendo gravado (o rotulo
-- do topico) para nao quebrar nada que ja o exibe.
alter table public.tickets add column if not exists topico text;
create index if not exists idx_tickets_topico on public.tickets(topico, atualizado_em desc);

-- ── CAIXA DE ENTRADA (notificacoes do painel) ────────────────────────────────
-- Uma linha por aviso recebido. Hoje nascem de: ticket respondido, ticket novo
-- (p/ o admin), creditos recebidos, revendedor novo na rede e aviso do admin.
-- `ref` guarda o id do que originou (ticket, por exemplo) p/ o clique abrir.
create table if not exists public.notificacoes (
  id            uuid primary key default gen_random_uuid(),
  revendedor_id uuid not null references public.revendedores(id) on delete cascade,
  tipo          text not null,               -- ticket | credito | rede | aviso
  titulo        text not null,
  corpo         text,
  ref           text,                        -- id do ticket/etc, quando houver
  lida          boolean not null default false,
  criado_em     timestamptz not null default now()
);
create index if not exists idx_notif_rev on public.notificacoes(revendedor_id, criado_em desc);
create index if not exists idx_notif_nao_lida on public.notificacoes(revendedor_id, lida);
alter table public.notificacoes enable row level security;
revoke all on public.notificacoes from anon, authenticated;
grant all on public.notificacoes to service_role;

-- ── PARCEIROS (dominios com ativacao liberada) ───────────────────────────────
-- Um parceiro e um SERVIDOR/dominio de lista. Todo dispositivo que recebe uma
-- playlist apontando pra ele entra ATIVO na hora — sem teste e sem consumir
-- credito. E o acordo comercial com quem revende o app junto do proprio painel
-- de IPTV. Quem cadastra/suspende e SO o admin.
create table if not exists public.parceiros (
  id        uuid primary key default gen_random_uuid(),
  dominio   text not null,               -- host[:porta], minusculo, sem esquema nem caminho
  nome      text,                        -- rotulo do acordo (opcional)
  ativo     boolean not null default true,
  cobranca  text not null default 'gratuito',   -- gratuito | mensal | por_device
  valor     numeric(12,2),               -- valor da mensalidade / por device
  nota      text,
  criado_em timestamptz not null default now()
);
create unique index if not exists idx_parceiros_dominio on public.parceiros(lower(dominio));
alter table public.parceiros enable row level security;
revoke all on public.parceiros from anon, authenticated;
grant all on public.parceiros to service_role;

-- HOST da playlist em texto claro. A URL continua CIFRADA (e ela que carrega
-- usuario e senha); aqui fica so o dominio, que e o que precisamos para casar
-- com um parceiro e para contar quantos devices usam cada um — sem ter que
-- decifrar a base inteira a cada consulta.
alter table public.playlists add column if not exists host text;
create index if not exists idx_playlists_host on public.playlists(host);

-- ── FATURAS DOS PARCEIROS ────────────────────────────────────────────────────
-- Uma linha por parceiro POR PERIODO. Nasce em "aguardando" quando o admin roda
-- a cobranca; vira "pago" (por ora na mao — nao ha gateway ainda) ou
-- "cancelado". `carencia_ate` e `extensoes` sustentam o "+ Carencia": apos o
-- vencimento o parceiro tem uns dias antes de ser suspenso, e o admin pode
-- estender um numero limitado de vezes (limites em `parceiros_config`).
create table if not exists public.parceiro_faturas (
  id           uuid primary key default gen_random_uuid(),
  parceiro_id  uuid not null references public.parceiros(id) on delete cascade,
  tipo         text not null,                       -- mensal | por_device
  periodo_ini  date not null,
  periodo_fim  date not null,
  devices      int  not null default 0,             -- devices contados no fechamento
  valor        numeric(12,2) not null default 0,
  status       text not null default 'aguardando',  -- aguardando | pago | cancelado
  vencimento   date not null,
  carencia_ate date,
  extensoes    int not null default 0,
  pago_em      timestamptz,
  criado_em    timestamptz not null default now()
);
-- Uma fatura por parceiro por periodo: e o que torna "Executar cobranca"
-- IDEMPOTENTE (rodar duas vezes no mesmo mes nao duplica nada).
create unique index if not exists idx_fatura_periodo on public.parceiro_faturas(parceiro_id, periodo_ini);
create index if not exists idx_fatura_status on public.parceiro_faturas(status, vencimento);
alter table public.parceiro_faturas enable row level security;
revoke all on public.parceiro_faturas from anon, authenticated;
grant all on public.parceiro_faturas to service_role;

-- ── CONFIGURACAO DO PROGRAMA DE PARCEIROS (linha unica) ──────────────────────
create table if not exists public.parceiros_config (
  id                 int primary key default 1 check (id = 1),
  modelo_mensal      boolean not null default true,   -- pre-pago: valor fixo/mes
  modelo_por_device  boolean not null default false,  -- pos-pago: por device ativo
  preco_mensal       numeric(12,2) not null default 0,
  preco_device       numeric(12,2) not null default 0,
  dia_cobranca       int not null default 5,          -- dia do mes do fechamento
  carencia_dias      int not null default 3,
  carencia_extra_max int not null default 7,
  carencia_extensoes int not null default 2,
  programa_ativo     boolean not null default true,
  banner_texto       text,
  atualizado_em      timestamptz not null default now()
);
insert into public.parceiros_config (id) values (1) on conflict (id) do nothing;
alter table public.parceiros_config enable row level security;
revoke all on public.parceiros_config from anon, authenticated;
grant all on public.parceiros_config to service_role;

-- ── SERVIDORES (atalho de login Xtream por CODIGO) ──────────────────────────
-- Em vez de digitar "http://servidor.com:8080" no aparelho, o usuario digita um
-- CODIGO curto e o app resolve para o host. E so um facilitador de digitacao —
-- nao guarda usuario/senha de ninguem.
--   `id_num` e o numero curto que aparece no painel ("ID #141"); o uuid continua
--   sendo a chave. `codigo` e case-insensitive (indice sobre upper()).
create table if not exists public.servidores (
  id         uuid primary key default gen_random_uuid(),
  id_num     bigint generated always as identity,
  codigo     text not null,
  host       text not null,                  -- URL base: http://servidor.com:8080
  nome       text,                           -- rotulo interno ("Api", "Razors"…)
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);
create unique index if not exists idx_servidor_codigo on public.servidores(upper(codigo));
create index if not exists idx_servidor_host on public.servidores(host);
alter table public.servidores enable row level security;
revoke all on public.servidores from anon, authenticated;
grant all on public.servidores to service_role;

-- ════════════════════════════════════════════════════════════════════════════
--  API PUBLICA (chaves) — integracao com paineis de terceiros.
--
--  A chave NUNCA e guardada em texto: so o SHA-256 dela. Quem cria ve o valor
--  UMA vez, na resposta da criacao; depois nao ha como recuperar, so revogar e
--  gerar outra. Se o banco vazar, as chaves nao vazam junto.
--
--  `prefixo` e o pedacinho visivel (ex.: "hp_a1b2c3d4") para o admin distinguir
--  uma chave da outra na tela sem precisar do segredo.
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.api_chaves (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,                  -- rotulo ("Painel do Danny", "Teste")
  prefixo       text not null,                  -- inicio da chave, visivel
  hash          text not null,                  -- SHA-256 hex da chave inteira
  revendedor_id uuid not null references public.revendedores(id) on delete cascade,
  ativo         boolean not null default true,
  ultimo_uso_em timestamptz,
  criado_em     timestamptz not null default now(),
  revogada_em   timestamptz
);
create unique index if not exists idx_api_chaves_hash on public.api_chaves(hash);

-- ── LOG DE REQUISICOES DA API ───────────────────────────────────────────────
-- Toda chamada a Edge Function `api` vira uma linha aqui, inclusive as que
-- falham na autenticacao: chave invalida batendo de novo e de novo e
-- justamente o que se quer enxergar.
--
-- ⚠️ NAO guarda corpo de requisicao nem query string. O corpo do
-- POST/PATCH /playlists leva `lista_url`, que carrega USUARIO E SENHA do
-- servidor Xtream em texto claro — a playlist e gravada cifrada no banco
-- exatamente para isso nao ficar a mostra, e um log de depuracao nao pode ser
-- a porta dos fundos dessa protecao. Guarda o caminho, o resultado e quanto
-- demorou, que e o que responde "essa integracao esta funcionando?".
create table if not exists public.api_logs (
  id         bigserial primary key,
  -- `on delete set null` + prefixo desnormalizado: revogar e apagar a chave
  -- nao pode apagar o historico do que ela fez.
  chave_id   uuid references public.api_chaves(id) on delete set null,
  prefixo    text,                             -- inicio da chave apresentada
  chave_nome text,                             -- rotulo no momento da chamada
  metodo     text not null,
  rota       text not null,                    -- caminho, SEM query string
  status     int  not null,
  ms         int,                              -- duracao
  ip         text,
  erro       text,                             -- mensagem NOSSA, nunca corpo
  criado_em  timestamptz not null default now()
);
create index if not exists idx_api_logs_criado on public.api_logs(criado_em desc);
create index if not exists idx_api_logs_chave  on public.api_logs(chave_id, criado_em desc);
create index if not exists idx_api_logs_status on public.api_logs(status, criado_em desc);
alter table public.api_logs enable row level security;
revoke all on public.api_logs from anon, authenticated;
grant all on public.api_logs to service_role;
grant usage, select on sequence public.api_logs_id_seq to service_role;

create index if not exists idx_api_chaves_rev on public.api_chaves(revendedor_id);
alter table public.api_chaves enable row level security;
revoke all on public.api_chaves from anon, authenticated;
grant all on public.api_chaves to service_role;

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