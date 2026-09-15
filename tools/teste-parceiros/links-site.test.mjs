// Todo endereço heroplaytv.com/... que o app de TV, o Flutter, o painel ou o
// site MOSTRAM tem que abrir.
//
// Existe por um 404 que durou meses: a tela de onboarding da TV manda digitar
// "heroplaytv.com/upload" (em três lugares), e o site só publicava
// "upload.html" — a Vercel, sem `cleanUrls`, não troca um pelo outro. Todo
// cliente que seguiu a instrução caiu num erro. O QR funcionava, porque aponta
// para upload.html; só o endereço que a pessoa DIGITA estava quebrado, e por
// isso ninguém viu.
//
// "Abre" aqui é: existe um arquivo publicado nesse caminho, ou um redirect, ou
// um rewrite no vercel.json. É checagem estática — não depende de rede.
//
// Rodar:  node tools/teste-parceiros/links-site.test.mjs
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const raiz = fileURLToPath(new URL('../../', import.meta.url))
const vercel = JSON.parse(readFileSync(join(raiz, 'vercel.json'), 'utf8'))
const redirects = new Set((vercel.redirects || []).map((r) => r.source))
const rewrites = new Set((vercel.rewrites || []).map((r) => r.source))

// Links que sabemos quebrados e que dependem de trabalho que ainda não foi feito.
// Cada um diz POR QUE está aqui. Quando o caminho passar a existir, o teste
// reprova para a exceção ser apagada — senão a lista vira um lugar para
// esconder link quebrado.
const PENDENTES = new Map([
  ['/pagar.html', 'website/ativacao.html manda para a página de pagamento, que ainda não existe (tarefa de pagamento)'],
])

// Onde procurar: tudo que chega a um usuário.
function arquivos() {
  const lista = []
  const add = (dir, filtro, recursivo = false) => {
    const abs = join(raiz, dir)
    if (!existsSync(abs)) return
    for (const nome of readdirSync(abs, { recursive: recursivo })) {
      const p = join(abs, String(nome))
      if (filtro.test(String(nome)) && statSync(p).isFile()) lista.push([join(dir, String(nome)), p])
    }
  }
  add('tv-app', /\.js$/)
  add('lib', /\.dart$/, true)
  add('painel', /\.js$/)
  add('website', /\.html$/)
  add('website/assets', /\.js$/)
  return lista
}

// Caminhos citados, com o arquivo de origem de cada um.
function citados() {
  const achados = new Map()
  for (const [rel, abs] of arquivos()) {
    const txt = readFileSync(abs, 'utf8')
    for (const m of txt.matchAll(/heroplaytv\.com(\/[A-Za-z0-9_./-]*)?/g)) {
      const caminho = (m[1] || '/').replace(/\.+$/, '') || '/'
      if (!achados.has(caminho)) achados.set(caminho, new Set())
      achados.get(caminho).add(rel)
    }
  }
  return achados
}

// O caminho abre na Vercel? Sem `.html` implícito: é exatamente essa suposição
// que deixou /upload quebrado.
function abre(caminho) {
  if (caminho === '/' || caminho === '') return true
  if (redirects.has(caminho) || rewrites.has(caminho)) return true
  // O build copia painel/ para website/painel/ (vercel.json → buildCommand).
  const base = caminho.startsWith('/painel') ? join(raiz, 'painel', caminho.slice('/painel'.length)) : join(raiz, 'website', caminho)
  if (existsSync(base) && statSync(base).isFile()) return true
  if (existsSync(join(base, 'index.html'))) return true
  return false
}

test('a varredura acha os links de verdade (senão passaria sem testar nada)', () => {
  const c = citados()
  for (const esperado of ['/upload', '/upload.html', '/fire']) {
    assert.ok(c.has(esperado), `a varredura não achou ${esperado} — mudou o formato do link?`)
  }
})

test('todo endereço heroplaytv.com/... citado abre', () => {
  const quebrados = []
  for (const [caminho, onde] of citados()) {
    if (PENDENTES.has(caminho)) continue
    if (!abre(caminho)) quebrados.push(`${caminho}  (citado em ${[...onde].join(', ')})`)
  }
  assert.deepEqual(quebrados, [], 'link que o usuário vê e que dá 404:\n  ' + quebrados.join('\n  '))
})

test('o endereço que a TV manda digitar abre', () => {
  // O caso que motivou este arquivo, travado por nome.
  assert.ok(abre('/upload'), 'heroplaytv.com/upload voltou a dar 404')
  const alvo = (vercel.rewrites || []).find((r) => r.source === '/upload')
  assert.ok(alvo, 'sem o rewrite /upload → /upload.html')
  // Rewrite, e não redirect: serve a página no próprio endereço e mantém o
  // ?mac=&key= que o QR leva.
  assert.equal(alvo.destination, '/upload.html')
  assert.ok(existsSync(join(raiz, 'website', 'upload.html')))
})

test('toda pendência ainda é necessária', () => {
  for (const [caminho, motivo] of PENDENTES) {
    assert.ok(!abre(caminho), `${caminho} já abre — apague a exceção (${motivo})`)
  }
})
