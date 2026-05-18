# DESIGN.md

## Color strategy
**Restrained**: tinted neutrals + one accent ≤10%.

## Palette (OKLCH-thinking, expressed in hex aproximado)

### Surfaces (off-black tintadas para morno)
- `surface0` = `#0F0E0D` — background base (NAO #000)
- `surface1` = `#1A1815` — superficies elevadas (cards, app bar)
- `surface2` = `#252220` — modais, popups, surfaces flutuantes
- `surface3` = `#332E2A` — chips, badges

### Text (off-white tintada para morno)
- `text-primary` = `#F5F1EC` — text principal (NAO #fff)
- `text-secondary` = `#A8A09A` — texto secundario
- `text-tertiary` = `#5C5650` — meta, hints

### Divider e outlines
- `divider` = `#2A2622`
- `outline-subtle` = `#3A3530`

### Accent (ambar quente - "cinema iluminado por lampada de tungstenio")
- `accent` = `#E5A56C` — accent principal (estrela favoritos, FAB, links)
- `accent-bright` = `#F2BC85` — hover / pressed
- `accent-on` = `#1A1815` — texto sobre o accent (escuro)
- `accent-dim` = `#3A2A1F` — fundo de chip com leve tinta accent

### Indicadores semanticos (saturacao moderada, nao gritante)
- `live` = `#D9534F` — apenas para indicador "AO VIVO" muito sutil
- `error` = `#C95A4F` — bordas e icons de erro
- `warn` = `#D9A23E`
- `success` = `#7BA68F`

## Typography
**Fonte**: Manrope (Google Fonts) — distinto, NAO Inter/Roboto generico.

### Scale (ratio 1.25)
- `display` = 32px / w700 / -0.4 letter-spacing
- `title-large` = 24px / w600 / -0.3
- `title` = 20px / w600 / -0.2
- `subtitle` = 16px / w600 / 0
- `body` = 14px / w500 / 0
- `caption` = 12px / w500 / 0.1
- `overline` = 11px / w600 / 0.6 / uppercase

### Numbers
Sempre tabular (`fontFeatures: [FontFeature.tabularFigures()]`) em contagens e metricas.

## Spacing
Escala base 4 (4, 8, 12, 16, 20, 24, 32, 48, 64). Aplicar VARIADO, nao tudo 16.

## Radii
- `radius-sm` = 6 (chips, badges)
- `radius` = 10 (cards, inputs, botoes)
- `radius-lg` = 16 (sheets, modals)
- `radius-pill` = 999 (FAB)

Variar: cards mais soft que botoes (10 vs 8 etc).

## Elevation
Sem box-shadow generico. Distincao por background-tint (surface0 → surface1 → surface2).

## Components

### Cards
- Sem border. Background = surface1.
- Padding interno 16. Vertical entre items: 1px divider.
- NUNCA card-in-card.

### Buttons
- Filled: background = accent, text = accent-on
- Tonal: background = surface2, text = text-primary
- Text: text = accent
- Scale on press: 0.97
- Radius 8.

### Lists
- ListTile com 64px de altura quando tem subtitle, 56px sem
- Leading: avatar 44x44 com radius 8

### Tabs
- Indicator slim 2px na cor accent
- Texto w500 inactive, w700 active
- Sem background no tab

### Inputs
- Background = surface2
- Border = none
- Radius 10
- Padding interno generoso (16)

## Motion
- Default ease: `Curves.easeOutQuart`
- Default duration: 250ms (chrome), 200ms (presses)
- Sem bounce, sem elastic.

## Decisoes registradas
- 2026-05-18: Dark forcado (cena fisica de uso a noite)
- 2026-05-18: Removido deepPurple, adotado ambar quente (anti AI-tell de startup roxo)
- 2026-05-18: Manrope > Inter (Manrope tem mais personalidade)