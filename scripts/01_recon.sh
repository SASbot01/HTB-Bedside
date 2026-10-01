#!/bin/bash
# Fase 01 - Reconocimiento de red
# Uso: ./01_recon.sh <IP>
IP="${1:-10.129.248.191}"
echo "[*] Barrido rapido de los 65535 puertos..."
sudo nmap -p- --min-rate 3000 -T4 -n -Pn "$IP" -oN allports.txt
PORTS=$(grep -oP '^\d+(?=/tcp\s+open)' allports.txt | paste -sd,)
echo "[*] Puertos abiertos: $PORTS"
echo "[*] Barrido profundo (versiones + scripts)..."
sudo nmap -sC -sV -p"$PORTS" -n -Pn "$IP" -oN services.txt
