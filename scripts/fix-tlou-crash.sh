#!/usr/bin/env bash
# fix-tlou-crash.sh
# Corrige el crash de The Last of Us Part I causado por la discordancia de
# versión en lib32-opencl-nvidia (595.71.05 vs nvidia-utils 580.95.05).
#
# DIAGNÓSTICO:
#   - lib32-opencl-nvidia 595.71.05-1  ← actualizado accidentalmente por pacman -Syu
#   - nvidia-utils/lib32-nvidia-utils   ← se mantienen en 580.95.05 (IgnorePkg)
#   - El juego se cuelga ~70 seg después del inicio, durante compilación de shaders
#   - El log del juego termina tras detectar la GPU → crash en VKD3D/Proton
#   - NO hay errores de kernel (distinto al crash anterior de nvidia-powerd)
#
# CAUSA RAÍZ:
#   lib32-opencl-nvidia 595 intenta cargar la plataforma OpenCL de nvidia desde
#   lib32-nvidia-utils 580 → discordancia ABI → crash en proceso hijo de Proton.
#   lib32-opencl-nvidia NO estaba en IgnorePkg → se actualizó sola con pacman -Syu.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── verificar que corremos como root ─────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "Ejecuta con sudo: sudo bash $0"

step "1/3  Verificar discordancia de versiones NVIDIA"

NVIDIA_VER=$(LANG=C pacman -Qi nvidia-utils 2>/dev/null | awk '/^Version/{print $3}')
OPENCL_VER=$(LANG=C pacman -Qi lib32-opencl-nvidia 2>/dev/null | awk '/^Version/{print $3}')

info "nvidia-utils:        ${NVIDIA_VER:-no instalado}"
info "lib32-opencl-nvidia: ${OPENCL_VER:-no instalado}"

if [[ -z "${OPENCL_VER:-}" ]]; then
    info "lib32-opencl-nvidia no está instalado. Nada que hacer."
elif [[ "$OPENCL_VER" == "$NVIDIA_VER" ]]; then
    info "Versiones coinciden — no hay discordancia."
else
    warn "¡DISCORDANCIA DETECTADA! nvidia-utils=$NVIDIA_VER pero lib32-opencl-nvidia=$OPENCL_VER"
fi

step "2/3  Eliminar lib32-opencl-nvidia y añadir a IgnorePkg"

# Eliminar el paquete problemático (nada lo requiere — Required By: None)
if LANG=C pacman -Qi lib32-opencl-nvidia &>/dev/null; then
    info "Eliminando lib32-opencl-nvidia..."
    pacman -Rns --noconfirm lib32-opencl-nvidia
    info "Paquete eliminado."
else
    info "lib32-opencl-nvidia ya no está instalado."
fi

# Añadir lib32-opencl-nvidia a IgnorePkg si no está ya
PACMAN_CONF="/etc/pacman.conf"
if grep -qP "^IgnorePkg\s*=.*lib32-opencl-nvidia" "$PACMAN_CONF"; then
    info "lib32-opencl-nvidia ya está en IgnorePkg."
else
    info "Añadiendo lib32-opencl-nvidia a IgnorePkg en $PACMAN_CONF ..."
    # Añade al final de la línea IgnorePkg existente
    sed -i 's/^\(IgnorePkg\s*=.*\)$/\1 lib32-opencl-nvidia/' "$PACMAN_CONF"
    info "IgnorePkg actualizado: $(grep '^IgnorePkg' "$PACMAN_CONF")"
fi

step "3/3  Instrucciones para lanzar el juego con diagnóstico"

cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 LISTO. Próximos pasos para The Last of Us Part I:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 1. Abre Steam > clic derecho en TLOU Part I > Propiedades > General
    En "Opciones de lanzamiento" pon:
    
      PROTON_LOG=1 %command%

    Esto generará ~/steam-1888930.log con el log completo de Proton/VKD3D
    si el juego vuelve a crashear.

 2. Si el juego SIGUE crasheando después de este fix, añade también:
    
      PROTON_ENABLE_NVAPI=1 PROTON_LOG=1 %command%

    NVAPI permite que NVIDIA DLSS y el driver se comuniquen correctamente
    con VKD3D-Proton para juegos D3D12.

 3. Si aún falla, prueba este launch option alternativo (desactiva hardware
    video upload, a veces soluciona cuelgues en VKD3D con nvidia-open):
    
      VKD3D_CONFIG=no_upload_hvv PROTON_ENABLE_NVAPI=1 PROTON_LOG=1 %command%

 4. Tras probar, comparte ~/steam-1888930.log para un diagnóstico más preciso.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 RESUMEN DEL CRASH:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 • Diferente al crash anterior (ese era nvidia-powerd + GSP assertion failure)
 • Este crash: lib32-opencl-nvidia 595.71.05 vs nvidia-utils 580.95.05
 • lib32-opencl-nvidia se actualizó a las 00:38 (hoy) porque NO estaba en
   IgnorePkg, pero nvidia-utils sí → pacman -Syu los desincronizó
 • El juego duró ~70 segundos → crash durante compilación de shaders
 • Sin errores de kernel: el proceso de Proton crasheó en user-space
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
