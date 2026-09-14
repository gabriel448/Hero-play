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
// ESCOPO desta versao: LEITURA + UPLOAD DE LISTA. So isso.
//   GET  /clientes                  -> { ok, clientes: [...] }
//   GET  /clientes/:id              -> { ok, cliente, dispositivos, playlists }
//   GET  /playlists                 -> { ok, playlists: [...] }
//   POST /playlists                 -> cria playlist e vincula a dispositivos
//
// ⚠️ O QUE ESTA API NAO FAZ, DE PROPOSITO:
//   - nao ativa nem renova dispositivo (isso CONSOME CREDITO: chave vazada
//     viraria prejuizo direto);
//   - nao cria/remove revendedor, nao transfere credito, nao mexe em parceiro
//     nem em servidor;
//   - nao exclui nada.
// Nada disso e por esquecimento: a superficie e uma lista fechada, escrita a
// mao. Acao que nao esta aqui nao e alcancavel por chave de API, mesmo que
// exista na `painel`.
// ============================================================================

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-api-key, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const sb = createClient(SB_URL, SERVICE)

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
/**
 * Parceiro ATIVO que cobre este host. Cadastro sem porta cobre qualquer porta.
 * MESMA regra da `painel` e da `ativacao` — as tres precisam decidir igual,
 * senao a mesma lista ativaria por um caminho e nao pelo outro.
 */
async function parceiroDoHost(host: string | null) {
  if (!host) return null
  try {
    const chaves = [...new Set([host, host.replace(/:\d+$/, '')])]
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
async function autenticar(req: Request) {
  const bruto = req.headers.get('x-api-key')
    || (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '')
  const chave = (bruto || '').trim()
  if (!chave) return { erro: erro('informe a chave de API em `Authorization: Bearer ...` ou `X-API-Key`', 401) }

  const { data: registro } = await sb.from('api_chaves')
    .select('id, revendedor_id, ativo').eq('hash', await hashDaChave(chave)).maybeSingle()
  if (!registro || !registro.ativo) return { erro: erro('chave de API invalida ou revogada', 401) }

  const { data: rev } = await sb.from('revendedores')
    .select('id, nome, usuario, papel, ativo').eq('id', registro.revendedor_id).maybeSingle()
  if (!rev || !rev.ativo) return { erro: erro('a conta dona desta chave esta inativa', 403) }
  // Nesta versao a API e so de admin. A checagem fica AQUI, e nao so na
  // criacao da chave: se a conta for rebaixada depois, a chave para de valer
  // na hora, sem ninguem precisar lembrar de revogar.
  if (rev.papel !== 'admin') return { erro: erro('esta chave nao pertence a uma conta admin', 403) }

  // Best-effort: registrar uso nao pode derrubar a requisicao.
  sb.from('api_chaves').update({ ultimo_uso_em: new Date().toISOString() })
    .eq('id', registro.id).then(() => {}, () => {})

  return { rev }
}

/** Ids dos clientes deste operador (mesmo escopo que ele ve no painel). */
async function clientesDoOperador(revId: string): Promise<string[]> {
  const { data } = await sb.from('clientes').select('id').eq('revendedor_id', revId)
  return (data || []).map((c) => c.id)
}

// deno-lint-ignore no-explicit-any
function statusEfetivo(d: any): string {
  const agora = Date.now()
  if (d.status === 'banido') return 'banido'
  if (d.status === 'ativo') return (d.expira_em && new Date(d.expira_em).getTime() < agora) ? 'expirado' : 'ativo'
  if (d.status === 'trial') return (d.trial_expira_em && new Date(d.trial_expira_em).getTime() < agora) ? 'expirado' : 'trial'
  return d.status || 'sem_lista'
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  try {
    const auth = await autenticar(req)
    if (auth.erro) return auth.erro
    const rev = auth.rev!

    // O caminho vem depois do nome da funcao: /api/clientes -> ["clientes"]
    const partes = new URL(req.url).pathname.split('/').filter(Boolean)
    const i = partes.indexOf('api')
    const rota = (i >= 0 ? partes.slice(i + 1) : partes)

    // ── GET /clientes ────────────────────────────────────────────────────────
    if (req.method === 'GET' && rota[0] === 'clientes' && !rota[1]) {
      const { data } = await sb.from('clientes')
        .select('id, nome, criado_em').eq('revendedor_id', rev.id)
        .order('criado_em', { ascending: false })
      return json({ ok: true, clientes: data || [] })
    }

    // ── GET /clientes/:id ────────────────────────────────────────────────────
    if (req.method === 'GET' && rota[0] === 'clientes' && rota[1]) {
      const cliente_id = rota[1]
      const { data: cliente } = await sb.from('clientes')
        .select('id, nome, criado_em').eq('id', cliente_id).eq('revendedor_id', rev.id).maybeSingle()
      if (!cliente) return erro('cliente nao encontrado', 404)

      const { data: disp } = await sb.from('dispositivos')
        .select('id, mac, device_key, modelo, status, plano, trial_expira_em, expira_em, ativado_por, criado_em')
        .eq('cliente_id', cliente_id).order('criado_em', { ascending: true })
      const { data: pls } = await sb.from('playlists')
        .select('id, nome, tipo, host, free_dns, criado_em')
        .eq('cliente_id', cliente_id).order('criado_em', { ascending: true })
      return json({
        ok: true,
        cliente,
        // deno-lint-ignore no-explicit-any
        dispositivos: (disp || []).map((d: any) => ({ ...d, status: statusEfetivo(d) })),
        playlists: pls || [],
      })
    }

    // ── GET /playlists ───────────────────────────────────────────────────────
    // A URL vai DECIFRADA: e a chave do admin, e sem a URL a integracao nao
    // consegue conferir o que subiu.
    if (req.method === 'GET' && rota[0] === 'playlists' && !rota[1]) {
      const cids = await clientesDoOperador(rev.id)
      if (!cids.length) return json({ ok: true, playlists: [] })
      const { data: pls } = await sb.from('playlists')
        .select('id, cliente_id, nome, tipo, url_cifrada, host, free_dns, criado_em, atualizado_em')
        .in('cliente_id', cids).order('criado_em', { ascending: false }).limit(1000)
      const playlists = []
      for (const p of (pls || [])) {
        let url = ''
        try { url = await decifrar(p.url_cifrada) } catch { /* nao derruba a lista inteira */ }
        playlists.push({
          id: p.id, cliente_id: p.cliente_id, nome: p.nome, tipo: p.tipo, url,
          host: p.host, free_dns: !!p.free_dns,
          criado_em: p.criado_em, atualizado_em: p.atualizado_em,
        })
      }
      return json({ ok: true, playlists })
    }

    // ── POST /playlists ──────────────────────────────────────────────────────
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

      // O cliente TEM que ser deste operador — nao basta o id existir.
      const { data: cliente } = await sb.from('clientes')
        .select('id').eq('id', cliente_id).eq('revendedor_id', rev.id).maybeSingle()
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

      // Alvos: os dispositivos informados (conferidos), ou TODOS do cliente.
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

    return erro('rota nao encontrada. Disponiveis: GET /clientes, GET /clientes/:id, GET /playlists, POST /playlists', 404)
  } catch (e) {
    return erro((e as Error).message || 'erro interno', 500)
  }
})
