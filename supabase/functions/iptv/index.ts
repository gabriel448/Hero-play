import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── CORS ──────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
}

// ── Criptografia AES-256-CBC (Web Crypto nativa do Deno) ──────────────────────

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
  if (bytes.length !== 32) throw new Error('ENCRYPTION_KEY deve ter exatamente 32 bytes')
  _chave = await crypto.subtle.importKey('raw', bytes, { name: 'AES-CBC' }, false, [
    'encrypt',
    'decrypt',
  ])
  return _chave
}

async function cifrar(texto: string): Promise<string> {
  const chave = await obterChave()
  const iv = crypto.getRandomValues(new Uint8Array(16))
  const cifrado = await crypto.subtle.encrypt(
    { name: 'AES-CBC', iv },
    chave,
    new TextEncoder().encode(texto),
  )
  const resultado = new Uint8Array(16 + cifrado.byteLength)
  resultado.set(iv)
  resultado.set(new Uint8Array(cifrado), 16)
  return btoa(String.fromCharCode(...resultado))
}

async function decifrar(dado: string): Promise<string> {
  const chave = await obterChave()
  const bytes = Uint8Array.from(atob(dado), (c) => c.charCodeAt(0))
  const decifrado = await crypto.subtle.decrypt(
    { name: 'AES-CBC', iv: bytes.slice(0, 16) },
    chave,
    bytes.slice(16),
  )
  return new TextDecoder().decode(decifrado)
}

// ── Deteccao e extracao de credenciais Xtream ─────────────────────────────────

function ehXtream(url: string): boolean {
  try {
    const u = new URL(url)
    return u.searchParams.has('username') && u.searchParams.has('password')
  } catch {
    return false
  }
}

function extrairXtream(url: string) {
  const u = new URL(url)
  const usuario = u.searchParams.get('username')!
  const senha = u.searchParams.get('password')!
  const serverUrl = u.origin
  u.searchParams.delete('username')
  u.searchParams.delete('password')
  u.hash = ''
  return { serverUrl, usuario, senha, urlSaneada: u.toString() }
}

function sanitizarUrl(url: string): string {
  return ehXtream(url) ? extrairXtream(url).urlSaneada : url
}

// Chave de armazenamento para listas Xtream: URL saneada + hash do usuario.
// Garante que dois usuarios diferentes no mesmo servidor gerem chaves distintas,
// evitando que o upsert sobrescreva listas de contas diferentes.
async function fonteXtream(urlSaneada: string, usuario: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(usuario),
  )
  const hex = Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  return urlSaneada + '#x' + hex.slice(0, 20)
}

// ── Helpers de resposta ────────────────────────────────────────────────────────

function respJson(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

function respErro(msg: string, status = 400) {
  return respJson({ error: msg }, status)
}

function validarUrl(url: string): string | null {
  try {
    const u = new URL(url)
    if (!['http:', 'https:'].includes(u.protocol)) return 'URL deve usar http ou https'
    return null
  } catch {
    return 'URL invalida'
  }
}

// ── Handler principal ─────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const auth = req.headers.get('Authorization')
  if (!auth) return respErro('Sem autorizacao', 401)

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } },
  )

  const { data: { user }, error: authErr } = await sb.auth.getUser()
  if (authErr || !user) return respErro('Nao autenticado', 401)

  try {
    // ── GET — listar listas com credenciais descriptografadas ──────────────────
    if (req.method === 'GET') {
      const { data, error: dbErr } = await sb
        .from('listas')
        .select('*')
        .order('ordem', { ascending: true })
        .order('created_at', { ascending: true })
      if (dbErr) throw dbErr

      const listas = await Promise.all(
        (data ?? []).map(async (row) => {
          let fonteReconstruida: string = row.fonte_url
          let epgReconstruida: string | null = row.epg_url

          if (row.xtream_user && row.xtream_pass) {
            try {
              const usuario = await decifrar(row.xtream_user)
              const senha = await decifrar(row.xtream_pass)

              // Reconstroi URL da M3U (strip do hash de unicidade antes de devolver)
              const u = new URL(row.fonte_url)
              u.hash = ''
              u.searchParams.set('username', usuario)
              u.searchParams.set('password', senha)
              fonteReconstruida = u.toString()

              // Reconstroi URL do EPG se for do mesmo servidor Xtream
              if (row.epg_url && row.server_url) {
                try {
                  if (new URL(row.epg_url).origin === new URL(row.server_url).origin) {
                    const eu = new URL(row.epg_url)
                    eu.hash = ''
                    eu.searchParams.set('username', usuario)
                    eu.searchParams.set('password', senha)
                    epgReconstruida = eu.toString()
                  }
                } catch { /* mantem epg_url saneada */ }
              }
            } catch {
              // Falha na decifragem: devolve URL saneada
            }
          }

          return {
            id: row.id,
            nome: row.nome,
            fonte_url: fonteReconstruida,
            epg_url: epgReconstruida,
            ordem: row.ordem,
            created_at: row.created_at,
          }
        }),
      )

      return respJson(listas)
    }

    // ── POST — criar / upsert lista ────────────────────────────────────────────
    if (req.method === 'POST') {
      const body = await req.json()
      const { nome, fonte_url, epg_url } = body

      if (!nome?.trim() || !fonte_url?.trim()) {
        return respErro('nome e fonte_url sao obrigatorios')
      }
      const erroUrl = validarUrl(fonte_url)
      if (erroUrl) return respErro(erroUrl)

      let payload: Record<string, unknown> = {
        user_id: user.id,
        nome: (nome as string).trim(),
        epg_url: epg_url?.trim() ? sanitizarUrl(epg_url.trim()) : null,
      }

      if (ehXtream(fonte_url)) {
        const { serverUrl, usuario, senha, urlSaneada } = extrairXtream(fonte_url)
        payload = {
          ...payload,
          fonte_url: await fonteXtream(urlSaneada, usuario),
          server_url: serverUrl,
          xtream_user: await cifrar(usuario),
          xtream_pass: await cifrar(senha),
        }
      } else {
        payload.fonte_url = (fonte_url as string).trim()
        payload.server_url = null
        payload.xtream_user = null
        payload.xtream_pass = null
      }

      const { error: dbErr } = await sb
        .from('listas')
        .upsert(payload, { onConflict: 'user_id,fonte_url' })
      if (dbErr) throw dbErr

      return respJson({ ok: true }, 201)
    }

    // ── PUT — atualizar lista pelo id (painel web) ─────────────────────────────
    if (req.method === 'PUT') {
      const body = await req.json()
      const { id, nome, fonte_url, epg_url } = body

      if (!id) return respErro('id obrigatorio')
      if (!nome?.trim() || !fonte_url?.trim()) {
        return respErro('nome e fonte_url sao obrigatorios')
      }
      const erroUrl = validarUrl(fonte_url)
      if (erroUrl) return respErro(erroUrl)

      let payload: Record<string, unknown> = {
        nome: (nome as string).trim(),
        epg_url: epg_url?.trim() ? sanitizarUrl(epg_url.trim()) : null,
      }

      if (ehXtream(fonte_url)) {
        const { serverUrl, usuario, senha, urlSaneada } = extrairXtream(fonte_url)
        payload = {
          ...payload,
          fonte_url: await fonteXtream(urlSaneada, usuario),
          server_url: serverUrl,
          xtream_user: await cifrar(usuario),
          xtream_pass: await cifrar(senha),
        }
      } else {
        payload.fonte_url = (fonte_url as string).trim()
        payload.server_url = null
        payload.xtream_user = null
        payload.xtream_pass = null
      }

      // RLS garante que o usuario so mexe nas proprias linhas; .eq user_id e
      // defesa em profundidade caso o RLS seja acidentalmente desativado.
      const { error: dbErr } = await sb
        .from('listas')
        .update(payload)
        .eq('id', id)
        .eq('user_id', user.id)
      if (dbErr) throw dbErr

      return respJson({ ok: true })
    }

    // ── DELETE — remover por id (painel) ou por fonte_url (app Flutter) ────────
    if (req.method === 'DELETE') {
      const body = await req.json().catch(() => ({}))
      const { id, fonte_url } = body

      if (!id && !fonte_url) return respErro('id ou fonte_url obrigatorio')

      let dbErr
      if (id) {
        ;({ error: dbErr } = await sb
          .from('listas')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id))
      } else if (ehXtream(fonte_url)) {
        // Xtream: tenta chave nova (hash) e URL saneada (linhas do formato antigo)
        // em paralelo para garantir retrocompatibilidade durante a transicao.
        const { usuario, urlSaneada } = extrairXtream(fonte_url)
        const chave = await fonteXtream(urlSaneada, usuario)
        const [r1, r2] = await Promise.all([
          sb.from('listas').delete().eq('user_id', user.id).eq('fonte_url', chave),
          sb.from('listas').delete().eq('user_id', user.id).eq('fonte_url', urlSaneada),
        ])
        dbErr = r1.error ?? r2.error
      } else {
        ;({ error: dbErr } = await sb
          .from('listas')
          .delete()
          .eq('user_id', user.id)
          .eq('fonte_url', sanitizarUrl(fonte_url)))
      }
      if (dbErr) throw dbErr

      return respJson({ ok: true })
    }

    return respErro('Metodo nao suportado', 405)
  } catch (e) {
    console.error('[iptv fn]', e)
    return respErro('Erro interno do servidor', 500)
  }
})
