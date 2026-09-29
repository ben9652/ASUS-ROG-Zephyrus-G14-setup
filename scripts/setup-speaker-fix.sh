#!/usr/bin/env bash
# setup-speaker-fix.sh
# Fuerza el estado correcto de los mixers de parlantes internos del codec
# Realtek ALC285 (controles 'Speaker' y 'Bass Speaker') del ASUS ROG Zephyrus
# G14 GA403UV.
#
# ¿Por qué hace falta?
#   Aunque el audio llega correctamente a los amplificadores Cirrus Logic
#   CS35L56 (y las barras de volumen se mueven), el ALC285 quedaba con
#   'Speaker' en 0%/off y 'Bass Speaker' apagado, de modo que no salía señal
#   hacia los parlantes. Además, ese estado roto estaba guardado en
#   /var/lib/alsa/asound.state, así que alsa-restore lo reaplicaba en cada
#   arranque.
#
# Instala:
#   - /usr/local/bin/asus-g14-speaker-fix        → sube/activa los mixers
#   - /etc/systemd/system/asus-g14-speaker-fix.service → arranque y resume
#   - Guarda el estado ALSA corregido con alsactl store
#
# Requisitos: alsa-utils (amixer, alsactl), systemd
#
# Uso: sudo bash setup-speaker-fix.sh

set -euo pipefail

SCRIPT_PATH="/usr/local/bin/asus-g14-speaker-fix"
SERVICE_PATH="/etc/systemd/system/asus-g14-speaker-fix.service"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root (sudo $0)" >&2
    exit 1
fi

if ! command -v amixer >/dev/null 2>&1; then
    echo "[ERROR] Falta alsa-utils. Instalalo con: sudo pacman -S alsa-utils" >&2
    exit 1
fi

# ── 1. Script que aplica el fix ───────────────────────────────────────────────
cat > "$SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# asus-g14-speaker-fix: fuerza el estado de los mixers de parlantes internos
# del ALC285 (ASUS ROG Zephyrus G14 GA403UV).
#
# El ALC285 expone 'Speaker' y 'Bass Speaker', que quedan en 0/off por defecto
# y dejan sin señal a los amplificadores CS35L56. Este script los sube/activa.
# Lo ejecuta asus-g14-speaker-fix.service al arrancar y al volver de suspensión.

set -u

# Detectar el número de tarjeta del códec ALC285
card="$(aplay -l 2>/dev/null | sed -n 's/^card \([0-9][0-9]*\): .*ALC285.*/\1/p' | head -n1)"

if [[ -z "$card" ]]; then
    # Fallback: primera tarjeta que exponga el control 'Bass Speaker'
    for c in /proc/asound/card*; do
        n="${c##*card}"
        if amixer -c "$n" sget 'Bass Speaker' >/dev/null 2>&1; then
            card="$n"
            break
        fi
    done
fi

[[ -z "$card" ]] && exit 0

amixer -c "$card" sset 'Speaker' 100% unmute >/dev/null 2>&1 || true
amixer -c "$card" sset 'Bass Speaker' on >/dev/null 2>&1 || true
EOF
chmod +x "$SCRIPT_PATH"
echo "  ✓ $SCRIPT_PATH"

# ── 2. Servicio systemd ───────────────────────────────────────────────────────
cat > "$SERVICE_PATH" << 'EOF'
[Unit]
Description=Force ALC285 speaker mixers (ASUS ROG G14)
After=sound.target alsa-restore.service suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/asus-g14-speaker-fix

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
echo "  ✓ $SERVICE_PATH"

# ── 3. Aplicar ahora, guardar estado y habilitar el servicio ──────────────────
"$SCRIPT_PATH" || true

if command -v alsactl >/dev/null 2>&1; then
    alsactl store
    echo "  ✓ Estado ALSA guardado en /var/lib/alsa/asound.state"
fi

systemctl daemon-reload
systemctl enable --now asus-g14-speaker-fix.service
echo "  ✓ asus-g14-speaker-fix.service habilitado y activo"

echo ""
echo "Listo. Los parlantes internos quedan activos al arrancar y al volver de suspensión."
echo "Para verificar:"
echo "  amixer -c 2 sget Speaker        # debe estar en 100% y on"
echo "  amixer -c 2 sget 'Bass Speaker' # debe estar on"
