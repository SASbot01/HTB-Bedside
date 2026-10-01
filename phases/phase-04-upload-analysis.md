# Fase 04 — Análisis del filtro de subida y la superficie de ataque

## 🎯 Objetivo
Entender **exactamente** cómo valida el portal los archivos, para saber qué ataque es viable y cuál no.
Esta fase es puro **método científico**: formulo hipótesis y las confirmo/descarto con el payload mínimo.

## 🧠 Por qué esta fase es la más importante del "foothold"

La tentación del principiante es lanzar un webshell `.php` y ver qué pasa. Pero si no entiendo **las
reglas**, disparo a ciegas. Mi objetivo aquí no es explotar todavía, sino **cartografiar el filtro**:
¿mira la extensión? ¿el `Content-Type`? ¿el contenido real? Cada respuesta elimina o habilita familias
enteras de ataque.

## 🧪 Experimento 1 — ¿Dónde aterrizan los archivos y se pueden ejecutar?

```bash
# Subo un PDF mínimo pero válido
curl -s -F "uploadFile=@/tmp/test.pdf" http://research.bedside.htb/
# -> "File uploaded successfully: test.pdf"

# ¿Es accesible por web?
curl -s -o /dev/null -w "%{http_code}" http://research.bedside.htb/uploads/test.pdf
# -> 200   ✅
```

**Interpretación:** confirmado — los archivos subidos se guardan en `/uploads/` **conservando el nombre**
y son **accesibles por web**. Como el vhost ejecuta PHP, *si lograra subir un `.php`, sería RCE directo*.
Esto convierte "bypass del filtro de subida" en la hipótesis más rentable… si es posible.

## 🧪 Experimento 2 — ¿Cómo valida el filtro? (el experimento decisivo)

Pruebo subir un payload PHP con **muchas variantes de nombre y `Content-Type`**, para aislar
*qué* comprueba exactamente el servidor:

```bash
echo '<?php system($_GET["c"]); ?>' > payload.php
# Se prueba con filename y Content-Type variados:
#   shell.php, shell.phtml, shell.php.pdf, shell.pdf.php,
#   shell.php5, shell.phar, shell.pHp, shell.png (con Content-Type: image/png)
```

| Intento | Content-Type | Resultado |
|---|---|---|
| `shell.php` | application/pdf | ❌ rechazado |
| `shell.phtml` | application/pdf | ❌ rechazado |
| `shell.php.pdf` (doble ext) | application/pdf | ❌ rechazado |
| `shell.pdf.php` | application/pdf | ❌ rechazado |
| `shell.php5` / `shell.phar` | image/png | ❌ rechazado |
| `shell.pHp` (mayúsculas) | application/pdf | ❌ rechazado |
| **`shell.png`** (nombre de imagen válido) | image/png | ❌ **rechazado** |

## 🔍 La deducción clave

El último caso es el que **lo resuelve todo**: subí un archivo llamado `shell.png`, con
`Content-Type: image/png`… y **también fue rechazado**. Pero su *contenido* era `<?php ... ?>`.

> 🎓 **Razonamiento:** si el servidor solo mirara la **extensión** o el **Content-Type**, `shell.png`
> habría pasado (ambos dicen "imagen"). Como lo rechaza, la conclusión es inequívoca: **el servidor
> valida el CONTENIDO real del archivo** (los *magic bytes* / la estructura del formato). Un PHP
> disfrazado de PNG no es un PNG válido → fuera.

**Consecuencia estratégica:** se cae toda la familia de "renombrar un `.php`". El archivo que suba tiene
que ser un **fichero genuinamente válido** del formato permitido. Por tanto el ataque **no está en
engañar al filtro**, sino en que un archivo *válido* **rompa el procesador** que lo convierte.

Esto **eleva** las otras hipótesis (que antes eran secundarias) a primarias:

1. 🥇 **Exploit del conversor/parseador** con un archivo válido pero malicioso:
   - PDF → si lo renderiza/convierte con **Ghostscript** → *CVE-2023-36664* (RCE por nombres de archivo
     con paréntesis en PostScript/PDF) es un candidato fortísimo.
   - Imagen (tiff/bmp) → **ImageMagick** (histórico de CVEs de RCE).
   - `.dcm` → librería **DICOM** de Python.
2. 🥈 **Archivos (zip)** → *zip-slip* / *symlink*.

## 🧪 Experimento 3 — Comportamiento de los archivos (zip)

```bash
zip test_archive.zip real.png                    # zip con una imagen válida dentro
curl -s -F "uploadFile=@test_archive.zip;filename=collection.zip;type=application/zip" \
  http://research.bedside.htb/
# -> "File uploaded successfully: collection.zip"

# ¿Se extrae el contenido a /uploads/?
curl -s -o /dev/null -w "%{http_code}" http://research.bedside.htb/uploads/collection.zip  # -> 200
curl -s -o /dev/null -w "%{http_code}" http://research.bedside.htb/uploads/real.png        # -> 404
```

**Interpretación:** el zip se acepta y se guarda, **pero su contenido NO aparece en `/uploads/`**. Es
decir, el archivo se **procesa en otro directorio** (probablemente el de "AI training", fuera del
webroot). Eso es precisamente donde un **zip-slip** (rutas `../../`) o un **symlink** tendrían efecto
interesante: escribir fuera del sandbox o leer ficheros del sistema.

## 📌 Estado de las hipótesis al cerrar la Fase 04

| # | Hipótesis | Estado | Prioridad |
|---|---|---|---|
| H1 | Bypass de extensión → webshell `.php` | ❌ **descartada** (valida contenido) | — |
| H2 | Exploit del conversor (Ghostscript/ImageMagick) con archivo válido | 🟢 viable | **ALTA** |
| H3 | pdfminer.six (parseo PDF) | 🟡 a investigar | media |
| H4 | DICOM (.dcm) parsing | 🟡 a investigar | media |
| H5 | Archivos zip → zip-slip / symlink | 🟢 viable | **ALTA** |

## ➡️ Decisión: siguiente paso (Fase 05)
Dos frentes vivos y de alta prioridad: **H2 (exploit de conversión)** y **H5 (zip-slip/symlink)**.
El plan es atacar primero el **conversor** (porque la cabecera `pdfminer.six` + "converted to standardized
formats" es la pista más dirigida del diseñador de la máquina), con un PDF/imagen que dispare RCE en la
cadena de conversión, y como plan B, el zip-slip. *(Documentación en progreso.)*
