#!/usr/bin/env python3
# Polyfill de `gap` em FLEXBOX p/ Chromium < 84 (webOS 5 = 68). Em cada regra que
# tem `display:flex|inline-flex` E `gap:V`, remove o `gap` e injeta a margem
# equivalente ENTRE filhos (owl `> * + *`): margin-left (row) ou margin-top
# (column). Grid `gap` é preservado (funciona no 68). Idempotente o suficiente.
import re, sys

def transform(css):
    out = []
    pos = 0
    # Casa SÓ regras "planas" (corpo sem chaves) — assim @media/@keyframes (que têm
    # chaves internas) não são tocados como bloco. Regras dentro deles seguem
    # intactas (não há flex+gap dentro de @media neste projeto).
    for m in re.finditer(r'([^{}]+)\{([^{}]*)\}', css):
        out.append(css[pos:m.start()])
        pos = m.end()
        sel, body = m.group(1), m.group(2)
        gm = re.search(r'(^|;|\{)\s*gap\s*:\s*([^;}]+)\s*;?', body)
        # Só pula se for claramente GRID (grid gap funciona no 68). Caso contrário
        # (flex explícito OU override que herda flex da base), converte. `gap` só
        # existe em flex/grid, então não há risco em bloco comum.
        is_grid = re.search(r'display\s*:\s*grid|grid-template', body)
        if not gm or is_grid:
            out.append(m.group(0)); continue
        val = gm.group(2).strip()
        is_col = re.search(r'flex-direction\s*:\s*column', body)
        prop = 'margin-top' if is_col else 'margin-left'
        # remove a declaração de gap do corpo
        newbody = (body[:gm.start()] + (';' if gm.group(1)==';' else gm.group(1)) + body[gm.end():])
        newbody = re.sub(r';\s*;', ';', newbody)
        # seletor do fallback (cada seletor da lista ganha `> * + *`)
        parts = [s.strip() for s in sel.split(',') if s.strip()]
        fb = ', '.join(p + ' > * + *' for p in parts)
        out.append('%s{%s}\n%s { %s: %s; }' % (sel, newbody, fb, prop, val))
    out.append(css[pos:])
    return ''.join(out)

if __name__ == '__main__':
    src = sys.argv[1]
    css = open(src, encoding='utf-8').read()
    res = transform(css)
    # sanidade: chaves balanceadas
    assert res.count('{') == res.count('}'), 'chaves desbalanceadas!'
    open(src, 'w', encoding='utf-8').write(res)
    print('flex-gap polyfill: %d regras flex+gap convertidas'
          % (css.count('gap:') - res.count('gap:')))