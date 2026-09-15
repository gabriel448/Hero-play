// Testa três telas do admin: ações nos revendedores (bloquear, redefinir senha,
// detalhe), histórico de créditos da plataforma e Downloads.
//
// Os riscos que importam aqui:
//  - uma conta de revendedor tomando outra (por isso as ações são só do admin);
//  - a senha provisória vazando para log ou notificação;
//  - o histórico da plataforma mentindo "nenhum movimento" com o schema velho;
//  - link de download apontando para um arquivo que não existe.
//
// Rodar:  node tools/teste-parceiros/painel-admin.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

// Fim de linha normalizado: parte dos fontes está em CRLF na cópia de trabalho,
// e um marcador com "\n" deixaria de achar o trecho só por causa disso.
const ler = (p) => readFileSync(new URL(p, import.meta.url), 'utf8').replace(/\r\n/g, '\n')
const fn = ler('../../supabase/functions/painel/index.ts')
const schema = ler('../../supabase/schema-tv.sql')
const ui = ler('../../painel/painel.js')
const vercel = JSON.parse(ler('../../vercel.json'))

const acao = (nome, ate) => {
  const i = fn.indexOf(`acao === '${nome}'`)
  const f = fn.indexOf(`acao === '${ate}'`)
  assert.ok(i >= 0 && f > i, `não achei o trecho de ${nome}`)
  return fn.slice(i, f)
}
const trecho = (src, de, ate) => {
  const i = src.indexOf(de)
  const f = src.indexOf(ate, i + 1)
  assert.ok(i >= 0 && f > i, `não achei o trecho entre "${de}" e "${ate}"`)
  return src.slice(i, f)
}
const semComentarios = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*/g, '')

// Tira o TEXTO das strings, mas mantém o que é interpolado nelas.
//
// Texto de mensagem ("falha ao redefinir a senha") não é uso da variável e não
// pode contar. Mas apagar o template inteiro esconderia justamente o vazamento
// que o teste existe para pegar: `Nova senha: ${senha}` sumiria junto. Então
// de um template sobra só o que está dentro de ${...}.
const semTextoDeStrings = (s) => s
  .replace(/`(?:[^`\\]|\\.)*`/g, (t) => (t.match(/\$\{[^}]*\}/g) || []).join(' '))
  .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
  .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')

// ── Tarefa 2: ações nos revendedores ───────────────────────────────────────────

const ativo = acao('revendedor_ativo', 'redefinir_senha_revendedor')
const senha = acao('redefinir_senha_revendedor', 'admin_revendedor_detalhe')
const detalhe = acao('admin_revendedor_detalhe', 'transferir_creditos')

test('bloquear, redefinir senha e ver detalhe são só do admin', () => {
  // Se quem indicou pudesse redefinir a senha, entraria na conta do indicado e
  // transferiria os créditos dele para si.
  for (const [nome, s] of [['revendedor_ativo', ativo], ['redefinir_senha_revendedor', senha], ['admin_revendedor_detalhe', detalhe]]) {
    assert.match(s, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/, `${nome} não é admin-only`)
  }
})

test('nenhuma ação alcança outro admin; bloquear não alcança a própria conta', () => {
  assert.match(ativo, /alvo\.papel === 'admin'/)
  assert.match(senha, /alvo\.papel === 'admin'/)
  // Bloquear a si mesmo trancaria o painel sem ninguém para abrir de novo.
  assert.match(ativo, /if \(id === rev\.id\) return erro/)
})

test('o bloqueio é relido antes de responder "ok"', () => {
  const i = ativo.indexOf('.update({ ativo })')
  const j = ativo.indexOf('depois.ativo !== ativo')
  assert.ok(i > 0 && j > i, 'bloqueio responde sem confirmar no banco')
})

test('a senha nova só aparece na resposta — nunca em log ou notificação', () => {
  // Contagem EXATA dos usos da variável: gerar, aplicar no Auth, devolver.
  // Qualquer uso a mais (console, notificar, insert, template com ${senha})
  // muda o número e reprova.
  const codigo = semTextoDeStrings(semComentarios(senha))
  const usos = codigo.match(/\bsenha\b/g) || []
  assert.equal(usos.length, 3, `a variável senha aparece ${usos.length}x — confira se vazou`)
  assert.match(codigo, /const senha = gerarSenha\(\)/)
  assert.match(codigo, /updateUserById\(id, \{ password: senha \}\)/)
  assert.match(codigo, /json\(\{ ok: true, senha \}\)/)
  assert.ok(!/console\./.test(codigo))
})

test('[executa] a senha é aleatória de verdade, sem caracteres ambíguos', () => {
  const fonte = trecho(fn, 'function gerarSenha(): string {', '\n}\n') + '\n}'
  const js = fonte.replace('(): string', '()')
  assert.ok(!/Math\.random/.test(js), 'senha gerada com Math.random')
  const gerarSenha = new Function(js + '\nreturn gerarSenha')()
  const vistas = new Set()
  for (let i = 0; i < 300; i++) {
    const s = gerarSenha()
    assert.equal(s.length, 10)
    assert.ok(!/[0O1Il]/.test(s), `senha com caractere ambíguo: ${s}`)
    vistas.add(s)
  }
  assert.equal(vistas.size, 300, 'senhas repetidas em 300 gerações')
})

test('conta bloqueada recebe uma mensagem que diz o que fazer', () => {
  assert.match(fn, /if \(!rev\.ativo\) return erro\('Conta bloqueada\. Fale com o suporte\.', 403\)/)
})

test('o detalhe abre mesmo antes do schema novo', () => {
  // Pedir as colunas novas aqui faria a gaveta vir vazia com o schema velho.
  const consulta = detalhe.match(/from\('creditos_transacoes'\)[\s\S]*?\.limit\(50\)/)
  assert.ok(consulta, 'não achei a consulta de transações do detalhe')
  assert.ok(!/dispositivo_id|contraparte_id|, plano/.test(consulta[0]))
})

test('a tela mantém os botões antigos e só o admin vê os novos', () => {
  const tela = trecho(ui, 'async function vRevendedores', '// ── Créditos (extrato)')
  // Regra do projeto: não remover botão sem perguntar.
  assert.match(tela, /data-acao="transferir"/)
  assert.match(tela, /data-acao="tier"/)
  assert.match(tela, /\$\{ehAdmin \? `<button class="btn-sec" data-acao="det"/)
  const det = trecho(ui, 'async function detalheRevendedor', 'async function abaMovimentacoes')
  for (const a of ['admin_revendedor_detalhe', 'revendedor_ativo', 'redefinir_senha_revendedor']) {
    assert.ok(det.includes(a), `a gaveta não chama ${a}`)
  }
  // As duas ações que tiram acesso pedem confirmação.
  assert.ok((det.match(/confirm\(/g) || []).length >= 2)
  assert.match(det, /única/)
})

// ── Tarefa 4: histórico de créditos da plataforma ─────────────────────────────

test('o schema ganha as colunas de "para onde", sem quebrar quem já rodou', () => {
  for (const col of ['dispositivo_id', 'plano', 'contraparte_id']) {
    assert.match(schema, new RegExp(`alter table public\\.creditos_transacoes add column if not exists ${col}\\b`))
  }
  assert.match(schema, /create index if not exists idx_creditos_criado/)
  // Backfill só onde ainda está nulo: rodar o schema de novo não reescreve nada.
  assert.match(schema, /where tipo = 'consumido' and plano is null/)
  assert.match(schema, /t\.tipo = 'consumido' and t\.dispositivo_id is null/)
})

test('as RPCs gravam as colunas novas', () => {
  const tr = trecho(schema, 'function public.rpc_transferir_creditos', 'end $$;')
  assert.equal((tr.match(/nota, contraparte_id\)/g) || []).length, 2, 'transferência sem contraparte')
  assert.match(tr, /p_nota_saida, p_para\)/)
  assert.match(tr, /p_nota_entrada, p_de\)/)
  const at = trecho(schema, 'function public.rpc_ativar_dispositivo(', 'end $$;')
  assert.match(at, /nota, dispositivo_id, plano\)/)
  assert.match(at, /p_dispositivo_id, p_plano\);/)
})

test('o histórico é admin-only, em lotes e honesto com o schema velho', () => {
  const s = acao('listar_movimentacoes_todas', 'criar_cliente')
  assert.match(s, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/)
  // Nada de filtro por dono: é a plataforma inteira.
  assert.ok(!/eq\('revendedor_id', rev\.id\)/.test(s))
  assert.match(s, /MAX_MOVIMENTACOES/)
  const ins = (s.match(/\.in\(/g) || []).length
  const lotes = (s.match(/emLotes\(/g) || []).length
  assert.ok(ins <= lotes, `.in() sem emLotes: ${ins} para ${lotes}`)
  assert.match(s, /if \(error\)[\s\S]*indisponivel/)
  assert.match(fn, /const MAX_MOVIMENTACOES = \d+/)
})

test('a aba só existe para o admin, e o extrato de quem não é admin não muda', () => {
  const tela = trecho(ui, 'async function vCreditos', '// ── Caixa de entrada')
  assert.match(tela, /\$\{adm \? `<div class="tabs" id="cr-tabs">/)
  assert.match(tela, /api\('listar_creditos'\)/)
  const aba = trecho(ui, 'async function abaMovimentacoes', 'const REL_DOWNLOADS')
  assert.match(aba, /api\('listar_movimentacoes_todas'/)
  assert.match(aba, /r\.indisponivel/)
  // A pílula acesa é a faixa que a aba carrega.
  const padrao = aba.match(/const st = \{ q: '', faixa: '([^']+)'/)[1]
  const acesa = aba.match(/pills\('Período',[\s\S]*?\], '([^']+)'\)/)[1]
  assert.equal(acesa, padrao)
  // Diz o que não aparece, para ninguém procurar a ativação de parceiro ali.
  assert.match(aba, /domínio parceiro não gastam crédito/)
})

// ── Tarefa 6: Downloads ───────────────────────────────────────────────────────

const fonteDownloads = trecho(ui, 'const REL_DOWNLOADS', 'async function vDownloads')
const DOWNLOADS = new Function(fonteDownloads + '\nreturn DOWNLOADS')()

test('todo download aponta para /releases/latest/', () => {
  // Versão nova entra sem ninguém editar a lista.
  assert.ok(DOWNLOADS.length >= 3)
  for (const d of DOWNLOADS) {
    assert.match(d.url, /^https:\/\/github\.com\/gabriel448\/heroplay-downloads\/releases\/latest\/download\/[\w.-]+$/, d.nome)
  }
})

test('todo link curto existe no vercel.json e leva ao MESMO arquivo', () => {
  // Link curto é o que o revendedor manda por mensagem. Se o redirect não
  // existir, ou levar a outro arquivo, o cliente baixa o app errado — ou nada.
  const redirects = new Map(vercel.redirects.map((r) => [r.source, r.destination]))
  for (const d of DOWNLOADS) {
    const caminho = d.curto.replace(/^heroplaytv\.com/, '')
    assert.ok(redirects.has(caminho), `falta o redirect ${caminho} no vercel.json`)
    assert.equal(redirects.get(caminho), d.url, `${caminho} leva a outro arquivo`)
  }
})

test('Downloads está no menu de todos os papéis', () => {
  // Sem `papeis` no item: é o revendedor que manda o link ao cliente.
  assert.match(ui, /\{ id: 'downloads', rotulo: 'Downloads', ic: 'download' \}/)
  assert.match(ui, /downloads: vDownloads/)
  const tela = trecho(ui, 'async function vDownloads', '// ── Caixa de entrada')
  assert.match(tela, /data-copiar=/)
  assert.match(tela, /Samsung e LG/)
})
