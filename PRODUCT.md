# PRODUCT.md

## Register
**Product** — design SERVES the product. Mobile app for consuming IPTV content.

## Cena fisica (theme decision)
Usuario no sofa, sala escura ou parcialmente iluminada, fim de tarde / noite, TV/celular como fonte principal de luz, modo descontraido. Estado mental: querendo relaxar, NAO querendo configurar nada.

Conclusao: **dark mode forcado**. Light mode seria erro de design - ningemtem assiste TV em sala bem iluminada planeja, e o brilho de tela clara cansa a vista a noite.

## Users
- Pessoa que ja tem uma lista IPTV (legal ou herdada de algum servico) e quer um player simples
- Idade variada, NAO necessariamente tech-savvy
- Quer abrir, achar canal, assistir. Sem fricçao.

## Anti-references
**Nao queremos parecer com:**
- Stremio (escuro + ciano, vibe pirate-but-pretty)
- Kodi (DOS-like, complexo demais)
- Apps IPTV piratas tipicos (preto + vermelho neon, layouts caoticos com banners)
- Apps de streaming oficiais (Netflix, Globoplay - cinematic mas com muito poster)
- SaaS-cream-and-purple (NÃO somos um tech startup)

## References positivas
- Calmness de Apple TV app (calm hierarchy, respect for content)
- Restraint de Letterboxd (typography forte, accent quente)
- Funcionalidade de VLC (no frills, just works)

## Brand mood
Aconchegante, confiavel, focado. NAO frio, NAO clinico, NAO pirata.

## Tone of voice
Conversacional brasileiro, sem jargão técnico. "Importar" é melhor que "Ingestar". "Canais" é melhor que "Streams". Erros em portugues claro.

## Strategic principles
1. **Conteudo > chrome**: a UI deve sumir quando o usuario quer assistir
2. **Toque, nao configure**: minimo de cliques pra ir do app aberto ao video tocando
3. **Listas grandes nao podem travar**: lazy rendering em tudo
4. **Erros sao explicacoes, nao acusacoes**: "stream fora do ar" e melhor que "ERRO 0xFF"

## Anti-AI tells a evitar
- DeepPurple (uso atual!) - typical SaaS startup color, BANIR
- Cliche IPTV pirate: preto puro + vermelho neon
- Cards-in-cards-in-cards
- Modal pra tudo
- Lucide/material default sem refinamento