# HTB — Bedside · Write-up razonado

> Documentación de la resolución de la máquina **Bedside** (HackTheBox), escrita no como un simple
> listado de comandos, sino explicando **la lógica de cada decisión**: por qué hago cada paso,
> qué hipótesis manejo, cómo interpreto cada resultado y por qué elijo el siguiente movimiento.
> El objetivo es que se entienda el *razonamiento de un pentester*, no solo el resultado.

- **Máquina:** Bedside
- **IP:** `10.129.248.191`
- **Plataforma:** HackTheBox (entorno de laboratorio autorizado)
- **Dominio:** `bedside.htb`

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
   luego profundizo solo donde hay señal. No gasto tiempo en profundidad donde no hay nada.
2. **Cada resultado es una pregunta nueva.** Un puerto abierto no es un fin; es "¿qué corre ahí?".
   Un redirect a `bedside.htb` no es un estorbo; es "esto usa *virtual hosts* → ¿habrá más?".
3. **El mínimo payload que confirma/descarta.** Para probar una idea uso lo más pequeño posible
   (un PDF vacío, un PNG de 1 píxel). Así aíslo la variable que estoy midiendo.
4. **Observar efectos secundarios.** No solo miro si "funciona"; miro *dónde* aterriza el archivo,
   *qué cabeceras* devuelve, *qué mensaje* da. Ahí están las pistas.
5. **Documentar el porqué, no solo el qué.** Si no sé explicar por qué hago algo, es que estoy
   probando a ciegas — y eso no escala.

---

## 📂 Estructura del repositorio

| Carpeta | Contenido |
|---|---|
| `phases/` | Una ficha por fase, con objetivo, razonamiento, comando, resultado e interpretación |
| `scripts/` | Los scripts/comandos exactos reutilizables de cada fase |
| `scans/` | Las salidas crudas de las herramientas (nmap, etc.) |

## 🗺️ Índice de fases

| Fase | Título | Estado |
|---|---|---|
| [00](phases/phase-00-setup.md) | Preparación del entorno (VPN, herramientas, diccionarios) | ✅ |
| [01](phases/phase-01-recon.md) | Reconocimiento de red (escaneo de puertos) | ✅ |
| [02](phases/phase-02-web-enum.md) | Enumeración web + descubrimiento del virtual host | ✅ |
| [03](phases/phase-03-vhost-research.md) | Análisis del portal `research` (subida de archivos) | ✅ |
| [04](phases/phase-04-upload-analysis.md) | Análisis del filtro de subida y superficie de ataque | ✅ |
| 05 | Explotación *(en progreso)* | ⏳ |

---

## ⚙️ Entorno de trabajo

- **Atacante:** VPS Linux (Ubuntu 24.04) conectado a la VPN de HTB vía OpenVPN (`tun0 = 10.10.14.95`).
- **Herramientas:** nmap, ffuf, gobuster, curl, impacket, netexec, evil-winrm.
- **Diccionarios:** SecLists (subdominios, directorios, ffuf) en `~/Documentos/diccionarios/`.
