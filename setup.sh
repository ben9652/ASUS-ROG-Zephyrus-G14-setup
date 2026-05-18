#!/usr/bin/env bash
# setup.sh
# Script de configuración inicial del sistema.
# Ejecuta en orden los pasos de configuración del entorno gaming.
#
# Uso: sudo ./setup.sh

set -euo pipefail

# ── colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${CYAN}${BOLD}══ $* ══${NC}\n"; }

# ── requiere root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Este script debe ejecutarse como root (sudo $0)"
    exit 1
fi

# Resolver HOME al directorio real del usuario que invocó sudo,
# para que los scripts hijos accedan a ~/.config/ correctamente.
if [[ -n "${SUDO_USER:-}" ]]; then
    export HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")/scripts" && pwd)"

run_step() {
    local num="$1" name="$2" script="$3"
    header "Paso $num: $name"
    if [[ ! -f "$SCRIPTS_DIR/$script" ]]; then
        error "Script no encontrado: $SCRIPTS_DIR/$script"
        exit 1
    fi
    bash "$SCRIPTS_DIR/$script"
    info "Paso $num completado."
}

# ── ejecución ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}Configuración inicial — ASUS ROG Zephyrus G14 GA403UV${NC}"
echo -e "Fecha: $(date '+%d/%m/%Y %H:%M')\n"

run_step 1 "Configuración de idioma del teclado"       "setup-keyboard-layout-switcher.sh"
run_step 2 "Configuración de luces del teclado"        "setup-keyboard-ambient.sh"
run_step 3 "Instalación de VSCode"                     "instalar-vscode.sh"
run_step 4 "Instalación de trans (translate-shell)"    "instalar-trans.sh"
run_step 5 "Instalación de Steam"                      "instalar-steam.sh"
run_step 6 "Limpieza automática de shader cache Steam"  "setup-steam-shadercache-cleanup.sh"
run_step 7 "Perfiles de rendimiento (Fn+F5)"           "setup-power-profiles.sh"
run_step 8 "Runtime power management (PCI/NVMe/USB)"   "setup-runtime-pm.sh"
run_step 9 "Botón M4 → ROG Control Center"             "setup-m4-rog-control.sh"
run_step 10 "Comandos de voz (Vosk)"                    "setup-voice-commands.sh"
run_step 11 "Atajos de captura de pantalla"             "setup-screenshots.sh"
run_step 12 "Compatibilidad Omarchy ↔ Hyprland"         "setup-hyprland-compat.sh"

# Paso 13 modifica ~/.config/ y llama a hyprctl: debe correr como el usuario real
header "Paso 13: Escala de Steam en monitor Full HD + laptop 3K"
if [[ -z "${SUDO_USER:-}" ]]; then
    warn "SUDO_USER no definido; ejecutando setup-steam-display.sh como root (puede fallar)."
    bash "$SCRIPTS_DIR/setup-steam-display.sh"
else
    sudo -u "$SUDO_USER" bash "$SCRIPTS_DIR/setup-steam-display.sh"
fi
info "Paso 13 completado."

echo -e "\n${GREEN}${BOLD}Configuración completa.${NC}"
echo -e "\n${YELLOW}IMPORTANTE — pasos finales como usuario (no root):${NC}"
echo -e "  1. Recarga Hyprland:   ${BOLD}hyprctl reload${NC}"
echo -e "  2. Reinicia Waybar:    ${BOLD}omarchy restart waybar${NC}"
echo -e "  3. Reinicia Steam para que la escala tome efecto."
