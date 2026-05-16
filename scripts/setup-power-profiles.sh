#!/usr/bin/env bash
# setup-power-profiles.sh
# Instala el ciclo de perfiles de energía mediante Fn+F5 en el ROG.
#
# Perfiles disponibles (vía power-profiles-daemon):
#   power-saver  → menor consumo (Silencio)
#   balanced     → uso general (Equilibrado)
#   performance  → máximo rendimiento (Rendimiento)
#
# Tecla configurada:
#   Fn+F5 (XF86Launch4) → cicla power-saver → balanced → performance → …
#
# Requisitos: power-profiles-daemon (powerprofilesctl)
#
# Uso: bash setup-power-profiles.sh

set -euo pipefail

BINDIR="$HOME/.local/bin"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"

mkdir -p "$BINDIR"

# ── 1. Script power-profile-cycle ─────────────────────────────────────────────
cat > "$BINDIR/power-profile-cycle" << 'EOF'
#!/usr/bin/env bash
# power-profile-cycle: Cicla al siguiente perfil de energía con power-profiles-daemon.
# Orden: power-saver -> balanced -> performance -> power-saver -> ...

PROFILES=(power-saver balanced performance)
LABELS=("🔇 Silencio" "⚖️ Equilibrado" "🚀 Rendimiento")

current=$(powerprofilesctl get 2>/dev/null)

idx=0
for i in "${!PROFILES[@]}"; do
    [[ "${PROFILES[$i]}" == "$current" ]] && idx=$i && break
done

next=$(( (idx + 1) % ${#PROFILES[@]} ))
next_profile="${PROFILES[$next]}"
next_label="${LABELS[$next]}"

powerprofilesctl set "$next_profile"

notify-send "Perfil de energía" "$next_label" --icon=battery -t 2000
EOF
chmod +x "$BINDIR/power-profile-cycle"
echo "  ✓ $BINDIR/power-profile-cycle"

# ── 2. Keybinding en Hyprland ─────────────────────────────────────────────────
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

# ── 3. Recargar Hyprland si está corriendo ─────────────────────────────────────
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    echo "  ✓ Hyprland recargado"
fi

echo ""
echo "Configuración completada."
echo ""
echo "  Fn+F5  →  ciclar perfil de energía (Silencio / Equilibrado / Rendimiento)"
