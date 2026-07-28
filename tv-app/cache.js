/* ============================================================================
   Hero Play TV — CACHE local (IndexedDB). Dois conteúdos:

   1) CATÁLOGO parseado. Parsear um M3U de 46 MB / 167k itens leva ~14s na TV.
      Isso NÃO dá pra otimizar em código (a TV é ~30x mais lenta que um desktop).
      A saída é parsear UMA vez e reaproveitar nos boots seguintes.
      Guardamos só as listas PLANAS ({canais, filmes, series}) — o `catalogo` e o
      `indice` são reconstruídos por Lista.montarCatalogo() na leitura (barato).

   2) METADADOS do TMDB (pôster, logo-título, sinopse/nota/elenco). Antes ficavam
      só em memória: a cada boot o app re-perguntava o pôster de CADA título ao
      TMDB — lento e visível ("a foto carrega de novo"). Agora persistimos, então
      no 2º boot o pôster aparece na hora, sem rede.

   ⚠️ Tudo aqui é best-effort e INSTRUMENTADO: `CacheLista.status` guarda o que
   aconteceu (ok / nome do erro / tempo), porque na TV não temos DevTools e
   precisamos ver no painel de Diagnóstico por que o cache falhou.
   ============================================================================ */
const CacheLista = (() => {
  const DB = 'heroplay', LOJA = 'catalogo', META = 'meta', CHAVE = 'atual';
  const DB_VERSAO = 2;      // 2 = adicionou a store `meta` (TMDB)
  const VERSAO = 1;         // suba isto se o formato do objeto mudar
  const VALIDADE_H = 24;    // re-checa a lista depois disso

  // Diagnóstico visível no painel (sem DevTools na TV).
  const status = { ler: '—', gravar: '—', msLer: 0, msGravar: 0, meta: '—' };

  // Conexão ÚNICA e reaproveitada. Antes cada operação abria e fechava o banco:
  // num boot são 3+ aberturas (meta, catálogo, gravação) e, quando o firmware
  // pendura o open(), cada uma custava os 15s do timeout — o boot inteiro ficava
  // ~45s parado na tela de loading. Agora abrimos UMA vez; se falhar, marcamos
  // `_morto` e as chamadas seguintes voltam na hora (o app segue sem cache, em
  // vez de esperar de novo). Se o open pendurado responder depois, adotamos a
  // conexão e o cache volta a funcionar sozinho.
  let _conn = null, _abrindo = null, _morto = null;
  function _abrir() {
    if (_conn) return Promise.resolve({ db: _conn, err: null });
    if (_morto) return Promise.resolve({ db: null, err: _morto });
    if (_abrindo) return _abrindo;
    _abrindo = new Promise((resolve) => {
      let pronto = false;
      const fim = (v, err) => {
        if (v) { _conn = v; _morto = null; } else if (err) { _morto = err; }
        if (!pronto) { pronto = true; _abrindo = null; resolve({ db: v, err: err || null }); }
      };
      try {
        if (!self.indexedDB) return fim(null, 'sem indexedDB');
        const req = indexedDB.open(DB, DB_VERSAO);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains(LOJA)) db.createObjectStore(LOJA);
          if (!db.objectStoreNames.contains(META)) db.createObjectStore(META);
        };
        req.onsuccess = () => {
          const db = req.result;
          // Solta a conexão se o banco for fechado por fora (upgrade de versão em
          // outra instância) — senão ficaríamos com um handle morto p/ sempre.
          try {
            db.onversionchange = () => { try { db.close(); } catch (_) {} if (_conn === db) _conn = null; };
            db.onclose = () => { if (_conn === db) _conn = null; };
          } catch (_) {}
          fim(db);
        };
        req.onerror = () => fim(null, 'open:' + ((req.error && req.error.name) || 'erro'));
        req.onblocked = () => fim(null, 'open:bloqueado');
        // Alguns firmwares de TV penduram o open() — não travamos o boot por isso.
        // (Esta TV leva vários segundos: o timeout curto anterior matava o cache.)
        setTimeout(() => fim(null, 'open:timeout'), 15000);
      } catch (e) { fim(null, 'open:' + ((e && e.name) || 'excecao')); }
    });
    return _abrindo;
  }

  // Resolve { ok, v, e } — nunca rejeita.
  function _tx(db, loja, modo, fn) {
    return new Promise((resolve) => {
      let pronto = false;
      const fim = (o) => { if (!pronto) { pronto = true; resolve(o); } };
      try {
        const t = db.transaction(loja, modo);
        const r = fn(t.objectStore(loja));
        r.onsuccess = () => fim({ ok: true, v: r.result });
        r.onerror = () => fim({ ok: false, e: (r.error && r.error.name) || 'req' });
        t.onabort = () => fim({ ok: false, e: (t.error && t.error.name) || 'abort' });
        t.onerror = () => fim({ ok: false, e: (t.error && t.error.name) || 'tx' });
        setTimeout(() => fim({ ok: false, e: 'timeout' }), 30000);
      } catch (e) { fim({ ok: false, e: (e && e.name) || 'excecao' }); }
    });
  }

  // Lê o catálogo salvo. Só devolve se casar com a playlist atual e estiver no prazo.
  async function ler(url, tam) {
    const t0 = Date.now();
    const { db, err } = await _abrir();
    if (!db) { status.ler = err || 'sem db'; return null; }
    const res = await _tx(db, LOJA, 'readonly', (s) => s.get(CHAVE));
    status.msLer = Date.now() - t0;
    if (!res.ok) { status.ler = 'erro:' + res.e; return null; }
    const reg = res.v;
    if (!reg) { status.ler = 'vazio (1o boot)'; return null; }
    if (reg.versao !== VERSAO) { status.ler = 'versao diferente'; return null; }
    if (reg.url !== url) { status.ler = 'outra playlist'; return null; }
    if (tam != null && reg.tam !== tam) { status.ler = 'lista mudou'; return null; }
    const horas = (Date.now() - (reg.quando || 0)) / 3600000;
    if (tam == null && horas > VALIDADE_H) { status.ler = 'expirado'; return null; }
    if (!reg.canais || !reg.filmes || !reg.series) { status.ler = 'incompleto'; return null; }
    // Catálogo vazio gravado por engano (parse de uma resposta inválida): ignora
    // e força o download — senão o app abriria vazio p/ sempre.
    if (!reg.canais.length && !reg.filmes.length && !reg.series.length) { status.ler = 'vazio (ignorado)'; return null; }
    status.ler = 'ok';
    return reg;
  }

  async function gravar(url, tam, parsed) {
    const t0 = Date.now();
    const { db, err } = await _abrir();
    if (!db) { status.gravar = err || 'sem db'; return false; }
    const reg = {
      versao: VERSAO, url, tam, quando: Date.now(),
      // só as listas planas (o catálogo/índice são remontados na leitura)
      canais: parsed.canais, filmes: parsed.filmes, series: parsed.series,
    };
    const res = await _tx(db, LOJA, 'readwrite', (s) => s.put(reg, CHAVE));
    status.msGravar = Date.now() - t0;
    status.gravar = res.ok ? 'ok' : ('erro:' + res.e);
    return !!res.ok;
  }

  // ── Metadados do TMDB ──────────────────────────────────────────────────────
  // Chave livre ('tmdb') com o dump do TMDB. Best-effort: se falhar, o app só
  // volta a buscar na rede como antes.
  async function lerMeta() {
    const t0 = Date.now();
    const { db, err } = await _abrir();
    if (!db) { status.meta = err || 'sem db'; return null; }
    const res = await _tx(db, META, 'readonly', (s) => s.get('tmdb'));
    if (!res.ok) { status.meta = 'erro:' + res.e; return null; }
    const reg = res.v;
    if (!reg) { status.meta = 'vazio'; return null; }
    const n = Object.keys(reg.poster || {}).length;
    status.meta = 'ok — ' + n + ' pôsteres (' + (Date.now() - t0) + ' ms)';
    return reg;
  }

  async function gravarMeta(dump) {
    const { db } = await _abrir();
    if (!db) return false;
    const res = await _tx(db, META, 'readwrite', (s) => s.put(dump, 'tmdb'));
    if (!res.ok) status.meta = 'gravar:' + res.e;
    return !!res.ok;
  }

  async function limpar() {
    const { db } = await _abrir(); if (!db) return;
    await _tx(db, LOJA, 'readwrite', (s) => s.delete(CHAVE));
    await _tx(db, META, 'readwrite', (s) => s.delete('tmdb'));
  }

  return { ler, gravar, lerMeta, gravarMeta, limpar, status };
})();