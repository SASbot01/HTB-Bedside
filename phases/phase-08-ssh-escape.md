# Fase 08 — Escape del contenedor: SSH como `developer` → user.txt

> Teníamos la clave SSH privada de `developer` (leída en la Fase 07 vía el path traversal del 3000).
> Esta fase la convierte en una **shell real en el host**, saliendo del contenedor.

## 🎯 Objetivo
Usar la clave robada para autenticarnos por SSH contra el **host** y pasar de `datawrangler`
(contenedor) a `developer` (máquina real).

## 🔑 Por qué una clave privada = acceso sin contraseña
SSH admite autenticación por **par de claves**: el usuario guarda la **pública** en su
`~/.ssh/authorized_keys` (la cerradura) y conserva la **privada** (la llave). Quien posea la privada
puede abrir esa cerradura **sin saber la contraseña**. Al leer `/home/developer/.ssh/id_rsa` con el
file-read, nos hicimos con esa llave.

## 🧪 Pasos

**1. Guardar la clave con permisos estrictos.** SSH rechaza claves legibles por otros:
```bash
mkdir -p ~/htb/loot
# pegar el contenido -----BEGIN...END----- en el fichero
chmod 600 ~/htb/loot/developer.key
ssh-keygen -y -f ~/htb/loot/developer.key    # valida: imprime la pública ssh-ed25519 -> OK
```

> ⚠️ **Gotcha real:** al copiar la clave del terminal, se guardó como una fila de **puntitos `••••`**
> (el copiado la enmascaró como si fuera una contraseña). El fichero tenía la forma correcta
> (`BEGIN`/`END`) pero el cuerpo era basura → `ssh: invalid format`. Solución: reescribir el fichero
> con el **base64 real** y validar con `ssh-keygen -y -f`. Lección: tras exfiltrar una clave,
> **verifícala siempre** antes de usarla.

**2. Conectar al host:**
```bash
ssh -i ~/htb/loot/developer.key -o IdentitiesOnly=yes developer@bedside.htb
```
- `-i` → usa **esta** clave.
- `-o IdentitiesOnly=yes` → usa **solo** esa (evita `Too many authentication failures` cuando el
  `ssh-agent` tiene varias claves cargadas).

**3. Resultado:** prompt `developer@bedside:~$`. Dejamos de ser `datawrangler` en el contenedor y
pasamos a ser `developer` en el **host real**. Eso es el **escape del contenedor**.

## 🚩 La user flag
`user.txt` vive en el home del usuario. Se obtiene de dos formas (hicimos las dos):
- **Vía file-read (Fase 07), sin shell:** `curl --path-as-is '...:3000/../../../../home/developer/user.txt'`.
  Una flag es solo un fichero de texto → con lectura arbitraria ya la tienes.
- **Vía SSH:** una vez dentro, `cat ~/user.txt`.

## 🔄 Gotcha de HTB: el reset (muy real, para el write-up)
Durante la resolución la máquina se **reseteó** (expiró y respawneó). Al resetear, HTB **restaura la
imagen**:

| Cosa | ¿Sobrevive al reset? |
|---|---|
| IP de la máquina | ❌ cambia (hay que actualizar `/etc/hosts`) |
| `user.txt` / `root.txt` | 🔄 se **regeneran** (nuevo valor) |
| Shell del contenedor, ficheros subidos | ❌ se pierden |
| **Clave SSH de `developer`** | ✅ **persiste** (es parte de la imagen) |

> 💡 **Lección de oro:** un foothold hay que **repetirlo** tras un reset; una **credencial robada
> persiste**. Por eso, en cuanto tuvimos la clave SSH, recuperar el acceso fue instantáneo
> (`ssh -i ...`) sin rehacer pdfminer ni el contenedor. Las credenciales valen más que los exploits.

## ➡️ Siguiente (Fase 09)
Ya como `developer` en el host: `sudo -l` → escalada a **root** vía el trainer de MONAI.
