#!/usr/bin/env bash
# Build do .apk do app de TV (Fire TV Stick / Android TV / TV Box).
#
# NAO confundir com o APK do app mobile (`flutter build apk`): este aqui embute
# o `tv-app/` — a mesma web app que roda na LG e na Samsung, ja feita para
# controle remoto e para a regra dos 10 pes.
#
# Passos:
#  1) Transpila o JS p/ chrome68 (esbuild) e aplica o polyfill de `flex gap`,
#     EXATAMENTE como o build-ipk.sh: TV Box barata costuma ter WebView antigo,
#     e `?.`/`??` ali sao erro de sintaxe, nao "so" um recurso faltando.
#  2) Copia o resultado para `tv-android/app/src/main/assets/www/`.
#  3) Gradle assembleRelease (assinado com o keystore de `android/key.properties`).
#
# Saida: tv-android/app/build/outputs/apk/release/app-release.apk
set -e
cd "$(dirname "$0")"
SRC=tv-app
STAGE=dist-build-android
WWW=tv-android/app/src/main/assets/www
ESBUILD="npx --yes esbuild@0.20.2"
# Fonte unica da versao da web app (a mesma que nomeia o .ipk da LG).
VER=$(python -c "import json;print(json.load(open('$SRC/appinfo.json'))['version'])")

echo "[1/3] Staging + transpile (chrome68)…"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r "$SRC"/. "$STAGE"/
# Fora do pacote: config das outras plataformas e docs.
rm -f "$STAGE"/vercel.json "$STAGE"/README.md "$STAGE"/config.xml \
      "$STAGE"/appinfo.json "$STAGE"/HeroPlay-TV.zip 2>/dev/null || true
for f in "$STAGE"/*.js "$STAGE"/vendor/*.js; do
  [ -f "$f" ] || continue
  $ESBUILD "$f" --target=chrome68 --outfile="$f.tp" --log-level=warning
  mv "$f.tp" "$f"
done
python tools/css-flex-gap.py "$STAGE/styles.css"
# VERSAO de verdade no pacote: troca o APP_VERSAO do config.js pela do
# appinfo.json. Antes era um '1.0.0-beta' fixo, igual em toda release — e ai nao
# havia como saber, olhando a TV, se o aparelho tinha atualizado.
python - "$STAGE/config.js" "$VER" <<'PYVER'
import re, sys
arq, ver = sys.argv[1], sys.argv[2]
s = open(arq, encoding='utf-8').read()
# Aspas dos DOIS tipos: o esbuild roda ANTES daqui e normaliza ' -> "
novo, n = re.subn(r"""const APP_VERSAO = ['"][^'"]*['"]""", "const APP_VERSAO = '%s'" % ver, s, count=1)
assert n == 1, 'APP_VERSAO nao encontrado em config.js'
open(arq, 'w', encoding='utf-8').write(novo)
print('  APP_VERSAO = %s' % ver)
PYVER

echo "[2/3] Copiando para os assets do APK…"
rm -rf "$WWW"; mkdir -p "$WWW"
cp -r "$STAGE"/. "$WWW"/

echo "[3/3] Gradle assembleRelease…"
cd tv-android
./gradlew --quiet assembleRelease
cd ..
APK=tv-android/app/build/outputs/apk/release/app-release.apk
ls -la "$APK"
sha256sum "$APK"
