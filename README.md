# pc-config

Configuración inicial del sistema para el **ASUS ROG Zephyrus G14 GA403UV**
con **CachyOS** y el entorno **Omarchy** (Hyprland + Wayland).

## Estructura

```
pc-config/
├── setup.sh                               ← script de configuración global
├── scripts/
│   ├── setup-keyboard-layout-switcher.sh  ← paso 1: idioma del teclado
│   ├── setup-keyboard-ambient.sh          ← paso 2: iluminación del teclado
│   └── instalar-steam.sh                  ← paso 3: instalación de Steam
└── docs/
    ├── luces-rog.tex / .pdf               ← documentación: iluminación ROG
    └── instalar-steam.tex / .pdf          ← documentación: instalación Steam
```

## Uso rápido

```bash
sudo ./setup.sh
```

Ejecuta los tres pasos en orden. Si alguno falla, el proceso se detiene e
indica exactamente cuál fue el problema.

Para ejecutar un paso concreto de forma independiente:

```bash
# Sólo idioma del teclado (no requiere root)
bash scripts/setup-keyboard-layout-switcher.sh

# Sólo iluminación (no requiere root)
bash scripts/setup-keyboard-ambient.sh

# Sólo Steam (requiere root)
sudo bash scripts/instalar-steam.sh
```

---

## Paso 1 — Idioma del teclado

**Script:** `scripts/setup-keyboard-layout-switcher.sh`

Configura la alternancia de distribución de teclado **US ↔ Latam** mediante
`Alt+Shift` y añade un indicador del idioma activo en la barra de **Waybar**.

| Atajo | Acción |
|---|---|
| `Alt+Shift` | Cambia entre US y Latam |

Modifica:
- `~/.config/hypr/input.conf` — añade `kb_layout = us,latam` y el atajo
- `~/.config/waybar/config.jsonc` — añade el módulo `hyprland/language`
- `~/.config/waybar/style.css` — estilos del indicador

Crea una copia de seguridad con marca de tiempo (`.bak.TIMESTAMP`) de cada
archivo antes de modificarlo. Es seguro de ejecutar más de una vez
(idempotente).

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

Dependencias instaladas automáticamente: `asusctl`, `grim`, `python-pillow`.

Instala en `~/.local/bin/`:
- `keyboard-ambient` — daemon que adapta el color del teclado al contenido
  de la pantalla en tiempo real
- `keyboard-aura-cycle` — cicla entre efectos Aura

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
3. Instala Steam con todas sus dependencias `lib32`.

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

## Hardware

| Componente | Detalle |
|---|---|
| Modelo | ASUS ROG Zephyrus G14 GA403UV |
| Sistema | CachyOS · kernel 7.x · Wayland |
| Entorno | Omarchy (Hyprland) |
| iGPU | AMD Radeon HawkPoint · driver `amdgpu` |
| dGPU | NVIDIA RTX 4060 Laptop (8 GB) · driver `nvidia-open` 595.x |
