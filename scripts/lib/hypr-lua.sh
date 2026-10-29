#!/usr/bin/env bash
# lib/hypr-lua.sh
#
# Helpers compartidos para que los scripts de este repo escriban configuración
# de Hyprland en el formato Lua que usa Omarchy 4.x (Quattro).
#
# Los scripts NO editan /usr/share/omarchy: solo escriben en ~/.config/hypr/*.lua
# usando bloques delimitados por marcadores, de modo que se pueden volver a
# ejecutar sin duplicar líneas y sin pisar el resto de la configuración del
# usuario.
#
# Uso:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/hypr-lua.sh"

HYPR_LUA_MARKER_PREFIX="${HYPR_LUA_MARKER_PREFIX:-omarchy-g14}"

# hypr_lua_upsert_block <archivo> <tag> <cuerpo-lua>
#
# Reemplaza el bloque delimitado por:
#   -- >>> omarchy-g14:<tag>
#   ...
#   -- <<< omarchy-g14:<tag>
# o lo añade al final si todavía no existe. Crea el archivo (y su directorio)
# si hace falta.
hypr_lua_upsert_block() {
    local file="$1" tag="$2" body="${3:-}"

    mkdir -p "$(dirname "$file")"

    HYPR_BLOCK_FILE="$file" \
    HYPR_BLOCK_TAG="$tag" \
    HYPR_BLOCK_PREFIX="$HYPR_LUA_MARKER_PREFIX" \
    HYPR_BLOCK_BODY="$body" \
    python3 - <<'PY'
import os
import re

path = os.environ["HYPR_BLOCK_FILE"]
tag = os.environ["HYPR_BLOCK_TAG"]
prefix = os.environ["HYPR_BLOCK_PREFIX"]
body = os.environ["HYPR_BLOCK_BODY"].strip("\n")

start = f"-- >>> {prefix}:{tag}"
end = f"-- <<< {prefix}:{tag}"
block = f"{start}\n"
if body:
    block += body + "\n"
block += end + "\n"

try:
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
except FileNotFoundError:
    text = ""

pattern = re.compile(
    rf"(?ms)^\s*{re.escape(start)}.*?^\s*{re.escape(end)}[ \t]*\n?"
)

if pattern.search(text):
    text = pattern.sub(lambda _m: block, text, count=1)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += block

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER:" "$file" 2>/dev/null || true
    fi
}

# hypr_lua_require_module <hyprland.lua> <modulo>
#
# Añade require("<modulo>") al final de hyprland.lua si todavía no está.
hypr_lua_require_module() {
    local file="$1" module="$2"

    if [[ ! -f "$file" ]]; then
        echo "  ⚠ No se encontró $file; no se pudo añadir require(\"$module\")." >&2
        return 1
    fi

    if grep -qE "require\\(['\"]${module}['\"]\\)" "$file"; then
        return 0
    fi

    printf '\nrequire("%s")\n' "$module" >>"$file"

    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER:" "$file" 2>/dev/null || true
    fi
}

# hypr_lua_reload
#
# Recarga Hyprland como el usuario real (útil cuando el script corre con sudo).
hypr_lua_reload() {
    if ! command -v hyprctl >/dev/null 2>&1; then
        return 0
    fi

    if [[ $EUID -eq 0 ]]; then
        local real_user="${SUDO_USER:-}"
        if [[ -n "$real_user" ]]; then
            sudo -u "$real_user" hyprctl reload >/dev/null 2>&1 || true
            return 0
        fi
    fi

    hyprctl reload >/dev/null 2>&1 || true
}

# hypr_lua_config_errors
#
# Imprime los errores de configuración de Hyprland (vacío si no hay).
hypr_lua_config_errors() {
    if ! command -v hyprctl >/dev/null 2>&1; then
        return 0
    fi

    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" hyprctl configerrors 2>/dev/null || true
    else
        hyprctl configerrors 2>/dev/null || true
    fi
}
