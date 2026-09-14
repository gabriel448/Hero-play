// Testa a separação "Clientes" (plataforma) x "Meus clientes" (do operador)
// no painel de ADMIN.
//
// O risco aqui não é a tela nova — é a ANTIGA mudar de escopo sem ninguém
// perceber. `listar_clientes` tem que continuar respondendo "os meus",
// inclusive para o admin, senão a aba que ele já usa todo dia passa a mostrar
// a plataforma inteira em silêncio.
//
// Rodar:  node tools/teste-parceiros/painel-clientes.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const ler = (p) => readFileSync(new URL(p, import.meta.url), 'utf8')
const fn = ler('../../supabase/functions/painel/index.ts')
const ui = ler('../../painel/painel.js')

const acao = (nome, ate) => fn.slice(fn.indexOf(`acao === '${nome}'`), fn.indexOf(`acao === '${ate}'`))

test('listar_clientes continua sendo SÓ os do operador, inclusive admin', () => {
  const trecho = acao('listar_clientes', 'listar_clientes_todos')
  assert.match(trecho, /eq\('revendedor_id', rev\.id\)/)
  // Se alguém puser um `if (ehAdmin)` aqui, a aba "Meus clientes" deixa de ser
  // "meus" — e a separação inteira perde o sentido.
  assert.doesNotMatch(trecho, /ehAdmin/)
})

test('listar_clientes_todos é admin-only e diz de quem é cada cliente', () => {
  const trecho = acao('listar_clientes_todos', 'admin_cliente_detalhe')
  assert.match(trecho, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/)
  // Sem filtro por dono: é a plataforma inteira.
  assert.doesNotMatch(trecho, /eq\('revendedor_id', rev\.id\)/)
  // Mas com o dono na resposta — lista de centenas de nomes sem contexto não
  // serve para nada.
  assert.match(trecho, /revendedor: donos\.get/)
  assert.match(trecho, /meu: c\.revendedor_id === rev\.id/)
  // Contagens numa consulta cada, não uma por cliente.
  assert.match(trecho, /in\('cliente_id', ids\)/)
  assert.match(trecho, /MAX_CLIENTES_PLATAFORMA/)
})

test('o detalhe de qualquer cliente é admin-only e não vaza URL', () => {
  const trecho = acao('admin_cliente_detalhe', 'cliente_detalhe')
  assert.match(trecho, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/)
  // Credencial de servidor de outro revendedor não precisa aparecer numa tela
  // de consulta.
  assert.doesNotMatch(trecho, /url_cifrada|decifrar/)
  assert.match(trecho, /mac, device_key/)
})

test('cliente_detalhe (o que escreve) continua exigindo ser do operador', () => {
  const trecho = fn.slice(fn.indexOf("acao === 'cliente_detalhe'"), fn.indexOf("acao === 'vincular_dispositivo'"))
  assert.match(trecho, /clienteDoRev\(cliente_id\)/)
})

test('o menu do admin tem as duas abas; o revendedor tem uma só', () => {
  assert.match(ui, /\{ id: 'todosclientes', rotulo: 'Clientes', ic: 'users', papeis: \['admin'\] \}/)
  assert.match(ui, /\{ id: 'clientes', rotulo: 'Meus clientes', ic: 'users', papeis: \['admin'\] \}/)
  assert.match(ui, /\{ id: 'clientes', rotulo: 'Clientes', ic: 'users', papeis: \['master', 'reseller'\] \}/)
  assert.match(ui, /todosclientes: vTodosClientes/)
})

test('a tela nova é de CONSULTA: não escreve nada', () => {
  const tela = ui.slice(ui.indexOf('async function vTodosClientes'), ui.indexOf('async function vCliente('))
  assert.ok(tela.length > 0, 'não achei vTodosClientes')
  assert.match(tela, /me\.papel !== 'admin'/)
  for (const escrita of ['criar_cliente', 'add_playlist', 'vincular_dispositivo', 'excluir_', 'remover_']) {
    assert.ok(!tela.includes(escrita), `a visão de plataforma não pode chamar \`${escrita}\``)
  }
  assert.match(tela, /listar_clientes_todos/)
  assert.match(tela, /admin_cliente_detalhe/)
})

test('o cache da visão de plataforma é invalidado quando os números mudam', () => {
  // Ela mostra contagem de device e playlist: criar cliente, vincular aparelho
  // ou mexer em lista muda o que está na tela.
  for (const gatilho of [
    /criar_cliente[\s\S]{0,80}invalidar\('clientes', 'todosclientes'\)/,
    /invalidar\('dispositivos', 'todosclientes', 'cliente:'/,
    /invalidar\('playlists', 'todosclientes'\)/,
  ]) {
    assert.match(ui, gatilho)
  }
})

test('o título da aba acompanha o menu', () => {
  // Menu dizendo "Meus clientes" e tela dizendo "Clientes" faria o admin achar
  // que está vendo a plataforma quando não está.
  assert.match(ui, /const titulo = me\.papel === 'admin' \? 'Meus clientes' : 'Clientes'/)
})

test('cliente sem revenda vem como null, nao como traco', () => {
  // O backend mandava '—'. Com isso a tela nao tinha como distinguir
  // "self-serve" de "revendedor com nome vazio", e aparecia um traco solto
  // onde deveria estar o dono — que foi exatamente o que o admin estranhou.
  const todos = acao('listar_clientes_todos', 'admin_cliente_detalhe')
  assert.match(todos, /revendedor: donos\.get\(c\.revendedor_id\) \|\| null/)
  const det = acao('admin_cliente_detalhe', 'cliente_detalhe')
  assert.match(det, /revendedor: dono \? \(dono\.nome \|\| dono\.usuario\) : null/)
})

test('a tela chama self-serve pelo nome, em vez de mostrar um traco', () => {
  const tela = ui.slice(ui.indexOf('async function vTodosClientes'), ui.indexOf('async function vCliente('))
  assert.match(tela, /Self-serve/)
  // Ramo explicito: null cai no rotulo, nao num fallback generico.
  assert.match(tela, /c\.revendedor$\s*\?/m)
  assert.match(tela, /d\.cliente\.revendedor$\s*\?/m)
  // E da pra filtrar por eles na busca.
  assert.match(tela, /c\.revendedor \|\| 'self-serve'/)
})

test('o detalhe e conteudo, nao nota de rodape', () => {
  // `.sv-ajuda` e 11px, o estilo de texto auxiliar. A gaveta inteira estava
  // nele — dai a queixa de letra pequena. Conteudo tem classe propria.
  const tela = ui.slice(ui.indexOf('async function vTodosClientes'), ui.indexOf('async function vCliente('))
  assert.ok(!tela.includes('sv-ajuda'), 'a gaveta voltou para o estilo de texto auxiliar')
  for (const c of ['tc-det', 'tc-sec', 'tc-linha', 'tc-rot', 'tc-val']) {
    assert.ok(tela.includes(c), `faltou .${c}`)
  }
})

test('toda classe tc-* usada na tela existe no CSS', () => {
  // Ja inventei classe que nao existia nesta mesma tela uma vez; o sintoma e
  // silencioso (renderiza sem estilo nenhum).
  const css = ler('../../painel/painel.css')
  const usadas = new Set((ui.match(/tc-[a-z-]+/g) || []).filter((c) => !c.startsWith('tc-busca') && c !== 'tc-sub' && c !== 'tc-cont' && c !== 'tc-lista'))
  for (const c of usadas) {
    const achou = [' ', ',', ':', '{'].some((fim) => css.includes('.' + c + fim))
    assert.ok(achou, `.${c} nao existe em painel.css`)
  }
})
