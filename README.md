# ASUS ROG Zephyrus G14 GA403UV — Setup

Configuración inicial del sistema para el **ASUS ROG Zephyrus G14 GA403UV**
con **CachyOS** y el entorno **Omarchy** (Hyprland + Wayland).

## Estructura

```
ASUS-ROG-Zephyrus-G14-setup/
├── setup.sh                               ← script de configuración global
├── scripts/
│   ├── setup-keyboard-layout-switcher.sh  ← paso 1: idioma del teclado
│   ├── setup-keyboard-ambient.sh          ← paso 2: iluminación del teclado
│   ├── instalar-steam.sh                  ← paso 3: instalación de Steam
│   ├── setup-power-profiles.sh            ← paso 4: perfiles de rendimiento
│   ├── setup-m4-rog-control.sh            ← paso 5: botón M4 → ROG Control Center
│   ├── setup-steam-display.sh             ← paso 6: escala de Steam multi-monitor
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

Ejecuta los pasos **1 al 6** en orden. Si alguno falla, el proceso se detiene e
indica exactamente cuál fue el problema.

| Paso | Script | Requiere root |
|------|--------|:---:|
| 1 | `setup-keyboard-layout-switcher.sh` | No |
| 2 | `setup-keyboard-ambient.sh` | No |
| 3 | `instalar-steam.sh` | Sí |
| 4 | `setup-power-profiles.sh` | No |
| 5 | `setup-m4-rog-control.sh` | No |
| 6 | `setup-steam-display.sh` | No (corre como usuario real vía `sudo -u $SUDO_USER`) |

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
- `~/.config/hypr/input.conf` — `kb_layout = us,latam`, `kb_options = compose:caps`
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

---

## Paso 3 — Steam

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

## Paso 4 — Perfiles de rendimiento

**Script:** `scripts/setup-power-profiles.sh`

Configura el ciclo de perfiles de rendimiento mediante `Fn+F5`, usando
`asusctl` (requiere que el servicio `asusd` esté activo, el script lo habilita
si no lo está).

| Atajo | Acción |
|---|---|
| `Fn+F5` | Cicla Quiet → Balanced → Performance → … |

Instala en `~/.local/bin/`:
- `power-profile-cycle` — lee el perfil activo con `asusctl profile get`,
  avanza al siguiente y muestra una notificación en pantalla.

---

## Paso 5 — Botón M4 → ROG Control Center

**Script:** `scripts/setup-m4-rog-control.sh`

El botón **M4** (Armoury Crate) genera el keycode `XF86Launch1`. Este script
lo configura para abrir o enfocar **ROG Control Center** (`rog-control-center`).
Si la aplicación ya está abierta, la trae al frente; si no, la lanza.
Instala `rog-control-center` con `pacman` si no está presente.

| Atajo | Acción |
|---|---|
| `M4` (Armoury Crate) | Abre / enfoca ROG Control Center |

---

## Paso 6 — Escala de Steam en configuración multi-monitor

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

## Hardware

| Componente | Detalle |
|---|---|
| Modelo | ASUS ROG Zephyrus G14 GA403UV |
| Sistema | CachyOS · kernel 7.x · Wayland |
| Entorno | Omarchy (Hyprland) |
| iGPU | AMD Radeon HawkPoint · driver `amdgpu` |
| dGPU | NVIDIA RTX 4060 Laptop (8 GB) · driver `nvidia-open` 595.x |
