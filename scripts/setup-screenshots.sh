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
HYPR_BINDINGS="$REAL_HOME/.config/hypr/bindings.lua"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hypr-lua.sh"

# ── 1. Dependencias ───────────────────────────────────────────────────────────

echo "==> [1/2] Instalando herramientas de captura..."
pacman -S --noconfirm --needed grim slurp wl-clipboard hyprpicker satty
echo "  ✓ grim slurp wl-clipboard hyprpicker satty"

# ── 2. Keybindings ────────────────────────────────────────────────────────────

echo "==> [2/2] Configurando atajos de captura de pantalla..."

BINDINGS_BLOCK=$(cat <<'LUA'
o.bind("XF86Launch5", "Smart screenshot", "omarchy-capture-screenshot")

-- Omarchy 4.x asigna Super+Shift+S a Google Maps; lo reemplazamos por la
-- selección de región (estilo Windows Snipping Tool).
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Region screenshot", "omarchy-capture-screenshot region")
LUA
)

hypr_lua_upsert_block "$HYPR_BINDINGS" "screenshots" "$BINDINGS_BLOCK"
echo "    ✓ Atajos de captura sincronizados en $HYPR_BINDINGS"

# ── Recargar atajos ───────────────────────────────────────────────────────────

if [[ -n "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$REAL_USER" hyprctl reload &>/dev/null || true
    else
        hyprctl reload &>/dev/null || true
    fi
fi

echo ""
echo "Capturas de pantalla configuradas."
echo "  Fn+F6          → captura inteligente (selecciona región o ventana)"
echo "  Super+Shift+S  → selección de región"
echo ""
echo "  Las capturas se guardan en ~/Pictures y se copian al portapapeles."
echo "  Después de capturar puedes anotar con Satty (editor integrado)."
