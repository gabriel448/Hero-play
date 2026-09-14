// Testa o LOG da API (`api_logs`): o que ele guarda, o que ele NUNCA pode
// guardar, e a tela que o mostra.
//
// O risco aqui não é a tela — é o log virar vazamento. O corpo de
// `POST /playlists` leva `lista_url`, que carrega usuário e senha do servidor
// Xtream em texto claro. A playlist é gravada CIFRADA no banco exatamente para
// isso não ficar à mostra; um log de depuração que gravasse o corpo desfaria
// essa proteção inteira, em silêncio e por escrito.
//
// Rodar:  node tools/teste-parceiros/api-logs.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const ler = (p) => readFileSync(new URL(p, import.meta.url), 'utf8')
const apiFn = ler('../../supabase/functions/api/index.ts')
const painelFn = ler('../../supabase/functions/painel/index.ts')
const schema = ler('../../supabase/schema-tv.sql')
const ui = ler('../../painel/painel.js')
const css = ler('../../painel/painel.css')

const tela = ui.slice(ui.indexOf('async function vApiLogs'), ui.indexOf('async function vApiChaves'))
// Comeca no JSDoc de proposito: a regra do "nao grava corpo" esta escrita la,
// e some do arquivo junto com ela se alguem reescrever a funcao.
const registrar = apiFn.slice(apiFn.indexOf('/**\n * Registra a chamada'), apiFn.indexOf('Deno.serve'))

test('a tabela existe, com índice e fechada para o cliente', () => {
  assert.match(schema, /create table if not exists public\.api_logs/)
  for (const col of ['chave_id', 'prefixo', 'metodo', 'rota', 'status', 'ms', 'ip', 'erro', 'criado_em']) {
    assert.match(schema, new RegExp('^\\s+' + col + '\\s', 'm'), `faltou a coluna ${col}`)
  }
  // Consulta padrão é "as mais recentes": sem índice por data isso vira
  // varredura da tabela inteira, que é justamente a que mais cresce.
  assert.match(schema, /idx_api_logs_criado on public\.api_logs\(criado_em desc\)/)
  assert.match(schema, /revoke all on public\.api_logs from anon, authenticated/)
  // bigserial precisa da sequence liberada, senão todo insert falha.
  assert.match(schema, /grant usage, select on sequence public\.api_logs_id_seq to service_role/)
})

test('revogar a chave não apaga o histórico do que ela fez', () => {
  const bloco = schema.slice(schema.indexOf('create table if not exists public.api_logs'))
  assert.match(bloco, /chave_id\s+uuid references public\.api_chaves\(id\) on delete set null/)
  // Prefixo e nome desnormalizados: com `set null`, sem eles a linha antiga
  // vira "alguém, em algum momento" — inútil para auditoria.
  assert.match(bloco, /prefixo\s+text/)
  assert.match(bloco, /chave_nome text/)
})

test('o log NUNCA grava corpo de requisição nem query string', () => {
  // LISTA BRANCA, não lista de proibidos.
  //
  // A primeira versão deste teste proibia `req.text`, `body`, `lista_url`… e
  // passava feliz com `corpo: await req.clone().text()` — que é exatamente o
  // vazamento que ele existia para impedir. Contra blocklist de substring
  // sempre há uma grafia a mais. Aqui o que vale é: as colunas gravadas são
  // ESTAS, e qualquer campo novo reprova até alguém decidir que pode entrar.
  const ins = registrar.slice(registrar.indexOf(".insert({"), registrar.indexOf("})", registrar.indexOf(".insert({")))
  assert.ok(ins.length > 0, 'não achei o insert do log')
  // Pega `chave: valor` E a forma abreviada (`rota`, `ms`, `ip`), que não tem
  // dois-pontos — um regex só de `chave:` perderia justo as três e a lista
  // branca ficaria menor do que a realidade.
  const campos = ins.slice(ins.indexOf('{') + 1).split(',')
    .map((t) => t.trim()).filter(Boolean)
    .map((t) => (t.includes(':') ? t.slice(0, t.indexOf(':')) : t).trim())
    .filter((t) => /^\w+$/.test(t)).sort()
  assert.deepEqual(campos, [
    'chave_id', 'chave_nome', 'erro', 'ip', 'metodo', 'ms', 'prefixo', 'rota', 'status',
  ], 'as colunas gravadas no log mudaram — confira se alguma carrega credencial')

  // E a rota é o CAMINHO: query string pode levar filtro, nunca o caminho todo.
  const codigo = registrar.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*/g, '')
  assert.ok(codigo.includes('api_logs'), 'a fatia sem comentários ficou vazia')
  assert.match(codigo, /u\.pathname/)
  for (const proibido of ['searchParams', 'u.search', '.text()', '.json()']) {
    // `.json()` só é permitido no clone da RESPOSTA, conferido noutro teste.
    if (proibido === '.json()') continue
    assert.ok(!codigo.includes(proibido), `registrarLog não pode tocar em \`${proibido}\``)
  }
})

test('o log guarda o prefixo da chave, nunca a chave inteira', () => {
  const aut = apiFn.slice(apiFn.indexOf('async function autenticar'), apiFn.indexOf('/** Mapa cliente_id'))
  assert.match(aut, /chave\.slice\(0, 11\)/)
  // A chave em texto nunca entra no objeto que vai para o banco.
  // O que nao pode e a chave INTEIRA virar valor do campo (`prefixo: chave,`).
  // `chave ? chave.slice(0, 11) : null` e justamente o jeito certo.
  assert.ok(!/prefixo:\s*chave\s*[,}]/.test(aut), 'a chave inteira foi parar no campo do log')
  assert.match(registrar, /prefixo: quem\.prefixo/)
})

test('chamada recusada também vira log', () => {
  // "Chave inválida batendo de novo e de novo" é exatamente o que se quer
  // enxergar. Se só o caminho feliz logasse, o log não serviria para segurança.
  const serve = apiFn.slice(apiFn.indexOf('Deno.serve'))
  assert.match(serve, /quem = auth\.quem/)
  // O registro fica FORA do if de erro: roda para toda resposta.
  const i = serve.indexOf('registrarLog(req, resposta')
  assert.ok(i > serve.indexOf('if (auth.erro) return auth.erro'), 'o log não cobre a recusa')
})

test('o log não pode derrubar nem atrasar a requisição', () => {
  assert.match(registrar, /try \{[\s\S]*\} catch \{/)
  const serve = apiFn.slice(apiFn.indexOf('Deno.serve'))
  // waitUntil deixa terminar DEPOIS da resposta; o await é o fallback para
  // runtime que não tem waitUntil — sem ele o log some em silêncio.
  assert.match(serve, /waitUntil\(tarefa\)/)
  assert.match(serve, /else await tarefa/)
  // E a resposta sai independente do log.
  assert.match(serve, /return resposta/)
})

test('ler a mensagem de erro não pode embaralhar requisições concorrentes', () => {
  // Guardar o último payload numa variável de módulo seria mais simples e
  // estaria errado: o mesmo isolate atende várias requisições ao mesmo tempo.
  assert.match(registrar, /resp\.clone\(\)/)
  assert.match(registrar, /corpo\?\.erro/)
})

test('as ações do painel são admin-only', () => {
  for (const [acao, ate] of [['listar_api_logs', 'limpar_api_logs'], ['limpar_api_logs', 'listar_notificacoes']]) {
    const i = painelFn.indexOf(`acao === '${acao}'`)
    const f = painelFn.indexOf(`acao === '${ate}'`)
    // Fatia sempre delimitada dos dois lados: um marcador que cai antes do
    // início devolveria o arquivo inteiro, e o teste passaria sem testar nada.
    assert.ok(i >= 0 && f > i, `não achei o trecho de ${acao}`)
    const trecho = painelFn.slice(i, f)
    assert.match(trecho, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/)
  }
})

test('tabela ausente diz que está ausente, em vez de "nenhuma chamada"', () => {
  // Esta é a falha silenciosa da vez: sem o schema rodado, a tela mostraria
  // vazio e mandaria o admin investigar a integração, que está boa.
  const trecho = painelFn.slice(painelFn.indexOf("acao === 'listar_api_logs'"), painelFn.indexOf("acao === 'limpar_api_logs'"))
  assert.match(trecho, /if \(error\)/)
  assert.match(trecho, /indisponivel/)
  assert.match(trecho, /schema-tv\.sql/)
  // E a tela tem que reagir a esse campo, não só o backend mandá-lo.
  assert.match(tela, /r\.indisponivel/)
})

test('limpar exige confirmação e tem teto', () => {
  const trecho = painelFn.slice(
    painelFn.indexOf("acao === 'limpar_api_logs'"),
    painelFn.indexOf("acao === 'listar_notificacoes'"))
  assert.match(trecho, /Math\.min\(Math\.max\(Number\(body\.dias\) \|\| 30, 1\), 365\)/)
  assert.match(tela, /confirm\(/)
})

test('a pílula acesa é a mesma que o filtro usa', () => {
  // `pills` acendia sempre a PRIMEIRA opção. Com o padrão em 24h e "1 hora"
  // primeiro na lista, a tela acenderia "1 hora" mostrando 24h de dados —
  // um filtro que mente sobre si mesmo.
  assert.match(ui, /function pills\(label, opts, sel\)/)
  assert.match(ui, /const ativo = sel === undefined \? \(opts\[0\] \|\| \[\]\)\[0\] : sel/)
  const padrao = tela.match(/const st = \{ q: '', faixa: '([^']+)'/)
  assert.ok(padrao, 'não achei o estado inicial da tela')
  const pilula = tela.match(/pills\('Período',[\s\S]*?\], '([^']+)'\)/)
  assert.ok(pilula, 'as pílulas de período não declaram qual nasce acesa')
  assert.equal(pilula[1], padrao[1], 'a pílula acesa não é a faixa que a tela carrega')
})

test('a tela é de consulta e está no menu do admin', () => {
  assert.match(ui, /\{ id: 'apilogs', rotulo: 'API Logs', ic: 'hash' \}/)
  assert.match(ui, /apilogs: vApiLogs/)
  assert.match(tela, /me\.papel !== 'admin'/)
  // Nada de escrita além da limpeza explícita.
  for (const escrita of ['criar_api_chave', 'revogar_api_chave', 'add_playlist', 'migrar_url']) {
    assert.ok(!tela.includes(escrita), `a tela de log não pode chamar \`${escrita}\``)
  }
})

test('a tela não mostra corpo de requisição', () => {
  // O backend não manda; a tela também não pode inventar uma coluna para isso.
  for (const campo of ['l.body', 'l.corpo', 'lista_url', 'l.url']) {
    assert.ok(!tela.includes(campo), `a tela não pode exibir \`${campo}\``)
  }
})

test('status 4xx e 5xx se distinguem: dizem para quem mandar o bug', () => {
  assert.match(ui, /const classeStatus = \(n\) => n >= 500 \? 'badge-expirado' : \(n >= 400 \? 'badge-trial' : 'badge-ativo'\)/)
  for (const c of ['badge-expirado', 'badge-trial', 'badge-ativo']) {
    assert.ok(css.includes('.' + c), `.${c} não existe no CSS`)
  }
})

test('o log mostra hora, e o tempo é mediana', () => {
  // "14/09" num log não serve para nada.
  // `fmtInstante`, nao `fmtDataHora`: aquele ja existia (detalhe do device) e
  // nao tem segundos. Declarar um segundo com o mesmo nome derrubou o painel
  // inteiro uma vez — ver painel-sintaxe.test.mjs.
  assert.match(ui, /const fmtInstante =/)
  assert.match(tela, /fmtInstante\(l\.criado_em\)/)
  assert.match(ui, /hour: '2-digit', minute: '2-digit', second: '2-digit'/)
  // Média deixa uma chamada de 8 s esconder que o resto está rápido.
  assert.match(tela, /const mediana =/)
  assert.ok(!/reduce\(\(a, x\) => a \+ x/.test(tela), 'voltou a usar média')
})

test('toda classe al-* da tela existe no CSS', () => {
  const usadas = new Set((tela.match(/class="[^"]*"/g) || [])
    .flatMap((a) => a.match(/al-[a-z-]+/g) || [])
    .map((c) => (c === 'al-m-' ? 'al-m-get' : c)))
  assert.ok(usadas.size > 0, 'não achei classe al-* nenhuma')
  for (const c of usadas) {
    const achou = [' ', ',', ':', '{'].some((fim) => css.includes('.' + c + fim))
    assert.ok(achou, `.${c} não existe em painel.css`)
  }
})
