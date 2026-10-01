#!/bin/bash
# Fase 02 - Enumeracion web + fuzzing de virtual hosts
# Uso: ./02_web_enum.sh <IP> <dominio>
IP="${1:-10.129.248.191}"; DOM="${2:-bedside.htb}"
WL="$HOME/Documentos/diccionarios/subdominios/subdomains-top5000.txt"
grep -q "$DOM" /etc/hosts || echo "$IP $DOM" | sudo tee -a /etc/hosts
echo "[*] Baseline de vhost inexistente:"
curl -s -H "Host: nope123.$DOM" "http://$IP/" -o /dev/null -w "  size=%{size_download} code=%{http_code}\n"
echo "[*] Fuzzing de vhosts (auto-calibrado):"
ffuf -u "http://$IP/" -H "Host: FUZZ.$DOM" -w "$WL" -mc all -ac
