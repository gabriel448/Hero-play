#!/usr/bin/env bash
# Build do .ipk (webOS/LG) do Hero Play TV.
#
# Passos e por quê (não remover):
#  1) TRANSPILA todo o JS p/ chrome68 (esbuild). A LG (webOS 5) roda Chromium 68,
#     que NÃO entende `?.` `??` `||=` etc. — cada um é ERRO DE SINTAXE e derruba o
#     arquivo inteiro (tela cinza). O esbuild converte tudo automaticamente, então
#     não precisamos caçar recurso por recurso. Vale também p/ vendor/hls.min.js.
#  2) `ares-package -n`: o minificador do ares (uglify antigo) não parseia JS
#     moderno e aborta — pulamos (o esbuild já cuidou da compatibilidade).
#  3) Corrige o `control`: o @webosose/ares-cli 2.4.0 grava
#     `webOS-Packager-Version: x.y.x` (placeholder inválido) e a LG REJEITA o
#     pacote com `ipk verified failed`. Reescrevemos o campo.
set -e
cd "$(dirname "$0")"
SRC=tv-app
STAGE=dist-build
OUT=dist-webos
# Versao vem do appinfo.json (fonte unica) — o ares nomeia o .ipk com ela.
VER=$(python -c "import json;print(json.load(open('$SRC/appinfo.json'))['version'])")
IPK="$OUT/com.heroplay.tv_${VER}_all.ipk"
ESBUILD="npx --yes esbuild@0.20.2"

echo "[1/4] Staging + transpile (chrome68)…"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
cp -r "$SRC"/. "$STAGE"/
# Tira clutter que não deve ir pro app (config Tizen, deploy web, docs).
rm -f "$STAGE"/vercel.json "$STAGE"/README.md "$STAGE"/config.xml "$STAGE"/HeroPlay-TV.zip 2>/dev/null || true
for f in "$STAGE"/*.js "$STAGE"/vendor/*.js; do
  [ -f "$f" ] || continue
  $ESBUILD "$f" --target=chrome68 --outfile="$f.tp" --log-level=warning
  mv "$f.tp" "$f"
done
# CSS: polyfill de `gap` em flexbox (não existe no Chromium 68) → margem entre
# filhos. Grid gap é preservado. (`inset` já foi corrigido no fonte.)
python tools/css-flex-gap.py "$STAGE/styles.css"

echo "[2/4] Empacotando…"
rm -f "$IPK"
ares-package "$STAGE" -n -o "$OUT"

echo "[3/4] Corrigindo control…"
python - "$IPK" "$VER" <<'PYEOF'
import sys, tarfile, io, time
src = sys.argv[1]
ver = sys.argv[2]
d = open(src, 'rb').read()
assert d[:8] == b'!<arch>\n', 'ipk invalido'
i, mem = 8, {}
while i < len(d):
    h = d[i:i+60]
    if len(h) < 60: break
    name = h[0:16].decode('latin1').strip()
    size = int(h[48:58].decode('latin1').strip())
    mem[name] = d[i+60:i+60+size]
    i += 60 + size + (size % 2)
control = (
    "Package: com.heroplay.tv\n"
    "Version: " + ver + "\n"
    "Section: misc\n"
    "Priority: optional\n"
    "Architecture: all\n"
    "Installed-Size: 1020812\n"
    "Maintainer: Hero Play <noreply@heroplaytv.com>\n"
    "Description: Hero Play\n"
    "webOS-Package-Format-Version: 2\n"
    "webOS-Packager-Version: 2.4.0\n"
).encode()
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w:gz', format=tarfile.GNU_FORMAT) as tf:
    ti = tarfile.TarInfo('control')
    ti.size, ti.mode, ti.mtime = len(control), 0o644, int(time.time())
    tf.addfile(ti, io.BytesIO(control))
def member(name, data):
    hdr = (name.ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6)
           + "100644".ljust(8) + str(len(data)).ljust(10) + "`\n")
    return hdr.encode('latin1') + data + (b"\n" if len(data) % 2 else b"")
ipk = b'!<arch>\n'
ipk += member('debian-binary', mem['debian-binary'])
ipk += member('control.tar.gz', buf.getvalue())
ipk += member('data.tar.gz', mem['data.tar.gz'])
open(src, 'wb').write(ipk)
print('  control OK (webOS-Packager-Version: 2.4.0)')
PYEOF

echo "[4/4] Pronto."
sha256sum "$IPK"