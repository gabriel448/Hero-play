# Hero Play — Brief de identidade visual (assets para o site)

Prompt único para o **Claude Design** (gerador de assets). Estilo: **minimalista,
cinematográfico, escuro, com UM acento vermelho**. Mantém o estilo já aplicado no
site (fundo escuro + vermelho play + tipografia Space Grotesk/DM Sans).

---

## PROMPT (cole no Claude Design)

> Crie um **kit de identidade visual minimalista** para o **Hero Play**, um
> reprodutor de mídia (player de playlists M3U/Xtream) para Smart TV, celular e
> desktop. Posicionamento NEUTRO: é só um player — não é serviço de canais.
>
> **Princípios:** minimalismo, muito espaço negativo, geometria limpa, 1 cor de
> acento só, nada de gradientes berrantes, nada de "glow" exagerado, sem clichês
> de IPTV. Visual sóbrio e premium (referência de acabamento: Apple/Linear/Vercel),
> porém com personalidade própria — **não copiar** layouts de players de IPTV.
>
> **Paleta (use exatamente):**
> - Fundo quase-preto `#070708` e `#0B0B0D`
> - Superfícies `#101012`, `#161619`
> - Texto `#F5F5F7` (primário), `#A1A1A6` (secundário)
> - Acento único — vermelho cinema `#E50914` (hover `#FF2D37`, profundo `#B00610`)
> - Branco puro só para o ícone "play"
>
> **Tipografia:** títulos em **Space Grotesk** (600/700), corpo em **DM Sans**.
>
> **Conceito do símbolo:** um **"play"** (triângulo) construído de forma engenhosa
> e minimalista — pode ser formado por **espaço negativo** dentro de um quadrado de
> cantos arredondados, ou pela junção do "H" de Hero com o triângulo de play.
> Monoline OU sólido, mas que **funcione nítido a 32 px**. Evitar detalhes finos.
>
> Gere os assets abaixo, cada um em **fundo transparente** quando fizer sentido, e
> entregue versões em **SVG** (vetor) + **PNG** nas resoluções pedidas:

### Assets a gerar

1. **Símbolo / app icon** — o "play" minimalista num quadrado de cantos
   arredondados (squircle). Fundo do ícone: vermelho `#E50914` com o play branco,
   **e** uma variação invertida (play vermelho em quadrado escuro `#101012`).
   - PNG: 1024, 512, 192, 180, 32, 16. SVG vetor. (favicon + app icon + touch icon)

2. **Logo horizontal (wordmark)** — símbolo + "Hero Play" ao lado. "Hero" em
   vermelho `#E50914`, "Play" em branco, fonte Space Grotesk 700, tracking justo.
   - Versões: sobre fundo escuro e sobre fundo claro. SVG + PNG (altura 64 e 128).

3. **Logo empilhado** (símbolo em cima, wordmark embaixo) — para splash/app de TV.
   SVG + PNG 512.

4. **Imagem do hero** — mockup minimalista mostrando o app numa **Smart TV** (e,
   opcional, um celular ao lado) com uma UI escura sugerida (cards/poster grid em
   tons de cinza + 1 destaque vermelho), sem texto legível, bem clean. Estilo de
   render limpo, sombra suave, sobre transparente. PNG 1600×1000 (2x) + 800×500.

5. **Open Graph / social** — card 1200×630, fundo `#070708`, símbolo + "Hero Play"
   + tagline curta ("Suas playlists, do jeito que a TV merece"), bem minimalista,
   1 detalhe vermelho. PNG.

6. **Favicon** — derivado do símbolo, legível a 16/32 px. ICO + PNG.

7. **Textura de fundo (opcional, sutil)** — um padrão **minimalista** próprio
   (ex.: malha de pontos finíssima OU linhas técnicas tênues) em PNG/SVG tileável,
   monocromático a ~3% de opacidade sobre `#070708`. NÃO usar ícones de "play"
   espalhados (clichê) — algo abstrato e discreto.

8. **Selo de loja / device chips (opcional)** — ícones monoline 24×24 (stroke 2px,
   cantos arredondados) para: Smart TV, celular, desktop, controle remoto, lista/
   playlist, escudo (privacidade). Conjunto coeso, mesmo peso de traço. SVG.

### Entregáveis
- Pasta com **SVGs** (logo, símbolo, ícones) + **PNGs** nas resoluções acima.
- 1 arquivo de **guia rápido** (cores hex, fontes, espaçamento mínimo do logo,
  área de proteção, do/don't).

### Restrições
- Nada de fotos de pessoas, nada de logos de terceiros, nada que sugira pirataria.
- Acessibilidade: contraste do texto ≥ 4.5:1; o vermelho só como acento.
- Minimalismo de verdade: se estiver em dúvida, **tire** elementos.

---

## Onde cada asset entra no site
| Asset | Uso no código |
|---|---|
| app icon 192/180 + favicon | `<link rel="icon">` em todas as páginas (hoje `assets/heroplay-icon-192.png`) |
| wordmark SVG | header e footer (`site.js` → `.brand`) — hoje é texto |
| imagem do hero | `index.html` `.hero-art` (hoje é um círculo play placeholder) |
| OG 1200×630 | `<meta property="og:image">` (adicionar nas páginas) |
| textura de fundo | opcional em `.bg-min` ([assets/site.css](assets/site.css)) |
| ícones device 24px | strip "Compatível com" / cards |

Tokens de referência já no código: [assets/site.css](assets/site.css) (`:root`).
