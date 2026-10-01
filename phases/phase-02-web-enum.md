# Fase 02 — Enumeración web + descubrimiento de virtual hosts

## 🎯 Objetivo
Entender el sitio web del 80 y, sobre todo, **descubrir virtual hosts ocultos** (la pista que dejó nmap).

## 🧠 Concepto clave: ¿qué es un virtual host y por qué lo busco?

Un servidor Apache puede alojar **varios sitios distintos en la misma IP**. ¿Cómo sabe cuál servir?
Por la cabecera HTTP **`Host`** que manda el navegador:

```
GET / HTTP/1.1
Host: research.bedside.htb     <-- Apache mira esto para decidir qué sitio servir
```

Si pido la IP a secas, Apache sirve el sitio por defecto (o redirige a `bedside.htb`, como vimos).
Pero pueden existir **otros nombres** (`admin.`, `dev.`, `research.`...) que **no están publicados en
ningún sitio** y solo responden si mandas el `Host` correcto. Esos son los *vhosts ocultos*, y a
menudo esconden la aplicación vulnerable. Buscarlos = **fuzzing de la cabecera `Host`**.

## 🛠️ Paso 1 — Preparar el acceso y mirar el sitio principal

```bash
# El DNS de HTB no resuelve .htb -> lo mapeo yo en /etc/hosts
echo "10.129.248.191 bedside.htb" | sudo tee -a /etc/hosts

# Miro el contenido (quitando el HTML para leer solo el texto)
curl -s http://bedside.htb/ | sed 's/<[^>]*>/ /g' | grep -v '^\s*$'
```

**Resultado:** una web estática de una clínica cardiológica ("Bedside Clinic"). Sin login, sin
formularios, sin parámetros. Un *folleto*. Único dato útil: un email `contact@bedside.htb`.

**Interpretación:** el sitio principal **no tiene superficie de ataque**. Esto *refuerza* la hipótesis
de que lo interesante está en otro vhost. Un sitio puramente estático rara vez es la vía de entrada.

## 🛠️ Paso 2 — Fuzzing de virtual hosts

### Mi razonamiento sobre cómo filtrar el ruido
El problema del fuzzing de vhosts: **todo responde**. Si pido `Host: cualquiercosa.bedside.htb`,
Apache devuelve el sitio por defecto (un 301 de 352 bytes). Si no filtro, tendría 5000 "falsos positivos".

Solución: **auto-calibración** (`-ac` en ffuf). ffuf aprende cómo es una respuesta "negativa"
(tamaño/código de un vhost que no existe) y me enseña **solo lo que se desvía** de ese patrón.

```bash
# Primero compruebo el baseline de un vhost inexistente (para entender qué filtrar)
curl -s -H "Host: nope123.bedside.htb" http://10.129.248.191/ \
  -o /dev/null -w "size=%{size_download} code=%{http_code}\n"
# -> size=352 code=301   (esto es "no existe")

# Fuzzing con auto-calibración
ffuf -u http://10.129.248.191/ -H "Host: FUZZ.bedside.htb" \
  -w ~/Documentos/diccionarios/subdominios/subdomains-top5000.txt \
  -mc all -ac
```

## 📊 Resultado

```
research     [Status: 200, ...]
```

**Un único vhost que se desvía del patrón: `research.bedside.htb`.**

## 🔍 Interpretación
La auto-calibración ha hecho su trabajo: de 5000 pruebas, solo `research` responde de forma distinta
al "no existe". Eso es exactamente lo que buscaba: un sitio oculto. La hipótesis de la Fase 01
(había más vhosts) queda **confirmada**.

## ➡️ Decisión: siguiente paso
Todo apunta a `research.bedside.htb`. Lo añado a `/etc/hosts` y lo analizo en profundidad.
→ **Fase 03 — análisis del portal `research`.**

```bash
sudo sed -i 's/^10.129.248.191 bedside.htb/10.129.248.191 bedside.htb research.bedside.htb/' /etc/hosts
```
