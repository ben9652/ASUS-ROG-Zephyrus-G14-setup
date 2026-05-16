#!/usr/bin/env bash
# instalar-vscode.sh
#
# Instala Visual Studio Code (versión propietaria de Microsoft) en CachyOS.
#
# Se usa el paquete 'visual-studio-code-bin' disponible en chaotic-aur,
# que CachyOS tiene habilitado por defecto. Esta versión (y no 'code' de los
# repos oficiales de Arch) es necesaria para usar GitHub Copilot y extensiones
# propietarias de Microsoft.
#
# Además configura VSCode para ejecutarse de forma nativa en Wayland, evitando
# el texto borroso que aparece al correr como app XWayland en pantallas HiDPI.
#
# Requiere root (invocado desde setup.sh con sudo).
# HOME debe apuntar al directorio real del usuario (setup.sh lo garantiza).

set -euo pipefail

# ── 1. Instalación del paquete ────────────────────────────────────────────────

echo "==> [1/2] Instalando visual-studio-code-bin..."

if command -v code &>/dev/null; then
    echo "    VSCode ya está instalado ($(code --version | head -1)), sin cambios."
else
    # chaotic-aur (habilitado por defecto en CachyOS) distribuye el paquete
    # precompilado, por lo que pacman puede instalarlo directamente.
    pacman -S --noconfirm --needed visual-studio-code-bin
    echo "    VSCode instalado correctamente."
fi

# ── 2. Configuración para Wayland nativo (evita texto borroso en HiDPI) ───────

echo "==> [2/2] Configurando flags de Wayland en ~/.config/code-flags.conf..."

FLAGS_FILE="$HOME/.config/code-flags.conf"

if grep -q 'ozone-platform-hint' "$FLAGS_FILE" 2>/dev/null; then
    echo "    Flags de Wayland ya presentes, sin cambios."
else
    # --ozone-platform-hint=auto  → usa Wayland si está disponible, XWayland si no
    # --enable-wayland-ime         → habilita el método de entrada en Wayland
    cat >> "$FLAGS_FILE" <<'EOF'

# Wayland nativo — evita texto borroso en pantallas HiDPI
--ozone-platform-hint=auto
--enable-wayland-ime
EOF
    echo "    Flags añadidos a $FLAGS_FILE."
fi

echo ""
echo "Instalación completada."
echo ""
echo "  Ejecuta 'code' para abrir VSCode."
echo "  NOTA: cierra y vuelve a abrir VSCode si ya estaba en ejecución."
