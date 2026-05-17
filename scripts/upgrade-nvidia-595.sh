#!/usr/bin/env bash
# upgrade-nvidia-595.sh
# Actualiza SOLO el módulo del kernel nvidia-open-dkms de 580.95.05 a 595.71.05,
# manteniendo el userspace (nvidia-utils y compañía) en 580.95.05.
#
# ¿Por qué este split intencional?
#
#   - nvidia-open-dkms 595: corrige el bug del firmware GSP que causa:
#       NVRM: nvCheckFailedNoLog: Check failed: put < size @ crashcat_queue_v1.c:66
#     (overflow de la cola CrashCAT bajo carga de compilación de shaders)
#
#   - nvidia-utils 580 (Vulkan ICD): evita los artifacts de renderizado
#     (bloques en personajes, humo roto) que aparecen con el ICD 595.
#
# Esta combinación (kernel 595 + userspace 580) es la que funcionó
# exitosamente en una sesión de 20+ minutos previa. NVIDIA emite un
# "API mismatch" warning pero Vulkan opera correctamente.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

[[ $EUID -ne 0 ]] && err "Ejecuta con sudo: sudo bash $0"

PACMAN_CONF=/etc/pacman.conf

# ── 1. Sacar SOLO nvidia-open-dkms del IgnorePkg ────────────────────────────
info "Eliminando nvidia-open-dkms de IgnorePkg (manteniendo el userspace fijo)..."

cp "$PACMAN_CONF" "${PACMAN_CONF}.bak-$(date +%Y%m%d-%H%M%S)"

# Eliminar solo nvidia-open-dkms de la línea IgnorePkg
sed -i 's/\bnvidia-open-dkms\b *//g' "$PACMAN_CONF"
# Limpiar espacios dobles residuales en IgnorePkg
sed -i 's/IgnorePkg =  \+/IgnorePkg = /g' "$PACMAN_CONF"

info "IgnorePkg resultante:"
grep "IgnorePkg" "$PACMAN_CONF"

# Verificar que nvidia-utils siga en IgnorePkg (por seguridad)
if ! grep -q "nvidia-utils" "$PACMAN_CONF"; then
    err "nvidia-utils no está en IgnorePkg — algo salió mal. Revisa $PACMAN_CONF"
fi

# ── 2. Actualizar SOLO el módulo del kernel ──────────────────────────────────
# nvidia-open-dkms 595 depende de nvidia-utils=595, pero sabemos que la
# combinación 595 kernel + 580 userspace funciona (sesión de 20min verificada).
# --nodeps omite la verificación de versión de la dependencia.
info "Sincronizando repos y actualizando nvidia-open-dkms a 595..."
pacman -Sy --noconfirm
pacman -S --nodeps --noconfirm nvidia-open-dkms

# ── 3. Verificar versión instalada ──────────────────────────────────────────
KMOD_VER=$(pacman -Q nvidia-open-dkms 2>/dev/null | awk '{print $2}')
USPACE_VER=$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}')
info "nvidia-open-dkms : $KMOD_VER  (módulo del kernel — debe ser 595.x)"
info "nvidia-utils     : $USPACE_VER  (userspace/Vulkan ICD — debe ser 580.x)"

# ── 4. Extraer firmware 595 del paquete nvidia-utils 595 (en caché) ─────────
# El módulo del kernel 595 necesita /usr/lib/firmware/nvidia/595.71.05/gsp_ga10x.bin
# Este firmware viene en nvidia-utils 595, NO en nvidia-open-dkms.
# Sin él, /dev/nvidia0 no se crea y la GPU no funciona.
info "Instalando firmware GSP 595 desde el paquete en caché..."
NV595_PKG=$(ls /var/cache/pacman/pkg/nvidia-utils-595.71.05-*-x86_64*.pkg.tar.zst 2>/dev/null | sort | tail -1)
if [[ -z "$NV595_PKG" ]]; then
    warn "No se encontró nvidia-utils-595 en caché. Descargando firmware desde el paquete..."
    pacman -Sw --noconfirm --nodeps nvidia-utils 2>/dev/null || true
    NV595_PKG=$(ls /var/cache/pacman/pkg/nvidia-utils-595.71.05-*-x86_64*.pkg.tar.zst 2>/dev/null | sort | tail -1)
fi
if [[ -n "$NV595_PKG" ]]; then
    FWDIR=$(mktemp -d)
    bsdtar -xf "$NV595_PKG" -C "$FWDIR" usr/lib/firmware/nvidia/595.71.05/ 2>/dev/null
    if [[ -d "$FWDIR/usr/lib/firmware/nvidia/595.71.05" ]]; then
        cp -r "$FWDIR/usr/lib/firmware/nvidia/595.71.05" /usr/lib/firmware/nvidia/
        info "Firmware 595 instalado en /usr/lib/firmware/nvidia/595.71.05/"
        ls /usr/lib/firmware/nvidia/595.71.05/
    else
        warn "No se encontró el directorio de firmware 595 en el paquete."
    fi
    rm -rf "$FWDIR"
else
    err "No se pudo obtener nvidia-utils-595 para extraer el firmware. Instálalo manualmente."
fi

# ── 6. Verificar DKMS ────────────────────────────────────────────────────────
info "Verificando módulo DKMS..."
KERNEL=$(uname -r)
if dkms status 2>/dev/null | grep -q "nvidia/595.*${KERNEL}.*installed"; then
    info "DKMS nvidia/595 instalado para kernel ${KERNEL}."
else
    warn "Reconstruyendo módulo DKMS manualmente..."
    dkms autoinstall --force
    dkms status | grep nvidia
fi

# ── 7. Resumen y siguiente paso ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Módulo del kernel actualizado: nvidia-open-dkms 595.71.05    ║${NC}"
echo -e "${GREEN}║  Userspace mantenido en:        nvidia-utils 580.95.05        ║${NC}"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}║  REINICIA el sistema para cargar el nuevo módulo.             ║${NC}"
echo -e "${GREEN}║                                                                ║${NC}"
echo -e "${GREEN}║  Opciones de lanzamiento en Steam para TLOU Part I:           ║${NC}"
echo -e "${GREEN}║    %command%                                                  ║${NC}"
echo -e "${GREEN}║  (sin variables especiales necesarias)                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
