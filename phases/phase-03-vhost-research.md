# Fase 03 — Análisis del portal `research.bedside.htb`

## 🎯 Objetivo
Entender qué hace el vhost oculto y **qué tecnología usa** (porque la tecnología define el ataque).

## 🛠️ Paso 1 — Cabeceras y contenido

```bash
curl -s -I http://research.bedside.htb/          # cabeceras
curl -s http://research.bedside.htb/ | sed 's/<[^>]*>/ /g' | grep -v '^\s*$'   # texto
```

**Cabeceras (lo importante):**
```
HTTP/1.1 200 OK
Server: Apache/2.4.68 (Debian)
X-Powered-By: pdfminer.six      <-- 🔔 PISTA ENORME
```

**Contenido:** un *"Bedside Research Portal"* con un **formulario de subida de archivos**. Texto clave:

> *"This portal allows staff to securely upload X-rays, fluoroscopy images, CT scans, and research
> documents... Please only upload files in the accepted formats: **jpeg, jpg, png, bmp, tiff, dcm, pdf**.
> **Collections can be uploaded as archives.** ... **Certain file formats may be converted to
> standardized formats** before being used for AI training."*

## 🧠 Cómo leo esto como atacante (razonamiento detallado)

Cada frase del portal es una pista sobre el backend. Las traduzco:

| Lo que dice el portal | Lo que significa técnicamente | Oportunidad de ataque |
|---|---|---|
| `X-Powered-By: pdfminer.six` | El backend usa la librería Python **pdfminer.six** para leer PDFs | ¿Vulnerabilidad en el parseo de PDF? |
| "formatos aceptados: ...dcm..." | Procesa **DICOM** (imágenes médicas) | Librería DICOM → posible parsing inseguro |
| "**converted to standardized formats**" | Hay un **conversor** server-side (probable ImageMagick / Ghostscript / Pillow) | Los conversores de imágenes son un **nido de CVEs de RCE** |
| "**uploaded as archives**" | **Descomprime** archivos (zip/tar) | **Zip-slip** (path traversal) / **symlink** → escribir o leer archivos arbitrarios |

> 🎓 **Lección de método:** la cabecera `X-Powered-By: pdfminer.six` es *demasiado* específica para ser
> casual. Cuando un servidor te "regala" el nombre exacto de una librería de procesamiento, casi
> siempre es porque **el fallo está en esa librería o en cómo la usan**. Lo subrayo como hipótesis #1.

## 🛠️ Paso 2 — Mapear el formulario y las rutas

```bash
# Estructura del formulario
curl -s http://research.bedside.htb/ | grep -iE '<form|<input|action=|enctype'
# -> <form method="post" enctype="multipart/form-data">
#    <input type="file" name="uploadFile" required>

# Rutas comunes
for p in robots.txt uploads index.php app.py server-status; do
  echo "$p -> $(curl -s -o /dev/null -w '%{http_code}' http://research.bedside.htb/$p)"
done
```

**Resultado:**
```
uploads       -> 301   (existe un directorio /uploads/)
index.php     -> 200   (la app es PHP)
server-status -> 403   (mod_status activo pero protegido)
```

Y fuzzing de directorios (con la lista raft, más rápida que la medium):
```bash
ffuf -u http://research.bedside.htb/FUZZ \
  -w ~/Documentos/diccionarios/ffuf/raft-medium-directories.txt -mc 200,301,302,403
# -> uploads, javascript, server-status
```

## 🔍 Interpretación
- La app es **PHP** (`index.php`) **pero** procesa archivos con **Python** (`pdfminer.six`).
  Deducción: PHP recibe la subida y **llama a un backend/script Python** para convertir. Arquitectura
  mixta → más superficie (la frontera PHP↔Python suele tener fallos de validación).
- Existe `/uploads/` → **¿es donde aterrizan los archivos subidos?** Si es web-accesible y además
  ejecuta PHP, un archivo malicioso ahí = **RCE**. Hay que comprobarlo (Fase 04).
- `name="uploadFile"` es el campo que usaré en todas las pruebas de subida.

## ➡️ Decisión: siguiente paso
Tengo el formulario localizado y cuatro hipótesis de ataque (pdfminer, conversor, DICOM, archivos).
Antes de disparar un exploit, necesito entender **las reglas del filtro de subida**: ¿valida por
extensión? ¿por contenido? ¿dónde deja los archivos? → **Fase 04 — análisis del filtro y la superficie.**
