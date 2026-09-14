// Guarda de sintaxe do painel.
//
// Existe por um bug que chegou ao ar: declarei um `const fmtDataHora` que já
// existia no arquivo. Duas declarações iguais no mesmo escopo fazem o MÓDULO
// INTEIRO não executar — o painel ficava preso em "Carregando…" para sempre,
// sem nada na tela dizendo por quê.
//
// E passou pela minha verificação porque `node --check painel/painel.js`
// parseia o arquivo como SCRIPT clássico. O `painel.js` é um MÓDULO (tem
// `import`, e o index.html o carrega com `type="module"`), e as regras de
// redeclaração são checadas no parse do módulo. O check certo é
// `node --input-type=module --check`.
//
// Rodar:  node tools/teste-parceiros/painel-sintaxe.test.mjs
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const caminho = fileURLToPath(new URL('../../painel/painel.js', import.meta.url))
const src = readFileSync(caminho, 'utf8')
const html = readFileSync(fileURLToPath(new URL('../../painel/index.html', import.meta.url)), 'utf8')

test('painel.js é válido COMO MÓDULO, que é como o navegador o carrega', () => {
  // `node --check` (script clássico) não basta: foi ele que deixou a
  // redeclaração passar.
  try {
    execFileSync(process.execPath, ['--input-type=module', '--check'], {
      input: src, stdio: ['pipe', 'pipe', 'pipe'],
    })
  } catch (e) {
    assert.fail('painel.js não parseia como módulo:\n' + String(e.stderr || e.message))
  }
})

test('o index.html realmente carrega painel.js como módulo', () => {
  // Se algum dia virar script clássico, o teste acima estaria checando a
  // gramática errada — e o `import` no topo nem funcionaria.
  assert.match(html, /<script[^>]+type="module"[^>]*painel\.js|<script[^>]+painel\.js[^>]*type="module"/)
})

test('nenhum nome declarado duas vezes no topo do arquivo', () => {
  // A mensagem do parser é clara, mas só aparece no console do navegador.
  // Aqui o teste diz QUAL nome, que é o que encurta o conserto.
  const nomes = new Map()
  const re = /^(?:const|let|function|async function|class)\s+([A-Za-z_$][\w$]*)/gm
  for (const m of src.matchAll(re)) {
    nomes.set(m[1], (nomes.get(m[1]) || 0) + 1)
  }
  const repetidos = [...nomes].filter(([, n]) => n > 1).map(([k]) => k)
  assert.deepEqual(repetidos, [], `declarado mais de uma vez no topo: ${repetidos.join(', ')}`)
})

test('toda view do roteador existe de fato', () => {
  // Uma entrada apontando para função inexistente só estoura quando o usuário
  // clica na aba — e o sintoma é a tela em branco, não um erro.
  const rota = src.slice(src.indexOf('const fn = {'), src.indexOf('}[v]') + 4)
  assert.ok(rota.length > 0, 'não achei o roteador')
  const vistas = [...rota.matchAll(/(\w+):\s*(v[A-Za-z]\w*)/g)].map((m) => m[2])
  assert.ok(vistas.length > 5, 'roteador com poucas views — o parse falhou')
  for (const v of new Set(vistas)) {
    const declarada = new RegExp(`(?:async function|function|const)\\s+${v}\\b`).test(src)
    assert.ok(declarada, `o roteador aponta para ${v}, que não existe`)
  }
})

test('todo id do menu tem uma view no roteador', () => {
  // Item de menu sem rota abre uma tela vazia, sem erro nenhum.
  const nav = src.slice(src.indexOf('const NAV = ['), src.indexOf('\n]', src.indexOf('const NAV = [')))
  const ids = [...nav.matchAll(/\{ id: '([a-z]+)'/g)].map((m) => m[1])
  assert.ok(ids.length > 5, 'NAV com poucos itens — o parse falhou')
  const rota = src.slice(src.indexOf('const fn = {'), src.indexOf('}[v]') + 4)
  for (const id of new Set(ids)) {
    assert.match(rota, new RegExp(`\\b${id}:`), `o menu tem "${id}", mas o roteador não`)
  }
})

test('todo ícone usado no menu existe', () => {
  // `IC[nome]` indefinido injeta "undefined" dentro do <svg> — some o ícone e
  // não há erro.
  const ic = src.slice(src.indexOf('const IC = {'), src.indexOf('const svg ='))
  const nav = src.slice(src.indexOf('const NAV = ['), src.indexOf('\n]', src.indexOf('const NAV = [')))
  for (const m of nav.matchAll(/ic: '(\w+)'/g)) {
    assert.match(ic, new RegExp(`^\\s+${m[1]}:`, 'm'), `o menu usa o ícone "${m[1]}", que não existe em IC`)
  }
})
