#!/usr/bin/env bash
# setup-keyboard-aura-boot.sh
# Fuerza el efecto Aura del teclado (Rainbow Cycle por defecto) y su brillo en
# cada arranque, después de que asusd esté activo y antes del login.
#
# ¿Por qué hace falta?
#   El EC del teclado no conserva el efecto Aura entre apagados. En Windows lo
#   reescribe Armoury Crate/Aura Sync; en Linux lo reescribe asusd, que reaplica
#   el último modo guardado en /etc/asusd/aura_<id>.ron. Ese modo cambia con
#   Fn+F4 y con el modo ambiental, y además asusd 6.5.0 no restaura el brillo al
#   arrancar: si quedó en Off, el teclado arranca apagado aunque el modo guardado
#   sea Rainbow Cycle.
#
#   Este servicio aplica modo + brillo de forma determinista en cada boot.
#
# Nota: durante POST/BIOS/Limine el teclado lo controla el EC; este servicio solo
#       puede aplicar cuando el kernel ya arrancó (justo antes del login).
#
# Requisitos: asusctl (asusd), systemd
#
# Uso: sudo bash setup-keyboard-aura-boot.sh

set -euo pipefail

SCRIPT_PATH="/usr/local/bin/keyboard-aura-boot"
SERVICE_PATH="/etc/systemd/system/keyboard-aura-boot.service"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root (sudo $0)" >&2
    exit 1
fi

if ! command -v asusctl >/dev/null 2>&1; then
    echo "[ERROR] Falta asusctl. Instalalo con: sudo pacman -S asusctl" >&2
    exit 1
fi

# ── 1. Wrapper: aplica efecto + brillo con reintentos ─────────────────────────
cat > "$SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# keyboard-aura-boot: aplica el efecto Aura y el brillo del teclado al arranque.
# Lo ejecuta keyboard-aura-boot.service después de asusd.service.
#
# MODE / BRIGHTNESS se pueden sobrescribir con variables de entorno del unit:
#   sudo systemctl edit keyboard-aura-boot
#   [Service]
#   Environment=KEYBOARD_AURA_MODE=rainbow-wave
#   Environment=KEYBOARD_AURA_BRIGHTNESS=high

set -u

MODE="${KEYBOARD_AURA_MODE:-rainbow-cycle}"
BRIGHTNESS="${KEYBOARD_AURA_BRIGHTNESS:-med}"

# asusd puede tardar un instante en aceptar conexiones D-Bus tras el arranque
for _ in $(seq 1 10); do
    if asusctl aura effect "$MODE" >/dev/null 2>&1; then
        asusctl leds set "$BRIGHTNESS" >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 1
done

echo "keyboard-aura-boot: no se pudo aplicar el efecto '$MODE'" >&2
exit 1
EOF
chmod +x "$SCRIPT_PATH"
echo "  ✓ $SCRIPT_PATH"

# ── 2. Servicio systemd ───────────────────────────────────────────────────────
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

systemctl daemon-reload
systemctl enable --now keyboard-aura-boot.service
echo "  ✓ keyboard-aura-boot.service habilitado y activo"

echo ""
echo "Listo. El teclado aplica Rainbow Cycle en cada arranque (tras asusd, antes del login)."
echo "Para cambiar efecto o brillo:"
echo "  sudo systemctl edit keyboard-aura-boot   # [Service] Environment=..."
echo "  o editá MODE/BRIGHTNESS en $SCRIPT_PATH"
