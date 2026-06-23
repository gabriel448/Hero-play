# Hero Play TV (web — Samsung Tizen + LG webOS)

Protótipo do app de TV. **Web única** (HTML/CSS/JS, sem framework) com navegação
por **controle remoto (D-pad)**. Identidade visual do Hero Play (mesma paleta/fonte
do site). Ver plano: `PLANO-TV-E-PAINEIS.md` (§12 stack, §13 lojas).

## Estrutura
```
tv-app/
├── index.html        # shell (sidebar + conteúdo)
├── styles.css        # tema Hero Play, layout TV, foco
├── data.js           # catálogo STUB (placeholder) — vira playlist real depois
├── spatial-nav.js    # navegação por D-pad (geométrica, vanilla)
├── app.js            # sidebar + render seções, TV ao vivo, players (HLS)
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

## Próximas fases (TODO)
- **Buscar** (teclado on-screen), **Playlists**, **Jogos do dia**.
- EPG/Programação real, **Qualidade** e **Fontes** funcionais.
- **Ativação por MAC+Key** (Edge Function do projeto Supabase novo) + QR.
- Ícones do app (`icon.png`/`largeIcon.png`) + assinatura p/ empacotar.
- Pôsteres reais (capa via metadados) no lugar dos placeholders coloridos.
