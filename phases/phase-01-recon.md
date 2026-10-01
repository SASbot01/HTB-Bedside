# Fase 01 — Reconocimiento de red (escaneo de puertos)

## 🎯 Objetivo
Responder a la primera pregunta de todo pentest: **¿qué servicios expone la máquina?**

## 🧠 Mi razonamiento (importante)

Aquí tomo **dos decisiones de diseño** que merece la pena explicar, porque definen la calidad del recon:

### Decisión 1: primero *todos* los puertos, rápido; luego *pocos* puertos, a fondo.
¿Por qué no lanzar directamente `nmap -sCV` (scripts + versiones) contra los 65535 puertos?
Porque sería **lentísimo**: `-sCV` sobre 65k puertos puede tardar 20–40 min. En cambio:

1. **Barrido rápido** (`-p-`, sin scripts): ¿qué puertos están abiertos? → segundos.
2. **Barrido profundo** solo sobre los abiertos (`-sCV -p22,80,3000`): versiones y scripts → segundos.

Esto es el principio del *funnel*: ancho y barato primero, estrecho y caro después.

### Decisión 2: `-Pn` y el "fantasma" del ping.
El usuario hizo `ping` y creyó que "no respondía" (en realidad sí). Dato técnico: muchas máquinas
**descartan ICMP** y nmap, por defecto, podría marcarlas como "down" y no escanearlas. Por eso uso
`-Pn` (*treat all hosts as online*): le digo a nmap "no pierdas tiempo comprobando si está viva,
escanea directamente". Evita falsos negativos.

**Flags y su porqué:**
| Flag | Significado | Por qué lo uso |
|---|---|---|
| `-p-` | Los 65535 puertos TCP | No asumir que solo están los "típicos"; el 3000 no es estándar |
| `--min-rate 3000` | ≥3000 paquetes/s | Acelera el barrido en una red de laboratorio estable |
| `-T4` | Timing agresivo | Laboratorio → puedo permitírmelo sin perder fiabilidad |
| `-n` | Sin resolución DNS | Más rápido; no necesito PTR en esta fase |
| `-Pn` | No hacer host discovery | Evita falsos "host down" por ICMP filtrado |
| `-sC -sV` | Scripts por defecto + versiones | Identifica *qué* software y *qué versión* corre |

## 🛠️ Comandos

```bash
# 1) Barrido rápido de TODOS los puertos
sudo nmap -p- --min-rate 3000 -T4 -n -Pn 10.129.248.191 -oN allports.txt

# 2) Barrido profundo solo sobre los abiertos
sudo nmap -sC -sV -p22,80,3000 -n -Pn 10.129.248.191 -oN services.txt
```

## 📊 Resultado

```
PORT     STATE    SERVICE VERSION
22/tcp   open     ssh     OpenSSH 10.0p2 Debian 7+deb13u4 (protocol 2.0)
80/tcp   open     http    Apache httpd 2.4.68 (Debian)
         |_http-title: Did not follow redirect to http://bedside.htb/
3000/tcp filtered ppp
```

## 🔍 Interpretación — qué me dice cada línea

- **22 SSH (OpenSSH 10.0p2, deb13):** versión muy reciente → Debian 13 "trixie". SSH actualizado =
  poco probable un exploit directo al servicio. Lo anoto como **vía de post-explotación** (entrar con
  credenciales que encuentre más adelante), no como vector de entrada.
- **80 HTTP (Apache 2.4.68):** el `http-title` dice *"Did not follow redirect to **http://bedside.htb/**"*.
  Esto es **oro**: la web redirige a un **nombre de dominio**, no a la IP. Significa que usa
  **virtual hosts** (varios sitios en la misma IP, distinguidos por la cabecera `Host`).
  → Implica dos acciones: (a) añadir `bedside.htb` a `/etc/hosts`, y (b) **buscar más vhosts** (Fase 02).
- **3000 filtered:** `filtered` ≠ `open`. Significa que un firewall **descarta** los paquetes (no hay
  RST ni SYN/ACK). El puerto 3000 es típico de servicios de desarrollo (**Gitea, Grafana, Node.js**).
  Hipótesis: es un servicio **interno** que quizá solo sea accesible desde dentro de la máquina
  (lo retomaré tras conseguir un punto de apoyo).

## ➡️ Decisión: siguiente paso
El único vector de entrada *directo* es el **80/HTTP**, y me ha regalado una pista enorme (vhosts).
Por tanto: **Fase 02 — enumerar la web y descubrir virtual hosts.** El SSH y el 3000 quedan en la
libreta para más tarde.
