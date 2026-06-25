import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ============================================================================
// Edge Function `ativacao` — backend do APP DE TV (device por MAC + Key).
// Sem login: o app fala só com esta função (service role). A URL/EPG da playlist
// são CIFRADOS (AES-256-CBC) antes de gravar. RLS bloqueia anon/authenticated.
//   GET  ?mac=&key=                      -> { status, lista_url, epg_url, trial_expira_em, expira_em }
//   POST { acao:'adicionar', mac,key,lista_url,epg_url?,modelo? } -> { ok, status, trial_expira_em }
//   POST { acao:'ativar', mac, codigo }  -> { ok, status:'ativo', expira_em }
// ⚠️ Reuso temporário do projeto atual — migrar p/ projeto próprio no painel.
// ============================================================================

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}
const DIA = 86_400_000

// ── Criptografia AES-256-CBC (mesma chave da função `iptv`) ───────────────────
let _chave: CryptoKey | null = null
async function obterChave(): Promise<CryptoKey> {
  if (_chave) return _chave
  const raw = Deno.env.get('ENCRYPTION_KEY') ?? ''
  if (!raw) throw new Error('ENCRYPTION_KEY nao configurada nos Secrets')
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

// ── Helpers ───────────────────────────────────────────────────────────────────
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

// deno-lint-ignore no-explicit-any
function statusAtual(d: any): string {
  const now = Date.now()
  if (d.status === 'banido') return 'banido'
  if (d.status === 'ativo') return (d.expira_em && new Date(d.expira_em).getTime() < now) ? 'expirado' : 'ativo'
  if (d.status === 'trial') return (d.trial_expira_em && new Date(d.trial_expira_em).getTime() < now) ? 'expirado' : 'trial'
  return d.status || 'sem_lista'
}

const sb = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  try {
    // ── GET: status + lista decifrada (TV faz polling) ────────────────────────
    if (req.method === 'GET') {
      const u = new URL(req.url)
      const mac = (u.searchParams.get('mac') || '').trim()
      const key = (u.searchParams.get('key') || '').trim()
      if (!mac) return erro('mac obrigatorio')

      const { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (!d) return json({ status: 'sem_lista', lista_url: '', epg_url: '' })
      if (key && d.device_key !== key) return erro('key invalida', 403)

      const { data: pl } = await sb.from('playlists').select('*')
        .eq('dispositivo_id', d.id).eq('selecionada', true)
        .order('atualizado_em', { ascending: false }).maybeSingle()

      let lista_url = '', epg_url = ''
      if (pl) {
        try { lista_url = await decifrar(pl.url_cifrada) } catch { /* ignore */ }
        if (pl.epg_cifrada) { try { epg_url = await decifrar(pl.epg_cifrada) } catch { /* ignore */ } }
      }
      return json({ status: statusAtual(d), lista_url, epg_url, trial_expira_em: d.trial_expira_em, expira_em: d.expira_em })
    }

    if (req.method !== 'POST') return erro('metodo nao suportado', 405)

    const body = await req.json().catch(() => ({}))
    const acao = body.acao

    // ── POST adicionar: cria/atualiza device + grava playlist cifrada ─────────
    if (acao === 'adicionar') {
      const mac = (body.mac || '').trim()
      const key = (body.key || '').trim()
      const lista_url = (body.lista_url || '').trim()
      const epg_url = (body.epg_url || '').trim()
      if (!mac || !key) return erro('mac e key obrigatorios')
      if (!urlValida(lista_url)) return erro('lista_url invalida (use http/https)')

      let { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (d) {
        if (d.device_key !== key) return erro('key invalida', 403)
      } else {
        const trial = new Date(Date.now() + 7 * DIA).toISOString()
        const ins = await sb.from('dispositivos')
          .insert({ mac, device_key: key, modelo: body.modelo || null, status: 'trial', trial_expira_em: trial })
          .select().single()
        if (ins.error) throw ins.error
        d = ins.data
      }

      const url_cifrada = await cifrar(lista_url)
      const epg_cifrada = epg_url ? await cifrar(epg_url) : null
      const tipo = ehXtream(lista_url) ? 'xtream' : 'm3u'

      // MVP: 1 lista selecionada por device — substitui a anterior.
      await sb.from('playlists').delete().eq('dispositivo_id', d.id)
      const insP = await sb.from('playlists').insert({
        dispositivo_id: d.id, nome: 'Minha lista', tipo, url_cifrada, epg_cifrada, selecionada: true,
      })
      if (insP.error) throw insP.error

      let status = statusAtual(d)
      if (status === 'sem_lista') {
        const trial = new Date(Date.now() + 7 * DIA).toISOString()
        await sb.from('dispositivos').update({ status: 'trial', trial_expira_em: trial, atualizado_em: new Date().toISOString() }).eq('id', d.id)
        status = 'trial'; d.trial_expira_em = trial
      }
      return json({ ok: true, status, trial_expira_em: d.trial_expira_em })
    }

    // ── POST ativar: valida codigo e ativa o device ──────────────────────────
    if (acao === 'ativar') {
      const mac = (body.mac || '').trim()
      const codigo = (body.codigo || '').trim()
      if (!mac || !codigo) return erro('mac e codigo obrigatorios')

      const { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (!d) return erro('dispositivo nao encontrado', 404)

      const { data: c } = await sb.from('codigos_ativacao_tv').select('*').eq('codigo', codigo).maybeSingle()
      if (!c || c.usado) return erro('codigo invalido ou ja usado', 400)

      const expira_em = c.dias ? new Date(Date.now() + c.dias * DIA).toISOString() : null
      await sb.from('dispositivos').update({ status: 'ativo', expira_em, ativado_por: 'codigo', atualizado_em: new Date().toISOString() }).eq('id', d.id)
      await sb.from('codigos_ativacao_tv').update({ usado: true, usado_por_mac: mac }).eq('codigo', codigo)
      return json({ ok: true, status: 'ativo', expira_em })
    }

    return erro('acao desconhecida')
  } catch (e) {
    return erro((e as Error).message || 'erro interno', 500)
  }
})
