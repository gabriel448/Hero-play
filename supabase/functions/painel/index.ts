import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ============================================================================
// Edge Function `painel` — backend do PAINEL DE REVENDA.
// Hierarquia: revendedor (master|reseller) → cliente → dispositivo → playlist.
// Auth: o painel manda o JWT do revendedor (Supabase Auth) no Authorization;
// aqui validamos a identidade e usamos o SERVICE ROLE p/ as operações. URLs de
// playlist são CIFRADAS (AES-256-CBC) antes de gravar — mesma chave da `ativacao`.
// Contas NÃO têm signup público: só um master cria revendedor/master (admin API).
//   POST { acao:'me' }                                   -> { id,nome,usuario,papel,saldo_creditos,codigo_indicacao }
//   POST { acao:'criar_revendedor', usuario,senha,nome }  (login por usuário; e-mail sintético)
//   POST { acao:'registrar_indicacao', ref,usuario,senha,nome }  (público, por link)
//   POST { acao:'listar_revendedores' }                  (só master) -> downline
//   POST { acao:'criar_cliente', nome }                  -> { cliente }
//   POST { acao:'listar_clientes' }                      -> { clientes }
//   POST { acao:'cliente_detalhe', cliente_id }          -> { cliente, dispositivos, playlists, vinculos }
//   POST { acao:'vincular_dispositivo', cliente_id, key, mac? }   (claim + ativa)
//   POST { acao:'add_playlist', cliente_id, nome, lista_url, epg_url?, dispositivo_ids? }
//   POST { acao:'selecionar_playlist', dispositivo_id, playlist_id }
//   POST { acao:'excluir_playlist', cliente_id, playlist_id }
//   SUPORTE: criar_ticket{assunto,mensagem} · listar_tickets{status?} (admin=todos)
//     · ticket_detalhe{ticket_id} · responder_ticket{ticket_id,mensagem} ·
//     fechar_ticket{ticket_id,reabrir?}
// ⚠️ Reuso temporário do projeto atual — migrar p/ projeto próprio (ver checklist).
// ============================================================================

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// ── Criptografia AES-256-CBC (mesma ENCRYPTION_KEY da `ativacao`/`iptv`) ──────
let _chave: CryptoKey | null = null
async function obterChave(): Promise<CryptoKey> {
  if (_chave) return _chave
  const raw = Deno.env.get('ENCRYPTION_KEY') ?? ''
  if (!raw) throw new Error('ENCRYPTION_KEY nao configurada')
  let bytes: Uint8Array
  if (raw.length === 64 && /^[0-9a-fA-F]+$/.test(raw)) {
    bytes = new Uint8Array(32)
    for (let i = 0; i < 32; i++) bytes[i] = parseInt(raw.slice(i * 2, i * 2 + 2), 16)
  } else {
    bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0))
  }
  if (bytes.length !== 32) throw new Error('ENCRYPTION_KEY deve ter 32 bytes')
  _chave = await crypto.subtle.importKey('raw', bytes, { name: 'AES-CBC' }, false, ['encrypt', 'decrypt'])
  return _chave
}
async function cifrar(texto: string): Promise<string> {
  const chave = await obterChave()
  const iv = crypto.getRandomValues(new Uint8Array(16))
  const cif = await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, chave, new TextEncoder().encode(texto))
  const out = new Uint8Array(16 + cif.byteLength)
  out.set(iv); out.set(new Uint8Array(cif), 16)
  return btoa(String.fromCharCode(...out))
}
// Par do `cifrar` — faltava neste arquivo (só existia na `ativacao`). Como as
// chamadas ficam dentro de try/catch, o ReferenceError era ENGOLIDO: a tela de
// Playlists mostrava a URL em branco e a migração de domínio em massa não
// encontrava nada pra trocar, sem erro nenhum na tela.
async function decifrar(dado: string): Promise<string> {
  const chave = await obterChave()
  const b = Uint8Array.from(atob(dado), (c) => c.charCodeAt(0))
  const dec = await crypto.subtle.decrypt({ name: 'AES-CBC', iv: b.slice(0, 16) }, chave, b.slice(16))
  return new TextDecoder().decode(dec)
}

// ── Helpers ──────────────────────────────────────────────────────────────────
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}
const erro = (msg: string, status = 400) => json({ ok: false, erro: msg }, status)
function ehXtream(url: string): boolean {
  try { const u = new URL(url); return u.searchParams.has('username') && u.searchParams.has('password') } catch { return false }
}
function urlValida(url: string): boolean {
  try { return ['http:', 'https:'].includes(new URL(url).protocol) } catch { return false }
}
/**
 * host[:porta] em minusculo, sem `www.` — a chave que casa uma playlist com um
 * parceiro. O `www.` sai dos DOIS lados (aqui e no cadastro do dominio): sem
 * isso uma lista em `www.parceiro.com` nao casaria com `parceiro.com`.
 */
function hostDe(url: string): string | null {
  try { return new URL(url).host.toLowerCase().replace(/^www\./, '') || null } catch { return null }
}
/**
 * Normaliza o que o admin digitar no cadastro de parceiro: aceita URL inteira,
 * "http://host:porta/get.php?...", "www.host" ou so o host. Sai host[:porta].
 */
function normalizarDominio(entrada: string): string {
  let s = String(entrada || '').trim().toLowerCase()
  if (!s) return ''
  if (!/^[a-z][a-z0-9+.-]*:\/\//.test(s)) s = 'http://' + s
  try {
    const h = new URL(s).host
    return h.replace(/^www\./, '')
  } catch { return '' }
}
/**
 * Configuracao do programa de parceiros (linha unica, id=1).
 *
 * Se a tabela ainda nao existir (schema nao rodado), devolve os MESMOS padroes
 * do banco em vez de estourar — a tela abre e mostra os valores default.
 */
async function lerConfigParceiros() {
  const padrao = {
    modelo_mensal: true, modelo_por_device: false,
    preco_mensal: 0, preco_device: 0, dia_cobranca: 5,
    carencia_dias: 3, carencia_extra_max: 7, carencia_extensoes: 2,
    programa_ativo: true, banner_texto: '',
  }
  try {
    const { data } = await sb.from('parceiros_config').select('*').eq('id', 1).maybeSingle()
    return data ? { ...padrao, ...data } : padrao
  } catch { return padrao }
}

/** Parceiro ATIVO deste host (ou null). Ver tabela `parceiros` no schema. */
async function parceiroDoHost(host: string | null) {
  if (!host) return null
  try {
    const { data } = await sb.from('parceiros')
      .select('id, dominio').eq('dominio', host).eq('ativo', true).maybeSingle()
    return data || null
  } catch { return null }
}
// Código de indicação: 8 chars sem caracteres ambíguos (0/O/1/I).
function gerarCodigo(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let s = ''
  for (let i = 0; i < 8; i++) s += chars[Math.floor(Math.random() * chars.length)]
  return s
}
// Código de indicação ÚNICO: gera aleatório e confere na tabela (o índice único
// impede duplicata; aqui evitamos o erro tentando de novo). Colisão em ~1,1 tri
// de combinações é raríssima, mas em produção não pode quebrar um cadastro.
async function gerarCodigoUnico(): Promise<string> {
  for (let i = 0; i < 8; i++) {
    const c = gerarCodigo()
    const { data } = await sb.from('revendedores').select('id').eq('codigo_indicacao', c).maybeSingle()
    if (!data) return c
  }
  // Fallback praticamente impossível de colidir (sufixo temporal).
  return gerarCodigo().slice(0, 5) + Date.now().toString(36).slice(-3).toUpperCase()
}

/**
 * PLANOS de ativacao: quantos MESES cada um vale. `null` = vitalicia (sem data).
 *
 * Meses (e nao dias) porque "1 ano" tem que cair no mesmo dia do ano seguinte —
 * 365 dias erra em ano bissexto. A conta em si e do Postgres (interval), aqui so
 * vive a tabela.
 *
 * `semestre` fica DEFINIDO mas NAO e oferecido no painel ainda (decisao do
 * usuario: por enquanto so ano e vitalicia). Quando for, e so mostrar a opcao.
 */
const PLANOS: Record<string, number | null> = {
  semestre: 6,
  ano: 12,
  vitalicia: null,
}
const planoValido = (p: unknown): string | null => {
  const s = String(p || '').trim().toLowerCase()
  return Object.prototype.hasOwnProperty.call(PLANOS, s) ? s : null
}

/**
 * Status REAL do device: a coluna `status` continua 'ativo' depois do
 * vencimento (ninguem passa varrendo o banco), entao quem manda e a DATA.
 * Mesma regra da Edge Function `ativacao` — as duas TEM que concordar, senao o
 * painel diz "ativo" e a TV nao abre.
 */
// deno-lint-ignore no-explicit-any
function statusEfetivo(d: any): string {
  const agora = Date.now()
  if (d.status === 'banido') return 'banido'
  if (d.status === 'ativo') return (d.expira_em && new Date(d.expira_em).getTime() < agora) ? 'expirado' : 'ativo'
  if (d.status === 'trial') return (d.trial_expira_em && new Date(d.trial_expira_em).getTime() < agora) ? 'expirado' : 'trial'
  return d.status || 'sem_lista'
}

/**
 * Codigo do SERVIDOR: 4 digitos, como no painel de referencia — o cliente digita
 * isso no controle da TV, entao numero curto ganha de string aleatoria bonita.
 * Confere colisao antes (o indice unico garante de verdade).
 */
async function gerarCodigoServidorUnico(): Promise<string> {
  for (let i = 0; i < 12; i++) {
    const c = String(1000 + Math.floor(Math.random() * 9000))
    const { data } = await sb.from('servidores').select('id').ilike('codigo', c).maybeSingle()
    if (!data) return c
  }
  return String(Date.now()).slice(-6)     // fallback: praticamente sem colisao
}

// ── Login por USUÁRIO (sem e-mail) ───────────────────────────────────────────
// O Supabase Auth exige e-mail; usamos um SINTÉTICO derivado do usuário. Nunca é
// enviado (contas nascem confirmadas). O mesmo derivador roda no frontend.
const USUARIO_DOMINIO = 'u.heroplaytv.com'
const normUsuario = (u: string) => String(u || '').trim().toLowerCase()
const usuarioValido = (u: string) => /^[a-z0-9._-]{3,30}$/.test(u)
const emailDeUsuario = (u: string) => normUsuario(u) + '@' + USUARIO_DOMINIO

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!
const sb = createClient(SB_URL, SERVICE) // service role (ignora RLS)

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return erro('use POST', 405)

  try {
    const body = await req.json().catch(() => ({}))
    const acao = body.acao

    // ── Caixa de entrada: grava um aviso p/ um ou varios revendedores ────────
    // Best-effort de proposito: falhar em notificar NUNCA pode derrubar a acao
    // que a originou (transferir credito, responder ticket...).
    async function notificar(
      destinos: string[],
      tipo: string,
      titulo: string,
      corpo?: string,
      ref?: string,
    ) {
      const alvos = [...new Set(destinos.filter(Boolean))]
      if (!alvos.length) return
      try {
        await sb.from('notificacoes').insert(
          alvos.map((id) => ({ revendedor_id: id, tipo, titulo, corpo: corpo || null, ref: ref || null })),
        )
      } catch (_) { /* nao quebra a acao principal */ }
    }

    // ── PÚBLICO (sem login): cadastro de revendedor por LINK DE INDICAÇÃO ──────
    const idsAdmins = async (): Promise<string[]> => {
      const { data } = await sb.from('revendedores').select('id').eq('papel', 'admin')
      // deno-lint-ignore no-explicit-any
      return (data || []).map((r: any) => r.id)
    }

    if (acao === 'registrar_indicacao') {
      const ref = (body.ref || '').trim()
      const usuario = normUsuario(body.usuario)
      const senha = String(body.senha || '')
      const nome = (body.nome || '').trim()
      if (!ref) return erro('link de indicação inválido')
      if (!usuarioValido(usuario)) return erro('usuário inválido (3-30 letras/números . _ -)')
      if (senha.length < 6) return erro('senha de no mínimo 6 caracteres')
      const { data: dono } = await sb.from('revendedores').select('id').eq('codigo_indicacao', ref).eq('ativo', true).maybeSingle()
      if (!dono) return erro('código de indicação inválido', 404)
      // usuário único (pré-checagem amigável; o Auth ainda barra o e-mail duplicado)
      const { data: ja } = await sb.from('revendedores').select('id').ilike('usuario', usuario).maybeSingle()
      if (ja) return erro('esse usuário já existe', 409)
      const { data: novo, error: e1 } = await sb.auth.admin.createUser({ email: emailDeUsuario(usuario), password: senha, email_confirm: true })
      if (e1 || !novo?.user) return erro((e1?.message || '').includes('registered') ? 'esse usuário já existe' : (e1?.message || 'falha ao criar conta'))
      const { error: e2 } = await sb.from('revendedores').insert({
        id: novo.user.id, nome, usuario, papel: 'reseller', criado_por: dono.id, codigo_indicacao: await gerarCodigoUnico(),
      })
      if (e2) { await sb.auth.admin.deleteUser(novo.user.id).catch(() => {}); return erro(e2.message) }
      await notificar([dono.id], 'rede', 'Novo revendedor na sua rede',
        `${nome || usuario} se cadastrou pelo seu link.`)
      return json({ ok: true })
    }

    // ── Daqui pra baixo EXIGE login (JWT do operador) ─────────────────────────
    const authHeader = req.headers.get('Authorization') || ''
    const sbUser = createClient(SB_URL, ANON, { global: { headers: { Authorization: authHeader } } })
    const { data: { user } } = await sbUser.auth.getUser()
    if (!user) return erro('nao autenticado', 401)

    const { data: rev } = await sb.from('revendedores').select('*').eq('id', user.id).maybeSingle()
    if (!rev || !rev.ativo) return erro('conta invalida ou inativa', 403)

    // Declarado AQUI, junto do `rev`: várias ações abaixo dependem dele (rede do
    // admin, tickets, avisos). Estava lá embaixo, no bloco de suporte, e como
    // `const` não é içado, `listar_revendedores` estourava
    // "Cannot access 'ehAdmin' before initialization" — e o Dashboard, que chama
    // essa ação, não carregava nenhum número.
    const ehAdmin = rev.papel === 'admin'

    // valida que o cliente pertence a este revendedor
    async function clienteDoRev(cliente_id: string): Promise<boolean> {
      if (!cliente_id) return false
      const { data } = await sb.from('clientes').select('id').eq('id', cliente_id).eq('revendedor_id', rev.id).maybeSingle()
      return !!data
    }

    if (acao === 'me') {
      // garante o código de indicação (gera na 1ª vez p/ contas antigas)
      let codigo = rev.codigo_indicacao
      if (!codigo) { codigo = await gerarCodigoUnico(); await sb.from('revendedores').update({ codigo_indicacao: codigo }).eq('id', rev.id) }
      // ADMIN nao tem saldo: ele e a FONTE do credito, nao um estoque. Manda
      // `null` p/ o painel nao exibir numero nenhum pra ele.
      return json({
        id: rev.id, nome: rev.nome, usuario: rev.usuario, papel: rev.papel,
        saldo_creditos: ehAdmin ? null : (rev.saldo_creditos ?? 0),
        codigo_indicacao: codigo,
      })
    }

    // Qualquer operador cria um REVENDEDOR (papel 'reseller'), sem limite de
    // profundidade. "Master" é um TIER dado pelo admin (ação `promover`) — não se
    // cria direto. (`admin` só existe via bootstrap/promote manual no banco.)
    if (acao === 'criar_revendedor') {
      const usuario = normUsuario(body.usuario)
      const senha = String(body.senha || '')
      const nome = (body.nome || '').trim()
      if (!usuarioValido(usuario)) return erro('usuário inválido (3-30 letras/números . _ -)')
      if (senha.length < 6) return erro('senha de no mínimo 6 caracteres')
      const { data: ja } = await sb.from('revendedores').select('id').ilike('usuario', usuario).maybeSingle()
      if (ja) return erro('esse usuário já existe', 409)

      const { data: novo, error: e1 } = await sb.auth.admin.createUser({ email: emailDeUsuario(usuario), password: senha, email_confirm: true })
      if (e1 || !novo?.user) return erro((e1?.message || '').includes('registered') ? 'esse usuário já existe' : (e1?.message || 'falha ao criar usuario'))
      const { error: e2 } = await sb.from('revendedores').insert({
        id: novo.user.id, nome, usuario, papel: 'reseller', criado_por: rev.id, codigo_indicacao: await gerarCodigoUnico(),
      })
      if (e2) { await sb.auth.admin.deleteUser(novo.user.id).catch(() => {}); return erro(e2.message) }
      return json({ ok: true, id: novo.user.id })
    }

    // Downline DIRETO (contas que EU criei). Todos têm downline (revendedor cria revendedor).
    if (acao === 'listar_revendedores') {
      // Revendedor ve a rede DIRETA dele; ADMIN ve a plataforma inteira, com o
      // codigo de indicacao de quem trouxe cada um (foi o pedido: saber de quem
      // veio cada revenda).
      let q = sb.from('revendedores')
        .select('id, nome, usuario, papel, ativo, saldo_creditos, criado_em, criado_por')
        .order('criado_em', { ascending: false })
      if (ehAdmin) q = q.neq('papel', 'admin'); else q = q.eq('criado_por', rev.id)
      const { data } = await q
      const lista = data || []
      if (!ehAdmin) return json({ revendedores: lista, admin: false })

      // Resolve o "indicado por" (nome + codigo) num unico select.
      // deno-lint-ignore no-explicit-any
      const paisIds = [...new Set(lista.map((r: any) => r.criado_por).filter(Boolean))]
      // deno-lint-ignore no-explicit-any
      const pai = new Map<string, any>()
      if (paisIds.length) {
        const { data: ps } = await sb.from('revendedores')
          .select('id, nome, usuario, codigo_indicacao').in('id', paisIds)
        // deno-lint-ignore no-explicit-any
        ;(ps || []).forEach((p: any) => pai.set(p.id, p))
      }
      // deno-lint-ignore no-explicit-any
      const revendedores = lista.map((r: any) => {
        const p = pai.get(r.criado_por)
        return {
          ...r,
          indicado_por: p ? (p.nome || p.usuario) : null,
          indicado_por_codigo: p ? (p.codigo_indicacao || null) : null,
        }
      })
      return json({ revendedores, admin: true })
    }

    // ── PARCEIROS (só admin) ──────────────────────────────────────────────────
    // Domínio parceiro = servidor com acordo: device que recebe uma playlist
    // apontando pra ele já entra ATIVO, sem teste e sem consumir crédito.
    if (acao === 'listar_parceiros') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const { data: lista } = await sb.from('parceiros').select('*').order('criado_em', { ascending: false })
      const parceiros = lista || []
      // Devices por domínio: playlists guardam o `host` em texto claro, então dá
      // pra contar sem decifrar nada. Conta o vínculo SELECIONADO — é a lista
      // que o aparelho está usando de fato.
      const contagem: Record<string, number> = {}
      if (parceiros.length) {
        // deno-lint-ignore no-explicit-any
        const hosts = parceiros.map((p: any) => p.dominio)
        const { data: pls } = await sb.from('playlists').select('id, host').in('host', hosts)
        // deno-lint-ignore no-explicit-any
        const porId = new Map((pls || []).map((p: any) => [p.id, p.host]))
        if (porId.size) {
          const { data: vins } = await sb.from('dispositivo_playlists')
            .select('playlist_id, dispositivo_id').eq('selecionada', true).in('playlist_id', [...porId.keys()])
          const vistos = new Set<string>()
          for (const v of (vins || [])) {
            // deno-lint-ignore no-explicit-any
            const vv = v as any
            if (vistos.has(vv.dispositivo_id)) continue      // 1 device conta 1x
            vistos.add(vv.dispositivo_id)
            const h = porId.get(vv.playlist_id)
            if (h) contagem[h] = (contagem[h] || 0) + 1
          }
        }
      }
      // deno-lint-ignore no-explicit-any
      return json({ parceiros: parceiros.map((p: any) => ({ ...p, devices: contagem[p.dominio] || 0 })) })
    }

    if (acao === 'criar_parceiro') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const dominio = normalizarDominio(body.dominio)
      if (!dominio) return erro('informe um domínio válido (ex.: meuservidor.com ou 1.2.3.4:25461)')
      const cobranca = ['gratuito', 'mensal', 'por_device'].includes(body.cobranca) ? body.cobranca : 'gratuito'
      const valor = cobranca === 'gratuito' ? null : (Number(body.valor) || 0)
      const { data: ja } = await sb.from('parceiros').select('id').eq('dominio', dominio).maybeSingle()
      if (ja) return erro('esse domínio já está cadastrado', 409)
      const { data, error } = await sb.from('parceiros')
        .insert({ dominio, nome: (body.nome || '').trim() || null, cobranca, valor })
        .select('id').single()
      if (error) return erro(error.message)
      // Playlists que JÁ apontam pra esse domínio passam a valer como parceiras,
      // e os aparelhos delas são ativados — senão o acordo só valeria daqui pra
      // frente e o admin teria que mexer device a device.
      const { data: pls } = await sb.from('playlists').select('id').eq('host', dominio)
      // deno-lint-ignore no-explicit-any
      const ids = (pls || []).map((p: any) => p.id)
      let ativados = 0
      if (ids.length) {
        await sb.from('playlists').update({ free_dns: true }).in('id', ids)
        const { data: vins } = await sb.from('dispositivo_playlists')
          .select('dispositivo_id').eq('selecionada', true).in('playlist_id', ids)
        // deno-lint-ignore no-explicit-any
        const devs = [...new Set((vins || []).map((v: any) => v.dispositivo_id))]
        if (devs.length) {
          await sb.from('dispositivos')
            .update({ status: 'ativo', ativado_por: 'parceiro', atualizado_em: new Date().toISOString() })
            .in('id', devs).neq('status', 'banido')
          ativados = devs.length
        }
      }
      return json({ ok: true, id: data.id, dominio, ativados })
    }

    if (acao === 'parceiro_ativo') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      const ativo = !!body.ativo
      if (!id) return erro('id obrigatorio')
      // Suspender NÃO desativa quem já está ativo: só para de valer p/ listas
      // novas. Tirar o acesso de quem já usa é outra decisão, e manual.
      const { error } = await sb.from('parceiros').update({ ativo }).eq('id', id)
      if (error) return erro(error.message)
      return json({ ok: true })
    }

    // ── FATURAS dos parceiros ────────────────────────────────────────────────
    if (acao === 'listar_faturas') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const { data } = await sb.from('parceiro_faturas').select('*')
        .order('periodo_ini', { ascending: false }).limit(300)
      const faturas = data || []
      // deno-lint-ignore no-explicit-any
      const ids = [...new Set(faturas.map((f: any) => f.parceiro_id))]
      const nomes = new Map<string, string>()
      if (ids.length) {
        const { data: ps } = await sb.from('parceiros').select('id, dominio, nome').in('id', ids)
        // deno-lint-ignore no-explicit-any
        for (const p of (ps || []) as any[]) nomes.set(p.id, p.dominio)
      }
      // deno-lint-ignore no-explicit-any
      return json({ faturas: faturas.map((f: any) => ({ ...f, dominio: nomes.get(f.parceiro_id) || '—' })) })
    }

    /**
     * "Executar cobrança": fecha o período corrente de cada parceiro pagante.
     *
     * IDEMPOTENTE de propósito — o índice único (parceiro_id, periodo_ini) faz
     * rodar duas vezes no mesmo mês não gerar nada novo. O admin pode apertar o
     * botão sem medo, que é o comportamento que se espera de um botão desses.
     * Parceiro `gratuito` não gera fatura.
     */
    if (acao === 'gerar_faturas') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const cfg = await lerConfigParceiros()
      const { data: ps } = await sb.from('parceiros').select('*').eq('ativo', true).neq('cobranca', 'gratuito')
      const parceiros = ps || []
      if (!parceiros.length) return json({ ok: true, criadas: 0 })

      // Período: do dia de fechamento do mês passado até o deste mês.
      const hoje = new Date()
      const dia = Math.min(Math.max(cfg.dia_cobranca || 1, 1), 28)
      const fim = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth(), dia))
      if (fim > hoje) fim.setUTCMonth(fim.getUTCMonth() - 1)
      const ini = new Date(fim); ini.setUTCMonth(ini.getUTCMonth() - 1)
      const venc = new Date(fim)
      const iso = (d: Date) => d.toISOString().slice(0, 10)

      // Devices por domínio (mesma contagem da aba Parceiros).
      // deno-lint-ignore no-explicit-any
      const hosts = parceiros.map((p: any) => p.dominio)
      const contagem: Record<string, number> = {}
      const { data: pls } = await sb.from('playlists').select('id, host').in('host', hosts)
      // deno-lint-ignore no-explicit-any
      const porId = new Map((pls || []).map((p: any) => [p.id, p.host]))
      if (porId.size) {
        const { data: vins } = await sb.from('dispositivo_playlists')
          .select('playlist_id, dispositivo_id').eq('selecionada', true).in('playlist_id', [...porId.keys()])
        const vistos = new Set<string>()
        for (const v of (vins || [])) {
          // deno-lint-ignore no-explicit-any
          const vv = v as any
          if (vistos.has(vv.dispositivo_id)) continue
          vistos.add(vv.dispositivo_id)
          const h = porId.get(vv.playlist_id)
          if (h) contagem[h] = (contagem[h] || 0) + 1
        }
      }

      let criadas = 0
      for (const p of parceiros) {
        // deno-lint-ignore no-explicit-any
        const pp = p as any
        const devices = contagem[pp.dominio] || 0
        // Valor do PARCEIRO quando houver; senão o padrão da configuração.
        const unit = Number(pp.valor) || (pp.cobranca === 'mensal' ? cfg.preco_mensal : cfg.preco_device) || 0
        const valor = pp.cobranca === 'mensal' ? unit : unit * devices
        const { error } = await sb.from('parceiro_faturas').insert({
          parceiro_id: pp.id,
          tipo: pp.cobranca === 'mensal' ? 'mensal' : 'por_device',
          periodo_ini: iso(ini), periodo_fim: iso(fim),
          devices, valor,
          vencimento: iso(venc),
        })
        if (!error) criadas++      // erro aqui = já existia a fatura do período
      }
      return json({ ok: true, criadas, periodo: [iso(ini), iso(fim)] })
    }

    if (acao === 'fatura_acao') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      const oque = body.oque
      if (!id) return erro('id obrigatorio')
      const { data: f } = await sb.from('parceiro_faturas').select('*').eq('id', id).maybeSingle()
      if (!f) return erro('fatura nao encontrada', 404)

      if (oque === 'pago') {
        await sb.from('parceiro_faturas')
          .update({ status: 'pago', pago_em: new Date().toISOString() }).eq('id', id)
        return json({ ok: true })
      }
      if (oque === 'cancelar') {
        await sb.from('parceiro_faturas').update({ status: 'cancelado' }).eq('id', id)
        return json({ ok: true })
      }
      if (oque === 'carencia') {
        const cfg = await lerConfigParceiros()
        if (f.extensoes >= cfg.carencia_extensoes) {
          return erro(`limite de ${cfg.carencia_extensoes} extensão(ões) atingido para esta fatura`)
        }
        const dias = Math.min(Number(body.dias) || cfg.carencia_dias, cfg.carencia_extra_max)
        const base = f.carencia_ate ? new Date(f.carencia_ate) : new Date(f.vencimento)
        base.setUTCDate(base.getUTCDate() + dias)
        await sb.from('parceiro_faturas')
          .update({ carencia_ate: base.toISOString().slice(0, 10), extensoes: f.extensoes + 1 }).eq('id', id)
        return json({ ok: true, carencia_ate: base.toISOString().slice(0, 10), dias })
      }
      return erro('acao de fatura desconhecida')
    }

    // ── Configuração do programa de parceiros ────────────────────────────────
    if (acao === 'parceiros_config') {
      if (!ehAdmin) return erro('apenas admin', 403)
      return json({ config: await lerConfigParceiros() })
    }

    if (acao === 'salvar_parceiros_config') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const c = body.config || {}
      const num = (v: unknown, pad = 0) => { const n = Number(v); return Number.isFinite(n) ? n : pad }
      const { error } = await sb.from('parceiros_config').update({
        modelo_mensal: !!c.modelo_mensal,
        modelo_por_device: !!c.modelo_por_device,
        preco_mensal: num(c.preco_mensal),
        preco_device: num(c.preco_device),
        // Limites do próprio banco (dia 1-28 para existir em todo mês).
        dia_cobranca: Math.min(Math.max(num(c.dia_cobranca, 1), 1), 28),
        carencia_dias: Math.min(Math.max(num(c.carencia_dias), 0), 30),
        carencia_extra_max: Math.min(Math.max(num(c.carencia_extra_max), 0), 30),
        carencia_extensoes: Math.min(Math.max(num(c.carencia_extensoes, 1), 1), 10),
        programa_ativo: !!c.programa_ativo,
        banner_texto: (c.banner_texto || '').trim() || null,
        atualizado_em: new Date().toISOString(),
      }).eq('id', 1)
      if (error) return erro(error.message)
      return json({ ok: true })
    }

    if (acao === 'excluir_parceiro') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      if (!id) return erro('id obrigatorio')
      const { error } = await sb.from('parceiros').delete().eq('id', id)
      if (error) return erro(error.message)
      return json({ ok: true })
    }

    // ── SERVIDORES (só admin) — atalho de login Xtream por código ────────────
    if (acao === 'listar_servidores') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const { data } = await sb.from('servidores').select('*').order('host', { ascending: true })
      const servidores = data || []
      // Devices por servidor: mesma contagem dos parceiros (host em texto claro
      // na playlist + vínculo selecionado), então não precisa decifrar nada.
      const contagem: Record<string, number> = {}
      if (servidores.length) {
        // deno-lint-ignore no-explicit-any
        const hosts = [...new Set(servidores.map((s: any) => hostDe(s.host)).filter(Boolean))] as string[]
        const { data: pls } = await sb.from('playlists').select('id, host').in('host', hosts)
        // deno-lint-ignore no-explicit-any
        const porId = new Map<string, string>((pls || []).map((p: any) => [p.id, p.host]))
        if (porId.size) {
          const { data: vins } = await sb.from('dispositivo_playlists')
            .select('playlist_id, dispositivo_id').eq('selecionada', true).in('playlist_id', [...porId.keys()])
          const vistos = new Set<string>()
          for (const v of (vins || [])) {
            // deno-lint-ignore no-explicit-any
            const vv = v as any
            if (vistos.has(vv.dispositivo_id)) continue
            vistos.add(vv.dispositivo_id)
            const h = porId.get(vv.playlist_id)
            if (h) contagem[h] = (contagem[h] || 0) + 1
          }
        }
      }
      // deno-lint-ignore no-explicit-any
      return json({ servidores: servidores.map((s: any) => ({ ...s, devices: contagem[hostDe(s.host) || ''] || 0 })) })
    }

    if (acao === 'salvar_servidor') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      let host = (body.host || '').trim().replace(/\/+$/, '')
      if (!host) return erro('informe o host do servidor')
      if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(host)) host = 'http://' + host
      if (!urlValida(host)) return erro('host inválido (use http/https)')
      // Código LIVRE (números ou letras, até 64) — é o que o cliente digita no
      // app. Vazio = gera um de 4 dígitos, como o painel de referência.
      let codigo = String(body.codigo || '').trim().toUpperCase().replace(/\s+/g, '')
      if (codigo && !/^[A-Z0-9._-]{2,64}$/.test(codigo)) return erro('código inválido (2-64 letras/números . _ -)')
      if (!codigo) codigo = await gerarCodigoServidorUnico()
      const nome = (body.nome || '').trim() || null

      // Código único (o índice do banco garante; aqui é só a mensagem amigável).
      const { data: ja } = await sb.from('servidores').select('id').ilike('codigo', codigo).maybeSingle()
      // deno-lint-ignore no-explicit-any
      if (ja && (ja as any).id !== id) return erro('esse código já está em uso', 409)

      if (id) {
        const { error } = await sb.from('servidores').update({ host, codigo, nome }).eq('id', id)
        if (error) return erro(error.message)
        return json({ ok: true, id, codigo })
      }
      const { data, error } = await sb.from('servidores')
        .insert({ host, codigo, nome }).select('id').single()
      if (error) return erro(error.message)
      return json({ ok: true, id: data.id, codigo })
    }

    // Gera um código novo para um servidor que já existe (o antigo para de valer).
    if (acao === 'servidor_codigo') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      if (!id) return erro('id obrigatorio')
      const codigo = await gerarCodigoServidorUnico()
      const { error } = await sb.from('servidores').update({ codigo }).eq('id', id)
      if (error) return erro(error.message)
      return json({ ok: true, codigo })
    }

    if (acao === 'servidor_ativo') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      if (!id) return erro('id obrigatorio')
      const { error } = await sb.from('servidores').update({ ativo: !!body.ativo }).eq('id', id)
      if (error) return erro(error.message)
      return json({ ok: true })
    }

    if (acao === 'excluir_servidor') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const id = (body.id || '').trim()
      if (!id) return erro('id obrigatorio')
      const { error } = await sb.from('servidores').delete().eq('id', id)
      if (error) return erro(error.message)
      return json({ ok: true })
    }

    // ── Caixa de entrada ──────────────────────────────────────────────────────
    if (acao === 'listar_notificacoes') {
      const { data } = await sb.from('notificacoes')
        .select('id, tipo, titulo, corpo, ref, lida, criado_em')
        .eq('revendedor_id', rev.id)
        .order('criado_em', { ascending: false }).limit(200)
      const nao_lidas = (data || []).filter((n) => !n.lida).length
      return json({ notificacoes: data || [], nao_lidas })
    }

    // Marca uma (`id`) ou TODAS como lidas.
    if (acao === 'ler_notificacoes') {
      const id = (body.id || '').trim()
      let q = sb.from('notificacoes').update({ lida: true }).eq('revendedor_id', rev.id)
      if (id) q = q.eq('id', id); else q = q.eq('lida', false)
      await q
      return json({ ok: true })
    }

    // Admin manda um aviso para TODOS os revendedores (ou para um so).
    if (acao === 'enviar_aviso') {
      if (!ehAdmin) return erro('apenas admin', 403)
      const titulo = (body.titulo || '').trim()
      const corpo = (body.corpo || '').trim()
      const alvo = (body.revendedor_id || '').trim()
      if (!titulo) return erro('informe o titulo do aviso')
      let destinos: string[] = []
      if (alvo) {
        destinos = [alvo]
      } else {
        const { data } = await sb.from('revendedores').select('id').neq('id', rev.id).eq('ativo', true)
        // deno-lint-ignore no-explicit-any
        destinos = (data || []).map((r: any) => r.id)
      }
      await notificar(destinos, 'aviso', titulo, corpo, undefined)
      return json({ ok: true, enviados: destinos.length })
    }

    // Admin promove/rebaixa o TIER de um revendedor (reseller ↔ master).
    if (acao === 'promover') {
      if (rev.papel !== 'admin') return erro('apenas admin promove a master', 403)
      const id = (body.revendedor_id || '').trim()
      const tier = body.tier === 'master' ? 'master' : 'reseller'
      const { data: alvo } = await sb.from('revendedores').select('papel').eq('id', id).maybeSingle()
      if (!alvo || alvo.papel === 'admin') return erro('revendedor invalido', 404)
      await sb.from('revendedores').update({ papel: tier }).eq('id', id)
      return json({ ok: true, tier })
    }

    // ── Créditos: transferir p/ um downline (debita quem dá, credita quem recebe) ─
    if (acao === 'transferir_creditos') {
      const alvo_id = (body.revendedor_id || '').trim()
      const qtd = Math.floor(Number(body.quantidade) || 0)
      if (!alvo_id || qtd <= 0) return erro('informe destinatario e quantidade > 0')
      const { data: alvo } = await sb.from('revendedores').select('id, nome, usuario').eq('id', alvo_id).maybeSingle()
      if (!alvo) return erro('destinatario nao encontrado', 404)
      // A transferência (débito+crédito+extrato) é ATÔMICA via RPC — evita o
      // double-spend do read-modify-write anterior. A checagem de downline
      // continua aqui (regra de negócio), mas o dinheiro só se move na função.
      const { data: novoSaldo, error: eT } = await sb.rpc('rpc_transferir_creditos', {
        p_de: rev.id, p_para: alvo_id, p_qtd: qtd, p_por: rev.id,
        p_nota_saida: 'Para ' + (alvo.nome || alvo.usuario || alvo_id),
        p_nota_entrada: 'De ' + (rev.nome || rev.usuario || rev.id),
      })
      if (eT) {
        if ((eT.message || '').includes('SALDO_INSUFICIENTE')) return erro('saldo insuficiente')
        return erro('falha na transferencia')
      }
      await notificar([alvo_id], 'credito', `Voce recebeu ${qtd} credito(s)`,
        `De ${rev.nome || rev.usuario}.`)
      return json({ ok: true, saldo: novoSaldo })
    }

    // Extrato do próprio saldo.
    if (acao === 'listar_creditos') {
      const { data } = await sb.from('creditos_transacoes')
        .select('id, tipo, quantidade, saldo_apos, nota, criado_em')
        .eq('revendedor_id', rev.id).order('criado_em', { ascending: false }).limit(200)
      return json({ saldo: ehAdmin ? null : (rev.saldo_creditos ?? 0), transacoes: data || [] })
    }

    // ── Clientes ──────────────────────────────────────────────────────────────
    if (acao === 'criar_cliente') {
      const nome = (body.nome || '').trim() || 'Cliente'
      const { data, error } = await sb.from('clientes').insert({ nome, revendedor_id: rev.id }).select('id, nome').single()
      if (error) return erro(error.message)
      return json({ ok: true, cliente: data })
    }

    if (acao === 'listar_clientes') {
      const { data } = await sb.from('clientes').select('id, nome, criado_em')
        .eq('revendedor_id', rev.id).order('criado_em', { ascending: false })
      return json({ clientes: data || [] })
    }

    if (acao === 'cliente_detalhe') {
      const cliente_id = (body.cliente_id || '').trim()
      if (!(await clienteDoRev(cliente_id))) return erro('cliente nao encontrado', 404)
      const { data: cliente } = await sb.from('clientes').select('id, nome').eq('id', cliente_id).maybeSingle()
      const { data: disp0 } = await sb.from('dispositivos')
        .select('id, mac, device_key, modelo, status, plano, trial_expira_em, expira_em, ativado_por, criado_em, atualizado_em')
        .eq('cliente_id', cliente_id).order('criado_em', { ascending: true })
      // deno-lint-ignore no-explicit-any
      const dispositivos = (disp0 || []).map((d: any) => ({ ...d, status: statusEfetivo(d) }))
      const { data: playlists } = await sb.from('playlists')
        .select('id, nome, tipo, criado_em').eq('cliente_id', cliente_id).order('criado_em', { ascending: true })
      // deno-lint-ignore no-explicit-any
      const dispIds = (dispositivos || []).map((d: any) => d.id)
      let vinculos: Record<string, unknown>[] = []
      if (dispIds.length) {
        const { data } = await sb.from('dispositivo_playlists').select('dispositivo_id, playlist_id, selecionada').in('dispositivo_id', dispIds)
        vinculos = data || []
      }
      return json({ cliente, dispositivos: dispositivos || [], playlists: playlists || [], vinculos })
    }

    // ── Vincular (claim) + ativar dispositivo por MAC + Key ───────────────────
    if (acao === 'vincular_dispositivo') {
      const cliente_id = (body.cliente_id || '').trim()
      const key = (body.key || '').trim()
      const mac = (body.mac || '').trim()
      const plano = planoValido(body.plano)
      if (!plano) return erro('escolha o plano da ativação')
      if (!(await clienteDoRev(cliente_id))) return erro('cliente nao encontrado', 404)
      if (!mac || !key) return erro('mac e key obrigatorios')
      // MAC é único → casa pelo MAC e CONFIRMA a Key.
      const { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (!d || d.device_key !== key) return erro('dispositivo nao encontrado (confira MAC e Key)', 404)

      // Consumo de 1 crédito + ativação são ATÔMICOS (RPC). Antes eram 3 statements
      // separados: duas ativações simultâneas gastavam 1 crédito por 2 devices.
      // Re-vincular um device VIGENTE não cobra de novo (a RPC decide isso).
      const { data: res, error: eA } = await sb.rpc('rpc_ativar_dispositivo', {
        p_dispositivo_id: d.id, p_cliente_id: cliente_id, p_rev: rev.id, p_mac: mac,
        p_plano: plano, p_meses: PLANOS[plano], p_renovar: false,
      })
      if (eA) {
        if ((eA.message || '').includes('SALDO_INSUFICIENTE')) {
          return erro('Saldo insuficiente: a ativação de um dispositivo consome 1 crédito.')
        }
        return erro('falha ao ativar o dispositivo')
      }
      return json({
        ok: true, dispositivo: { id: d.id, mac: d.mac },
        saldo: res?.saldo, cobrado: !!res?.cobrado, expira_em: res?.expira_em ?? null, plano,
      })
    }

    /**
     * RENOVAR a assinatura de um device que já é do revendedor.
     *
     * Sempre cobra 1 crédito — é uma venda nova. Renovar ANTES de vencer soma ao
     * que resta (o cliente não perde o que já pagou); vencido, conta de hoje.
     */
    if (acao === 'renovar_dispositivo') {
      const dispositivo_id = (body.dispositivo_id || '').trim()
      const plano = planoValido(body.plano)
      if (!plano) return erro('escolha o plano da renovação')
      const { data: d } = await sb.from('dispositivos').select('id, mac, cliente_id').eq('id', dispositivo_id).maybeSingle()
      if (!d || !(await clienteDoRev(d.cliente_id))) return erro('dispositivo nao encontrado', 404)
      const { data: res, error: eR } = await sb.rpc('rpc_ativar_dispositivo', {
        p_dispositivo_id: d.id, p_cliente_id: null, p_rev: rev.id, p_mac: d.mac,
        p_plano: plano, p_meses: PLANOS[plano], p_renovar: true,
      })
      if (eR) {
        if ((eR.message || '').includes('SALDO_INSUFICIENTE')) {
          return erro('Saldo insuficiente: renovar um dispositivo consome 1 crédito.')
        }
        return erro('falha ao renovar o dispositivo')
      }
      return json({ ok: true, saldo: res?.saldo, expira_em: res?.expira_em ?? null, plano })
    }

    // ── Playlists do cliente (cifra) + vínculo aos dispositivos ───────────────
    if (acao === 'add_playlist') {
      const cliente_id = (body.cliente_id || '').trim()
      const lista_url = (body.lista_url || '').trim()
      const epg_url = (body.epg_url || '').trim()
      const nome = (body.nome || '').trim() || 'Playlist'
      const dispositivo_ids: string[] = Array.isArray(body.dispositivo_ids) ? body.dispositivo_ids : []
      if (!(await clienteDoRev(cliente_id))) return erro('cliente nao encontrado', 404)
      if (!urlValida(lista_url)) return erro('lista_url invalida (use http/https)')

      const url_cifrada = await cifrar(lista_url)
      const epg_cifrada = epg_url ? await cifrar(epg_url) : null
      const tipo = ehXtream(lista_url) ? 'xtream' : 'm3u'
      // Host em texto claro + parceiro: mesma regra da `ativacao` — playlist de
      // domínio parceiro ativa o device na hora, sem teste e sem crédito.
      const host = hostDe(lista_url)
      const parceiro = await parceiroDoHost(host)
      const { data: pl, error } = await sb.from('playlists')
        .insert({ cliente_id, nome, tipo, url_cifrada, epg_cifrada, host, free_dns: !!parceiro })
        .select('id').single()
      if (error) return erro(error.message)

      // alvos: os dispositivos informados, OU todos do cliente
      let alvos = dispositivo_ids
      if (!alvos.length) {
        const { data } = await sb.from('dispositivos').select('id').eq('cliente_id', cliente_id)
        // deno-lint-ignore no-explicit-any
        alvos = (data || []).map((x: any) => x.id)
      }
      for (const did of alvos) {
        // se o device ainda não tem nenhuma selecionada, esta vira a ativa
        const { count } = await sb.from('dispositivo_playlists').select('*', { count: 'exact', head: true }).eq('dispositivo_id', did).eq('selecionada', true)
        await sb.from('dispositivo_playlists').insert({ dispositivo_id: did, playlist_id: pl.id, selecionada: !count })
      }
      if (parceiro && alvos.length) {
        await sb.from('dispositivos')
          .update({ status: 'ativo', ativado_por: 'parceiro', atualizado_em: new Date().toISOString() })
          .in('id', alvos).neq('status', 'banido')
      }
      return json({ ok: true, playlist_id: pl.id, vinculados: alvos.length, parceiro: !!parceiro })
    }

    if (acao === 'selecionar_playlist') {
      const dispositivo_id = (body.dispositivo_id || '').trim()
      const playlist_id = (body.playlist_id || '').trim()
      const { data: d } = await sb.from('dispositivos').select('cliente_id').eq('id', dispositivo_id).maybeSingle()
      if (!d || !(await clienteDoRev(d.cliente_id))) return erro('dispositivo nao encontrado', 404)
      // Playlist tem que ser do MESMO cliente do device.
      const { data: pl } = await sb.from('playlists').select('id').eq('id', playlist_id).eq('cliente_id', d.cliente_id).maybeSingle()
      if (!pl) return erro('playlist nao encontrada', 404)
      // Desmarca todas do device e GARANTE o vínculo (cria se não existir — antes o
      // UPDATE falhava p/ device adicionado DEPOIS da playlist: sem linha p/ atualizar).
      await sb.from('dispositivo_playlists').update({ selecionada: false }).eq('dispositivo_id', dispositivo_id)
      const { data: ex } = await sb.from('dispositivo_playlists').select('dispositivo_id')
        .eq('dispositivo_id', dispositivo_id).eq('playlist_id', playlist_id).maybeSingle()
      if (ex) {
        await sb.from('dispositivo_playlists').update({ selecionada: true }).eq('dispositivo_id', dispositivo_id).eq('playlist_id', playlist_id)
      } else {
        await sb.from('dispositivo_playlists').insert({ dispositivo_id, playlist_id, selecionada: true })
      }
      return json({ ok: true })
    }

    // ── Remover (desvincular) um dispositivo do cliente ───────────────────────
    // NÃO devolve o crédito (a ativação é irreversível). O device volta a "sem_lista"
    // e some do cliente; se re-ativado depois, consome outro crédito.
    if (acao === 'remover_dispositivo') {
      const dispositivo_id = (body.dispositivo_id || '').trim()
      const { data: d } = await sb.from('dispositivos').select('cliente_id').eq('id', dispositivo_id).maybeSingle()
      if (!d || !(await clienteDoRev(d.cliente_id))) return erro('dispositivo nao encontrado', 404)
      await sb.from('dispositivo_playlists').delete().eq('dispositivo_id', dispositivo_id)
      await sb.from('dispositivos').update({
        cliente_id: null, status: 'sem_lista', ativado_por: null, atualizado_em: new Date().toISOString(),
      }).eq('id', dispositivo_id)
      return json({ ok: true })
    }

    if (acao === 'excluir_playlist') {
      const cliente_id = (body.cliente_id || '').trim()
      const playlist_id = (body.playlist_id || '').trim()
      if (!(await clienteDoRev(cliente_id))) return erro('cliente nao encontrado', 404)
      await sb.from('playlists').delete().eq('id', playlist_id).eq('cliente_id', cliente_id)
      return json({ ok: true }) // vínculos somem por cascade
    }

    // ── VISÃO GLOBAL: todos os dispositivos do operador (de todos os clientes) ──
    if (acao === 'listar_dispositivos') {
      const { data: clis } = await sb.from('clientes').select('id, nome').eq('revendedor_id', rev.id)
      const cids = (clis || []).map((c) => c.id)
      if (!cids.length) return json({ dispositivos: [] })
      const { data: disp } = await sb.from('dispositivos')
        .select('id, mac, device_key, modelo, status, plano, trial_expira_em, expira_em, cliente_id, criado_em, ativado_por, atualizado_em')
        .in('cliente_id', cids).order('criado_em', { ascending: false })
      // deno-lint-ignore no-explicit-any
      const nomeCli = new Map((clis || []).map((c: any) => [c.id, c.nome]))
      // deno-lint-ignore no-explicit-any
      const dispositivos = (disp || []).map((d: any) => ({
        ...d, cliente: nomeCli.get(d.cliente_id) || '', status: statusEfetivo(d),
      }))
      return json({ dispositivos })
    }

    // ── VISÃO GLOBAL: todas as playlists do operador (URL decifrada p/ exibir) ──
    if (acao === 'listar_playlists') {
      const { data: clis } = await sb.from('clientes').select('id, nome').eq('revendedor_id', rev.id)
      const cids = (clis || []).map((c) => c.id)
      if (!cids.length) return json({ playlists: [] })
      const { data: pls } = await sb.from('playlists')
        .select('id, cliente_id, nome, tipo, url_cifrada, pin, free_dns, criado_em, atualizado_em')
        .in('cliente_id', cids).order('criado_em', { ascending: false })
      const plIds = (pls || []).map((p) => p.id)
      // deno-lint-ignore no-explicit-any
      let vinc: any[] = []
      if (plIds.length) { const { data } = await sb.from('dispositivo_playlists').select('playlist_id, selecionada').in('playlist_id', plIds); vinc = data || [] }
      // deno-lint-ignore no-explicit-any
      const nomeCli = new Map((clis || []).map((c: any) => [c.id, c.nome]))
      const playlists = []
      for (const p of (pls || [])) {
        let url = ''
        try { url = await decifrar(p.url_cifrada) } catch { /* ignore */ }
        const vs = vinc.filter((v) => v.playlist_id === p.id)
        playlists.push({
          id: p.id, cliente: nomeCli.get(p.cliente_id) || '', nome: p.nome, tipo: p.tipo, url,
          pin: p.pin || null, free_dns: !!p.free_dns, selecionada: vs.some((v) => v.selecionada),
          devices: vs.length, criado_em: p.criado_em, atualizado_em: p.atualizado_em, cliente_id: p.cliente_id,
        })
      }
      return json({ playlists })
    }

    // ── Migrar URL em massa: troca a base (protocolo+domínio+porta) mantendo o resto ──
    if (acao === 'migrar_url') {
      const origem = (body.origem || '').trim().replace(/\/+$/, '')
      const destino = (body.destino || '').trim().replace(/\/+$/, '')
      const preview = !!body.preview
      if (!origem || !destino) return erro('informe origem e destino')
      const { data: clis } = await sb.from('clientes').select('id').eq('revendedor_id', rev.id)
      const cids = (clis || []).map((c) => c.id)
      if (!cids.length) return json({ ok: true, afetadas: [], aplicado: false })
      const { data: pls } = await sb.from('playlists').select('id, nome, url_cifrada, epg_cifrada').in('cliente_id', cids)
      const afetadas = []
      for (const p of (pls || [])) {
        let url = ''
        try { url = await decifrar(p.url_cifrada) } catch { continue }
        if (!url.startsWith(origem)) continue
        const nova = destino + url.slice(origem.length)
        afetadas.push({ id: p.id, nome: p.nome, de: url, para: nova })
        if (!preview) {
          const url_cifrada = await cifrar(nova)
          let epg_cifrada = p.epg_cifrada
          if (p.epg_cifrada) {
            try { const e = await decifrar(p.epg_cifrada); if (e.startsWith(origem)) epg_cifrada = await cifrar(destino + e.slice(origem.length)) } catch { /* ignore */ }
          }
          await sb.from('playlists').update({ url_cifrada, epg_cifrada, atualizado_em: new Date().toISOString() }).eq('id', p.id)
        }
      }
      return json({ ok: true, afetadas, aplicado: !preview })
    }

    // ── SUPORTE (tickets) ──────────────────────────────────────────────────────
    // Revendedor abre; ADMIN vê TODOS, responde e encerra. Owner vê/responde os seus.
    if (acao === 'criar_ticket') {
      // O assunto deixou de ser texto livre: e um TOPICO fechado. Assim o
      // suporte tria por categoria e o revendedor so descreve o problema.
      const TOPICOS: Record<string, string> = {
        financeiro: 'Financeiro',
        tecnico: 'Tecnico',
        login: 'Login',
      }
      const topico = (body.topico || '').trim().toLowerCase()
      const rotulo = TOPICOS[topico]
      const mensagem = (body.mensagem || '').trim()
      if (!rotulo) return erro('escolha um topico (financeiro, tecnico ou login)')
      if (!mensagem) return erro('descreva o problema')
      const { data: tk, error } = await sb.from('tickets')
        .insert({ revendedor_id: rev.id, assunto: rotulo, topico }).select('id').single()
      if (error) return erro(error.message)
      await sb.from('ticket_mensagens').insert({ ticket_id: tk.id, autor_id: rev.id, do_admin: ehAdmin, corpo: mensagem })
      // Admin recebe na caixa de entrada — e o que faz o ticket ser VISTO.
      await notificar(await idsAdmins(), 'ticket', `Novo ticket · ${rotulo}`,
        `${rev.nome || rev.usuario}: ${mensagem.slice(0, 140)}`, tk.id)
      return json({ ok: true, id: tk.id })
    }

    if (acao === 'listar_tickets') {
      const status = (body.status || '').trim()
      let q = sb.from('tickets').select('id, revendedor_id, assunto, status, criado_em, atualizado_em')
        .order('atualizado_em', { ascending: false }).limit(300)
      if (!ehAdmin) q = q.eq('revendedor_id', rev.id)   // revendedor só vê os seus
      if (status) q = q.eq('status', status)
      const { data: tks } = await q
      // deno-lint-ignore no-explicit-any
      const ids = [...new Set((tks || []).map((t: any) => t.revendedor_id))]
      // deno-lint-ignore no-explicit-any
      const autor = new Map<string, any>()
      if (ids.length) { const { data } = await sb.from('revendedores').select('id, nome, usuario').in('id', ids); (data || []).forEach((r: any) => autor.set(r.id, r)) }
      // deno-lint-ignore no-explicit-any
      const tickets = (tks || []).map((t: any) => { const a = autor.get(t.revendedor_id) || {}; return { ...t, de: a.nome || a.usuario || '—' } })
      return json({ tickets, admin: ehAdmin })
    }

    if (acao === 'ticket_detalhe') {
      const id = (body.ticket_id || '').trim()
      const { data: tk } = await sb.from('tickets').select('*').eq('id', id).maybeSingle()
      if (!tk) return erro('ticket nao encontrado', 404)
      if (!ehAdmin && tk.revendedor_id !== rev.id) return erro('sem acesso', 403)
      const { data: msgs } = await sb.from('ticket_mensagens').select('id, autor_id, do_admin, corpo, criado_em')
        .eq('ticket_id', id).order('criado_em', { ascending: true })
      const { data: dono } = await sb.from('revendedores').select('nome, usuario').eq('id', tk.revendedor_id).maybeSingle()
      return json({ ticket: { ...tk, de: (dono && (dono.nome || dono.usuario)) || '—' }, mensagens: msgs || [], admin: ehAdmin })
    }

    if (acao === 'responder_ticket') {
      const id = (body.ticket_id || '').trim()
      const mensagem = (body.mensagem || '').trim()
      if (!mensagem) return erro('mensagem vazia')
      const { data: tk } = await sb.from('tickets').select('id, revendedor_id, assunto').eq('id', id).maybeSingle()
      if (!tk) return erro('ticket nao encontrado', 404)
      if (!ehAdmin && tk.revendedor_id !== rev.id) return erro('sem acesso', 403)
      await sb.from('ticket_mensagens').insert({ ticket_id: id, autor_id: rev.id, do_admin: ehAdmin, corpo: mensagem })
      // admin responde → 'respondido'; dono responde → 'aberto' (volta pra fila do admin)
      const novo = ehAdmin ? 'respondido' : 'aberto'
      await sb.from('tickets').update({ status: novo, atualizado_em: new Date().toISOString() }).eq('id', id)
      // Avisa o OUTRO lado: o dono quando o suporte responde; os admins quando
      // o dono responde (senao a resposta dele passa despercebida).
      if (ehAdmin) {
        await notificar([tk.revendedor_id], 'ticket', `Suporte respondeu · ${tk.assunto}`,
          mensagem.slice(0, 140), id)
      } else {
        await notificar(await idsAdmins(), 'ticket', `Resposta do revendedor · ${tk.assunto}`,
          `${rev.nome || rev.usuario}: ${mensagem.slice(0, 140)}`, id)
      }
      return json({ ok: true, status: novo })
    }

    if (acao === 'fechar_ticket') {
      const id = (body.ticket_id || '').trim()
      const reabrir = !!body.reabrir
      const { data: tk } = await sb.from('tickets').select('id, revendedor_id').eq('id', id).maybeSingle()
      if (!tk) return erro('ticket nao encontrado', 404)
      if (!ehAdmin && tk.revendedor_id !== rev.id) return erro('sem acesso', 403)
      await sb.from('tickets').update({ status: reabrir ? 'aberto' : 'fechado', atualizado_em: new Date().toISOString() }).eq('id', id)
      return json({ ok: true })
    }

    return erro('acao desconhecida')
  } catch (e) {
    return erro((e as Error).message || 'erro interno', 500)
  }
})