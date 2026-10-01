# Fase 00 — Preparación del entorno

> Antes de tocar la máquina, hay que tener la "mesa de operaciones" lista. Un pentest con el entorno
> a medias se traduce en errores tontos (payloads que no salen, IPs equivocadas en las reverse shells,
> perder tiempo instalando a mitad de un ataque).

## 🎯 Objetivo
Dejar el equipo atacante capaz de (1) **alcanzar la red** de HTB y (2) **operar** sobre la máquina.

## 🧩 Mi razonamiento
Divido la preparación en tres bloques, en este orden lógico:

1. **Conectividad (VPN).** Si no hay ruta a `10.129.x.x`, nada de lo demás sirve. Es el requisito 0.
2. **Herramientas.** El toolkit mínimo para las 6 fases del bucle: escaneo (nmap), web (ffuf/gobuster/curl),
   post-explotación (impacket, netexec, evil-winrm).
3. **Diccionarios.** El fuzzing (directorios y subdominios) necesita listas de calidad. Sin ellas,
   la fase de enumeración es ciega.

## 🛠️ Qué hice

### 1. VPN de HackTheBox (OpenVPN)
El `.ovpn` lleva el certificado personal del usuario. Se levanta como demonio:

```bash
sudo openvpn --config ~/htb/htb.ovpn --daemon \
  --log ~/htb/vpn.log --writepid ~/htb/vpn.pid
```

**Verificación** (clave: no fiarse del "parece que arrancó", sino comprobar la interfaz):
```bash
ip -4 addr show tun0 | grep inet   # -> inet 10.10.14.95/23  => conectado
```

> ⚠️ **Lección aprendida en el proceso:** OpenVPN con `--daemon` no imprime nada tras conectar,
> solo un WARNING. Lanzar el comando dos veces crea **dos procesos** y un `tun1` que choca en las rutas.
> Regla: lanzarlo **una vez** y verificar con `ip addr`, nunca por la salida de la terminal.
> Limpieza de duplicados: `sudo pkill -x openvpn` (`-x` evita que el patrón mate al propio shell).

### 2. Herramientas
```bash
sudo apt-get install -y openvpn nmap ncat netcat-openbsd dnsutils \
  smbclient ldap-utils ffuf gobuster python3-pip python3-venv git curl wget
pipx install impacket
pipx install git+https://github.com/Pennyw0rth/NetExec   # netexec (nxc)
sudo gem install evil-winrm
```

### 3. Diccionarios (SecLists)
```
~/Documentos/diccionarios/
├── subdominios/subdomains-top5000.txt          (5.000 líneas)
├── directorios/directory-list-2.3-medium.txt   (220.560 líneas)
└── ffuf/raft-medium-directories.txt            (29.999 líneas)
```

## ✅ Resultado
Entorno operativo: VPN arriba (`tun0`), toolkit completo, diccionarios listos.

## ➡️ Decisión: siguiente paso
Con conectividad confirmada, el primer movimiento ofensivo **siempre** es el mismo: *¿qué hay escuchando
en la máquina?* → **Fase 01: escaneo de puertos.**
