#!/usr/bin/env bash
# setup-steam-display.sh
#
# Soluciona el problema de escala de Steam en configuración multi-monitor mixta:
#   Pantalla laptop : 2880x1800 (3K), Hyprland scale=2.0
#   Monitor externo : 1920x1080 (Full HD), Hyprland scale=1.0
#
# PROBLEMA:
#   Steam es una app XWayland. Con force_zero_scaling=true (activo en Omarchy),
#   XWayland le reporta a Steam scale=1, pero Steam igual detecta el DPI físico
#   alto de la pantalla 3K y escala su UI 2x internamente. Resultado:
#     · En la laptop    → se ve pequeño (la UI 1x queda diminuta en 2880x1800)
#     · En el Full HD   → se ve enorme, excede la pantalla (la UI 2x sobre 1080p)
#
# SOLUCIÓN APLICADA:
#   1. STEAM_FORCE_DESKTOPUI_SCALING=1 en ~/.config/hypr/envs.lua
#      → Fuerza la UI de Steam a escala 1x sin auto-detección de DPI.
#   2. Regla de tamaño en ~/.config/hypr/hyprland.lua (solo si Omarchy no la trae)
#      → Garantiza que la ventana principal de Steam no exceda 1100x700.
#   3. (Opcional) Borrado de geometría guardada de Steam
#      → Limpia el tamaño/posición almacenado para que las nuevas reglas apliquen
#        desde cero en el primer arranque tras la corrección.
#
# USO:
#   bash setup-steam-display.sh          # aplica solo los cambios de Hyprland
#   bash setup-steam-display.sh --reset  # también borra la geometría guardada
#
# Seguro de ejecutar múltiples veces (idempotente).
# Requisito: Hyprland instalado y configurado en ~/.config/hypr/

set -euo pipefail

RESET_GEOMETRY=false
[[ "${1:-}" == "--reset" ]] && RESET_GEOMETRY=true

HYPR_ENVS="$HOME/.config/hypr/envs.lua"
HYPR_CONF="$HOME/.config/hypr/hyprland.lua"
STEAM_REGISTRY="$HOME/.local/share/Steam/registry.vdf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hypr-lua.sh"

# ── colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── validaciones ──────────────────────────────────────────────────────────────
if [[ ! -f "$HYPR_CONF" ]]; then
    error "No se encontró: $HYPR_CONF"
    error "Asegúrate de que Omarchy 4.x está configurado antes de ejecutar este script."
    exit 1
fi

# ── paso 1: STEAM_FORCE_DESKTOPUI_SCALING ─────────────────────────────────────
SCALING_VAR="STEAM_FORCE_DESKTOPUI_SCALING"
ENV_BLOCK=$(cat <<'LUA'
-- Steam: forzar escala de UI a 1x para evitar que se vea enorme en el monitor
-- Full HD cuando la pantalla de la laptop es 3K (scale=2.0).
hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "1")
LUA
)

hypr_lua_upsert_block "$HYPR_ENVS" "steam-display" "$ENV_BLOCK"
hypr_lua_require_module "$HYPR_CONF" "hypr.envs"
info "Paso 1/3: $SCALING_VAR=1 asegurado en envs.lua."

# ── paso 2: regla de tamaño ───────────────────────────────────────────────────
# Omarchy 4.x ya incluye la regla en default/hypr/apps/steam.lua:
#   o.window({ class = "steam", title = "Steam" }, { center = true, size = { 1100, 700 } })
# Con STEAM_FORCE_DESKTOPUI_SCALING=1 esa regla es suficiente.
if [[ -f "${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr/apps/steam.lua" ]]; then
    info "Paso 2/3: Omarchy ya gestiona el tamaño de la ventana de Steam — sin cambios."
else
    SIZE_BLOCK=$(cat <<'LUA'
o.window({ class = "steam", title = "Steam" }, { size = { 1100, 700 } })
LUA
)
    hypr_lua_upsert_block "$HYPR_CONF" "steam-size" "$SIZE_BLOCK"
    info "Paso 2/3: Regla de tamaño para Steam añadida a hyprland.lua."
fi

# ── paso 3 (opcional): resetear geometría guardada ───────────────────────────
if [[ "$RESET_GEOMETRY" == true ]]; then
    if pgrep -x steam &>/dev/null; then
        warn "Paso 3/3: Steam está corriendo. Ciérralo antes de resetear la geometría."
    else
        # Steam guarda posiciones de ventana en registry.vdf (formato binario/texto)
        # La clave relevante es "width"/"height" dentro del nodo MainWindowSize
        if [[ -f "$STEAM_REGISTRY" ]]; then
            cp "$STEAM_REGISTRY" "${STEAM_REGISTRY}.bak.$(date +%s)"
            # Eliminar las entradas de geometría de la ventana principal de Steam
            sed -i \
                -e '/\"MainWindowType\"/d' \
                -e '/\"MainWindowLeft\"/d' \
                -e '/\"MainWindowTop\"/d'  \
                -e '/\"MainWindowWidth\"/d' \
                -e '/\"MainWindowHeight\"/d' \
                "$STEAM_REGISTRY"
            info "Paso 3/3: Geometría guardada de Steam reseteada (backup en ${STEAM_REGISTRY}.bak)."
        else
            warn "Paso 3/3: No se encontró registry.vdf de Steam — no había geometría que limpiar."
        fi
    fi
else
    info "Paso 3/3: Omitido. Usa --reset para borrar también la geometría guardada de Steam."
fi

# ── recarga Hyprland ──────────────────────────────────────────────────────────
echo ""
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    ERRORS=$(hyprctl configerrors 2>/dev/null || true)
    if [[ -z "$ERRORS" || "$ERRORS" == "no config errors" ]]; then
        info "Hyprland recargado sin errores."
    else
        warn "Hyprland recargado con advertencias:"
        echo "$ERRORS"
    fi
else
    warn "hyprctl no disponible. Recarga Hyprland manualmente (Super+Shift+R o hyprctl reload)."
fi

echo ""
echo "  ✓ Reinicia Steam para que STEAM_FORCE_DESKTOPUI_SCALING=1 tome efecto."
echo "  · En la laptop, Steam seguirá viéndose pequeño en modo escritorio"
echo "    (lo esperado en 3K con scale=2). Usá Big Picture con el DualSense."
echo "  · En el monitor Full HD, Steam debería verse a tamaño normal."
