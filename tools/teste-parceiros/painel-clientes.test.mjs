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
  // Contagens em lote, não uma consulta por cliente.
  assert.match(trecho, /emLotes\(ids,/)
  assert.match(trecho, /in\('cliente_id', parte\)/)
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
    /invalidar\('dispositivos', 'todosdispositivos', 'todosclientes', 'cliente:'/,
    /invalidar\('playlists', 'todasplaylists', 'todosclientes'\)/,
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

// ── Dispositivos e Playlists: mesma divisao dos Clientes ────────────────────

test('listar_dispositivos e listar_playlists continuam sendo SO do operador', () => {
  // Mesmo risco da `listar_clientes`: um `if (ehAdmin)` aqui e a aba de
  // trabalho do admin passa a mostrar a plataforma inteira em silencio.
  const disp = acao('listar_dispositivos', 'listar_playlists')
  assert.match(disp, /eq\('revendedor_id', rev\.id\)/)
  assert.doesNotMatch(disp, /ehAdmin/)
  const pls = acao('listar_playlists', 'listar_dispositivos_todos')
  assert.match(pls, /eq\('revendedor_id', rev\.id\)/)
  assert.doesNotMatch(pls, /ehAdmin/)
})

test('as visoes de plataforma sao admin-only e dizem de quem e cada linha', () => {
  const disp = acao('listar_dispositivos_todos', 'listar_playlists_todos')
  assert.match(disp, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/)
  assert.doesNotMatch(disp, /eq\('revendedor_id', rev\.id\)/)
  assert.match(disp, /revendedor: donos\.get/)
  assert.match(disp, /MAX_LINHAS_PLATAFORMA/)

  const pls = acao('listar_playlists_todos', 'migrar_url')
  assert.match(pls, /if \(!ehAdmin\) return erro\('apenas admin', 403\)/)
  assert.doesNotMatch(pls, /eq\('revendedor_id', rev\.id\)/)
  assert.match(pls, /revendedor: donos\.get/)
  assert.match(pls, /MAX_LINHAS_PLATAFORMA/)
})

test('a visao de plataforma NAO devolve URL de playlist', () => {
  // Credencial de servidor de outro revendedor nao aparece numa tela de
  // consulta. Quem precisa da URL usa a API por chave, onde o acesso e nominal.
  // Mesma regra ja aplicada na `admin_cliente_detalhe`.
  const pls = acao('listar_playlists_todos', 'migrar_url')
  assert.doesNotMatch(pls, /url_cifrada|decifrar/)
  assert.match(pls, /host: pl\.host/)
})

test('consulta por muitos IDs vai em lotes', () => {
  // `.in(...)` monta a query string inteira na URL: 2000 UUIDs passam de 70 KB
  // e o pedido morre. As visoes de plataforma buscam exatamente nessa escala.
  assert.match(fn, /async function emLotes/)
  const todas = [
    acao('listar_clientes_todos', 'admin_cliente_detalhe'),
    acao('listar_dispositivos_todos', 'listar_playlists_todos'),
    acao('listar_playlists_todos', 'migrar_url'),
  ]
  for (const trecho of todas) {
    const ins = trecho.match(/\.in\(/g) || []
    const lotes = trecho.match(/emLotes\(/g) || []
    assert.ok(ins.length <= lotes.length,
      `sobrou um .in() sem emLotes: ${ins.length} in() para ${lotes.length} emLotes()`)
  }
})

test('o menu do admin divide as tres abas; o revendedor tem uma de cada', () => {
  for (const linha of [
    /\{ id: 'todosdispositivos', rotulo: 'Dispositivos', ic: 'monitor', papeis: \['admin'\] \}/,
    /\{ id: 'dispositivos', rotulo: 'Meus dispositivos', ic: 'monitor', papeis: \['admin'\] \}/,
    /\{ id: 'dispositivos', rotulo: 'Dispositivos', ic: 'monitor', papeis: \['master', 'reseller'\] \}/,
    /\{ id: 'todasplaylists', rotulo: 'Playlists', ic: 'listv', papeis: \['admin'\] \}/,
    /\{ id: 'playlists', rotulo: 'Minhas playlists', ic: 'listv', papeis: \['admin'\] \}/,
    /\{ id: 'playlists', rotulo: 'Playlists', ic: 'listv', papeis: \['master', 'reseller'\] \}/,
    /todosdispositivos: vTodosDispositivos/,
    /todasplaylists: vTodasPlaylists/,
  ]) {
    assert.match(ui, linha)
  }
})

test('as telas de plataforma sao de CONSULTA: nao escrevem e nao migram', () => {
  const corta = (de, ate) => ui.slice(ui.indexOf(de), ui.indexOf(ate))
  const telas = {
    vTodosDispositivos: corta('async function vTodosDispositivos', '// ── Listas da PLATAFORMA'),
    vTodasPlaylists: corta('async function vTodasPlaylists', 'async function modalVincularGlobal'),
  }
  for (const [nome, tela] of Object.entries(telas)) {
    assert.ok(tela.length > 0, `nao achei ${nome}`)
    assert.match(tela, /me\.papel !== 'admin'/)
    for (const escrita of ['excluir_playlist', 'vincular_dispositivo', 'modalVincularGlobal', 'modalMigrarUrl', 'migrar_url']) {
      assert.ok(!tela.includes(escrita), `${nome} nao pode chamar \`${escrita}\``)
    }
  }
  // Migrar em massa daqui exigiria um escopo "todos", que foi REMOVIDO de
  // proposito (deixava reescrever playlist de cliente dos outros).
  assert.ok(!telas.vTodasPlaylists.includes('Migrar URL'))
})

test('os titulos das abas do operador acompanham o menu do admin', () => {
  assert.match(ui, /me\.papel === 'admin' \? 'Meus dispositivos' : 'Dispositivos'/)
  assert.match(ui, /me\.papel === 'admin' \? 'Minhas playlists' : 'Playlists'/)
})

test('o cache das visoes de plataforma e invalidado quando os numeros mudam', () => {
  for (const gatilho of [
    /invalidar\('dispositivos', 'todosdispositivos', 'todosclientes', 'cliente:'/,
    /invalidar\('playlists', 'todasplaylists', 'todosclientes'\)/,
    // Mexer em parceiro muda o Free DNS das listas e ativa aparelhos.
    /invalidar\('parceiros', 'dispositivos', 'todosdispositivos', 'todasplaylists'\)/,
  ]) {
    assert.match(ui, gatilho)
  }
})

test('self-serve tem um so lugar que decide como e mostrado', () => {
  // Se cada tela inventar o proprio fallback, uma delas volta a mostrar traco.
  assert.match(ui, /const celRevenda = \(r\) => r \? esc\(r\) : '<span class="tc-self">Self-serve<\/span>'/)
  for (const tela of ['vTodosDispositivos', 'vTodasPlaylists']) {
    const i = ui.indexOf('async function ' + tela)
    assert.ok(ui.slice(i, i + 6000).includes('celRevenda('), `${tela} nao usa celRevenda`)
  }
})
