#!/usr/bin/env bash
# setup-screenshots.sh
#
# Configura los atajos de captura de pantalla del ROG Zephyrus G14:
#
#   Fn+F6 (XF86Launch5) → captura inteligente (ventana o región)
#   Super+Shift+S       → selección de región (estilo Windows Snipping Tool)
#
# Herramientas necesarias (ya incluidas en Omarchy):
#   grim       ← captura de pantalla en Wayland
#   slurp      ← selección interactiva de región
#   wl-clipboard ← portapapeles Wayland
#   hyprpicker ← overlay de congelación durante la selección
#   satty      ← editor de anotaciones post-captura
#
# Uso: sudo bash setup-screenshots.sh
# (invocado desde setup.sh)

set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
HYPR_BINDINGS="$REAL_HOME/.config/hypr/bindings.conf"

# ── 1. Dependencias ───────────────────────────────────────────────────────────

echo "==> [1/2] Instalando herramientas de captura..."
pacman -S --noconfirm --needed grim slurp wl-clipboard hyprpicker satty
echo "  ✓ grim slurp wl-clipboard hyprpicker satty"

# ── 2. Keybindings ────────────────────────────────────────────────────────────

echo "==> [2/2] Configurando atajos de captura de pantalla..."

if grep -qF 'XF86Launch5' "$HYPR_BINDINGS" 2>/dev/null; then
    echo "    Binding Fn+F6 (XF86Launch5) ya existe, sin cambios."
else
    cat >> "$HYPR_BINDINGS" << 'BIND'

# Fn+F6 (XF86Launch5): captura inteligente — selecciona región o ventana
bindd = , XF86Launch5, Smart screenshot, exec, omarchy-capture-screenshot
BIND
    echo "    ✓ Binding Fn+F6 (XF86Launch5) añadido."
fi

if grep -qE '^[^#]*SUPER SHIFT.*,.*S.*screenshot|^[^#]*screenshot.*SUPER SHIFT.*S' "$HYPR_BINDINGS" 2>/dev/null; then
    echo "    Binding Super+Shift+S ya existe, sin cambios."
else
    # Eliminar la línea comentada preexistente si la hay, para no dejar ruido
    sed -i '/^#.*bind.*SUPER SHIFT.*S.*omarchy-capture-screenshot/d' "$HYPR_BINDINGS"

    cat >> "$HYPR_BINDINGS" << 'BIND'

# Super+Shift+S: selección de región (estilo Windows Snipping Tool)
bindd = SUPER SHIFT, S, Region screenshot, exec, omarchy-capture-screenshot region
BIND
    echo "    ✓ Binding Super+Shift+S añadido."
fi

# ── Recargar atajos ───────────────────────────────────────────────────────────

if [[ -n "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    sudo -u "$REAL_USER" hyprctl keyword bind ", XF86Launch5, exec, omarchy-capture-screenshot" &>/dev/null || true
    sudo -u "$REAL_USER" hyprctl keyword bind "SUPER SHIFT, S, exec, omarchy-capture-screenshot region" &>/dev/null || true
fi

echo ""
echo "Capturas de pantalla configuradas."
echo "  Fn+F6          → captura inteligente (selecciona región o ventana)"
echo "  Super+Shift+S  → selección de región"
echo ""
echo "  Las capturas se guardan en ~/Pictures y se copian al portapapeles."
echo "  Después de capturar puedes anotar con Satty (editor integrado)."
