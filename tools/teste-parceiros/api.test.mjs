// Testa a API PÚBLICA do Hero (Edge Function `api`) e as chaves que a abrem.
//
// O que dá para testar sem Deno nem Supabase é justamente onde mora o risco:
// o hash da chave (calculado em DOIS arquivos, que precisam concordar) e o
// tamanho da superfície exposta.
//
// Rodar:  node tools/teste-parceiros/api.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const ler = (p) => readFileSync(new URL(p, import.meta.url), 'utf8')
const api = ler('../../supabase/functions/api/index.ts')
const painel = ler('../../supabase/functions/painel/index.ts')

/** Extrai uma função do fonte e tira as anotações de tipo. */
function extrair(src, marcador, fim) {
  const i = src.indexOf(marcador)
  assert.ok(i >= 0, `não achei "${marcador}"`)
  const j = src.indexOf(fim, i)
  assert.ok(j > i, `não achei o fim de "${marcador}"`)
  // A alternativa (`| null`) tem que sair JUNTO do `: string`, senão sobra um
  // `| null` solto e o `new Function` não compila.
  return src.slice(i, j + fim.length)
    .replace(/export /g, '')
    .replace(/:\s*(?:Promise<string>|string\[\]|string)(?:\s*\|\s*null)?/g, '')
}

test('[executa] o hash da chave é IGUAL nos dois arquivos', async () => {
  // Se divergirem, nenhuma chave criada pelo painel abre a API — e o sintoma é
  // "chave inválida" para uma chave que acabou de ser gerada.
  const daApi = extrair(api, 'export async function hashDaChave(', '\n}')
  const doPainel = extrair(painel, 'async function hashDaChave(', '\n}')
  assert.equal(
    daApi.replace(/\s+/g, ' ').trim(),
    doPainel.replace(/\s+/g, ' ').trim(),
    'as duas implementações de hashDaChave precisam ser idênticas',
  )

  // E roda de verdade, contra um vetor conhecido de SHA-256.
  const fn = new Function(`${daApi}; return hashDaChave`)()
  assert.equal(
    await fn('abc'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  )
  assert.equal((await fn('hp_teste')).length, 64)
})

test('[executa] a chave gerada tem o formato esperado e não se repete', () => {
  const gerar = new Function(`${extrair(painel, 'function gerarChaveApi(', '\n}')}; return gerarChaveApi`)()
  const uma = gerar()
  assert.match(uma, /^hp_[0-9a-f]{40}$/)
  // 20 bytes aleatórios: colisão em 100 mil é praticamente impossível, e um
  // gerador quebrado (constante) cai aqui na hora.
  const muitas = new Set(Array.from({ length: 100_000 }, gerar))
  assert.equal(muitas.size, 100_000)
})

test('a chave nunca é gravada em texto', () => {
  const criar = painel.slice(painel.indexOf("acao === 'criar_api_chave'"), painel.indexOf("acao === 'revogar_api_chave'"))
  assert.match(criar, /hash: await hashDaChave\(chave\)/)
  // O insert não pode ter um campo com a chave crua.
  assert.doesNotMatch(criar, /\bchave,\s*$/m)
  assert.doesNotMatch(criar, /valor: chave|chave_texto|segredo: chave/)
  // O prefixo visível é só o começo — nunca a chave inteira.
  assert.match(criar, /prefixo: chave\.slice\(0, 11\)/)
  // Listar não devolve o hash.
  const listar = painel.slice(painel.indexOf("acao === 'listar_api_chaves'"), painel.indexOf("acao === 'criar_api_chave'"))
  assert.doesNotMatch(listar, /select\([^)]*hash/)
})

test('a API só aceita chave — sem porta dos fundos por JWT', () => {
  const autenticar = api.slice(api.indexOf('async function autenticar('), api.indexOf('/** Ids dos clientes'))
  assert.match(autenticar, /x-api-key/)
  assert.match(autenticar, /hash', await hashDaChave\(chave\)/)
  // Nada de sessão de usuário nesta função.
  assert.doesNotMatch(api, /auth\.getUser\(\)/)
  assert.doesNotMatch(api, /grant_type=password/)
  // Chave revogada não passa.
  assert.match(autenticar, /!registro\.ativo/)
  // O papel é conferido A CADA requisição, não só ao criar a chave: conta
  // rebaixada perde acesso na hora, sem depender de alguém lembrar de revogar.
  assert.match(autenticar, /rev\.papel !== 'admin'/)
})

test('a superfície é FECHADA: nada que gaste crédito ou mexa em conta', () => {
  // Uma chave vazada não pode ativar dispositivo (consome crédito), nem criar
  // revendedor, nem transferir crédito, nem apagar nada.
  for (const proibido of [
    'rpc_ativar_dispositivo', 'vincular_dispositivo', 'renovar_dispositivo',
    'transferir_creditos', 'criar_revendedor', 'promover',
    'criar_parceiro', 'excluir_parceiro', 'parceiro_ativo',
    'salvar_servidor', 'excluir_servidor', 'migrar_url',
  ]) {
    assert.ok(!api.includes(proibido), `a API pública não pode alcançar \`${proibido}\``)
  }
  // E nenhum delete, em hipótese alguma.
  assert.doesNotMatch(api, /\.delete\(\)/)
})

test('as sete rotas combinadas, e só elas', () => {
  const rotas = [...api.matchAll(/req\.method === '(GET|POST|PATCH)' && rota\[0\] === '([a-z]+)'/g)]
    .map((m) => `${m[1]} /${m[2]}`)
  assert.deepEqual(rotas, [
    'GET /clientes',       // lista
    'GET /clientes',       // detalhe (:id)
    'GET /dispositivos',
    'GET /playlists',
    'POST /playlists',     // migrar
    'POST /playlists',     // criar
    'PATCH /playlists',
  ])
})

test('escopo de admin: enxerga a plataforma inteira, de propósito', () => {
  // Diferente da `painel`, que filtra tudo por `revendedor_id = rev.id`. Aqui a
  // chave é de admin e a API existe para administrar tudo de fora — então as
  // listagens NÃO podem estar presas ao dono da chave.
  const listar = api.slice(api.indexOf("rota[0] === 'clientes' && !rota[1]"), api.indexOf("rota[0] === 'clientes' && rota[1]"))
  assert.doesNotMatch(listar, /eq\('revendedor_id', rev\.id\)/)
  // Mas a resposta diz de QUEM é cada cliente — listagem cega seria inútil.
  assert.match(listar, /revendedor: nomeRev\.get/)
  const disp = api.slice(api.indexOf("rota[0] === 'dispositivos'"), api.indexOf("rota[0] === 'playlists' && !rota[1]"))
  assert.match(disp, /mac, device_key/)
  assert.match(disp, /revendedor: mapa\.get/)
  // O que sustenta esse escopo é o papel ser conferido a cada requisição.
  assert.match(api, /rev\.papel !== 'admin'/)
})

test('criar lista não contamina outro cliente', () => {
  const post = api.slice(api.indexOf("req.method === 'POST' && rota[0] === 'playlists' && !rota[1]"))
  // O cliente tem que existir…
  assert.match(post, /from\('clientes'\)\.select\('id'\)\.eq\('id', cliente_id\)/)
  // …e os dispositivos informados têm que ser DELE. Sem isso, a lista de um
  // cliente entraria no aparelho de outro.
  assert.match(post, /eq\('cliente_id', cliente_id\)\.in\('id', alvos\)/)
  assert.match(post, /nenhum dos dispositivo_ids pertence a este cliente/)
})

test('[executa] troca em massa casa por HOST, nunca por prefixo de URL', () => {
  // Prefixo pegaria vizinho: "old.com" casaria "old.company.com" (porque
  // "company" começa com "com") e a troca reescreveria a playlist errada.
  const filtro = new Function(`${extrair(api, 'const filtroDoHost =', "`\n)")}; return filtroDoHost`)()
  assert.equal(filtro('a.com'), 'host.eq.a.com,host.like.a.com:*')
  assert.equal(filtro('a.com:8080'), 'host.eq.a.com:8080')

  const trocar = new Function(`${extrair(api, 'function trocarHost(', '\n}')}; return trocarHost`)()
  // Preserva esquema, caminho e query — só o host muda.
  assert.equal(
    trocar('http://a.com:8080/get.php?username=u&password=p', 'b.com:9090'),
    'http://b.com:9090/get.php?username=u&password=p',
  )
  assert.equal(trocar('https://a.com/lista.m3u', 'b.com'), 'https://b.com/lista.m3u')
  assert.equal(trocar('não é url', 'b.com'), null)

  const migrar = api.slice(api.indexOf("rota[1] === 'migrar'"), api.indexOf("req.method === 'POST' && rota[0] === 'playlists' && !rota[1]"))
  assert.match(migrar, /or\(filtroDoHost\(de\)\)/)
  assert.doesNotMatch(migrar, /startsWith\(/)
})

test('troca em massa é PRÉVIA por padrão', () => {
  const migrar = api.slice(api.indexOf("rota[1] === 'migrar'"), api.indexOf("req.method === 'POST' && rota[0] === 'playlists' && !rota[1]"))
  // Só altera com `aplicar: true` explícito. Um corpo esquecido não reescreve
  // as listas da plataforma inteira.
  assert.match(migrar, /const aplicar = body\.aplicar === true/)
  assert.match(migrar, /if \(aplicar\) \{/)
  assert.match(migrar, /de === para/)          // recusa origem igual ao destino
  // Pagina por cursor: cada volta anda, sem repetir o mesmo lote.
  assert.match(migrar, /q\.gt\('id', cursor\)/)
  assert.match(migrar, /proximo: restam_mais/)
  // E devolve os dois números, para dar pra conferir em vez de confiar.
  assert.match(migrar, /encontradas: afetadas\.length/)
  assert.match(migrar, /alteradas,/)
})

test('toda troca de URL mantém host e free_dns em dia', () => {
  // O `host` em texto claro é o que casa parceiro, conta device por domínio e
  // fecha fatura. Deixar ele para trás foi bug real no `migrar_url` do painel.
  const aplicar = api.slice(api.indexOf('async function aplicarHostNaPlaylist'), api.indexOf('Deno.serve'))
  assert.match(aplicar, /host: novoHost/)
  assert.match(aplicar, /free_dns: !!parceiro/)
  assert.match(aplicar, /url_cifrada: await cifrar\(novaUrl\)/)
  // Um único ponto faz isso — PATCH e migração em massa passam os dois por aqui.
  const patch = api.slice(api.indexOf("req.method === 'PATCH'"))
  assert.match(patch, /aplicarHostNaPlaylist\(/)
  const migrar = api.slice(api.indexOf("rota[1] === 'migrar'"), api.indexOf("req.method === 'POST' && rota[0] === 'playlists' && !rota[1]"))
  assert.match(migrar, /aplicarHostNaPlaylist\(/)
})

test('a URL da playlist entra CIFRADA, como no painel', () => {
  const post = api.slice(api.indexOf("req.method === 'POST' && rota[0] === 'playlists'"))
  assert.match(post, /url_cifrada: await cifrar\(lista_url\)/)
  assert.doesNotMatch(post, /url: lista_url/)
  // E o host em texto claro acompanha — é por ele que se casa parceiro e se
  // conta device por domínio.
  assert.match(post, /host, free_dns: !!parceiro/)
})

test('a plataforma nao pode exigir JWT na funcao da API', () => {
  // A API autentica por CHAVE. Com verify_jwt ligado, o gateway do Supabase
  // derruba a requisicao antes da funcao rodar e responde "Invalid JWT" —
  // a API inteira fica inalcancavel e NENHUM teste de codigo percebe, porque
  // o codigo esta certo. Ja aconteceu: a funcao subiu sem esta entrada.
  const cfg = readFileSync(new URL('../../supabase/config.toml', import.meta.url), 'utf8')
  const bloco = cfg.slice(cfg.indexOf('[functions.api]'))
  assert.ok(bloco.startsWith('[functions.api]'), 'faltou [functions.api] no config.toml')
  assert.match(bloco.split('[').slice(0, 2).join('['), /verify_jwt\s*=\s*false/)
})
