#!/usr/bin/env bash
# setup-keyboard-aura-boot.sh
# Fuerza el efecto Aura del teclado (Rainbow Cycle por defecto) y su brillo:
#   - en cada arranque, después de que asusd esté activo y antes del login;
#   - al volver de suspensión/hibernación;
#   - al desbloquear la pantalla (Hyprland/Omarchy), que apaga el teclado al
#     bloquear y a veces no lo restaura.
#
# ¿Por qué hace falta?
#   El EC del teclado no conserva el efecto Aura entre apagados. En Windows lo
#   reescribe Armoury Crate/Aura Sync; en Linux lo reescribe asusd, que reaplica
#   el último modo guardado en /etc/asusd/aura_<id>.ron. Ese modo cambia con
#   Fn+F4 y con el modo ambiental, y además asusd 6.5.0 no restaura el brillo:
#   si quedó en Off, el teclado queda apagado aunque el modo guardado sea
#   Rainbow Cycle.
#
# Nota: durante POST/BIOS/Limine el teclado lo controla el EC; estos servicios
#       solo pueden aplicar cuando el kernel ya arrancó.
#
# Requisitos: asusctl (asusd), systemd, Python 3 (watcher de desbloqueo)
#
# Uso: sudo bash setup-keyboard-aura-boot.sh

set -euo pipefail

SCRIPT_PATH="/usr/local/bin/keyboard-aura-boot"
SERVICE_PATH="/etc/systemd/system/keyboard-aura-boot.service"
RESUME_SERVICE_PATH="/etc/systemd/system/keyboard-aura-resume.service"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root (sudo $0)" >&2
    exit 1
fi

if ! command -v asusctl >/dev/null 2>&1; then
    echo "[ERROR] Falta asusctl. Instalalo con: sudo pacman -S asusctl" >&2
    exit 1
fi

# ── 0. Usuario real (soporta sudo y pkexec) ───────────────────────────────────
REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
    REAL_USER="$(stat -c '%U' "$(dirname "$(readlink -f "$0")")" 2>/dev/null || true)"
fi
REAL_HOME=""
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
fi

run_user_systemctl() {
    local target_uid runtime_dir bus_addr
    target_uid="$(id -u "$REAL_USER")"
    runtime_dir="/run/user/$target_uid"
    bus_addr="unix:path=$runtime_dir/bus"

    if [[ ! -S "$runtime_dir/bus" ]]; then
        return 1
    fi

    sudo -u "$REAL_USER" \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="$bus_addr" \
        systemctl --user "$@"
}

# ── 1. Wrapper: aplica el efecto guardado + brillo con reintentos ─────────────
cat > "$SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# keyboard-aura-boot: reaplica el efecto Aura guardado y el brillo del teclado.
# Lo ejecutan keyboard-aura-boot.service (arranque),
# keyboard-aura-resume.service (volver de suspensión) y keyboard-aura-watch
# (al desbloquear la pantalla).
#
# Por defecto respeta el último efecto guardado por asusd (LedModeData): así el
# color fijo elegido con keyboard-aura-static o el efecto elegido con Fn+F4
# sobreviven arranques, suspensiones y desbloqueos.
#
# Para forzar un modo fijo desde el unit:
#   sudo systemctl edit keyboard-aura-boot
#   [Service]
#   Environment=KEYBOARD_AURA_MODE=rainbow-wave
#   Environment=KEYBOARD_AURA_SPEED=high
#   Environment=KEYBOARD_AURA_BRIGHTNESS=high

set -u

BRIGHTNESS="${KEYBOARD_AURA_BRIGHTNESS:-med}"
AURA_OBJ="xyz.ljones.Asusd /xyz/ljones/aura/19b6_3_4 xyz.ljones.Aura"

rgb_hex() { printf '%02x%02x%02x' "$1" "$2" "$3"; }

mode_name() {
    case "$1" in
        0)  echo "static" ;;
        1)  echo "breathe" ;;
        2)  echo "rainbow-cycle" ;;
        3)  echo "rainbow-wave" ;;
        10) echo "pulse" ;;
        *)  echo "" ;;
    esac
}

build_from_saved() {
    local data vals mode zone r1 g1 b1 r2 g2 b2 speed dir name

    data="$(busctl get-property $AURA_OBJ LedModeData 2>/dev/null)" || return 1
    [[ -z "$data" ]] && return 1

    vals="$(printf '%s' "$data" | sed -e 's/(uu(yyy)(yyy)ss)//' -e 's/[()"]//g')"
    read -r mode zone r1 g1 b1 r2 g2 b2 speed dir <<< "$vals"
    [[ "$mode" =~ ^[0-9]+$ ]] || return 1

    speed="${speed,,}"
    dir="${dir,,}"
    [[ -z "$speed" || "$speed" == "0" ]] && speed="med"
    [[ -z "$dir" ]] && dir="right"

    name="$(mode_name "$mode")"
    case "$name" in
        static)
            effect_cmd=(asusctl aura effect static -c "$(rgb_hex "$r1" "$g1" "$b1")")
            ;;
        breathe)
            effect_cmd=(asusctl aura effect breathe \
                --colour "$(rgb_hex "$r1" "$g1" "$b1")" \
                --colour2 "$(rgb_hex "$r2" "$g2" "$b2")" \
                --speed "$speed")
            ;;
        rainbow-cycle)
            effect_cmd=(asusctl aura effect rainbow-cycle --speed "$speed")
            ;;
        rainbow-wave)
            effect_cmd=(asusctl aura effect rainbow-wave \
                --speed "$speed" --direction "$dir")
            ;;
        pulse)
            effect_cmd=(asusctl aura effect pulse -c "$(rgb_hex "$r1" "$g1" "$b1")")
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${KEYBOARD_AURA_MODE:-}" ]]; then
    # Override manual por entorno
    SPEED="${KEYBOARD_AURA_SPEED:-med}"
    case "$KEYBOARD_AURA_MODE" in
        static)
            effect_cmd=(asusctl aura effect static -c "${KEYBOARD_AURA_COLOUR:-ff00ff}")
            ;;
        breathe)
            effect_cmd=(asusctl aura effect breathe \
                --colour "${KEYBOARD_AURA_COLOUR:-ff00ff}" \
                --colour2 "${KEYBOARD_AURA_COLOUR2:-0000ff}" \
                --speed "$SPEED")
            ;;
        rainbow-cycle)
            effect_cmd=(asusctl aura effect rainbow-cycle --speed "$SPEED")
            ;;
        rainbow-wave)
            effect_cmd=(asusctl aura effect rainbow-wave \
                --direction "${KEYBOARD_AURA_DIRECTION:-right}" \
                --speed "$SPEED")
            ;;
        pulse)
            effect_cmd=(asusctl aura effect pulse -c "${KEYBOARD_AURA_COLOUR:-ff00ff}")
            ;;
        *)
            effect_cmd=(asusctl aura effect "$KEYBOARD_AURA_MODE" --speed "$SPEED")
            ;;
    esac
else
    # Último efecto guardado por asusd (color fijo, Rainbow Cycle, etc.)
    build_from_saved || effect_cmd=(asusctl aura effect rainbow-cycle --speed "med")
fi

# asusd puede tardar un instante en aceptar conexiones D-Bus tras el arranque
for _ in $(seq 1 10); do
    if "${effect_cmd[@]}" >/dev/null 2>&1; then
        asusctl leds set "$BRIGHTNESS" >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 1
done

echo "keyboard-aura-boot: no se pudo reaplicar el efecto Aura" >&2
exit 1
EOF
chmod +x "$SCRIPT_PATH"
echo "  ✓ $SCRIPT_PATH"

# ── 2. Servicio de arranque ───────────────────────────────────────────────────
cat > "$SERVICE_PATH" << 'EOF'
[Unit]
Description=ROG keyboard Aura effect at boot
After=asusd.service
Requires=asusd.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/keyboard-aura-boot

[Install]
WantedBy=multi-user.target
EOF
echo "  ✓ $SERVICE_PATH"

# ── 3. Servicio de resume (suspensión/hibernación) ────────────────────────────
cat > "$RESUME_SERVICE_PATH" << 'EOF'
[Unit]
Description=Restore ROG keyboard Aura after resume
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/keyboard-aura-boot

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
echo "  ✓ $RESUME_SERVICE_PATH"

systemctl daemon-reload
systemctl enable --now keyboard-aura-boot.service
systemctl enable keyboard-aura-resume.service
echo "  ✓ keyboard-aura-boot.service y keyboard-aura-resume.service habilitados"

# ── 4. Watcher de desbloqueo (usuario) ────────────────────────────────────────
# Omarchy apaga el teclado al bloquear (omarchy-system-lock) y lo restaura con
# brightnessctl al desbloquear. Si el estado guardado quedó en 0, queda apagado.
if [[ -n "$REAL_HOME" ]]; then
    BINDIR="$REAL_HOME/.local/bin"
    SYSTEMD_USER_DIR="$REAL_HOME/.config/systemd/user"
    WATCHER_PATH="$BINDIR/keyboard-aura-watch"
    USER_SERVICE_PATH="$SYSTEMD_USER_DIR/keyboard-aura-watch.service"

    install -d -o "$REAL_USER" -g "$REAL_USER" "$BINDIR" "$SYSTEMD_USER_DIR"

    cat > "$WATCHER_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""keyboard-aura-watch: reaplica el efecto Aura al desbloquear la pantalla.

Omarchy apaga el teclado al bloquear (omarchy-system-lock) y lo restaura con
brightnessctl al desbloquear. Si el estado guardado quedó en 0, el teclado
queda apagado. hyprlock usa el protocolo ext-session-lock (no wlr-layer-shell),
así que no hay evento de desbloqueo en el socket IPC de Hyprland: este watcher
vigila el proceso hyprlock y reaplica el efecto + brillo cuando termina.
"""

import subprocess
import time

APPLY_CMD = "/usr/local/bin/keyboard-aura-boot"
POLL_SECONDS = 1


def hyprlock_running():
    result = subprocess.run(
        ["pgrep", "-x", "hyprlock"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def apply_aura():
    subprocess.run([APPLY_CMD], check=False)


def main():
    was_locked = hyprlock_running()

    while True:
        time.sleep(POLL_SECONDS)
        is_locked = hyprlock_running()

        if was_locked and not is_locked:
            apply_aura()
            # Omarchy programa un "off" con 3 s de retardo al bloquear;
            # se reaplica una vez más por si acaso.
            time.sleep(4)
            apply_aura()

        was_locked = is_locked


if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$WATCHER_PATH"
    chown "$REAL_USER:$REAL_USER" "$WATCHER_PATH"
    echo "  ✓ $WATCHER_PATH"

    cat > "$USER_SERVICE_PATH" << 'EOF'
[Unit]
Description=Reapply ROG keyboard Aura after unlocking (Hyprland)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/keyboard-aura-watch
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
    chown "$REAL_USER:$REAL_USER" "$USER_SERVICE_PATH"
    echo "  ✓ $USER_SERVICE_PATH"

    if run_user_systemctl daemon-reload \
        && run_user_systemctl enable keyboard-aura-watch.service \
        && run_user_systemctl restart keyboard-aura-watch.service; then
        echo "  ✓ keyboard-aura-watch.service habilitado y activo"
    else
        echo "  ⚠ No se pudo habilitar keyboard-aura-watch.service ahora."
        echo "    Iniciá sesión gráfica y ejecutá:"
        echo "      systemctl --user daemon-reload && systemctl --user enable --now keyboard-aura-watch.service"
    fi
else
    echo "  ⚠ No se pudo determinar el usuario real; omitiendo el watcher de desbloqueo."
fi

echo ""
echo "Listo. El teclado reaplica su efecto guardado (Rainbow Cycle, color fijo, etc.)"
echo "y el brillo al arrancar (tras asusd, antes del login), al volver de suspensión"
echo "y al desbloquear la pantalla."
echo "Para forzar un modo fijo:"
echo "  sudo systemctl edit keyboard-aura-boot   # [Service] Environment=KEYBOARD_AURA_MODE=..."
