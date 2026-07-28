#!/usr/bin/env bash
# Build do .wgt (Samsung Tizen) do Hero Play TV.
#
# ⚠️ PRÉ-REQUISITOS (não dá para empacotar sem eles):
#   1. Tizen Studio instalado (com o "TV Extension"), e o `tizen` CLI no PATH:
#      https://developer.samsung.com/smarttv/develop/tools/tizen-studio.html
#      O CLI costuma ficar em <tizen-studio>/tools/ide/bin/
#   2. Um SECURITY PROFILE (certificado de autor + distribuidor) criado no
#      Certificate Manager do Tizen Studio, vinculado a uma conta Samsung.
#      Um .wgt SEM assinatura é REJEITADO na instalação — não existe atalho.
#      Para testar em TV própria basta o certificado de desenvolvimento; para
#      publicar na loja é preciso o de distribuição (Samsung Seller Office).
#
# Uso:
#   ./build-wgt.sh [nome-do-security-profile]
#
# Os passos 1 e 2 (transpile + polyfill) são os MESMOS do build-ipk.sh: a
# Samsung também roda um Chromium antigo dependendo do ano da TV, então o
# código precisa da mesma conversão que a LG exige.
set -e
cd "$(dirname "$0")"
SRC=tv-app
STAGE=dist-build-tizen
OUT=dist-tizen
PERFIL="${1:-HeroPlay}"
ESBUILD="npx --yes esbuild@0.20.2"

if ! command -v tizen >/dev/null 2>&1; then
  echo "ERRO: o CLI 'tizen' não está no PATH."
  echo "Instale o Tizen Studio + TV Extension e adicione <tizen-studio>/tools/ide/bin ao PATH."
  exit 1
fi

echo "[1/4] Staging + transpile (chrome68)…"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
cp -r "$SRC"/. "$STAGE"/
# Tira o que é da LG/web e não deve ir no pacote Samsung.
rm -f "$STAGE"/vercel.json "$STAGE"/README.md "$STAGE"/appinfo.json "$STAGE"/HeroPlay-TV.zip 2>/dev/null || true
for f in "$STAGE"/*.js "$STAGE"/vendor/*.js; do
  [ -f "$f" ] || continue
  $ESBUILD "$f" --target=chrome68 --outfile="$f.tp" --log-level=warning
  mv "$f.tp" "$f"
done
python tools/css-flex-gap.py "$STAGE/styles.css"

echo "[2/4] Empacotando (.wgt)…"
tizen build-web -e ".*" -e "gitignore" -- "$STAGE"
# O build-web joga o resultado em <stage>/.buildResult
tizen package -t wgt -s "$PERFIL" -- "$STAGE/.buildResult" -o "$OUT"

echo "[3/4] Resultado:"
ls -la "$OUT"/*.wgt

echo "[4/4] Para instalar numa TV Samsung em Developer Mode:"
echo "  sdb connect <IP-DA-TV>"
echo "  tizen install -n <arquivo>.wgt -t <nome-do-device> -- $OUT"
