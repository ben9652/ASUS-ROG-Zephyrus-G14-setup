#!/usr/bin/env bash
# instalar-mods-rdr2.sh
#
# Instala Lenny's Mod Loader (LML) en Red Dead Redemption 2 y deja todo listo
# para instalar el mod de glyphs de PlayStation/DualSense.
#
# QUÉ HACE:
#   1. Descarga desde ModsCloud.net (links directos, sin login):
#        · Lenny's Mod Loader RDR  → vfs.asi, lml.ini, carpeta lml/, DLLs
#        · Script Hook RDR2        → se usa solo su dinput8.dll (ASI loader)
#   2. Copia al directorio del juego:
#        · dinput8.dll, vfs.asi, lml.ini, ModManager*.dll, NLog.dll, lml/
#   3. Instala el mod de glyphs que le indiques:
#        · --mod-zip archivo.zip   → desde un archivo local (zip/rar/7z)
#        · --nexus-api-key KEY     → descarga desde Nexus Mods (requiere Premium)
#          Mod: "PlayStation Icons Replacement" (Nexus 660), archivo (PS5),
#          que reemplaza los glyphs de Xbox por iconos de DualSense.
#      Si no indicás ninguno, solo instala LML y te dice qué falta.
#   4. Configura las opciones de lanzamiento de Steam (si Steam está cerrado):
#        WINEDLLOVERRIDES="dinput8=n,b" prime-run %command%
#      Sin ese override Proton usa su dinput8 y LML nunca carga.
#
# USO:
#   bash instalar-mods-rdr2.sh                              # LML + ASI loader
#   bash instalar-mods-rdr2.sh --mod-zip ~/Descargas/ps5.zip
#   bash instalar-mods-rdr2.sh --nexus-api-key TU_API_KEY
#   bash instalar-mods-rdr2.sh --nexus-api-key TU_API_KEY --nxm 'nxm://reddeadredemption2/mods/660/files/4687?key=...&expires=...'
#   bash instalar-mods-rdr2.sh --force                      # reinstala encima
#   sudo bash instalar-mods-rdr2.sh                         # válido (se re-ejecuta como usuario)
#
#   API key de Nexus: https://www.nexusmods.com/users/myaccount?tab=api
#   · Premium: alcanza con la API key.
#   · Cuenta free: Nexus exige además key+expires del link nxm://. Instalá una
#     vez 'setup-nexus-nxm-handler.sh' y usá el botón "Mod Manager Download";
#     este script detecta el link en ~/.cache/nexus-nxm.txt automáticamente.
#   · Sin API: descargá "PlayStation Icons Replacement (PS5)" a mano y usá --mod-zip.
#
# ADVERTENCIA:
#   · Mods SOLO para single-player. No entres al online (RDO) con mods: riesgo de ban.
#   · "Verificar integridad" en Steam borra los mods → volvé a correr este script.

set -euo pipefail

# ── re-ejecutar como el usuario real si se invocó con sudo ────────────────────
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    exec sudo -u "$SUDO_USER" HOME="$REAL_HOME" bash "$(readlink -f "$0")" "$@"
fi

FORCE=false
MOD_ZIP=""
NEXUS_KEY="${NEXUS_API_KEY:-}"
NXM_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true; shift ;;
        --mod-zip)
            MOD_ZIP="${2:-}"; shift 2 ;;
        --nexus-api-key)
            NEXUS_KEY="${2:-}"; shift 2 ;;
        --nxm)
            NXM_URL="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '2,50p' "$0"; exit 0 ;;
        *)
            echo "Opción desconocida: $1 (usá --help)"; exit 1 ;;
    esac
done

UA="Mozilla/5.0 (X11; Linux x86_64)"
MODSCLOUD="https://modscloud.net"
PAGE_LML="$MODSCLOUD/red-dead-redemption-2/rdr2-tools/lennys-mod-loader-rdr/"
PAGE_SH="$MODSCLOUD/red-dead-redemption-2/rdr2-scripts/rdr2-script-hook/"
NEXUS_GAME="reddeadredemption2"
NEXUS_MOD_ID="660"

LAUNCH_OPTIONS='WINEDLLOVERRIDES="dinput8=n,b" prime-run %command%'

# ── colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── dependencias ──────────────────────────────────────────────────────────────
for cmd in curl python3; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Falta el comando '$cmd'. Instalalo y volvé a intentar."
        exit 1
    fi
done

# ── localizar el juego ────────────────────────────────────────────────────────
detect_game_dir() {
    local base lf p
    if [[ -n "${RDR2_DIR:-}" ]]; then echo "$RDR2_DIR"; return; fi
    for base in "$HOME/.steam/steam" "$HOME/.local/share/Steam"; do
        if [[ -d "$base/steamapps/common/Red Dead Redemption 2" ]]; then
            echo "$base/steamapps/common/Red Dead Redemption 2"; return
        fi
    done
    for lf in "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
              "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf"; do
        [[ -f "$lf" ]] || continue
        while IFS= read -r p; do
            if [[ -d "$p/steamapps/common/Red Dead Redemption 2" ]]; then
                echo "$p/steamapps/common/Red Dead Redemption 2"; return
            fi
        done < <(grep -oP '"path"\s+"\K[^"]+' "$lf" 2>/dev/null || true)
    done
    echo ""
}

GAME_DIR="$(detect_game_dir)"
if [[ -z "$GAME_DIR" || ! -f "$GAME_DIR/RDR2.exe" ]]; then
    error "No se encontró la instalación de RDR2 (RDR2.exe)."
    error "Probá con: RDR2_DIR=/ruta/al/juego bash $0"
    exit 1
fi
info "Juego detectado en: $GAME_DIR"

if pgrep -af "RDR2.exe" &>/dev/null; then
    error "RDR2 está corriendo. Cerralo antes de instalar mods."
    exit 1
fi

# ── helpers de descarga / extracción ──────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

download() { # $1 url, $2 destino
    curl -fsSL -A "$UA" --retry 3 --max-time 180 -o "$2" "$1"
}

scrape_files() { # $1 = página de ModsCloud → "nombre<TAB>url"
    curl -fsSL -A "$UA" "$1" | python3 -c '
import sys, re, html
h = sys.stdin.read()
for m in re.finditer(r"<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", h, re.S | re.I):
    url = html.unescape(m.group(1))
    name = html.unescape(re.sub("<[^>]+>", "", m.group(2))).strip()
    if "download=" in url:
        print(f"{name}\t{url}")
'
}

get_first_url() { scrape_files "$1" | awk -F'\t' 'NF>1 && !seen[$2]++ {print $2; exit}'; }

extract_archive() { # $1 archivo, $2 destino
    local file="$1" dest="$2"
    mkdir -p "$dest"
    case "${file,,}" in
        *.zip)
            if command -v unzip &>/dev/null; then unzip -q "$file" -d "$dest"
            else bsdtar -xf "$file" -C "$dest"; fi ;;
        *.rar)
            if command -v unrar &>/dev/null; then unrar x -o+ -inul "$file" "$dest/"
            else bsdtar -xf "$file" -C "$dest"; fi ;;
        *.7z)
            if command -v 7z &>/dev/null; then 7z x -y -o"$dest" "$file" >/dev/null
            elif command -v 7za &>/dev/null; then 7za x -y -o"$dest" "$file" >/dev/null
            else bsdtar -xf "$file" -C "$dest"; fi ;;
        *)
            bsdtar -xf "$file" -C "$dest" ;;
    esac
}

install_lml_mod() { # $1 = carpeta extraída, $2 = nombre de referencia
    local src="$1" label="$2" xml dir dest
    if [[ -d "$src/lml" ]]; then                   # el paquete ya trae lml/
        mkdir -p "$GAME_DIR/lml"
        cp -a "$src/lml/." "$GAME_DIR/lml/"
        return 0
    fi
    xml="$(find "$src" -maxdepth 3 -name install.xml -print -quit 2>/dev/null || true)"
    if [[ -n "$xml" ]]; then                       # carpeta de mod LML estándar
        dir="$(dirname "$xml")"
        if [[ "$dir" == "$src" ]]; then
            dest="$GAME_DIR/lml/$label"
            mkdir -p "$dest"; cp -a "$src/." "$dest/"
        else
            cp -a "$dir" "$GAME_DIR/lml/"
        fi
        return 0
    fi
    dest="$GAME_DIR/lml/$label"                    # fallback
    mkdir -p "$dest"; cp -a "$src/." "$dest/"
}

# ── paso 1: descargas base (LML + Script Hook) ────────────────────────────────
echo ""
info "Paso 1/4: descargando Lenny's Mod Loader y Script Hook..."
LML_URL="$(get_first_url "$PAGE_LML")"
SH_URL="$(get_first_url "$PAGE_SH")"
if [[ -z "$LML_URL" || -z "$SH_URL" ]]; then
    error "No se pudieron obtener los links de ModsCloud (¿cambió la página o no hay red?)."
    exit 1
fi
download "$LML_URL" "$TMP_DIR/lml.zip"
download "$SH_URL"  "$TMP_DIR/scripthook.zip"
info "  · lml.zip ($(du -h "$TMP_DIR/lml.zip" | cut -f1))"
info "  · scripthook.zip ($(du -h "$TMP_DIR/scripthook.zip" | cut -f1))"

# ── paso 2: LML + ASI loader ──────────────────────────────────────────────────
info "Paso 2/4: instalando Lenny's Mod Loader y el ASI loader..."
if [[ -e "$GAME_DIR/vfs.asi" && "$FORCE" != true ]]; then
    info "  · LML ya estaba instalado — se omite (usá --force para reinstalarlo)."
else
    mkdir -p "$TMP_DIR/lml"
    extract_archive "$TMP_DIR/lml.zip" "$TMP_DIR/lml"
    cp -a "$TMP_DIR/lml/ModLoader/." "$GAME_DIR/"
    rm -f "$GAME_DIR/_PLACE ALL THIS IN THE GAME ROOT"
    info "  · vfs.asi, lml.ini, ModManager*.dll, NLog.dll y lml/ instalados."
fi

if [[ -e "$GAME_DIR/dinput8.dll" && "$FORCE" != true ]]; then
    info "  · dinput8.dll ya existe (¿otro mod?) — se omite."
else
    [[ -e "$GAME_DIR/dinput8.dll" ]] && cp "$GAME_DIR/dinput8.dll" "$GAME_DIR/dinput8.dll.bak.$(date +%s)"
    if ! unzip -q -j "$TMP_DIR/scripthook.zip" 'bin/dinput8.dll' -d "$GAME_DIR" 2>/dev/null; then
        bsdtar -xf "$TMP_DIR/scripthook.zip" -C "$TMP_DIR" --include '*/dinput8.dll'
        cp "$(find "$TMP_DIR" -name dinput8.dll -print -quit)" "$GAME_DIR/"
    fi
    info "  · dinput8.dll (ASI loader) instalado."
fi

# ── paso 3: mod de glyphs ─────────────────────────────────────────────────────
echo ""
info "Paso 3/4: mod de glyphs de PlayStation/DualSense..."

# Sacar el mod viejo equivocado (era un recoloreado de botones de Xbox)
if [[ -d "$GAME_DIR/lml/Elegant_Gamepad_PlaystationXbox" ]]; then
    rm -rf "$GAME_DIR/lml/Elegant_Gamepad_PlaystationXbox"
    info "  · Eliminado 'Elegant_Gamepad_PlaystationXbox' (no era de PlayStation)."
fi

# Link nxm capturado por el handler (cuenta free) — se ignora si es viejo
if [[ -z "$NXM_URL" && -f "$HOME/.cache/nexus-nxm.txt" ]]; then
    if [[ -n "$(find "$HOME/.cache/nexus-nxm.txt" -mmin -15 2>/dev/null)" ]]; then
        NXM_URL="$(tail -1 "$HOME/.cache/nexus-nxm.txt")"
        info "  · Link nxm reciente detectado en ~/.cache/nexus-nxm.txt."
    fi
fi

GLYPH_SRC=""
if [[ -n "$MOD_ZIP" ]]; then
    if [[ ! -f "$MOD_ZIP" ]]; then
        error "--mod-zip: no existe el archivo $MOD_ZIP"
        exit 1
    fi
    info "  · Usando archivo local: $MOD_ZIP"
    extract_archive "$MOD_ZIP" "$TMP_DIR/modsrc"
    GLYPH_SRC="$TMP_DIR/modsrc"

elif [[ -n "$NEXUS_KEY" || -n "$NXM_URL" ]]; then
    info "  · Consultando Nexus (mod $NEXUS_MOD_ID: PlayStation Icons Replacement)..."
    NEXUS_HEADERS=(-A "$UA" -H "Accept: application/json" \
                   -H "Application-Name: instalar-mods-rdr2" \
                   -H "Application-Version: 1.0")
    [[ -n "$NEXUS_KEY" ]] && NEXUS_HEADERS+=(-H "apikey: $NEXUS_KEY")

    NXM_FILE_ID=""; NXM_KEY=""; NXM_EXPIRES=""
    if [[ -n "$NXM_URL" ]]; then
        _path="${NXM_URL#nxm://}"; _query="${_path#*\?}"; _path="${_path%%\?*}"
        NXM_FILE_ID="$(echo "$_path" | awk -F/ '{print $5}')"
        NXM_KEY="$(echo "$_query" | tr '&' '\n' | sed -n 's/^key=//p')"
        NXM_EXPIRES="$(echo "$_query" | tr '&' '\n' | sed -n 's/^expires=//p')"
        if [[ "$NXM_FILE_ID" =~ ^[0-9]+$ ]]; then
            info "  · Link nxm: archivo id $NXM_FILE_ID."
        else
            warn "  · No pude parsear el link nxm; se ignora."
            NXM_FILE_ID=""
        fi
    fi

    FILE_ID="$NXM_FILE_ID"; FILE_NAME=""
    if [[ -z "$FILE_ID" && -n "$NEXUS_KEY" ]]; then
        HTTP="$(curl -sSL "${NEXUS_HEADERS[@]}" -w '%{http_code}' -o "$TMP_DIR/files.json" \
                "https://api.nexusmods.com/v1/games/$NEXUS_GAME/mods/$NEXUS_MOD_ID/files.json" || echo 000)"
        if [[ "$HTTP" != "200" ]]; then
            warn "  · Nexus rechazó la lista de archivos (HTTP $HTTP)."
            NEXUS_MSG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("message",""))' "$TMP_DIR/files.json" 2>/dev/null || true)"
            [[ -n "$NEXUS_MSG" ]] && warn "    $NEXUS_MSG"
        else
            read -r FILE_ID FILE_NAME < <(python3 - "$TMP_DIR/files.json" <<'PYEOF'
import sys, json
files = json.load(open(sys.argv[1])).get("files", [])
cands = [f for f in files if any(k in f.get("name","").lower() for k in ("ps5","dualsense","dual sense"))]
pick = (cands or files)[0] if (cands or files) else {}
print(pick.get("file_id",""), pick.get("name","").replace(" ","_"))
PYEOF
)
            [[ -n "$FILE_ID" ]] && info "  · Archivo elegido: ${FILE_NAME//_/ } (id $FILE_ID)"
        fi
    fi

    if [[ -n "$FILE_ID" ]]; then
        DL_ENDPOINT="https://api.nexusmods.com/v1/games/$NEXUS_GAME/mods/$NEXUS_MOD_ID/files/$FILE_ID/download_link.json"
        [[ -n "$NXM_KEY" ]] && DL_ENDPOINT+="?key=$NXM_KEY&expires=$NXM_EXPIRES"
        HTTP="$(curl -sSL "${NEXUS_HEADERS[@]}" -w '%{http_code}' -o "$TMP_DIR/link.json" "$DL_ENDPOINT" || echo 000)"
        if [[ "$HTTP" != "200" ]]; then
            warn "  · Nexus no dio link de descarga (HTTP $HTTP)."
            NEXUS_MSG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("message",""))' "$TMP_DIR/link.json" 2>/dev/null || true)"
            [[ -n "$NEXUS_MSG" ]] && warn "    $NEXUS_MSG"
            if [[ -z "$NXM_KEY" ]]; then
                warn "    Cuenta free: falta el link nxm. Instalá una vez"
                warn "    'setup-nexus-nxm-handler.sh' y click en 'Mod Manager"
                warn "    Download' del archivo (PS5) en la pestaña Files; este"
                warn "    script lo detecta solo en ~/.cache/nexus-nxm.txt."
            fi
        else
            DL_URL="$(python3 -c 'import sys,json; print(json.load(open(sys.argv[1]))[0]["URI"])' "$TMP_DIR/link.json")"
            download "$DL_URL" "$TMP_DIR/glyphs.bin"
            extract_archive "$TMP_DIR/glyphs.bin" "$TMP_DIR/modsrc"
            GLYPH_SRC="$TMP_DIR/modsrc"
        fi
    fi
fi

if [[ -n "$GLYPH_SRC" ]]; then
    install_lml_mod "$GLYPH_SRC" "PlayStation Icons Replacement (PS5)"
    if find "$GAME_DIR/lml" -maxdepth 3 -name install.xml -print -quit | grep -q .; then
        info "  · Mod de glyphs instalado en lml/."
    else
        warn "  · Se copiaron archivos, pero no encontré install.xml (revisá el contenido)."
    fi
else
    warn "  · No se instaló ningún mod de glyphs."
    warn "    Opciones:"
    warn "      a) Descargá 'PlayStation Icons Replacement (PS5)' desde"
    warn "         https://www.nexusmods.com/reddeadredemption2/mods/660?tab=files"
    warn "         y corré:  bash $0 --mod-zip /ruta/al/archivo.zip"
    warn "      b) Con API key (free o premium) y el handler nxm instalado:"
    warn "         bash $0 --nexus-api-key TU_API_KEY"
fi

# ── paso 4: opciones de lanzamiento de Steam ──────────────────────────────────
echo ""
info "Paso 4/4: configurando opciones de lanzamiento de Steam..."

if pgrep -x steam &>/dev/null; then
    warn "Steam está abierto: no edité LaunchOptions (las sobreescribe al cerrar)."
    warn "Cerrá Steam y volvé a ejecutar el script, o pegalo a mano en"
    warn "RDR2 → Propiedades → Opciones de lanzamiento:"
    echo "      $LAUNCH_OPTIONS"
else
    declare -A SEEN_VDF=()
    for vdf in "$HOME/.steam/steam/userdata/"*/config/localconfig.vdf \
               "$HOME/.local/share/Steam/userdata/"*/config/localconfig.vdf; do
        [[ -f "$vdf" ]] || continue
        REAL_VDF="$(readlink -f "$vdf")"
        [[ -n "${SEEN_VDF[$REAL_VDF]:-}" ]] && continue
        SEEN_VDF[$REAL_VDF]=1
        cp "$vdf" "$vdf.bak.$(date +%s)"
        RESULT="$(python3 - "$vdf" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path, encoding="utf-8", errors="surrogateescape") as fh:
    lines = [l.rstrip("\n") for l in fh.readlines()]

block_start = block_end = None
i = 0
while i < len(lines):
    if re.match(r'^\s*"1174180"\s*$', lines[i]) and i + 1 < len(lines) and lines[i+1].strip().startswith("{"):
        depth = 0
        for j in range(i + 1, len(lines)):
            depth += lines[j].count("{") - lines[j].count("}")
            if depth == 0:
                block = "".join(lines[i:j+1])
                if '"Playtime"' in block or '"LastPlayed"' in block:
                    block_start, block_end = i, j
                i = j
                break
    if block_start is not None:
        break
    i += 1

if block_start is None:
    print("NOBLOCK")
    sys.exit(0)

for k in range(block_start + 1, block_end + 1):
    m = re.match(r'^(\s*)"LaunchOptions"\s+"(.*)"\s*$', lines[k])
    if m:
        current = m.group(2).replace('\\"', '"')
        if "dinput8=n,b" in current:
            print("ALREADY")
            sys.exit(0)
        base = current if current else "prime-run %command%"
        if "%command%" not in base:
            base += " %command%"
        new = 'WINEDLLOVERRIDES="dinput8=n,b" ' + base
        lines[k] = m.group(1) + '"LaunchOptions"\t\t"' + new.replace('"', '\\"') + '"'
        break
else:
    indent = re.match(r'^(\s*)', lines[block_start + 1]).group(1)
    new = 'WINEDLLOVERRIDES="dinput8=n,b" prime-run %command%'
    lines.insert(block_end, indent + '"LaunchOptions"\t\t"' + new.replace('"', '\\"') + '"')

with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
    fh.write("\n".join(lines) + "\n")
print("UPDATED")
PYEOF
)"
        case "$RESULT" in
            UPDATED) info "  · LaunchOptions actualizadas en: $vdf (backup .bak)" ;;
            ALREADY) info "  · LaunchOptions ya contenían el override — sin cambios." ;;
            NOBLOCK) warn "  · No encontré el bloque de RDR2 en $vdf — configurá las opciones a mano." ;;
        esac
    done
fi

# ── verificación final ────────────────────────────────────────────────────────
echo ""
info "Verificando instalación..."
MISSING=0
for f in dinput8.dll vfs.asi lml.ini ModManager.Core.dll NLog.dll; do
    if [[ -f "$GAME_DIR/$f" ]]; then echo "  ✓ $f"; else echo "  ✗ $f  (FALTA)"; MISSING=1; fi
done
echo "  · Mods LML instalados:"
find "$GAME_DIR/lml" -maxdepth 2 -name install.xml 2>/dev/null | while read -r xml; do
    echo "      - $(basename "$(dirname "$xml")")"
done

echo ""
if [[ "$MISSING" -eq 0 ]]; then
    echo "  Base lista (LML + ASI loader)."
else
    warn "Faltan archivos base. Probá con --force."
fi
echo "  · Iniciá RDR2: los prompts deberían verse de PlayStation/DualSense."
echo "  · RDO: no entres al online con mods instalados."
