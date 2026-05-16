#!/usr/bin/env bash
# setup-power-profiles.sh
# Instala el ciclo de perfiles de energía mediante Fn+F5 en el ROG.
#
# Perfiles disponibles (vía power-profiles-daemon):
#   power-saver  → menor consumo, 60Hz (Silencio)
#   balanced     → uso general, 120Hz (Equilibrado)
#   performance  → máximo rendimiento, 120Hz (Rendimiento)
#
# Tecla configurada:
#   Fn+F5 (XF86Launch4) → cicla power-saver → balanced → performance → …
#
# También instala display-hz-sync: sincroniza Hz con el estado de AC automáticamente.
#
# Requisitos: power-profiles-daemon (powerprofilesctl), hyprctl
#
# Uso: bash setup-power-profiles.sh

set -euo pipefail

BINDIR="$HOME/.local/bin"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

mkdir -p "$BINDIR" "$SYSTEMD_USER_DIR"

# ── 1. Script power-profile-cycle ─────────────────────────────────────────────
cat > "$BINDIR/power-profile-cycle" << 'EOF'
#!/usr/bin/env bash
# power-profile-cycle: Cicla al siguiente perfil de energía con power-profiles-daemon.
# Orden: power-saver -> balanced -> performance -> power-saver -> ...

PROFILES=(power-saver balanced performance)
LABELS=("🔇 Silencio (60Hz)" "⚖️ Equilibrado (120Hz)" "🚀 Rendimiento (120Hz)")

current=$(powerprofilesctl get 2>/dev/null)

idx=0
for i in "${!PROFILES[@]}"; do
    [[ "${PROFILES[$i]}" == "$current" ]] && idx=$i && break
done

next=$(( (idx + 1) % ${#PROFILES[@]} ))
next_profile="${PROFILES[$next]}"
next_label="${LABELS[$next]}"

powerprofilesctl set "$next_profile"

# Adjust display refresh rate
if command -v hyprctl &>/dev/null; then
    case "$next_profile" in
        power-saver)
            hyprctl keyword monitor "eDP-2,2880x1800@60,0x0,2" &>/dev/null ;;
        *)
            hyprctl keyword monitor "eDP-2,2880x1800@120,0x0,2" &>/dev/null ;;
    esac
fi

notify-send "Perfil de energía" "$next_label" --icon=battery -t 2000
EOF
chmod +x "$BINDIR/power-profile-cycle"
echo "  ✓ $BINDIR/power-profile-cycle"

# ── 2. Script display-hz-sync ─────────────────────────────────────────────────
cat > "$BINDIR/display-hz-sync" << 'EOF'
#!/usr/bin/env bash
# display-hz-sync: Synchronizes display refresh rate with AC power state.
# 60Hz on battery, 120Hz when plugged in. Runs as a systemd user service.

apply_hz() {
    local online
    online=$(cat /sys/class/power_supply/ACAD/online 2>/dev/null || echo "1")
    if [[ "$online" == "1" ]]; then
        hyprctl keyword monitor "eDP-2,2880x1800@120,0x0,2" &>/dev/null
    else
        hyprctl keyword monitor "eDP-2,2880x1800@60,0x0,2" &>/dev/null
    fi
}

# Apply immediately on start
apply_hz

# Watch for AC state changes
stdbuf -oL udevadm monitor --kernel --subsystem-match=power_supply 2>/dev/null \
    | while read -r _; do
        apply_hz
    done
EOF
chmod +x "$BINDIR/display-hz-sync"
echo "  ✓ $BINDIR/display-hz-sync"

# ── 3. Systemd user service: display-hz-sync ──────────────────────────────────
cat > "$SYSTEMD_USER_DIR/display-hz-sync.service" << 'EOF'
[Unit]
Description=Display refresh rate sync with AC power state
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/display-hz-sync
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable display-hz-sync.service
echo "  ✓ display-hz-sync.service habilitado"

# ── 4. Udev rule: auto-switch power profile on AC plug/unplug ─────────────────
if [[ -w /etc/udev/rules.d ]]; then
    cat > /etc/udev/rules.d/99-power-profile.rules << 'EOF'
# Auto-switch power profile based on AC adapter state
SUBSYSTEM=="power_supply", KERNEL=="ACAD", ATTR{online}=="0", RUN+="/usr/bin/powerprofilesctl set power-saver"
SUBSYSTEM=="power_supply", KERNEL=="ACAD", ATTR{online}=="1", RUN+="/usr/bin/powerprofilesctl set balanced"
EOF
    echo "  ✓ /etc/udev/rules.d/99-power-profile.rules"
else
    echo "  · Omitiendo udev rule (requiere root). Ejecuta el script con sudo para instalarla."
fi

# ── 5. Keybinding en Hyprland ─────────────────────────────────────────────────
BINDING_COMMENT="# Fn+F5 (XF86Launch4): ciclar perfil de energía (power-saver / balanced / performance)"
BINDING_LINE="bindd = , XF86Launch4, Power profile cycle, exec, power-profile-cycle"

if ! grep -qF "XF86Launch4" "$HYPR_BINDINGS" 2>/dev/null; then
    {
        echo ""
        echo "$BINDING_COMMENT"
        echo "$BINDING_LINE"
    } >> "$HYPR_BINDINGS"
    echo "  ✓ Binding añadido a $HYPR_BINDINGS"
else
    echo "  · Binding XF86Launch4 ya existe, no se modifica"
fi

# ── 6. Recargar Hyprland si está corriendo ────────────────────────────────────
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    echo "  ✓ Hyprland recargado"
fi

echo ""
echo "Configuración completada."
echo ""
echo "  Fn+F5  →  ciclar perfil de energía (Silencio 60Hz / Equilibrado 120Hz / Rendimiento 120Hz)"
echo "  AC     →  se cambia automáticamente (desconectado=Silencio, conectado=Equilibrado)"
