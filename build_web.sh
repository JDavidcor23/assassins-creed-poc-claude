#!/usr/bin/env bash
# PROTOTYPE - NOT FOR PRODUCTION
# Build web + preparacion del directorio de deploy para Vercel.
#
# Requisito previo (una sola vez): tener los export templates de 4.7.2 en
#   %APPDATA%/Godot/export_templates/4.7.2.stable/
# Se bajan desde el editor: Editor -> Manage Export Templates -> Download.
set -euo pipefail

GODOT="${GODOT:-C:/Users/PC/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$PROJ/build/web"

echo "==> Limpiando $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Exportando (preset Web)"
# OJO: sin el "|| true", set -e aborta aca y el diagnostico de abajo NUNCA se
# imprime — solo se ve el error crudo de Godot. Se captura el codigo a mano.
CODIGO=0
"$GODOT" --headless --path "$PROJ" --export-release "Web" "$OUT/index.html" || CODIGO=$?

if [ ! -f "$OUT/index.wasm" ]; then
  echo
  echo "=============================================================="
  echo " EL BUILD NO SE GENERO  (codigo de salida: $CODIGO)"
  echo "=============================================================="
  if [ ! -d "$HOME/AppData/Roaming/Godot/export_templates/4.7.2.stable" ]; then
    echo " Causa: FALTAN LOS EXPORT TEMPLATES de 4.7.2."
    echo
    echo " Arreglo: abri Godot y anda a"
    echo "   Editor -> Manage Export Templates -> Download and Install"
    echo " Son ~1.22 GB. Quedan instalados para siempre."
    echo
    echo " Despues volve a correr:  bash build_web.sh"
  else
    echo " Los templates estan, asi que es otra cosa."
    echo " Revisa el error de Godot que aparece mas arriba."
  fi
  echo "=============================================================="
  exit 1
fi

echo "==> Copiando vercel.json (cabeceras COOP/COEP)"
# Sin estas cabeceras Godot no puede usar SharedArrayBuffer y arranca en negro.
cp "$PROJ/vercel.json" "$OUT/vercel.json"

echo
echo "Listo. Archivos en $OUT:"
ls -la "$OUT"
echo
echo "Probar local:  python '$PROJ/serve_web.py'    -> http://localhost:8000"
echo "               (NO uses 'python -m http.server': no manda COOP/COEP"
echo "                y Godot arranca en pantalla negra)"
echo "Deploy:        cd '$OUT' && vercel --prod"
