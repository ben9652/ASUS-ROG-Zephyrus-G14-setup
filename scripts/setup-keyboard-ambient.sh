#!/usr/bin/env bash
# setup-keyboard-ambient.sh
# Instala el modo de iluminación ambiental del teclado (screen-sync) en el sistema,
# y restaura el comportamiento original de la tecla Fn+F4 (AURA) del ROG.
#
# Teclas configuradas:
#   Fn+F4            → cicla efectos Aura (Static, Breathe, Rainbow, etc.)
#   Shift+Fn+F4      → cicla brillo del teclado
#   Super+F4         → activa/desactiva modo ambiental (screen-sync)
#
# Requisitos: asusctl, grim, python-pillow (se instalan automáticamente si faltan)
#
# Uso: bash setup-keyboard-ambient.sh

set -euo pipefail

BINDIR="$HOME/.local/bin"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"

mkdir -p "$BINDIR"

install_pkg_pacman() {
    local pkg="$1"

    if ! command -v pacman >/dev/null 2>&1; then
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        pacman -S --needed --noconfirm "$pkg"
    elif command -v sudo >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm "$pkg"
    else
        return 1
    fi
}

ensure_ambient_dependencies() {
    local missing=0

    if ! command -v asusctl >/dev/null 2>&1; then
        echo "[INFO] Falta asusctl; intentando instalar..."
        if install_pkg_pacman asusctl; then
            echo "✓ asusctl instalado"
        else
            echo "✗ No se pudo instalar asusctl"
            missing=1
        fi
    fi

    if ! command -v grim >/dev/null 2>&1; then
        echo "[INFO] Falta grim; intentando instalar..."
        if install_pkg_pacman grim; then
            echo "✓ grim instalado"
        else
            echo "✗ No se pudo instalar grim"
            missing=1
        fi
    fi

    if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
        echo "[INFO] Falta python-pillow (PIL); intentando instalar..."
        if install_pkg_pacman python-pillow; then
            echo "✓ python-pillow instalado"
        else
            echo "✗ No se pudo instalar python-pillow"
            missing=1
        fi
    fi

    if [[ $missing -ne 0 ]]; then
        echo "[ERROR] Dependencias incompletas."
        echo "        Instala manualmente: sudo pacman -S asusctl grim python-pillow"
        exit 1
    fi
}

ensure_asusd_ready() {
    local run_root_cmd=""

    if [[ ! -d /etc/asusd ]]; then
        if [[ $EUID -eq 0 ]]; then
            mkdir -p /etc/asusd
            echo "✓ /etc/asusd creado"
        elif command -v sudo >/dev/null 2>&1; then
            if sudo mkdir -p /etc/asusd; then
                echo "✓ /etc/asusd creado (sudo)"
            else
                echo "⚠ No se pudo crear /etc/asusd (sudo falló)."
            fi
        else
            echo "⚠ Falta /etc/asusd y no hay sudo disponible para crearlo."
        fi
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        return
    fi

    if [[ $EUID -eq 0 ]]; then
        run_root_cmd=""
    elif command -v sudo >/dev/null 2>&1; then
        run_root_cmd="sudo "
    else
        echo "⚠ No se puede gestionar asusd sin root/sudo."
        return
    fi

    ${run_root_cmd}systemctl reset-failed asusd.service >/dev/null 2>&1 || true
    ${run_root_cmd}systemctl start asusd.service >/dev/null 2>&1 || true

    if systemctl is-active --quiet asusd.service; then
        echo "✓ asusd activo"
    else
        echo "⚠ asusd sigue inactivo; revisa: systemctl status asusd.service"
    fi
}

ensure_ambient_dependencies
ensure_asusd_ready

# ── 1. Script principal: keyboard-ambient ─────────────────────────────────────
cat > "$BINDIR/keyboard-ambient" << 'PYEOF'
#!/usr/bin/env python3
"""
keyboard-ambient: Adapta el color del teclado al color dominante de la pantalla.

Usa asusctl directamente — sin OpenRGB, sin conflicto con asusd, sin parpadeo.

Requiere: grim, asusctl, python-pillow
Uso:   keyboard-ambient [--fps 0.5-10] [--brightness 0.0-1.0]
"""

import subprocess
import sys
import time
import signal
import argparse
from io import BytesIO
from PIL import Image


def dominant_color(brightness: float):
    """Captura la pantalla y devuelve el color dominante como (r, g, b)."""
    try:
        result = subprocess.run(
            ['grim', '-t', 'jpeg', '-q', '5', '-'],
            capture_output=True,
            timeout=1.5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None

    if result.returncode != 0:
        return None

    # Reducir a 1x1 para obtener el promedio ponderado de toda la pantalla
    img = Image.open(BytesIO(result.stdout)).convert('RGB')
    img = img.resize((1, 1), Image.BOX)
    r, g, b = img.getpixel((0, 0))

    # Boost: preservar matiz aunque la pantalla esté oscura
    MIN_BRIGHTNESS = 80
    peak = max(r, g, b, 1)
    if peak < MIN_BRIGHTNESS:
        scale = MIN_BRIGHTNESS / peak
        r = min(255, int(r * scale))
        g = min(255, int(g * scale))
        b = min(255, int(b * scale))

    if brightness < 1.0:
        r = int(r * brightness)
        g = int(g * brightness)
        b = int(b * brightness)

    return (r, g, b)


def set_keyboard_color(r, g, b):
    hex_color = f'{r:02x}{g:02x}{b:02x}'
    subprocess.run(
        ['asusctl', 'aura', 'effect', 'static', '-c', hex_color],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=2.0,
    )


def run(fps, brightness):
    interval = 1.0 / fps
    last_color = None
    running = True

    def _stop(sig, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT,  _stop)
    signal.signal(signal.SIGTERM, _stop)

    print(f"[ambient] Activo — {fps:.1f} fps, brillo {brightness:.0%}. Ctrl+C para detener.",
          flush=True)

    while running:
        t0 = time.monotonic()

        color = dominant_color(brightness)
        if color and color != last_color:
            set_keyboard_color(*color)
            last_color = color

        elapsed = time.monotonic() - t0
        wait = interval - elapsed
        if wait > 0:
            time.sleep(wait)

    print("[ambient] Detenido.", flush=True)


def main():
    parser = argparse.ArgumentParser(
        description='Iluminacion ambiental del teclado basada en la pantalla'
    )
    parser.add_argument('--brightness', type=float, default=1.0,
                        help='Brillo 0.0-1.0 (defecto: 1.0)')
    parser.add_argument('--fps', type=float, default=4.0,
                        help='Actualizaciones por segundo (defecto: 4)')
    args = parser.parse_args()

    run(max(0.5, min(10.0, args.fps)),
        max(0.0, min(1.0, args.brightness)))


if __name__ == '__main__':
    main()
PYEOF
chmod +x "$BINDIR/keyboard-ambient"
echo "✓ ~/.local/bin/keyboard-ambient instalado"

# ── 2. Script de toggle: keyboard-ambient-toggle ──────────────────────────────
cat > "$BINDIR/keyboard-ambient-toggle" << 'BASHEOF'
#!/usr/bin/env bash
# Toggle del modo ambient: si está corriendo lo para, si no lo inicia.
# Al desactivar, restaura el efecto Aura que había antes.

PIDFILE="/tmp/keyboard-ambient.pid"
STATEFILE="/tmp/keyboard-aura-state"
AURA_DBUS_OBJ="xyz.ljones.Asusd /xyz/ljones/aura/19b6_3_4 xyz.ljones.Aura"

mode_name() {
    case "$1" in
        0)  echo "static" ;;
        1)  echo "breathe" ;;
        2)  echo "rainbow-cycle" ;;
        3)  echo "rainbow-wave" ;;
        4)  echo "stars" ;;
        5)  echo "rain" ;;
        6)  echo "highlight" ;;
        7)  echo "laser" ;;
        8)  echo "ripple" ;;
        10) echo "pulse" ;;
        11) echo "comet" ;;
        12) echo "flash" ;;
        *)  echo "static" ;;
    esac
}

rgb_hex() { printf '%02x%02x%02x' "$1" "$2" "$3"; }

restore_aura() {
    [[ ! -f "$STATEFILE" ]] && return
    read -r data < "$STATEFILE"
    data="${data#* }"
    read -r mode speed r1 g1 b1 r2 g2 b2 speed_str dir_str <<< "$data"
    speed_str="${speed_str//\"/}"; speed_str="${speed_str,,}"
    dir_str="${dir_str//\"/}";     dir_str="${dir_str,,}"
    [[ -z "$speed_str" || "$speed_str" == "0" ]] && speed_str="med"
    [[ -z "$dir_str"   || "$dir_str"   == "0" ]] && dir_str="right"
    local name c1 c2
    name=$(mode_name "$mode")
    c1=$(rgb_hex "$r1" "$g1" "$b1")
    c2=$(rgb_hex "$r2" "$g2" "$b2")
    case "$name" in
        static)        asusctl aura effect static -c "$c1" ;;
        breathe)       asusctl aura effect breathe --colour "$c1" --colour2 "$c2" --speed "$speed_str" ;;
        rainbow-cycle) asusctl aura effect rainbow-cycle --speed "$speed_str" ;;
        rainbow-wave)  asusctl aura effect rainbow-wave --speed "$speed_str" --direction "$dir_str" ;;
        pulse)         asusctl aura effect pulse -c "$c1" ;;
        *)             asusctl aura effect "$name" ;;
    esac
    rm -f "$STATEFILE"
}

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    restore_aura
    notify-send "Teclado" "Modo ambiental desactivado" --icon=input-keyboard -t 2000
else
    busctl get-property $AURA_DBUS_OBJ LedModeData 2>/dev/null > "$STATEFILE"
    keyboard-ambient --fps 4 &
    echo $! > "$PIDFILE"
    notify-send "Teclado" "Modo ambiental activado" --icon=input-keyboard -t 2000
fi
BASHEOF
chmod +x "$BINDIR/keyboard-ambient-toggle"
echo "✓ ~/.local/bin/keyboard-ambient-toggle instalado"

# ── 3. Script ciclador de efectos Aura: keyboard-aura-cycle ──────────────────
cat > "$BINDIR/keyboard-aura-cycle" << 'BASHEOF'
#!/usr/bin/env bash
# keyboard-aura-cycle: Cicla al siguiente efecto Aura (equivalente a Fn+F4 en Armoury Crate).
# Si el modo ambiental está activo, lo desactiva primero.

PIDFILE="/tmp/keyboard-ambient.pid"
AURA_OBJ="xyz.ljones.Asusd /xyz/ljones/aura/19b6_3_4 xyz.ljones.Aura"

mode_label() {
    case "$1" in
        0)  echo "Static" ;;
        1)  echo "Breathe" ;;
        2)  echo "Rainbow Cycle" ;;
        3)  echo "Rainbow Wave" ;;
        4)  echo "Stars" ;;
        5)  echo "Rain" ;;
        6)  echo "Highlight" ;;
        7)  echo "Laser" ;;
        8)  echo "Ripple" ;;
        10) echo "Pulse" ;;
        11) echo "Comet" ;;
        12) echo "Flash" ;;
        *)  echo "Mode $1" ;;
    esac
}

# Detener modo ambiental si estaba corriendo
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
fi

asusctl aura effect --next-mode

mode_num=$(busctl get-property $AURA_OBJ LedMode 2>/dev/null | awk '{print $2}')
notify-send "Aura" "$(mode_label "$mode_num")" --icon=input-keyboard -t 1500
BASHEOF
chmod +x "$BINDIR/keyboard-aura-cycle"
echo "✓ ~/.local/bin/keyboard-aura-cycle instalado"

# ── 4. Script del slash bar: keyboard-slash-cycle ─────────────────────────────
cat > "$BINDIR/keyboard-slash-cycle" << 'BASHEOF'
#!/usr/bin/env bash
# keyboard-slash-cycle: Cicla al siguiente modo del slash bar de la tapa.

MODES=(Static Bounce Slash Loading BitStream Transmission Flow Flux Phantom Spectrum Hazard Interfacing Ramp GameOver Start Buzzer)
STATEFILE="/tmp/keyboard-slash-mode"

current=0
[[ -f "$STATEFILE" ]] && current=$(cat "$STATEFILE")

next=$(( (current + 1) % ${#MODES[@]} ))
echo "$next" > "$STATEFILE"

mode="${MODES[$next]}"
asusctl slash --mode "$mode"

notify-send "Slash Bar" "$mode" --icon=input-keyboard -t 1500
BASHEOF
chmod +x "$BINDIR/keyboard-slash-cycle"
echo "✓ ~/.local/bin/keyboard-slash-cycle instalado"

# ── 5. Keybindings en Hyprland ────────────────────────────────────────────────
# ── 4. Keybindings en Hyprland ────────────────────────────────────────────────
BINDING_AMBIENT='bindd = SUPER, F4, Toggle ambient keyboard lighting, exec, keyboard-ambient-toggle'
BINDING_AURA='bindd = , XF86Launch3, Aura next effect, exec, keyboard-aura-cycle'
MARKER='# Add extra bindings'

BINDING_SLASH='bindd = SUPER, backslash, Slash bar next mode, exec, keyboard-slash-cycle'

if [[ ! -f "$HYPR_BINDINGS" ]]; then
    echo "⚠ No se encontró $HYPR_BINDINGS — añade estos bindings manualmente:"
    echo "  $BINDING_AMBIENT"
    echo "  $BINDING_AURA"
    echo "  $BINDING_SLASH"
else
    # Ambient toggle (Super+F4)
    if grep -qF 'keyboard-ambient-toggle' "$HYPR_BINDINGS"; then
        echo "✓ Keybinding ambient ya presente (sin cambios)"
    else
        sed -i "s|${MARKER}|${MARKER}\n${BINDING_AMBIENT}|" "$HYPR_BINDINGS"
        echo "✓ Keybinding Super+F4 (ambient) añadido"
    fi

    # Aura cycle (Fn+F4 = XF86Launch3)
    if grep -qF 'keyboard-aura-cycle' "$HYPR_BINDINGS"; then
        echo "✓ Keybinding Aura ya presente (sin cambios)"
    else
        sed -i "/keyboard-ambient-toggle/a \\
\\
# Fn+F4 (Aura key = XF86Launch3): ciclar efectos Aura como en Armoury Crate\\
${BINDING_AURA}" "$HYPR_BINDINGS"
        echo "✓ Keybinding Fn+F4 (Aura = XF86Launch3) añadido"
    fi
    # Slash bar (Super+\)
    if grep -qF 'keyboard-slash-cycle' "$HYPR_BINDINGS"; then
        echo "✓ Keybinding slash bar ya presente (sin cambios)"
    else
        sed -i "/keyboard-aura-cycle/a \\
\\
# Super+\\\\ : ciclar modo del slash bar (barra deslizante de la tapa)\\
${BINDING_SLASH}" "$HYPR_BINDINGS"
        echo "✓ Keybinding Super+\\ (slash bar) añadido"
    fi
fi

echo ""
echo "Listo. Recarga Hyprland (hyprctl reload) para activar los nuevos atajos:"
echo "  Fn+F4      → siguiente efecto Aura"
echo "  Super+F4   → activar/desactivar modo ambiental (screen-sync)"
echo "  Super+\\   → siguiente modo del slash bar"
