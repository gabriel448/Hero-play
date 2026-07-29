import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ============================================================================
// Edge Function `ativacao` — backend do APP DE TV (device por MAC + Key).
// Modelo reseller-ready: revendedor → cliente → dispositivo → playlist (a playlist
// é do CLIENTE e vinculada a dispositivos via `dispositivo_playlists`). No self-serve
// a função cria um cliente automático p/ o device. URL/EPG CIFRADOS (AES-256-CBC).
//   GET  ?mac=&key=                      -> { status, lista_url, epg_url, trial_expira_em, expira_em }  (lista SELECIONADA)
//   POST { acao:'adicionar', mac,key,lista_url,epg_url?,nome?,modelo? } -> { ok, status, trial_expira_em }
//   POST { acao:'listar', mac,key }      -> { status, playlists:[{id,nome,tipo,selecionada}] }
//   POST { acao:'selecionar', mac,key,id } -> { ok }   (define a playlist ativa do device)
//   POST { acao:'excluir', mac,key,id }  -> { ok }   (tira o vínculo; apaga a playlist se ficar órfã)
//   POST { acao:'ativar', mac, codigo }  -> { ok, status:'ativo', expira_em }
// ⚠️ Reuso temporário do projeto atual — migrar p/ projeto próprio no painel.
// ============================================================================

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}
const DIA = 86_400_000
const DIAS_TESTE = 3   // periodo de teste de um aparelho novo (era 7)

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
/**
 * host[:porta] em minusculo, sem `www.` — a chave que casa uma playlist com um
 * parceiro. O `www.` sai dos DOIS lados (aqui e no cadastro do dominio): sem
 * isso uma lista em `www.parceiro.com` nao casaria com `parceiro.com`.
 */
function hostDe(url: string): string | null {
  try { return new URL(url).host.toLowerCase().replace(/^www\./, '') || null } catch { return null }
}
/**
 * Dominio PARCEIRO? Se for, o device entra ativo na hora: sem teste e sem
 * consumir credito (e o acordo com quem revende o app junto do painel dele).
 * Best-effort: se a consulta falhar, o fluxo normal (teste) continua valendo.
 */
async function parceiroDoHost(host: string | null) {
  if (!host) return null
  try {
    const { data } = await sb.from('parceiros')
      .select('id, dominio, ativo').eq('dominio', host).eq('ativo', true).maybeSingle()
    return data || null
  } catch { return null }
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
      const modelo = (u.searchParams.get('modelo') || '').trim() || null
      if (!mac) return erro('mac obrigatorio')

      let { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (!d) {
        // 1º contato: REGISTRA o device (sem cliente/lista) p/ ficar "claimable" no
        // painel — o revendedor reivindica pela Key antes mesmo de ter lista (GTV).
        // Grava o `modelo` (plataforma real: webos/tizen/roku) já aqui.
        if (!key) return json({ status: 'sem_lista', lista_url: '', epg_url: '' })
        const ins = await sb.from('dispositivos').insert({ mac, device_key: key, modelo, status: 'sem_lista' }).select().single()
        if (ins.error) return json({ status: 'sem_lista', lista_url: '', epg_url: '' })
        d = ins.data
      } else if (modelo && d.modelo !== modelo) {
        // Device já existia (ex.: registrado sem modelo) → preenche/atualiza a
        // plataforma detectada agora. Best-effort: não bloqueia a resposta.
        await sb.from('dispositivos').update({ modelo }).eq('id', d.id)
        d.modelo = modelo
      }
      if (key && d.device_key !== key) return erro('key invalida', 403)

      // playlist ATIVA naquele device (via junção dispositivo_playlists)
      const { data: dp } = await sb.from('dispositivo_playlists').select('playlist_id')
        .eq('dispositivo_id', d.id).eq('selecionada', true).limit(1).maybeSingle()
      let lista_url = '', epg_url = ''
      if (dp?.playlist_id) {
        const { data: pl } = await sb.from('playlists').select('url_cifrada, epg_cifrada').eq('id', dp.playlist_id).maybeSingle()
        if (pl) {
          try { lista_url = await decifrar(pl.url_cifrada) } catch { /* ignore */ }
          if (pl.epg_cifrada) { try { epg_url = await decifrar(pl.epg_cifrada) } catch { /* ignore */ } }
        }
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

      // Dominio parceiro → nasce ATIVO (sem teste, sem credito). Ver `parceiros`.
      const host = hostDe(lista_url)
      const parceiro = await parceiroDoHost(host)

      let { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (d) {
        if (d.device_key !== key) return erro('key invalida', 403)
      } else {
        const novo = parceiro
          ? { status: 'ativo', trial_expira_em: null, ativado_por: 'parceiro' }
          : { status: 'trial', trial_expira_em: new Date(Date.now() + DIAS_TESTE * DIA).toISOString() }
        const ins = await sb.from('dispositivos')
          .insert({ mac, device_key: key, modelo: body.modelo || null, ...novo })
          .select().single()
        if (ins.error) throw ins.error
        d = ins.data
      }

      // Garante um CLIENTE p/ o device (self-serve cria automático).
      let cliente_id = d.cliente_id
      if (!cliente_id) {
        const insC = await sb.from('clientes').insert({ nome: 'Cliente ' + mac }).select('id').single()
        if (insC.error) throw insC.error
        cliente_id = insC.data.id
        await sb.from('dispositivos').update({ cliente_id }).eq('id', d.id)
      }

      const nome = (body.nome || '').trim() || 'Minha lista'
      const url_cifrada = await cifrar(lista_url)
      const epg_cifrada = epg_url ? await cifrar(epg_url) : null
      const tipo = ehXtream(lista_url) ? 'xtream' : 'm3u'

      // Cria a playlist no cliente e vincula ao device como SELECIONADA (desmarca
      // as outras do device). NÃO apaga as anteriores — agora são múltiplas.
      // `host` em texto claro (a URL segue cifrada): e por ele que se casa a
      // playlist com um parceiro e se conta quantos devices usam cada dominio.
      const insP = await sb.from('playlists')
        .insert({ cliente_id, nome, tipo, url_cifrada, epg_cifrada, host, free_dns: !!parceiro })
        .select('id').single()
      if (insP.error) throw insP.error
      await sb.from('dispositivo_playlists').update({ selecionada: false }).eq('dispositivo_id', d.id)
      const insDP = await sb.from('dispositivo_playlists').insert({ dispositivo_id: d.id, playlist_id: insP.data.id, selecionada: true })
      if (insDP.error) throw insDP.error

      let status = statusAtual(d)
      // Parceiro: ATIVA na hora, inclusive um device que ja existia em teste ou
      // expirado — a lista nova e que decide.
      if (parceiro && status !== 'banido' && status !== 'ativo') {
        await sb.from('dispositivos')
          .update({ status: 'ativo', ativado_por: 'parceiro', atualizado_em: new Date().toISOString() })
          .eq('id', d.id)
        status = 'ativo'
      } else if (status === 'sem_lista') {
        const trial = new Date(Date.now() + DIAS_TESTE * DIA).toISOString()
        await sb.from('dispositivos').update({ status: 'trial', trial_expira_em: trial, atualizado_em: new Date().toISOString() }).eq('id', d.id)
        status = 'trial'; d.trial_expira_em = trial
      }
      return json({ ok: true, status, trial_expira_em: d.trial_expira_em, parceiro: !!parceiro })
    }

    // ── POST listar: playlists vinculadas ao device (na ordem de criação) ─────
    if (acao === 'listar') {
      const mac = (body.mac || '').trim()
      const key = (body.key || '').trim()
      if (!mac) return erro('mac obrigatorio')
      const { data: d } = await sb.from('dispositivos').select('*').eq('mac', mac).maybeSingle()
      if (!d) return json({ status: 'sem_lista', playlists: [] })
      if (key && d.device_key !== key) return erro('key invalida', 403)

      const { data: vinc } = await sb.from('dispositivo_playlists')
        .select('playlist_id, selecionada, criado_em').eq('dispositivo_id', d.id)
        .order('criado_em', { ascending: true })
      // deno-lint-ignore no-explicit-any
      const ids = (vinc || []).map((v: any) => v.playlist_id)
      let pls: Record<string, unknown>[] = []
      if (ids.length) {
        const { data } = await sb.from('playlists').select('id, nome, tipo').in('id', ids)
        pls = data || []
      }
      // deno-lint-ignore no-explicit-any
      const playlists = (vinc || []).map((v: any) => {
        const p = pls.find((x) => x.id === v.playlist_id) || {}
        return { id: v.playlist_id, nome: p.nome ?? null, tipo: p.tipo ?? null, selecionada: v.selecionada }
      })
      return json({ status: statusAtual(d), playlists })
    }

    // ── POST selecionar: define a playlist ATIVA do device ────────────────────
    if (acao === 'selecionar') {
      const mac = (body.mac || '').trim()
      const key = (body.key || '').trim()
      const id = (body.id || '').trim()
      if (!mac || !id) return erro('mac e id obrigatorios')
      const { data: d } = await sb.from('dispositivos').select('id, device_key').eq('mac', mac).maybeSingle()
      if (!d) return erro('dispositivo nao encontrado', 404)
      if (key && d.device_key !== key) return erro('key invalida', 403)
      await sb.from('dispositivo_playlists').update({ selecionada: false }).eq('dispositivo_id', d.id)
      const up = await sb.from('dispositivo_playlists').update({ selecionada: true }).eq('dispositivo_id', d.id).eq('playlist_id', id)
      if (up.error) throw up.error
      return json({ ok: true })
    }

    // ── POST excluir: tira o vínculo do device; apaga a playlist se ficar órfã ─
    if (acao === 'excluir') {
      const mac = (body.mac || '').trim()
      const key = (body.key || '').trim()
      const id = (body.id || '').trim()
      if (!mac || !id) return erro('mac e id obrigatorios')
      const { data: d } = await sb.from('dispositivos').select('id, device_key').eq('mac', mac).maybeSingle()
      if (!d) return erro('dispositivo nao encontrado', 404)
      if (key && d.device_key !== key) return erro('key invalida', 403)

      const { data: vinc } = await sb.from('dispositivo_playlists').select('selecionada')
        .eq('dispositivo_id', d.id).eq('playlist_id', id).maybeSingle()
      await sb.from('dispositivo_playlists').delete().eq('dispositivo_id', d.id).eq('playlist_id', id)

      // órfã (sem nenhum outro device) → apaga a playlist do Supabase
      const { count } = await sb.from('dispositivo_playlists').select('*', { count: 'exact', head: true }).eq('playlist_id', id)
      if (!count) await sb.from('playlists').delete().eq('id', id)

      // se era a ativa e ainda há outras no device, ativa a 1ª
      if (vinc?.selecionada) {
        const { data: rest } = await sb.from('dispositivo_playlists').select('playlist_id')
          .eq('dispositivo_id', d.id).order('criado_em', { ascending: true }).limit(1).maybeSingle()
        if (rest?.playlist_id) await sb.from('dispositivo_playlists').update({ selecionada: true }).eq('dispositivo_id', d.id).eq('playlist_id', rest.playlist_id)
      }
      return json({ ok: true })
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
