# Hero Play TV (web — Samsung Tizen + LG webOS)

Protótipo do app de TV. **Web única** (HTML/CSS/JS, sem framework) com navegação
por **controle remoto (D-pad)**. Identidade visual do Hero Play (mesma paleta/fonte
do site). Ver plano: `PLANO-TV-E-PAINEIS.md` (§12 stack, §13 lojas).

## Estrutura
```
tv-app/
├── index.html        # shell (sidebar + conteúdo). Ordem dos scripts importa
│                     #   (data → lista → tmdb → spatial-nav → device → app)
├── styles.css        # tema Hero Play, layout TV, foco, hero, telas de detalhe
├── data.js           # catálogo STUB (placeholder) — fallback se não houver lista
├── lista.js          # parser M3U/Xtream + organização (PORTADO do mobile):
│                     #   agrupamento ao vivo (fonte+qualidade), filmes/séries,
│                     #   ordem de categorias por popularidade, trilhos A-Z/lançamentos
├── tmdb.js           # cliente TMDB via proxy Vercel (poster, backdrop, nota,
│                     #   sinopse, elenco, logo-título, temporadas) + caches
├── device.js         # ativação MAC+Key via Edge Function `ativacao` (Supabase)
├── spatial-nav.js    # navegação por D-pad (geométrica, vanilla) + aoFocar()
├── app.js            # sidebar, render seções, hero animado, TV ao vivo,
│                     #   players (HLS), telas de detalhe, preload de banners
├── heroplay-icon.svg # logo oficial (H) usada na sidebar
├── appinfo.json      # config LG webOS (.ipk)
└── config.xml        # config Samsung Tizen (.wgt)
```

## Como testar (loop rápido)
1. **Chrome** (90% do dev): abra `index.html` ou rode `npx serve tv-app`.
   - **Setas** = D-pad · **Enter** = selecionar · **Backspace** = voltar ao menu.
   - No Chrome, passar o **mouse** também foca (conveniência de dev).
2. **TV real (a verdade):**
   - **LG:** `ares-package tv-app` → `ares-install <ipk>` → `ares-launch com.heroplay.tv`
     → `ares-inspect -a com.heroplay.tv` (DevTools na TV). Precisa Developer Mode + device (`ares-setup-device`).
   - **Samsung:** empacotar `.wgt` (Tizen Studio/CLI + security profile) → instalar via `sdb`.

## Implementado neste protótipo
- Sidebar (estilo GTV): só ícones, **expande os rótulos ao focar**, centralizada
  verticalmente.
- **Início / Filmes / Séries** no MESMO formato: **banner de destaque** no topo +
  **trilhos horizontais** de pôsteres. Detalhe simples ao abrir um item.
- **TV ao vivo (2 colunas)**:
  - Esquerda: **categorias** (Favoritos primeiro) que dão lugar aos **canais** com
    **slide**; as categorias ficam como _peek_ escurecido (←/OK volta a elas).
    →/OK abre a categoria; ← de um canal volta às categorias.
  - Direita (~60%, prioridade ao player): **mini-player** (preview) + **EPG**
    abaixo + botão de **favoritar**. Foca a tela e OK → **tela cheia**.
  - **Tela cheia estilo TV a cabo**: barra inferior (nº/nome, programa atual +
    próximo com horário, relógio, logo, Programação), Voltar (canto sup. esq.),
    Qualidade/Fontes/Favoritar (canto sup. dir.).
- **Navegação D-pad**: foco visível, **vertical preso na coluna/área** (não vaza
  da sidebar p/ o conteúdo nem entre colunas), animações só em transform/opacity
  (60 fps); `prefers-reduced-motion` respeitado.
- **Players (HLS via hls.js)**:
  - **VOD** ("Assistir"): controles por D-pad (play/pause, scrub com até 3 níveis
    de aceleração + tooltip de tempo, voltar), auto-hide (revela na 1ª tecla),
    placeholders de CC/áudio.
  - **Preview**: `<video>` **persistente** — troca de canal só faz `loadSource`
    (sem recriar elemento/instância → sem tela preta nem acúmulo de players).
  - **Tela cheia ao vivo** reaproveita o MESMO `<video>` do preview (move e
    devolve), evitando 2 instâncias HLS.
  - Stream público de teste por enquanto. ⚠️ Live pode exigir **AVPlay** no
    Tizen (validar na TV).

## Implementado (atualização 2026-06-27)
Além do protótipo acima, já está no app:
- **Lista real:** `lista.js` faz o parse de M3U/Xtream e a **mesma organização do
  mobile** — ao vivo agrupado por canal (com seleção de **fonte** e **qualidade**
  dentro do canal), filmes vs séries (agrupadas por nome, episódios), categorias
  ordenadas por popularidade (ao vivo) e A-Z com lançamentos primeiro (VOD).
  Classificação live/VOD é **por URL** (`/movie/`,`/series/`,extensão) — não por
  group-title (corrigia Telecine/TC Premium aparecendo em Filmes).
- **Ativação MAC+Key** (`device.js`) via Edge Function `ativacao` (Supabase atual,
  temporário — ver PLANO §3): consulta status (trial/ativo/inativo), tela de QR +
  link do site, aviso de teste de 7 dias, botão recarregar.
- **TMDB** (`tmdb.js` via proxy Vercel): pôster vertical (séries), backdrop, nota,
  sinopse, **elenco**, **logo-título** (PNG), recomendados, capas de episódio por
  temporada. Nomenclatura de busca portada do mobile (LEG/DUB só p/ busca, acentos
  transliterados via NFD p/ "Pokémon"="Pokemon", caracteres especiais).
- **Hero fixo animado** (Início/Filmes/Séries): backdrop ~62% à direita ancorado no
  topo, gradiente sobre o texto, logo-título PNG (fallback p/ nome), nota/sinopse;
  troca com animação ao mudar o foco (estilo GTV). Filme sem backdrop usa **blur
  padrão Hero Play** (nunca o backdrop do item anterior).
- **Telas de detalhe** (pós-seleção, filme e série): elenco em carrossel acima dos
  recomendados, botão/tela "Créditos e mais informações" (direção/elenco/gêneros/
  sinopse) e, em séries, "Episódios e mais" com **menu hambúrguer de temporada** e
  capas de episódio.
- **Preload de banners:** os pôsteres das séries **inicialmente visíveis** (~24, na
  ordem real de exibição) são carregados **antes de abrir** o app (com teto de tempo
  no loading); o resto carrega em **background com concorrência limitada** (evita
  rate-limit do TMDB). Observer dos pôsteres é **cache-first** (instantâneo).

## Próximas fases (TODO)
- **Buscar** (teclado on-screen), **Playlists** (CRUD na TV), **Jogos do dia**.
- EPG/Programação real (derivar URL do EPG a partir da M3U), **Qualidade**/**Fontes**
  totalmente funcionais no player.
- **Player nativo p/ live `.ts`/`.mkv`/H265** (Tizen **AVPlay**) — `<video>`+hls.js
  só toca `.mp4`(h264)/`.m3u8`. Limitação conhecida.
- **QR de pagamento/ativação independente** (só build sideload — ver PLANO §4/§7).
- Ícones do app (`icon.png`/`largeIcon.png`) + assinatura p/ empacotar (.wgt/.ipk).
- Migrar o backend TV p/ **projeto Supabase separado** ao iniciar o painel (PLANO §3).
