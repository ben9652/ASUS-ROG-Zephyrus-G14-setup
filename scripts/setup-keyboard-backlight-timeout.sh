#!/usr/bin/env bash
# setup-keyboard-backlight-timeout.sh
# Instala un daemon de usuario que replica el comportamiento del teclado ROG en
# Windows: el LED queda encendido mientras se teclea, se apaga tras N segundos
# sin actividad y vuelve al brillo anterior al presionar cualquier tecla.
#
# ¿Por qué hace falta?
#   En Linux el LED queda encendido indefinidamente (por ejemplo, mientras se
#   mira un video, que inhibe el idle/lock de Omarchy). El EC no expone el
#   timeout del firmware, así que se replica desde usuarios.
#
# Instala:
#   - ~/.local/bin/keyboard-backlight-timeout
#   - ~/.config/systemd/user/keyboard-backlight-timeout.service
#
# Requisitos: brightnessctl, Python 3, usuario en el grupo 'input'
# Uso: sudo bash setup-keyboard-backlight-timeout.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root (sudo $0)" >&2
    exit 1
fi

if ! command -v brightnessctl >/dev/null 2>&1; then
    echo "[ERROR] Falta brightnessctl. Instalalo con: sudo pacman -S brightnessctl" >&2
    exit 1
fi

# ── 0. Usuario real (soporta sudo y pkexec) ───────────────────────────────────
REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
    REAL_USER="$(stat -c '%U' "$(dirname "$(readlink -f "$0")")" 2>/dev/null || true)"
fi
if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
    echo "[ERROR] No se pudo determinar el usuario real." >&2
    exit 1
fi
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

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

if ! id -nG "$REAL_USER" | grep -qw input; then
    echo "  ⚠ '$REAL_USER' no pertenece al grupo 'input'; el daemon no podrá leer"
    echo "    /dev/input/event*. Agregalo con: sudo usermod -aG input $REAL_USER"
fi

# ── 1. Daemon ─────────────────────────────────────────────────────────────────
BINDIR="$REAL_HOME/.local/bin"
SYSTEMD_USER_DIR="$REAL_HOME/.config/systemd/user"
DAEMON_PATH="$BINDIR/keyboard-backlight-timeout"
SERVICE_PATH="$SYSTEMD_USER_DIR/keyboard-backlight-timeout.service"

install -d -o "$REAL_USER" -g "$REAL_USER" "$BINDIR" "$SYSTEMD_USER_DIR"

cat > "$DAEMON_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""keyboard-backlight-timeout: apaga el LED del teclado tras N segundos sin
tecleo y lo vuelve a encender (al brillo anterior) al presionar una tecla.

Replica el comportamiento del firmware ASUS en Windows. Variables:
  KEYBOARD_BACKLIGHT_LED  (def: asus::kbd_backlight)
  KEYBOARD_BACKLIGHT_IDLE (def: 180 segundos)
"""

import glob
import os
import select
import struct
import subprocess
import sys
import time

LED = os.environ.get("KEYBOARD_BACKLIGHT_LED", "asus::kbd_backlight")
IDLE_SECONDS = int(os.environ.get("KEYBOARD_BACKLIGHT_IDLE", "180"))
EVENT_FMT = "llHHI"
EVENT_SIZE = struct.calcsize(EVENT_FMT)
BRIGHTNESS_PATH = f"/sys/class/leds/{LED}/brightness"


def log(message):
    print(message, flush=True)


def read_brightness():
    try:
        with open(BRIGHTNESS_PATH) as fh:
            return int(fh.read().strip())
    except OSError:
        return None


def set_brightness(value):
    subprocess.run(
        ["brightnessctl", "-d", LED, "set", str(value)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def is_key_press(ev_type, code, value):
    # EV_KEY == 1, tecla presionada. Los botones de mouse/touchpad (BTN_*)
    # arrancan en 0x100, así que se excluyen con code < 0x100.
    return ev_type == 1 and value == 1 and 0 < code < 0x100


def main():
    devices = {}

    def scan_devices():
        for path in sorted(glob.glob("/dev/input/event*")):
            if path in devices:
                continue
            try:
                devices[path] = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError:
                continue

    scan_devices()
    if not devices:
        log("keyboard-backlight-timeout: no hay /dev/input/event* legibles")
        return 1

    log(f"keyboard-backlight-timeout: activo (LED {LED}, timeout {IDLE_SECONDS}s)")

    saved_brightness = None
    last_activity = time.monotonic()
    fd_paths = {fd: path for path, fd in devices.items()}

    while True:
        ready, _, _ = select.select(list(devices.values()), [], [], 1.0)

        for fd in ready:
            try:
                data = os.read(fd, EVENT_SIZE)
            except OSError:
                data = b""

            if len(data) < EVENT_SIZE:
                path = fd_paths.pop(fd, None)
                if path:
                    devices.pop(path, None)
                os.close(fd)
                continue

            _, _, ev_type, code, value = struct.unpack(EVENT_FMT, data)
            if is_key_press(ev_type, code, value):
                last_activity = time.monotonic()
                if saved_brightness is not None:
                    set_brightness(saved_brightness)
                    log(f"actividad: brillo restaurado a {saved_brightness}")
                    saved_brightness = None

        if (
            saved_brightness is None
            and time.monotonic() - last_activity >= IDLE_SECONDS
        ):
            current = read_brightness()
            if current:
                saved_brightness = current
                set_brightness(0)
                log(f"sin tecleo {IDLE_SECONDS}s: brillo apagado (guardado {current})")

        scan_devices()
        fd_paths = {fd: path for path, fd in devices.items()}


if __name__ == "__main__":
    sys.exit(main())
PYEOF
chmod +x "$DAEMON_PATH"
chown "$REAL_USER:$REAL_USER" "$DAEMON_PATH"
echo "  ✓ $DAEMON_PATH"

# ── 2. Servicio de usuario ────────────────────────────────────────────────────
cat > "$SERVICE_PATH" << 'EOF'
[Unit]
Description=Turn off ROG keyboard backlight after inactivity
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/keyboard-backlight-timeout
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
chown "$REAL_USER:$REAL_USER" "$SERVICE_PATH"
echo "  ✓ $SERVICE_PATH"

# ── 3. Habilitar y arrancar ───────────────────────────────────────────────────
if run_user_systemctl daemon-reload \
    && run_user_systemctl enable keyboard-backlight-timeout.service \
    && run_user_systemctl restart keyboard-backlight-timeout.service; then
    echo "  ✓ keyboard-backlight-timeout.service habilitado y activo"
else
    echo "  ⚠ No se pudo habilitar keyboard-backlight-timeout.service ahora."
    echo "    Iniciá sesión gráfica y ejecutá:"
    echo "      systemctl --user daemon-reload && systemctl --user enable --now keyboard-backlight-timeout.service"
fi

echo ""
echo "Listo. El teclado se apaga tras 180 s sin tecleo y vuelve al presionar una tecla."
echo "Para cambiar el tiempo:"
echo "  sudo systemctl edit keyboard-backlight-timeout"
echo "  # [Service]"
echo "  # Environment=KEYBOARD_BACKLIGHT_IDLE=120"
