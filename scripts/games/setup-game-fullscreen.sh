#!/usr/bin/env bash
# setup-game-fullscreen.sh
#
# Hace que TODOS los juegos se abran en pantalla completa real en Hyprland/Omarchy.
#
# PROBLEMA:
#   En Wayland no existe el fullscreen exclusivo. Los juegos (Steam/Proton,
#   Wine) en modo "Fullscreen" crean una ventana borderless del tamaño de la
#   pantalla, pero no le piden al compositor el estado "fullscreen". Hyprland
#   la trata como una ventana normal: respeta el espacio reservado de la barra,
#   queda desfasada y el sobrante se corta (se ve wallpaper abajo o al costado).
#
#   Pasa con cualquier juego, no solo con Red Dead Redemption 2.
#
# SOLUCIÓN:
#   Reglas de ventana generales en ~/.config/hypr/games.lua:
#     · Todos los juegos de Steam  → class ^(steam_app_[0-9]+)$
#     · Wine/Proton fuera de Steam → class ^.*\.exe$
#       (Lutris, Heroic, Bottles; si algún instalador se abre fullscreen,
#        comentá esa línea en games.lua)
#
#   games.lua se carga con require("hypr.games") desde ~/.config/hypr/hyprland.lua.
#   No se modifica nada dentro de /usr/share/omarchy/.
#
# USO:
#   bash setup-game-fullscreen.sh           # aplica las reglas
#   bash setup-game-fullscreen.sh --force   # regenera games.lua (con backup)
#   sudo bash setup-game-fullscreen.sh      # también válido (se re-ejecuta como usuario)
#
# PARCHE MANUAL: con el juego abierto, Super+F lo pone en fullscreen al instante.
#
# Idempotente: se puede ejecutar varias veces sin duplicar nada.

set -euo pipefail

# ── re-ejecutar como el usuario real si se invocó con sudo ────────────────────
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    exec sudo -u "$SUDO_USER" HOME="$REAL_HOME" bash "$(readlink -f "$0")" "$@"
fi

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/hypr-lua.sh"

HYPR_DIR="$HOME/.config/hypr"
HYPR_CONF="$HYPR_DIR/hyprland.lua"
GAMES_LUA="$HYPR_DIR/games.lua"

# ── colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── validaciones ──────────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    error "Ejecutá este script como tu usuario (sin sudo), o invocalo con 'sudo'."
    exit 1
fi

if [[ ! -f "$HYPR_CONF" ]]; then
    error "No se encontró: $HYPR_CONF"
    error "Asegurate de que Hyprland/Omarchy está configurado antes de ejecutar este script."
    exit 1
fi

# ── paso 1: crear games.lua con las reglas generales ──────────────────────────
GAMES_BLOCK=$(cat <<'LUA'
-- Reglas generales para juegos en Hyprland — generado por setup-game-fullscreen.sh
--
-- En Wayland no hay fullscreen exclusivo: los juegos crean ventanas borderless
-- del tamaño de la pantalla sin pedirle el estado "fullscreen" al compositor.
-- Estas reglas fuerzan el fullscreen real de Hyprland.

-- Steam: todos los juegos usan la clase steam_app_<appid>
o.window({ class = "^(steam_app_[0-9]+)$" }, { fullscreen = true })

-- Wine/Proton fuera de Steam (Lutris, Heroic, Bottles): clase *.exe
-- Si algún instalador o diálogo se abre fullscreen, comentá esta línea.
o.window({ class = "^.*\\.exe$" }, { fullscreen = true })
LUA
)

if [[ -f "$GAMES_LUA" && "$FORCE" == false ]]; then
    info "Paso 1/2: $GAMES_LUA ya existe — sin cambios (usá --force para regenerarlo)."
else
    if [[ -f "$GAMES_LUA" ]]; then
        cp "$GAMES_LUA" "$GAMES_LUA.bak.$(date +%s)"
        info "Paso 1/2: backup de games.lua creado."
    fi
    hypr_lua_upsert_block "$GAMES_LUA" "game-fullscreen" "$GAMES_BLOCK"
    info "Paso 1/2: creado $GAMES_LUA."
fi

# ── paso 2: cargar games.lua desde hyprland.lua ───────────────────────────────
if grep -qE 'require\(["'"'"']hypr\.games["'"'"']\)' "$HYPR_CONF"; then
    info "Paso 2/2: hyprland.lua ya carga hypr.games — sin cambios."
else
    cp "$HYPR_CONF" "$HYPR_CONF.bak.$(date +%s)"
    hypr_lua_require_module "$HYPR_CONF" "hypr.games"
    info "Paso 2/2: añadido require(\"hypr.games\") a hyprland.lua (backup creado)."
fi

# ── recarga y validación ──────────────────────────────────────────────────────
echo ""
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload &>/dev/null || true
    ERRORS="$(hyprctl configerrors 2>/dev/null || true)"
    if [[ -z "$ERRORS" || "$ERRORS" == *"no config errors"* ]]; then
        info "Hyprland recargado sin errores."
    else
        warn "Hyprland recargó con advertencias:"
        echo "$ERRORS"
    fi
else
    warn "hyprctl no disponible. Recargá Hyprland manualmente: hyprctl reload"
fi

echo ""
echo "  ✓ Los juegos de Steam y de Wine deberían abrir en pantalla completa real."
echo "  · Si alguno queda raro igual: Super+F lo pone en fullscreen al instante."
echo "  · Dentro del juego conviene elegir 'Windowed Borderless' (más estable"
echo "    en Wayland); con estas reglas se ve igual de fullscreen."
echo "  · Si un instalador de Wine se abre fullscreen y molesta, comentá la"
echo "    línea del '.exe' en ~/.config/hypr/games.lua y recargá Hyprland."
