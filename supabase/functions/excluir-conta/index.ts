import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Edge Function: EXCLUIR CONTA + DADOS do usuario logado.
//
// Requisito da Play Store / App Store: o usuario precisa conseguir apagar a
// conta e todos os dados associados por um caminho proprio. Apagar um usuario
// do Supabase Auth exige a SERVICE ROLE (o cliente com anon key nao pode).
//
// Fluxo:
//   1. Valida o JWT do chamador (cliente anon com o Authorization do usuario)
//      para descobrir QUEM esta pedindo a exclusao.
//   2. Com a SERVICE ROLE, apaga os dados (listas/perfis/biblioteca) e o
//      proprio usuario do Auth. As FKs tem ON DELETE CASCADE, mas apagamos
//      explicitamente antes como defesa em profundidade.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function respJson(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

function respErro(msg: string, status = 400) {
  return respJson({ error: msg }, status)
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return respErro('Metodo nao suportado', 405)

  const auth = req.headers.get('Authorization')
  if (!auth) return respErro('Sem autorizacao', 401)

  // 1) Cliente do usuario — valida o JWT e identifica quem pede a exclusao.
  const sbUser = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } } },
  )

  const { data: { user }, error: authErr } = await sbUser.auth.getUser()
  if (authErr || !user) return respErro('Nao autenticado', 401)

  try {
    // 2) Cliente admin (service role) — unico que pode apagar usuarios do Auth.
    const sbAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // Apaga explicitamente os dados do usuario (defesa em profundidade; as FKs
    // ja tem ON DELETE CASCADE no user_id).
    await sbAdmin.from('biblioteca').delete().eq('user_id', user.id)
    await sbAdmin.from('perfis').delete().eq('user_id', user.id)
    await sbAdmin.from('listas').delete().eq('user_id', user.id)

    // Apaga a conta de autenticacao (cascateia qualquer dado restante).
    const { error: delErr } = await sbAdmin.auth.admin.deleteUser(user.id)
    if (delErr) throw delErr

    return respJson({ ok: true })
  } catch (e) {
    console.error('[excluir-conta]', e)
    return respErro('Erro ao excluir a conta', 500)
  }
})
