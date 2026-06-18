import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Edge Function: CODIGO DE CRIACAO do beta fechado (mobile/desktop).
//
// O mobile/desktop e um beta fechado. A conta so e criada PELO SITE com um
// "codigo de criacao" que o dev gera (INSERT em public.codigos_ativacao). A
// confirmacao de e-mail CONTINUA valendo — esta funcao NAO cria o usuario nem
// confirma e-mail; o site faz o `signUp` normal (que dispara o e-mail de
// confirmacao via Resend). Aqui so:
//
//   acao 'validar' { codigo }            -> diz se o codigo existe/ativo/livre
//                                           (sem queimar) — chamado ANTES do signUp.
//   acao 'ativar'  { codigo, userId }    -> re-valida, marca contas_ativacao
//                                           (ativado=true) e QUEIMA o codigo —
//                                           chamado DEPOIS do signUp.
//
// Convencao: desfechos ESPERADOS voltam HTTP 200 com { ok: true|false, error? }
// (assim o site le `data.ok` direto; o `functions.invoke` so trata non-2xx como
// erro). Apenas falhas inesperadas voltam 500.
//
// Os codigos vivem numa tabela sem acesso de anon/authenticated (so service
// role), entao toda a logica fica aqui. Invocada com a anon key (verify_jwt ok).

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

function respInvalido(error: string) {
  return respJson({ ok: false, error })
}

function normalizar(codigo: unknown): string {
  return String(codigo ?? '').trim().toUpperCase()
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return respJson({ ok: false, error: 'Metodo nao suportado' }, 405)

  let body: { acao?: string; codigo?: string; userId?: string }
  try {
    body = await req.json()
  } catch {
    return respInvalido('Corpo invalido.')
  }

  const acao = body.acao
  const codigo = normalizar(body.codigo)
  if (!codigo) return respInvalido('Informe o codigo de criacao.')

  const sbAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )

  try {
    // Busca o codigo (service role ignora RLS).
    const { data: cod, error: selErr } = await sbAdmin
      .from('codigos_ativacao')
      .select('codigo, ativo, usado_por')
      .eq('codigo', codigo)
      .maybeSingle()
    if (selErr) throw selErr

    const valido = !!cod && cod.ativo === true && !cod.usado_por
    if (!valido) return respInvalido('Codigo invalido ou ja utilizado.')

    // 'validar' so confere — nao queima (usado ANTES de criar a conta).
    if (acao === 'validar') return respJson({ ok: true })

    // 'ativar' — exige o userId recem-criado pelo signUp do site.
    if (acao === 'ativar') {
      const userId = String(body.userId ?? '').trim()
      if (!userId) return respInvalido('userId ausente.')

      // Queima o codigo de forma atomica (so vence se ainda estiver ativo/livre).
      const { data: queima, error: updErr } = await sbAdmin
        .from('codigos_ativacao')
        .update({ ativo: false, usado_por: userId, usado_em: new Date().toISOString() })
        .eq('codigo', codigo)
        .eq('ativo', true)
        .is('usado_por', null)
        .select('codigo')
      if (updErr) throw updErr
      if (!queima || queima.length === 0) {
        return respInvalido('Codigo invalido ou ja utilizado.')
      }

      // Marca a conta como ativada (beta liberado).
      const { error: upErr } = await sbAdmin
        .from('contas_ativacao')
        .upsert({
          user_id: userId,
          ativado: true,
          ativado_em: new Date().toISOString(),
          codigo,
        })
      if (upErr) throw upErr

      return respJson({ ok: true })
    }

    return respInvalido('Acao desconhecida.')
  } catch (e) {
    console.error('[codigo-beta]', e)
    return respJson({ ok: false, error: 'Erro ao processar o codigo.' }, 500)
  }
})
