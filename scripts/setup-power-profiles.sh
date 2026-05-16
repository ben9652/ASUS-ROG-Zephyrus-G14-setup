#!/usr/bin/env bash
# setup-power-profiles.sh
# Instala el ciclo de perfiles de rendimiento mediante Fn+F5 en el ROG.
#
# Perfiles disponibles (vía asusctl):
#   Quiet      → menor consumo, ventiladores silenciosos
#   Balanced   → uso general
#   Performance → máximo rendimiento
#
# Tecla configurada:
#   Fn+F5 (XF86Launch4) → cicla Quiet → Balanced → Performance → …
#
# Requisitos: asusctl (asusd debe estar activo)
#
# Uso: bash setup-power-profiles.sh

set -euo pipefail

BINDIR="$HOME/.local/bin"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"

mkdir -p "$BINDIR"

# ── 1. Script power-profile-cycle ─────────────────────────────────────────────
cat > "$BINDIR/power-profile-cycle" << 'EOF'
#!/usr/bin/env bash
# power-profile-cycle: Cicla al siguiente perfil de rendimiento con asusctl.
# Orden: LowPower → Balanced → Performance → LowPower → …

PROFILES=(LowPower Balanced Performance)
LABELS=("🔇 Silencio" "⚖️ Equilibrado" "🚀 Rendimiento")

current=$(asusctl profile get 2>/dev/null | grep "^Active profile:" | awk '{print $NF}')

idx=0
for i in "${!PROFILES[@]}"; do
    [[ "${PROFILES[$i]}" == "$current" ]] && idx=$i
done

next=$(( (idx + 1) % ${#PROFILES[@]} ))
next_profile="${PROFILES[$next]}"
next_label="${LABELS[$next]}"

asusctl profile set "$next_profile"

notify-send "Perfil de energía" "$next_label" --icon=battery -t 2000
EOF
chmod +x "$BINDIR/power-profile-cycle"
echo "  ✓ $BINDIR/power-profile-cycle"

# ── 2. Keybinding en Hyprland ─────────────────────────────────────────────────
BINDING_COMMENT="# Fn+F5 (XF86Launch4): ciclar perfil de rendimiento (Quiet → Balanced → Performance)"
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

# ── 3. Verificar que asusd está activo ────────────────────────────────────────
# asusd requiere que /etc/asusd exista (ReadWritePaths en su unit file)
mkdir -p /etc/asusd

if ! systemctl is-active --quiet asusd 2>/dev/null; then
    echo "  ⚠ asusd no está activo. Iniciando..."
    systemctl reset-failed asusd 2>/dev/null || true
    systemctl start asusd || echo "  ⚠ No se pudo iniciar asusd. Comprueba con: systemctl status asusd"
fi

# ── 4. Recargar Hyprland si está corriendo ────────────────────────────────────
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    echo "  ✓ Hyprland recargado"
fi

echo ""
echo "Configuración completada."
echo ""
echo "  Fn+F5  →  ciclar perfil de rendimiento (Quiet / Balanced / Performance)"
