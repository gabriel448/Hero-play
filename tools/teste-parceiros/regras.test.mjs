// Testa as REGRAS DE DOMÍNIO dos parceiros (Free DNS) da Edge Function `painel`.
//
// Não há Deno nem Supabase aqui, então o teste roda só a parte PURA — que é
// justamente onde mora o risco: normalizar o que o admin/Player Hub digita e
// decidir se um parceiro cobre o host de uma playlist.
//
// As funções são EXTRAÍDAS do próprio `index.ts` (não copiadas): se alguém
// mudar a forma delas, a extração falha e o teste acusa, em vez de continuar
// validando uma cópia velha.
//
// Rodar:  node tools/teste-parceiros/regras.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const FONTE = new URL('../../supabase/functions/painel/index.ts', import.meta.url)
const src = readFileSync(FONTE, 'utf8')

/** Pega um trecho do fonte por marcador e tira as anotações de tipo. */
function extrair(marcador, fim) {
  const i = src.indexOf(marcador)
  assert.ok(i >= 0, `não achei "${marcador}" em painel/index.ts — a função mudou de forma?`)
  const j = src.indexOf(fim, i)
  assert.ok(j > i, `não achei o fim de "${marcador}"`)
  // Tira as anotações de tipo — só as formas que aparecem nestas funções. A
  // alternativa (`| null`) tem que sair JUNTO, senão sobra um `| null` solto.
  return src.slice(i, j + fim.length)
    .replace(/:\s*(?:Set<string>|string\[\]|string)(?:\s*\|\s*null)?/g, '')
}

const codigo = [
  extrair('const semPorta =', "'')"),
  extrair('const filtroPlaylistsDeParceiros =', ").join(',')"),
  extrair('function parceiroQueCobre(', '\n}'),
  extrair('function normalizarDominio(', '\n}'),
].join('\n\n')

const { semPorta, filtroPlaylistsDeParceiros, parceiroQueCobre, normalizarDominio } =
  new Function(`${codigo}; return { semPorta, filtroPlaylistsDeParceiros, parceiroQueCobre, normalizarDominio }`)()

test('normalizarDominio tira esquema, www, caminho, usuário e senha', () => {
  assert.equal(normalizarDominio('exemplo.com'), 'exemplo.com')
  assert.equal(normalizarDominio('https://exemplo.com'), 'exemplo.com')
  assert.equal(normalizarDominio('http://www.exemplo.com'), 'exemplo.com')
  assert.equal(normalizarDominio('  HTTP://WWW.Exemplo.COM  '), 'exemplo.com')
  assert.equal(normalizarDominio('http://exemplo.com/get.php?username=a&password=b'), 'exemplo.com')
  assert.equal(normalizarDominio('http://user:senha@exemplo.com/x'), 'exemplo.com')
  assert.equal(normalizarDominio(''), '')
  assert.equal(normalizarDominio('   '), '')
})

test('normalizarDominio PRESERVA a porta (o Hero casa por host[:porta])', () => {
  assert.equal(normalizarDominio('http://exemplo.com:8080/get.php'), 'exemplo.com:8080')
  assert.equal(normalizarDominio('1.2.3.4:25461'), '1.2.3.4:25461')
})

test('parceiro sem porta cobre a playlist em QUALQUER porta', () => {
  const cadastrados = new Set(['exemplo.com'])
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com'), 'exemplo.com')
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com:8080'), 'exemplo.com')
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com:25461'), 'exemplo.com')
  assert.equal(parceiroQueCobre(cadastrados, 'outro.com:8080'), null)
})

test('parceiro COM porta casa exato — não vaza para outra porta', () => {
  const cadastrados = new Set(['exemplo.com:8080'])
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com:8080'), 'exemplo.com:8080')
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com:9090'), null)
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com'), null)
})

test('o exato ganha do domínio nu quando os dois estão cadastrados', () => {
  const cadastrados = new Set(['exemplo.com', 'exemplo.com:8080'])
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com:8080'), 'exemplo.com:8080')
  assert.equal(parceiroQueCobre(cadastrados, 'exemplo.com:9090'), 'exemplo.com')
})

test('filtro PostgREST pede a porta curinga só para domínio sem porta', () => {
  assert.equal(filtroPlaylistsDeParceiros(['a.com']), 'host.eq.a.com,host.like.a.com:*')
  assert.equal(filtroPlaylistsDeParceiros(['a.com:8080']), 'host.eq.a.com:8080')
  assert.equal(
    filtroPlaylistsDeParceiros(['a.com', 'b.com:1']),
    'host.eq.a.com,host.like.a.com:*,host.eq.b.com:1',
  )
  assert.equal(filtroPlaylistsDeParceiros([]), '')
})

test('semPorta', () => {
  assert.equal(semPorta('a.com:8080'), 'a.com')
  assert.equal(semPorta('a.com'), 'a.com')
  assert.equal(semPorta('1.2.3.4:25461'), '1.2.3.4')
})

// ─── Garantias do `migrar_url` (troca de DNS em massa) ───────────────────────
// Aqui a checagem é sobre o FONTE: o corpo da ação depende de banco e sessão,
// então não dá para executar. O que importa é que as travas não sumam.
const migrar = src.slice(src.indexOf("if (acao === 'migrar_url')"), src.indexOf("// ── SUPORTE"))

test('escopo global existe, é opt-in e só admin', () => {
  assert.ok(migrar.length > 0, 'não achei a ação migrar_url')
  assert.match(migrar, /const todos = body\.escopo === 'todos'/)
  assert.match(migrar, /if \(todos && !ehAdmin\) return erro\('apenas admin/)
  // O padrão NÃO pode virar global: sem opt-in continua "meus clientes".
  assert.match(migrar, /if \(!todos\) \{[\s\S]*?eq\('revendedor_id', rev\.id\)/)
})

test('pré-filtra por host, o que também mata o falso positivo do prefixo', () => {
  assert.match(migrar, /const hostOrigem = hostDe\(origem\)/)
  assert.match(migrar, /q\.or\(filtroPlaylistsDeParceiros\(\[hostOrigem\]\)\)/)
})

test('pagina por cursor — cada volta anda, nao repete o mesmo lote', () => {
  assert.match(migrar, /MAX_MIGRACAO/)
  assert.match(migrar, /const apos = String\(body\.apos \|\| ''\)\.trim\(\)/)
  assert.match(migrar, /q\.order\('id', \{ ascending: true \}\)/)
  assert.match(migrar, /if \(apos\) q = q\.gt\('id', apos\)/)
  // O cursor e o que garante terminacao: linha que casa o HOST mas nao casa o
  // PREFIXO (ex.: https quando a passada e http) nunca sai do filtro, entao
  // "consultar de novo" ficaria preso nela para sempre.
  assert.match(migrar, /proximo: restam_mais \? proximo : null/)
})

test('a migração mantém host e free_dns em dia', () => {
  assert.match(migrar, /const novoHost = hostDe\(nova\)/)
  assert.match(migrar, /host: novoHost, free_dns: !!novoParceiro/)
})
