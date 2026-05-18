# ASUS ROG Zephyrus G14 GA403UV — Setup

Configuración inicial del sistema para el **ASUS ROG Zephyrus G14 GA403UV**
con **CachyOS** y el entorno **Omarchy** (Hyprland + Wayland).

## Estructura

```
ASUS-ROG-Zephyrus-G14-setup/
├── setup.sh                               ← script de configuración global
├── scripts/
│   ├── setup-keyboard-layout-switcher.sh  ← paso 1: idioma y touchpad
│   ├── setup-keyboard-ambient.sh          ← paso 2: iluminación del teclado
│   ├── instalar-vscode.sh                 ← paso 3: instalación de VSCode
│   ├── instalar-trans.sh                  ← paso 4: instalación de trans
│   ├── instalar-steam.sh                  ← paso 5: instalación de Steam
│   ├── setup-power-profiles.sh            ← paso 6: perfiles de rendimiento y Hz
│   ├── setup-runtime-pm.sh                ← paso 7: runtime PM (ahorro de batería)
│   ├── setup-m4-rog-control.sh            ← paso 8: botón M4 → ROG Control Center
│   ├── setup-voice-commands.sh            ← paso 9: comandos de voz offline
│   ├── setup-steam-display.sh             ← paso 12: escala de Steam multi-monitor
│   └── setup-monitor-workspaces.sh        ← standalone: workspaces por monitor
└── docs/
    ├── luces-rog.tex / .pdf               ← documentación: iluminación ROG
    └── instalar-steam.tex / .pdf          ← documentación: instalación Steam
```

---

## Script global

```bash
sudo ./setup.sh
```

Ejecuta los pasos **1 al 12** en orden. Si alguno falla, el proceso se detiene e
indica exactamente cuál fue el problema.

| Paso | Script | Requiere root |
|------|--------|:---:|
| 1 | `setup-keyboard-layout-switcher.sh` | No |
| 2 | `setup-keyboard-ambient.sh` | No |
| 3 | `instalar-vscode.sh` | Sí |
| 4 | `instalar-trans.sh` | Sí |
| 5 | `instalar-steam.sh` | Sí |
| 6 | `setup-power-profiles.sh` | No |
| 7 | `setup-runtime-pm.sh` | Sí |
| 8 | `setup-m4-rog-control.sh` | No |
| 9 | `setup-voice-commands.sh` | Sí |
| 10 | `setup-screenshots.sh` | No |
| 11 | `setup-hyprland-compat.sh` | No |
| 12 | `setup-steam-display.sh` | No (corre como usuario real vía `sudo -u $SUDO_USER`) |

> `setup-monitor-workspaces.sh` **no forma parte del setup global** porque
> requiere conocer los nombres exactos de tus monitores. Ejecútalo por separado
> una vez que tengas ambas pantallas conectadas.

---

## Paso 1 — Idioma del teclado

**Script:** `scripts/setup-keyboard-layout-switcher.sh`

Configura la alternancia de distribución de teclado **US ↔ Latam** y añade un
indicador del idioma activo en la barra de **Waybar**.

Se usa un keybinding de Hyprland (`Alt+\``) en lugar de la opción XKB
`grp:alt_shift_toggle` porque esta colisiona con `Shift+Alt+Tab` (cambio de
foco entre ventanas).

| Atajo | Acción |
|---|---|
| `Alt+`` ` | Cambia entre US y Latam |

Modifica:
- `~/.config/hypr/input.conf` — `kb_layout = us,latam`, `kb_options =` (vacío), `natural_scroll = true`
- `~/.config/hypr/bindings.conf` — keybinding `Alt+grave → switchxkblayout`
- `~/.config/waybar/config.jsonc` — añade el módulo `hyprland/language`
- `~/.config/waybar/style.css` — estilos del indicador de idioma

Crea una copia de seguridad con marca de tiempo (`.bak.TIMESTAMP`) de cada
archivo antes de modificarlo. Es idempotente.

---

## Paso 2 — Iluminación del teclado

**Script:** `scripts/setup-keyboard-ambient.sh`  
**Documentación:** `docs/luces-rog.pdf`

Instala el modo de iluminación ambiental (*screen-sync*) y restaura el
comportamiento original de `Fn+F4` para ciclar efectos Aura.

| Atajo | Acción |
|---|---|
| `Fn+F4` | Cicla efectos Aura (Static, Breathe, Rainbow…) |
| `Shift+Fn+F4` | Cicla brillo del teclado |
| `Super+F4` | Activa/desactiva modo ambiental (screen-sync) |
| `Super+\` | Cicla modos del slash bar (barra LED de la tapa) |

Instala en `~/.local/bin/`:
- `keyboard-ambient` — daemon Python que captura la pantalla con `grim`,
  extrae el color dominante y lo aplica al teclado vía `asusctl` en tiempo real.
  Acepta `--fps` (0.5–10, defecto 4) y `--brightness` (0.0–1.0, defecto 1.0).
- `keyboard-ambient-toggle` — activa/desactiva el daemon; al desactivar,
  restaura el efecto Aura que había antes.
- `keyboard-aura-cycle` — avanza al siguiente efecto Aura (equivalente a
  `Fn+F4` en Armoury Crate). Si el modo ambiental está activo, lo detiene primero.
- `keyboard-slash-cycle` — cicla entre los 16 modos del slash bar de la tapa
  (Static, Bounce, Slash, Loading, BitStream…).

Dependencias requeridas: `asusctl`, `grim`, `python-pillow`.
Si falta alguna, el script intenta instalarla automáticamente con `pacman`
(`--needed`) usando root/sudo.

El setup también valida `asusd`: si falta `/etc/asusd`, lo crea (con permisos
de root/sudo), hace `reset-failed` del servicio y lo inicia para evitar el
error `226/NAMESPACE` al usar `asusctl`.

---

## Paso 3 — VSCode

**Script:** `scripts/instalar-vscode.sh`

Instala **Visual Studio Code** en su versión propietaria de Microsoft
(`visual-studio-code-bin`), disponible en el repositorio **chaotic-aur** que
CachyOS tiene habilitado por defecto.

Se usa esta versión (y no el paquete `code` de los repos oficiales de Arch)
porque la versión open-source usa el registro Open VSX en lugar del
Marketplace de Microsoft, por lo que extensiones como **GitHub Copilot** no
estarán disponibles.

Además configura `~/.config/code-flags.conf` para ejecutar VSCode de forma
nativa en Wayland, evitando el texto borroso que aparece en pantallas HiDPI
(como la pantalla 3K de esta laptop) al correr bajo XWayland.

---

## Paso 4 — trans (translate-shell)

**Script:** `scripts/instalar-trans.sh`

Instala la utilidad de traducción en terminal `trans` mediante el paquete
`translate-shell` de Arch/CachyOS. El script es idempotente: si `trans` ya
existe, no modifica nada.

Guía rápida:

```bash
# Inglés -> Español
trans en:es "hello world"

# Auto-detectar idioma origen -> Español
trans :es "how are you?"

# Español -> Inglés
trans es:en "¿Dónde está la estación?"

# Traducción de una sola palabra
trans :es keyboard

# Modo interactivo
trans -shell
```

Tip: puedes crear alias cortos en tu shell, por ejemplo `te` para traducir a
español (`alias te='trans :es'`).

---

## Paso 5 — Steam

**Script:** `scripts/instalar-steam.sh`  
**Documentación:** `docs/instalar-steam.pdf`

Resuelve los dos problemas conocidos al instalar Steam en CachyOS e instala
el paquete del repositorio `multilib`:

1. Resincroniza forzosamente los repositorios (`pacman -Syy`) para corregir
   las advertencias `%INSTALLED_DB%` de la base de datos local.
2. Elimina la caché obsoleta de `lib32-libxss` que causaba errores 404 en
   todos los mirrors.
3. Instala `steam` con todas sus dependencias `lib32`.

### Usar la GPU NVIDIA en juegos

La laptop usa arquitectura **PRIME Offload**: la iGPU AMD gestiona el display
y la RTX 4060 hace el trabajo de render. Para forzar la NVIDIA en un juego,
añade en *Propiedades del juego → Opciones de lanzamiento* en Steam:

```
prime-run %command%
```

Para el overlay de rendimiento (FPS, uso de GPU/CPU, temperaturas):

```
MANGOHUD=1 prime-run %command%
```

### MUX Switch (modo Ultimate)

El G14 GA403UV tiene MUX switch, lo que conecta la NVIDIA directamente al
panel (máximo rendimiento, sin pasar por la iGPU). Se gestiona con
`supergfxctl`:

```bash
sudo pacman -S supergfxctl
sudo systemctl enable --now supergfxd

supergfxctl --mode AsusMuxDgpu  # NVIDIA directo al panel (requiere reinicio)
supergfxctl --mode Hybrid       # PRIME normal (ahorro de batería)
```

---

## Paso 6 — Perfiles de rendimiento y frecuencia de pantalla

**Script:** `scripts/setup-power-profiles.sh`

Configura el ciclo de perfiles de rendimiento mediante `Fn+F5` usando
`power-profiles-daemon` (PPD), cambia automáticamente la frecuencia de
refresco de la pantalla según el perfil, y sincroniza el perfil al
conectar/desconectar el cargador.

| Atajo | Acción |
|---|---|
| `Fn+F5` | Cicla Silencio (60 Hz) → Equilibrado (120 Hz) → Rendimiento (120 Hz) |

Instala en `~/.local/bin/`:
- `power-profile-cycle` — lee el perfil activo con `powerprofilesctl get`,
  avanza al siguiente, ajusta la frecuencia de pantalla con
  `hyprctl keyword monitor` y muestra una notificación.
- `display-hz-sync` — daemon que observa el estado del adaptador de AC
  con `udevadm monitor` y aplica 60 Hz en batería / 120 Hz en corriente
  automáticamente, incluso sin pulsar `Fn+F5`.

Crea el servicio de usuario `~/.config/systemd/user/display-hz-sync.service`
(habilitado en la sesión gráfica) y la regla udev del sistema
`/etc/udev/rules.d/99-power-profile.rules` que cambia el perfil PPD al
desconectar (`power-saver`) o conectar (`balanced`) el cargador.

> El hardware es un **ASUS ROG GA403UV**: `asusd` está en ejecución pero
> `asusctl` no funciona correctamente con esta versión del firmware/kernel.
> Se usa `power-profiles-daemon` como capa de control exclusiva.
> `amd_pstate=active` está confirmado activo.

---

## Paso 7 — Runtime Power Management

**Script:** `scripts/setup-runtime-pm.sh`

Habilita el runtime power management para dispositivos PCI, NVMe y USB.
Por defecto, el kernel deja muchos dispositivos PCIe en estado `active`
aunque estén inactivos, consumiendo varios vatios innecesariamente.

Este script instala `/usr/local/bin/pci-runtime-pm` y el servicio
`/etc/systemd/system/powertop-autotune.service` que lo ejecuta en cada arranque.

Qué hace el script de runtime PM:
- **PCI**: pone todos los dispositivos en `power/control = auto`
- **NVMe**: activa runtime PM del SSD
- **USB**: activa autosuspend en todos los dispositivos excepto los HID
  (teclado, ratón, touchpad)

Ahorro típico: **~8–10 W** en batería (de ~21 W → ~13 W con perfil `power-saver`).

---

## Paso 8 — Botón M4 → ROG Control Center

**Script:** `scripts/setup-m4-rog-control.sh`

El botón **M4** (Armoury Crate) genera el keycode `XF86Launch1`. Este script
lo configura para abrir o enfocar **ROG Control Center** (`rog-control-center`).
Si la aplicación ya está abierta, la trae al frente; si no, la lanza.
Instala `rog-control-center` con `pacman` si no está presente.

| Atajo | Acción |
|---|---|
| `M4` (Armoury Crate) | Abre / enfoca ROG Control Center |

---

## Paso 9 — Comandos de voz

**Script:** `scripts/setup-voice-commands.sh`

Instala un daemon de reconocimiento de voz **offline** (sin internet, sin nube)
basado en [Vosk](https://alphacephei.com/vosk/) con el modelo pequeño de
español (~40 MB). Al escuchar una frase, ejecuta directamente el comando de
shell asociado.

| Atajo | Acción |
|---|---|
| `Super+Alt+V` | Activar / desactivar escucha |
| `Ctrl+Return` | Ejecutar comando (Walker) |
| `Super+Shift+V` | Abrir Visual Studio Code |

Instala en `~/.local/bin/`:
- `voice-commands` — daemon Python que carga el modelo Vosk, construye una
  gramática limitada a las frases conocidas (más rápido y preciso) y ejecuta
  el comando shell correspondiente al reconocer una frase.
- `voice-commands-toggle` — inicia o detiene el daemon; muestra notificación
  en pantalla.

Configuración en `~/.config/voice-commands/commands.conf`:

```
# Formato: frase = comando shell
ejecutar comando         = omarchy-launch-walker
abrir twitter            = omarchy-launch-webapp "https://x.com/"
abrir navegador          = omarchy-launch-browser
abrir terminal           = xdg-terminal-exec
abrir visual studio code = code
```

Añadir o cambiar comandos: editar el archivo y reiniciar el daemon con
`Super+Alt+V` dos veces (apagar → encender).

Dependencias: `python-vosk` (chaotic-aur / AUR), `python-pyaudio` (repos
oficiales), modelo `vosk-model-small-es-0.42`.

---

## Paso 10 — Atajos de captura de pantalla

**Script:** `scripts/setup-screenshots.sh`

Instala herramientas de captura para Wayland (`grim`, `slurp`,
`wl-clipboard`, `hyprpicker`, `satty`) y configura atajos en Hyprland.

| Atajo | Acción |
|---|---|
| `Fn+F6` (`XF86Launch5`) | Captura inteligente (ventana o región) |
| `Super+Shift+S` | Captura de región |

Las capturas se guardan en `~/Pictures`, se copian al portapapeles y se pueden
anotar con Satty.

---

## Paso 11 — Compatibilidad Omarchy ↔ Hyprland

**Script:** `scripts/setup-hyprland-compat.sh`

Corrige incompatibilidades de configuración en
`~/.local/share/omarchy/default/hypr/looknfeel.conf` para Hyprland 0.48+:

- Reemplaza `col.border_locked_active = -1` y
  `col.border_locked_inactive = -1` por valores válidos.
- Comenta `pseudotile` en el bloque `dwindle` (opción eliminada).

El script es idempotente y puede recargar Hyprland automáticamente si hay
sesión activa.

---

## Paso 12 — Escala de Steam en configuración multi-monitor

**Script:** `scripts/setup-steam-display.sh`

Soluciona el problema de escala de Steam en la configuración de doble monitor
mixta de esta laptop: pantalla integrada 3K (scale=2.0) + monitor Full HD
(scale=1.0).

**Problema:** Steam es una app XWayland. Con `force_zero_scaling = true`
(activo en Omarchy), XWayland reporta `scale=1` a Steam, pero Steam igualmente
detecta el DPI físico alto de la pantalla 3K y escala su UI 2x internamente.
Resultado: en la laptop se ve muy pequeño, y en el monitor Full HD excede el
tamaño de la pantalla.

**Solución:** añade `STEAM_FORCE_DESKTOPUI_SCALING=1` en
`~/.config/hypr/envs.conf`, forzando a Steam a usar escala 1x sin
auto-detección de DPI.

```bash
# Aplicar corrección de escala
bash scripts/setup-steam-display.sh

# Además limpiar la geometría guardada de Steam (si sigue abriéndose grande)
bash scripts/setup-steam-display.sh --reset
```

> Tras aplicarlo, **reinicia Steam** para que la variable de entorno tome efecto.

---

## Script standalone — Workspaces por monitor

**Script:** `scripts/setup-monitor-workspaces.sh`

> Este script **no se ejecuta desde `setup.sh`** porque requiere que ambas
> pantallas estén conectadas y que conozcas los nombres de tus monitores
> (`hyprctl monitors`).

Asigna workspaces a monitores en Hyprland:

| Workspaces | Monitor |
|---|---|
| 1–2 | Pantalla integrada (`eDP-1`) |
| 3–10 | Monitor externo (`HDMI-A-1` por defecto) |

Los nombres de monitor se pueden sobrescribir con variables de entorno:

```bash
EXTERNAL_MONITOR=DP-1 bash scripts/setup-monitor-workspaces.sh
```

Crea un backup del `hyprland.conf` antes de modificarlo y es idempotente
(reemplaza el bloque si ya existe).

---

## Bootloader

El gestor de arranque es **Limine**, configurado en `/boot/limine.conf`.

- `default_entry: 3` → arranca directamente en `linux-cachyos` (sin menú)
- `timeout: 0` → no muestra el menú de selección

> `/boot/limine.conf` es **regenerado automáticamente** por `limine-entry-tool`
> cada vez que se actualiza el kernel. Los cambios manuales (como los parámetros
> de energía) deben reaplicarse tras cada actualización del kernel.

Parámetros de cmdline añadidos manualmente en la entrada `linux-cachyos`:

```
pcie_aspm.policy=powersupersave
nvme_core.default_ps_max_latency_us=0
```

---

## Hardware

| Componente | Detalle |
|---|---|
| Modelo | ASUS ROG Zephyrus G14 GA403UV |
| Sistema | CachyOS · kernel `linux-cachyos` 7.x · Wayland |
| Kernel LTS | `linux-cachyos-lts` 6.18 instalado pero no por defecto |
| Entorno | Omarchy (Hyprland) |
| iGPU | AMD Radeon HawkPoint · driver `amdgpu` · `amd_pstate=active` |
| dGPU | NVIDIA RTX 4060 Laptop (8 GB) · driver `nvidia-open` 595.x |
| Bluetooth | MT7922 · funciona en kernel 7.x (falla en LTS 6.18 por protocolo WMT) |
| Pantalla | 2880×1800 · 120 Hz máx · escala 2.0 · nombre `eDP-2` |
| Adaptador AC | `/sys/class/power_supply/ACAD/online` (0 = batería, 1 = AC) |
