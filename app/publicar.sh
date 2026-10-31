#!/usr/bin/env bash
# Gera o APK assinado e publica em https://comandasbrasil.com.br/app/ (pasta media do servidor).
# Uso:   ./publicar.sh "o que mudou nesta versão"
# Antes: suba o número em pubspec.yaml (version: 1.0.1+2 — o número depois do + precisa crescer sempre).
# Opções: SERVIDOR=http://192.168.3.19:8100 ./publicar.sh   (endereço padrão embutido no app)
#         AAB=1 ./publicar.sh                                (gera também o .aab para a Play Store)
#         VPS=root@IP ./publicar.sh "..."                    (envia o APK para a VPS, em /srv/comandas)
set -euo pipefail
cd "$(dirname "$0")"
NOTAS="${1:-}"
SERVIDOR="${SERVIDOR:-https://comandasbrasil.com.br}"
[ -f android/key.properties ] || { echo "Falta android/key.properties (chave de assinatura em ~/chaves-comandas)"; exit 1; }

VERSAO=$(grep '^version:' pubspec.yaml | sed 's/version: *//')
NOME=${VERSAO%+*}; BUILD=${VERSAO#*+}
echo "== Comandas $NOME (build $BUILD) · servidor $SERVIDOR"

flutter build apk --release --dart-define=SERVIDOR="$SERVIDOR"
if [ "${AAB:-0}" = "1" ]; then
  flutter build appbundle --release --dart-define=SERVIDOR="$SERVIDOR"
  mkdir -p ../loja && cp build/app/outputs/bundle/release/app-release.aab "../loja/comandas-$NOME.aab"
  echo "AAB: loja/comandas-$NOME.aab"
fi

DEST=../servidor/media/app
mkdir -p "$DEST"
cp build/app/outputs/flutter-apk/app-release.apk "$DEST/comandas.apk"
python3 - "$NOME" "$BUILD" "$NOTAS" "$DEST/versao.json" <<'PY'
import json, sys, datetime
nome, build, notas, arq = sys.argv[1:]
json.dump({'versao': nome, 'build': int(build), 'notas': notas,
           'data': datetime.date.today().isoformat()}, open(arq, 'w'), ensure_ascii=False)
PY
echo "Publicado: $SERVIDOR/app/  ($(du -h "$DEST/comandas.apk" | cut -f1))"
if [ -n "${VPS:-}" ]; then
  REMOTO=/srv/comandas/servidor/media/app
  rsync -av "$DEST/comandas.apk" "$DEST/versao.json" "$VPS:$REMOTO/"
  ssh "$VPS" "chown -R comandas:comandas $REMOTO && chmod -R o+rX $REMOTO"
  echo "Enviado para a VPS ($VPS)."
else
  echo "Atenção: só copiado para a pasta local. Para a VPS: VPS=root@IP ./publicar.sh \"...\""
fi
