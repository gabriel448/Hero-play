import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ============================================================================
// Edge Function `api` — API PUBLICA do Hero Play, para paineis de terceiros.
//
// Existe SEPARADA da `painel` de proposito. A `painel` e o contrato interno do
// nosso painel e muda quando precisamos; se um painel de terceiro pendurasse
// nela, toda mudanca nossa viraria quebra de contrato pra fora. Aqui a
// superficie e pequena, explicita e estavel.
//
// AUTENTICACAO: chave de API no header.
//     Authorization: Bearer hp_xxxxxxxx...      (ou)  X-API-Key: hp_xxxx...
// A chave e de um ADMIN. Nao existe login de usuario/senha aqui.
//
// ESCOPO: a chave de admin enxerga a PLATAFORMA INTEIRA — clientes,
// dispositivos e playlists de TODOS os revendedores. Diferente das acoes da
// `painel`, que mostram so o que e do proprio operador. E proposital: esta API
// existe para o admin administrar tudo de fora.
//
//   GET   /clientes                 -> todos os clientes, com o revendedor dono
//   GET   /clientes/:id             -> cliente + aparelhos + listas
//   GET   /dispositivos             -> todos os aparelhos, com MAC e Key
//   GET   /playlists                -> todas as listas, com a URL decifrada
//   POST  /playlists                -> cria lista e vincula aos aparelhos
//   PATCH /playlists/:id            -> troca a URL/nome/EPG de UMA lista
//   POST  /playlists/migrar         -> troca de dominio em MASSA (previa + aplicar)
//
// ⚠️ O QUE ESTA API NAO FAZ, DE PROPOSITO:
//   - nao ativa nem renova dispositivo (isso CONSOME CREDITO: chave vazada
//     viraria prejuizo direto);
//   - nao cria/remove revendedor, nao transfere credito, nao mexe em parceiro
//     nem em servidor;
//   - nao apaga nada.
// Nao e esquecimento: a superficie e uma lista fechada, escrita a mao. Acao que
// nao esta aqui nao e alcancavel por chave de API, mesmo existindo na `painel`.
// ============================================================================

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-api-key, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
}

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const sb = createClient(SB_URL, SERVICE)

/** Teto por chamada na troca em massa: Edge Function tem limite de tempo e
 *  cada linha custa um decifra + um cifra. Quem chama repete com `apos`. */
const MAX_MIGRACAO = 300
/** Teto das listagens. Acima disso, pagina com `apos`. */
const MAX_LISTA = 1000

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
const erro = (msg: string, status = 400) => json({ ok: false, erro: msg }, status)

// ── Criptografia: mesma ENCRYPTION_KEY da `painel`/`ativacao` ────────────────
// A URL da playlist e gravada CIFRADA. Esta funcao precisa cifrar ao criar e
// decifrar ao listar — e o mesmo cofre, senao o painel nao le o que a API
// escreveu (e vice-versa).
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
async function decifrar(dado: string): Promise<string> {
  const chave = await obterChave()
  const b = Uint8Array.from(atob(dado), (c) => c.charCodeAt(0))
  const dec = await crypto.subtle.decrypt({ name: 'AES-CBC', iv: b.slice(0, 16) }, chave, b.slice(16))
  return new TextDecoder().decode(dec)
}

/** SHA-256 em hex — mesma conta que a `painel` usa ao criar a chave. */
export async function hashDaChave(chave: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(chave))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function ehXtream(url: string): boolean {
  try { const u = new URL(url); return u.searchParams.has('username') && u.searchParams.has('password') } catch { return false }
}
function urlValida(url: string): boolean {
  try { return ['http:', 'https:'].includes(new URL(url).protocol) } catch { return false }
}
/** host[:porta] minusculo, sem `www.` — mesma regra da `painel`. */
function hostDe(url: string): string | null {
  try { return new URL(url).host.toLowerCase().replace(/^www\./, '') || null } catch { return null }
}
/** "servidor.com:8080" -> "servidor.com". */
const semPorta = (h: string) => h.replace(/:\d+$/, '')

/**
 * Normaliza o que vier como dominio: aceita URL inteira, "www.host" ou so o
 * host. Sai host[:porta] — a mesma chave que a coluna `host` guarda.
 */
function normalizarDominio(entrada: unknown): string {
  let s = String(entrada || '').trim().toLowerCase()
  if (!s) return ''
  if (!/^[a-z][a-z0-9+.-]*:\/\//.test(s)) s = 'http://' + s
  try { return new URL(s).host.replace(/^www\./, '') } catch { return '' }
}

/**
 * Filtro PostgREST das playlists de um dominio.
 *
 * Dominio SEM porta cobre qualquer porta ("servidor.com" cobre
 * "servidor.com:8080"); COM porta casa exato. A URL de playlist IPTV quase
 * sempre traz porta, entao exigir igualdade exata faria a busca nunca achar
 * nada para quem digitou so o dominio.
 */
const filtroDoHost = (d: string) => (
  /:\d+$/.test(d) ? `host.eq.${d}` : `host.eq.${d},host.like.${d}:*`
)

/**
 * Parceiro ATIVO que cobre este host. Cadastro sem porta cobre qualquer porta.
 * MESMA regra da `painel` e da `ativacao` — as tres precisam decidir igual,
 * senao a mesma lista ativaria por um caminho e nao pelo outro.
 */
async function parceiroDoHost(host: string | null) {
  if (!host) return null
  try {
    const chaves = [...new Set([host, semPorta(host)])]
    const { data } = await sb.from('parceiros')
      .select('id, dominio').in('dominio', chaves).eq('ativo', true)
    const achados = data || []
    // deno-lint-ignore no-explicit-any
    return achados.find((p: any) => p.dominio === host) || achados[0] || null
  } catch { return null }
}

/**
 * Resolve a chave de API do header -> linha do revendedor.
 *
 * So aceita chave. NAO ha fallback para JWT de sessao: fallback e como API
 * publica vira porta dos fundos do painel.
 */
async function autenticar(req: Request): Promise<{ erro?: Response; rev?: Rev; quem: Quem }> {
  const bruto = req.headers.get('x-api-key')
    || (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '')
  const chave = (bruto || '').trim()
  // Prefixo da chave APRESENTADA, para o log saber quem bateu mesmo quando a
  // chave nao vale. So os 11 primeiros caracteres — o mesmo pedaco que ja
  // aparece no painel; a chave inteira nunca sai daqui.
  const quem: Quem = { id: null, prefixo: chave ? chave.slice(0, 11) : null, nome: null }
  if (!chave) return { erro: erro('informe a chave de API em `Authorization: Bearer ...` ou `X-API-Key`', 401), quem }

  const { data: registro } = await sb.from('api_chaves')
    .select('id, nome, prefixo, revendedor_id, ativo').eq('hash', await hashDaChave(chave)).maybeSingle()
  if (!registro || !registro.ativo) return { erro: erro('chave de API invalida ou revogada', 401), quem }
  quem.id = registro.id
  quem.nome = registro.nome
  quem.prefixo = registro.prefixo || quem.prefixo

  const { data: rev } = await sb.from('revendedores')
    .select('id, nome, usuario, papel, ativo').eq('id', registro.revendedor_id).maybeSingle()
  if (!rev || !rev.ativo) return { erro: erro('a conta dona desta chave esta inativa', 403), quem }
  // O papel e conferido A CADA requisicao, e nao so na criacao da chave: se a
  // conta for rebaixada depois, a chave para de valer na hora, sem ninguem
  // precisar lembrar de revogar. E e o que sustenta o escopo "ve tudo".
  if (rev.papel !== 'admin') return { erro: erro('esta chave nao pertence a uma conta admin', 403), quem }

  // Best-effort: registrar uso nao pode derrubar a requisicao.
  sb.from('api_chaves').update({ ultimo_uso_em: new Date().toISOString() })
    .eq('id', registro.id).then(() => {}, () => {})

  return { rev, quem }
}

/** Mapa cliente_id -> { nome, revendedor }, para as listagens nao virem cegas. */
async function mapaDeClientes(ids: string[]) {
  const mapa = new Map<string, { nome: string; revendedor: string | null }>()
  if (!ids.length) return mapa
  const { data: cls } = await sb.from('clientes').select('id, nome, revendedor_id').in('id', ids)
  // deno-lint-ignore no-explicit-any
  const revIds = [...new Set(((cls || []) as any[]).map((c) => c.revendedor_id).filter(Boolean))]
  const nomeRev = new Map<string, string>()
  if (revIds.length) {
    const { data: revs } = await sb.from('revendedores').select('id, nome, usuario').in('id', revIds)
    // deno-lint-ignore no-explicit-any
    for (const r of ((revs || []) as any[])) nomeRev.set(r.id, r.nome || r.usuario || '')
  }
  // deno-lint-ignore no-explicit-any
  for (const c of ((cls || []) as any[])) {
    mapa.set(c.id, { nome: c.nome, revendedor: nomeRev.get(c.revendedor_id) ?? null })
  }
  return mapa
}

// deno-lint-ignore no-explicit-any
function statusEfetivo(d: any): string {
  const agora = Date.now()
  if (d.status === 'banido') return 'banido'
  if (d.status === 'ativo') return (d.expira_em && new Date(d.expira_em).getTime() < agora) ? 'expirado' : 'ativo'
  if (d.status === 'trial') return (d.trial_expira_em && new Date(d.trial_expira_em).getTime() < agora) ? 'expirado' : 'trial'
  return d.status || 'sem_lista'
}

/** Troca o HOST de uma URL preservando esquema, caminho e query. */
function trocarHost(url: string, novoHost: string): string | null {
  try { const u = new URL(url); u.host = novoHost; return u.toString() } catch { return null }
}

/** Reavalia `host`/`free_dns` e ativa os aparelhos se o destino for parceiro. */
async function aplicarHostNaPlaylist(playlistId: string, novaUrl: string, epgCifrada: string | null, epgNova: string | null) {
  const novoHost = hostDe(novaUrl)
  const parceiro = await parceiroDoHost(novoHost)
  // ⚠️ O `host` em texto claro TEM que acompanhar a URL: e por ele que se casa
  // a playlist com um parceiro, se conta device por dominio e se fecha fatura.
  const { error } = await sb.from('playlists').update({
    url_cifrada: await cifrar(novaUrl),
    epg_cifrada: epgNova !== null ? epgNova : epgCifrada,
    host: novoHost,
    free_dns: !!parceiro,
    atualizado_em: new Date().toISOString(),
  }).eq('id', playlistId)
  if (error) return { erro: error.message, ativados: 0, parceiro: !!parceiro }

  let ativados = 0
  if (parceiro) {
    const { data: vins } = await sb.from('dispositivo_playlists')
      .select('dispositivo_id').eq('playlist_id', playlistId)
    // deno-lint-ignore no-explicit-any
    const devs = [...new Set(((vins || []) as any[]).map((v) => v.dispositivo_id))]
    if (devs.length) {
      await sb.from('dispositivos')
        .update({ status: 'ativo', ativado_por: 'parceiro', atualizado_em: new Date().toISOString() })
        .in('id', devs).neq('status', 'banido')
      ativados = devs.length
    }
  }
  return { erro: null, ativados, parceiro: !!parceiro }
}

/** Quem fez a chamada, do ponto de vista do log. */
type Quem = { id: string | null; prefixo: string | null; nome: string | null }
// deno-lint-ignore no-explicit-any
type Rev = any

/**
 * Registra a chamada em `api_logs`.
 *
 * ⚠️ NAO grava corpo nem query string. O corpo do POST/PATCH /playlists leva
 * `lista_url`, que carrega USUARIO E SENHA do servidor Xtream em texto claro —
 * a playlist e gravada cifrada no banco justamente para isso nao ficar a
 * mostra, e um log de depuracao nao pode ser a porta dos fundos dessa
 * protecao. Vai o caminho, o resultado e a duracao.
 *
 * A resposta e CLONADA para ler a mensagem de erro. Guardar o ultimo payload
 * numa variavel de modulo seria mais simples e estaria errado: o mesmo isolate
 * atende requisicoes concorrentes, e uma embaralharia o log da outra.
 */
async function registrarLog(req: Request, resp: Response, quem: Quem, ms: number) {
  try {
    const u = new URL(req.url)
    const i = u.pathname.indexOf('/api')
    const rota = (i >= 0 ? u.pathname.slice(i + 4) : u.pathname) || '/'
    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim()
      || req.headers.get('cf-connecting-ip') || null

    let mensagem: string | null = null
    if (resp.status >= 400) {
      try {
        const corpo = await resp.clone().json()
        // So a mensagem NOSSA (`erro`), nunca o corpo inteiro.
        if (typeof corpo?.erro === 'string') mensagem = corpo.erro.slice(0, 300)
      } catch { /* resposta sem JSON: fica sem mensagem */ }
    }

    await sb.from('api_logs').insert({
      chave_id: quem.id, prefixo: quem.prefixo, chave_nome: quem.nome,
      metodo: req.method, rota, status: resp.status, ms, ip, erro: mensagem,
    })
  } catch { /* log que derruba a requisicao e pior que log nenhum */ }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const t0 = Date.now()
  let quem: Quem = { id: null, prefixo: null, nome: null }
  const resposta = await (async (): Promise<Response> => {
  try {
    const auth = await autenticar(req)
    quem = auth.quem
    if (auth.erro) return auth.erro

    const url = new URL(req.url)
    const partes = url.pathname.split('/').filter(Boolean)
    const i = partes.indexOf('api')
    const rota = (i >= 0 ? partes.slice(i + 1) : partes)
    const apos = (url.searchParams.get('apos') || '').trim()

    // ── GET /clientes ────────────────────────────────────────────────────────
    // TODOS os clientes da plataforma, com o revendedor dono de cada um.
    if (req.method === 'GET' && rota[0] === 'clientes' && !rota[1]) {
      let q = sb.from('clientes').select('id, nome, revendedor_id, criado_em')
        .order('id', { ascending: true }).limit(MAX_LISTA + 1)
      if (apos) q = q.gt('id', apos)
      const { data } = await q
      const linhas = data || []
      const restam_mais = linhas.length > MAX_LISTA
      const lote = linhas.slice(0, MAX_LISTA)
      // deno-lint-ignore no-explicit-any
      const revIds = [...new Set((lote as any[]).map((c) => c.revendedor_id).filter(Boolean))]
      const nomeRev = new Map<string, string>()
      if (revIds.length) {
        const { data: revs } = await sb.from('revendedores').select('id, nome, usuario').in('id', revIds)
        // deno-lint-ignore no-explicit-any
        for (const r of ((revs || []) as any[])) nomeRev.set(r.id, r.nome || r.usuario || '')
      }
      return json({
        ok: true,
        // deno-lint-ignore no-explicit-any
        clientes: (lote as any[]).map((c) => ({
          id: c.id, nome: c.nome, criado_em: c.criado_em,
          revendedor_id: c.revendedor_id, revendedor: nomeRev.get(c.revendedor_id) ?? null,
        })),
        restam_mais,
        proximo: restam_mais && lote.length ? lote[lote.length - 1].id : null,
      })
    }

    // ── GET /clientes/:id ────────────────────────────────────────────────────
    if (req.method === 'GET' && rota[0] === 'clientes' && rota[1]) {
      const cliente_id = rota[1]
      const { data: cliente } = await sb.from('clientes')
        .select('id, nome, revendedor_id, criado_em').eq('id', cliente_id).maybeSingle()
      if (!cliente) return erro('cliente nao encontrado', 404)
      const { data: rev } = await sb.from('revendedores')
        .select('id, nome, usuario').eq('id', cliente.revendedor_id).maybeSingle()

      const { data: disp } = await sb.from('dispositivos')
        .select('id, mac, device_key, modelo, status, plano, trial_expira_em, expira_em, ativado_por, criado_em')
        .eq('cliente_id', cliente_id).order('criado_em', { ascending: true })
      const { data: pls } = await sb.from('playlists')
        .select('id, nome, tipo, host, free_dns, criado_em')
        .eq('cliente_id', cliente_id).order('criado_em', { ascending: true })
      return json({
        ok: true,
        cliente: {
          ...cliente,
          revendedor: rev ? (rev.nome || rev.usuario || null) : null,
        },
        // deno-lint-ignore no-explicit-any
        dispositivos: (disp || []).map((d: any) => ({ ...d, status: statusEfetivo(d) })),
        playlists: pls || [],
      })
    }

    // ── GET /dispositivos ────────────────────────────────────────────────────
    // TODOS os aparelhos, com MAC e Key, e de quem e cada um.
    if (req.method === 'GET' && rota[0] === 'dispositivos' && !rota[1]) {
      let q = sb.from('dispositivos')
        .select('id, mac, device_key, modelo, status, plano, trial_expira_em, expira_em, cliente_id, ativado_por, criado_em, atualizado_em')
        .order('id', { ascending: true }).limit(MAX_LISTA + 1)
      if (apos) q = q.gt('id', apos)
      const { data } = await q
      const linhas = data || []
      const restam_mais = linhas.length > MAX_LISTA
      const lote = linhas.slice(0, MAX_LISTA)
      // deno-lint-ignore no-explicit-any
      const mapa = await mapaDeClientes([...new Set((lote as any[]).map((d) => d.cliente_id).filter(Boolean))])
      return json({
        ok: true,
        // deno-lint-ignore no-explicit-any
        dispositivos: (lote as any[]).map((d) => ({
          ...d,
          status: statusEfetivo(d),
          cliente: mapa.get(d.cliente_id)?.nome ?? null,
          revendedor: mapa.get(d.cliente_id)?.revendedor ?? null,
        })),
        restam_mais,
        proximo: restam_mais && lote.length ? lote[lote.length - 1].id : null,
      })
    }

    // ── GET /playlists ───────────────────────────────────────────────────────
    // TODAS as listas, com a URL decifrada: e a chave do admin, e sem a URL a
    // integracao nao consegue conferir o que subiu.
    if (req.method === 'GET' && rota[0] === 'playlists' && !rota[1]) {
      let q = sb.from('playlists')
        .select('id, cliente_id, nome, tipo, url_cifrada, host, free_dns, criado_em, atualizado_em')
        .order('id', { ascending: true }).limit(MAX_LISTA + 1)
      if (apos) q = q.gt('id', apos)
      const filtroHost = normalizarDominio(url.searchParams.get('host'))
      if (filtroHost) q = q.or(filtroDoHost(filtroHost))
      const { data } = await q
      const linhas = data || []
      const restam_mais = linhas.length > MAX_LISTA
      const lote = linhas.slice(0, MAX_LISTA)
      // deno-lint-ignore no-explicit-any
      const mapa = await mapaDeClientes([...new Set((lote as any[]).map((p) => p.cliente_id).filter(Boolean))])
      const playlists = []
      for (const p of lote) {
        let lista_url = ''
        try { lista_url = await decifrar(p.url_cifrada) } catch { /* nao derruba a lista inteira */ }
        playlists.push({
          id: p.id, cliente_id: p.cliente_id,
          cliente: mapa.get(p.cliente_id)?.nome ?? null,
          revendedor: mapa.get(p.cliente_id)?.revendedor ?? null,
          nome: p.nome, tipo: p.tipo, url: lista_url,
          host: p.host, free_dns: !!p.free_dns,
          criado_em: p.criado_em, atualizado_em: p.atualizado_em,
        })
      }
      return json({
        ok: true, playlists, restam_mais,
        proximo: restam_mais && lote.length ? lote[lote.length - 1].id : null,
      })
    }

    // ── POST /playlists/migrar — troca de dominio em MASSA ───────────────────
    // Corpo: { de, para, aplicar?, apos? }
    // Sem `aplicar: true` e PREVIA: nada e alterado.
    if (req.method === 'POST' && rota[0] === 'playlists' && rota[1] === 'migrar') {
      const body = await req.json().catch(() => ({}))
      const de = normalizarDominio(body.de)
      const para = normalizarDominio(body.para)
      const aplicar = body.aplicar === true
      const cursor = String(body.apos || '').trim()
      if (!de || !para) return erro('informe `de` e `para` (dominio ou URL do servidor)')
      if (de === para) return erro('`de` e `para` sao o mesmo dominio')

      // Casa por HOST, nao por prefixo de URL. Prefixo casaria vizinho:
      // "old.com" pegaria "old.company.com" (porque "company" comeca com
      // "com") e a troca reescreveria a playlist errada.
      let q = sb.from('playlists')
        .select('id, cliente_id, nome, url_cifrada, epg_cifrada, host')
        .or(filtroDoHost(de)).order('id', { ascending: true }).limit(MAX_MIGRACAO + 1)
      if (cursor) q = q.gt('id', cursor)
      const { data } = await q
      const linhas = data || []
      const restam_mais = linhas.length > MAX_MIGRACAO
      const lote = linhas.slice(0, MAX_MIGRACAO)

      const afetadas = []
      let alteradas = 0
      for (const p of lote) {
        let atual = ''
        try { atual = await decifrar(p.url_cifrada) } catch { continue }
        // O host do destino herda a porta do cadastro quando `para` nao traz
        // uma: trocar "a.com:8080" por "b.com" mantém :8080.
        const novoHost = /:\d+$/.test(para) ? para
          : (/:\d+$/.test(p.host || '') ? `${para}:${(p.host || '').split(':').pop()}` : para)
        const nova = trocarHost(atual, novoHost)
        if (!nova) continue
        afetadas.push({ id: p.id, nome: p.nome, cliente_id: p.cliente_id, de: atual, para: nova })
        if (aplicar) {
          let epgNova: string | null = null
          if (p.epg_cifrada) {
            try {
              const e = await decifrar(p.epg_cifrada)
              const trocada = hostDe(e) === p.host ? trocarHost(e, novoHost) : null
              if (trocada) epgNova = await cifrar(trocada)
            } catch { /* EPG ilegivel nao impede a troca da lista */ }
          }
          const r = await aplicarHostNaPlaylist(p.id, nova, p.epg_cifrada, epgNova)
          if (!r.erro) alteradas++
        }
      }
      return json({
        ok: true,
        aplicado: aplicar,
        encontradas: afetadas.length,
        alteradas,
        // Na previa vai a lista inteira do lote, para conferir antes de aplicar.
        amostra: aplicar ? afetadas.slice(0, 20) : afetadas,
        restam_mais,
        proximo: restam_mais && lote.length ? lote[lote.length - 1].id : null,
      })
    }

    // ── POST /playlists — cria lista ─────────────────────────────────────────
    // Corpo: { cliente_id, nome?, lista_url, epg_url?, dispositivo_ids? }
    if (req.method === 'POST' && rota[0] === 'playlists' && !rota[1]) {
      const body = await req.json().catch(() => ({}))
      const cliente_id = String(body.cliente_id || '').trim()
      const lista_url = String(body.lista_url || '').trim()
      const epg_url = String(body.epg_url || '').trim()
      const nome = String(body.nome || '').trim() || 'Playlist'
      const dispositivo_ids: string[] = Array.isArray(body.dispositivo_ids) ? body.dispositivo_ids : []

      if (!cliente_id) return erro('informe o cliente_id')
      if (!urlValida(lista_url)) return erro('lista_url invalida (use http ou https)')
      if (epg_url && !urlValida(epg_url)) return erro('epg_url invalida (use http ou https)')

      const { data: cliente } = await sb.from('clientes').select('id').eq('id', cliente_id).maybeSingle()
      if (!cliente) return erro('cliente nao encontrado', 404)

      const host = hostDe(lista_url)
      const parceiro = await parceiroDoHost(host)
      const { data: pl, error } = await sb.from('playlists').insert({
        cliente_id, nome,
        tipo: ehXtream(lista_url) ? 'xtream' : 'm3u',
        url_cifrada: await cifrar(lista_url),
        epg_cifrada: epg_url ? await cifrar(epg_url) : null,
        host, free_dns: !!parceiro,
      }).select('id, nome, tipo, host, free_dns, criado_em').single()
      if (error) return erro(`falha ao gravar a playlist: ${error.message}`, 500)

      // Alvos: os dispositivos informados (conferidos contra o cliente), ou
      // TODOS do cliente.
      let alvos = dispositivo_ids
      if (alvos.length) {
        const { data: meus } = await sb.from('dispositivos')
          .select('id').eq('cliente_id', cliente_id).in('id', alvos)
        // deno-lint-ignore no-explicit-any
        alvos = (meus || []).map((d: any) => d.id)
        if (!alvos.length) return erro('nenhum dos dispositivo_ids pertence a este cliente', 400)
      } else {
        const { data } = await sb.from('dispositivos').select('id').eq('cliente_id', cliente_id)
        // deno-lint-ignore no-explicit-any
        alvos = (data || []).map((d: any) => d.id)
      }

      for (const did of alvos) {
        // Sem nenhuma selecionada ainda? Esta vira a ativa.
        const { count } = await sb.from('dispositivo_playlists')
          .select('*', { count: 'exact', head: true })
          .eq('dispositivo_id', did).eq('selecionada', true)
        await sb.from('dispositivo_playlists')
          .insert({ dispositivo_id: did, playlist_id: pl.id, selecionada: !count })
      }

      // Dominio parceiro ativa o aparelho na hora, sem teste e SEM CREDITO —
      // mesma regra da `painel`. Nao e a API gastando credito: e o acordo do
      // dominio valendo, exatamente como quando a lista entra pelo painel.
      let ativados = 0
      if (parceiro && alvos.length) {
        await sb.from('dispositivos')
          .update({ status: 'ativo', ativado_por: 'parceiro', atualizado_em: new Date().toISOString() })
          .in('id', alvos).neq('status', 'banido')
        ativados = alvos.length
      }
      return json({ ok: true, playlist: pl, vinculados: alvos.length, parceiro: !!parceiro, ativados }, 201)
    }

    // ── PATCH /playlists/:id — troca a lista de UM cliente ───────────────────
    // Corpo: { lista_url?, nome?, epg_url? } — manda so o que muda.
    if (req.method === 'PATCH' && rota[0] === 'playlists' && rota[1] && rota[1] !== 'migrar') {
      const playlist_id = rota[1]
      const body = await req.json().catch(() => ({}))
      const lista_url = String(body.lista_url || '').trim()
      const epg_url = String(body.epg_url || '').trim()
      const nome = String(body.nome || '').trim()
      if (!lista_url && !nome && !epg_url) return erro('nada para alterar: mande `lista_url`, `nome` ou `epg_url`')
      if (lista_url && !urlValida(lista_url)) return erro('lista_url invalida (use http ou https)')
      if (epg_url && !urlValida(epg_url)) return erro('epg_url invalida (use http ou https)')

      const { data: pl } = await sb.from('playlists')
        .select('id, cliente_id, nome, url_cifrada, epg_cifrada, host').eq('id', playlist_id).maybeSingle()
      if (!pl) return erro('playlist nao encontrada', 404)

      if (nome) await sb.from('playlists').update({ nome }).eq('id', playlist_id)

      let ativados = 0, parceiro = false
      if (lista_url) {
        const epgNova = epg_url ? await cifrar(epg_url) : null
        const r = await aplicarHostNaPlaylist(playlist_id, lista_url, pl.epg_cifrada, epgNova)
        if (r.erro) return erro(`falha ao atualizar a playlist: ${r.erro}`, 500)
        ativados = r.ativados; parceiro = r.parceiro
      } else if (epg_url) {
        await sb.from('playlists')
          .update({ epg_cifrada: await cifrar(epg_url), atualizado_em: new Date().toISOString() })
          .eq('id', playlist_id)
      }

      const { data: depois } = await sb.from('playlists')
        .select('id, cliente_id, nome, tipo, host, free_dns, atualizado_em').eq('id', playlist_id).maybeSingle()
      if (!depois) return erro('o banco nao confirmou a alteracao', 500)
      return json({ ok: true, playlist: depois, parceiro, ativados })
    }

    return erro(
      'rota nao encontrada. Disponiveis: GET /clientes, GET /clientes/:id, GET /dispositivos, '
      + 'GET /playlists, POST /playlists, PATCH /playlists/:id, POST /playlists/migrar',
      404,
    )
  } catch (e) {
    return erro((e as Error).message || 'erro interno', 500)
  }
  })()

  // O log e esperado de verdade — `EdgeRuntime.waitUntil` deixa ele terminar
  // DEPOIS de a resposta sair, sem somar latencia. Sem ele, cai no await: um
  // log que some em silencio e pior que nenhum, porque a tela mostra vazio e
  // ninguem descobre que o problema e o log, nao a integracao.
  const tarefa = registrarLog(req, resposta, quem, Date.now() - t0)
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime
  if (rt?.waitUntil) rt.waitUntil(tarefa); else await tarefa

  return resposta
})
