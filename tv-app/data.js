/* ============================================================================
   Catalogo STUB (placeholder) — so para prototipar o layout/navegacao.
   Depois isto vem da playlist do dispositivo (parse M3U/Xtream) + metadados.
   Titulos inventados de proposito (player neutro, sem conteudo real embutido).
   ============================================================================ */

function _item(id, titulo, ano, nota, generos, sinopse, tipo) {
  return { id, titulo, ano, nota, generos, sinopse, tipo };
}

const SINOPSE =
  'Numa trama cheia de reviravoltas, escolhas difíceis levam personagens ao ' +
  'limite enquanto o tempo se esgota e nada é o que parece.';

const FILMES = [
  _item('f1', 'Rota de Fuga', 2025, 7.4, ['Ação', 'Suspense'], SINOPSE, 'filme'),
  _item('f2', 'Maré Alta', 2024, 6.9, ['Drama'], SINOPSE, 'filme'),
  _item('f3', 'Cidade Cinza', 2025, 8.1, ['Crime', 'Drama'], SINOPSE, 'filme'),
  _item('f4', 'O Último Verão', 2023, 7.0, ['Romance'], SINOPSE, 'filme'),
  _item('f5', 'Zona de Risco', 2025, 7.7, ['Ação'], SINOPSE, 'filme'),
  _item('f6', 'Eclipse', 2024, 6.5, ['Ficção'], SINOPSE, 'filme'),
  _item('f7', 'Noite Sem Fim', 2025, 8.3, ['Terror'], SINOPSE, 'filme'),
  _item('f8', 'Herança', 2022, 7.2, ['Drama'], SINOPSE, 'filme'),
  _item('f9', 'Velocidade Máxima', 2025, 7.9, ['Ação'], SINOPSE, 'filme'),
  _item('f10', 'O Truque', 2024, 6.8, ['Comédia'], SINOPSE, 'filme'),
  _item('f11', 'Fronteira', 2025, 7.5, ['Aventura'], SINOPSE, 'filme'),
  _item('f12', 'Silêncio Profundo', 2023, 8.0, ['Suspense'], SINOPSE, 'filme'),
  _item('f13', 'Coração de Ferro', 2025, 7.1, ['Drama', 'Ação'], SINOPSE, 'filme'),
  _item('f14', 'A Grande Aposta', 2024, 6.6, ['Comédia'], SINOPSE, 'filme'),
];

const SERIES = [
  _item('s1', 'Linha do Tempo', 2025, 8.6, ['Ficção'], SINOPSE, 'serie'),
  _item('s2', 'Bairro Alto', 2024, 7.8, ['Drama'], SINOPSE, 'serie'),
  _item('s3', 'Sob Pressão', 2025, 8.2, ['Médico'], SINOPSE, 'serie'),
  _item('s4', 'Caçadores', 2023, 7.4, ['Aventura'], SINOPSE, 'serie'),
  _item('s5', 'Vidas Cruzadas', 2025, 7.9, ['Romance'], SINOPSE, 'serie'),
  _item('s6', 'Código Negro', 2024, 8.0, ['Suspense'], SINOPSE, 'serie'),
  _item('s7', 'Reino Perdido', 2025, 8.4, ['Fantasia'], SINOPSE, 'serie'),
  _item('s8', 'Plantão', 2022, 7.1, ['Drama'], SINOPSE, 'serie'),
  _item('s9', 'Fora da Lei', 2025, 7.7, ['Crime'], SINOPSE, 'serie'),
  _item('s10', 'Estúdio 9', 2024, 6.9, ['Comédia'], SINOPSE, 'serie'),
  _item('s11', 'Maré de Sorte', 2025, 7.3, ['Comédia'], SINOPSE, 'serie'),
  _item('s12', 'O Enigma', 2023, 8.1, ['Mistério'], SINOPSE, 'serie'),
  _item('s13', 'Geração', 2025, 7.6, ['Drama'], SINOPSE, 'serie'),
  _item('s14', 'Contagem Regressiva', 2024, 7.0, ['Ação'], SINOPSE, 'serie'),
];

function _trilhosPorGenero(itens) {
  const porGenero = {};
  for (const it of itens) {
    for (const g of it.generos) (porGenero[g] ||= []).push(it);
  }
  return Object.entries(porGenero)
    .filter(([, l]) => l.length >= 3)
    .map(([g, l]) => ({ titulo: g, itens: l }));
}

const CATALOGO = {
  inicio: {
    destaque: FILMES[8], // "Velocidade Máxima"
    trilhos: [
      { titulo: 'Novidades da semana', itens: [...FILMES.slice(0, 7), ...SERIES.slice(0, 3)] },
      { titulo: 'Em alta', itens: [...SERIES.slice(3, 9), ...FILMES.slice(7, 11)] },
      { titulo: 'Continuar assistindo', itens: [FILMES[2], SERIES[6], FILMES[11], SERIES[0]] },
    ],
  },
  filmes: {
    destaque: FILMES[2], // "Cidade Cinza"
    trilhos: [
      { titulo: 'Lançamentos', itens: FILMES.slice(0, 10) },
      { titulo: 'Em alta', itens: [...FILMES].reverse().slice(0, 10) },
      ..._trilhosPorGenero(FILMES),
    ],
  },
  series: {
    destaque: SERIES[6], // "Reino Perdido"
    trilhos: [
      { titulo: 'Lançamentos', itens: SERIES.slice(0, 10) },
      { titulo: 'Em alta', itens: [...SERIES].reverse().slice(0, 10) },
      ..._trilhosPorGenero(SERIES),
    ],
  },
};

// Canais ao vivo (stub) — agora/proxima sao placeholders de EPG.
const CANAIS = [
  { id: 'c1', num: '101', nome: 'Hero News', categoria: 'Notícias', agora: 'Jornal da Manhã', prox: 'Mesa Redonda', proxIni: '09:30' },
  { id: 'c2', num: '102', nome: 'Hero Esportes', categoria: 'Esportes', agora: 'Futebol Ao Vivo', prox: 'Resenha Esportiva', proxIni: '22:00' },
  { id: 'c3', num: '103', nome: 'Hero Filmes', categoria: 'Filmes', agora: 'Sessão da Tarde', prox: 'Cine Noite', proxIni: '21:00' },
  { id: 'c4', num: '104', nome: 'Hero Séries', categoria: 'Séries', agora: 'Maratona', prox: 'Episódio Final', proxIni: '20:00' },
  { id: 'c5', num: '105', nome: 'Hero Kids', categoria: 'Infantil', agora: 'Desenhos', prox: 'Hora da História', proxIni: '18:00' },
  { id: 'c6', num: '106', nome: 'Hero Doc', categoria: 'Documentário', agora: 'Planeta Vivo', prox: 'Civilizações', proxIni: '19:15' },
  { id: 'c7', num: '107', nome: 'Hero Música', categoria: 'Música', agora: 'Top Hits', prox: 'Acústico', proxIni: '23:00' },
  { id: 'c8', num: '108', nome: 'Hero Novelas', categoria: 'Novelas', agora: 'Capítulo 42', prox: 'Resumo Semanal', proxIni: '21:45' },
];
