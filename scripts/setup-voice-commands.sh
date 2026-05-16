#!/usr/bin/env bash
# setup-voice-commands.sh
#
# Instala un daemon de reconocimiento de voz offline (Vosk) que ejecuta
# comandos de shell al escuchar frases específicas en español.
#
# Qué instala:
#   ~/.local/bin/voice-commands         ← daemon Python (Vosk)
#   ~/.local/bin/voice-commands-toggle  ← activa/desactiva el daemon
#   ~/.config/voice-commands/commands.conf ← frases → comandos
#   ~/.local/share/vosk/model-es/       ← modelo de español (~40 MB)
#
# Atajos añadidos a bindings.conf:
#   Ctrl+Return      → Walker (lanzador de aplicaciones)
#   Super+Shift+V    → Visual Studio Code
#   Super+Alt+V      → Activar/desactivar comandos de voz
#
# Uso: sudo bash setup-voice-commands.sh
# (invocado desde setup.sh, que exporta HOME al directorio real del usuario)

set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

BIN_DIR="$REAL_HOME/.local/bin"
CONF_DIR="$REAL_HOME/.config/voice-commands"
MODEL_DIR="$REAL_HOME/.local/share/vosk/model-es"
HYPR_BINDINGS="$REAL_HOME/.config/hypr/bindings.conf"

MODEL_URL="https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip"
MODEL_ZIP="/tmp/vosk-model-small-es.zip"

mkdir -p "$BIN_DIR" "$CONF_DIR" "$(dirname "$MODEL_DIR")"

# ── 1. Dependencias Python ────────────────────────────────────────────────────

echo "==> [1/5] Instalando dependencias Python (vosk, sounddevice)..."

# python-pyaudio está en los repos oficiales de Arch
pacman -S --noconfirm --needed python-pyaudio portaudio

# python-vosk está en chaotic-aur (CachyOS lo tiene habilitado por defecto)
if pacman -S --noconfirm --needed python-vosk 2>/dev/null; then
    echo "    python-vosk instalado vía pacman."
else
    echo "    python-vosk no encontrado en los repos de pacman."
    echo "    Intentando con paru (AUR)..."
    if command -v paru &>/dev/null; then
        su -l "$REAL_USER" -c "paru -S --noconfirm --needed python-vosk"
    elif command -v yay &>/dev/null; then
        su -l "$REAL_USER" -c "yay -S --noconfirm --needed python-vosk"
    else
        echo ""
        echo "  ERROR: No se pudo instalar python-vosk automáticamente."
        echo "  Instálalo manualmente con:  paru -S python-vosk"
        echo "  Luego vuelve a ejecutar este script."
        exit 1
    fi
fi

# ── 2. Modelo de español (vosk-model-small-es-0.42, ~40 MB) ──────────────────

echo "==> [2/5] Descargando modelo de español Vosk..."

if [[ -f "$MODEL_DIR/am/final.mdl" ]]; then
    echo "    Modelo ya presente en $MODEL_DIR, sin cambios."
else
    echo "    Descargando $MODEL_URL"
    # --insecure: el certificado SSL de alphacephei.com está caducado (mayo 2026).
    # Riesgo mínimo: descargamos un modelo público de ML, no credenciales.
    curl -L --insecure --progress-bar -o "$MODEL_ZIP" "$MODEL_URL"

    echo "    Extrayendo modelo..."
    python3 -m zipfile -e "$MODEL_ZIP" /tmp/vosk-extract/

    # El zip contiene una carpeta con nombre variable; la movemos a model-es
    EXTRACTED=$(find /tmp/vosk-extract/ -maxdepth 1 -mindepth 1 -type d | head -1)
    mv "$EXTRACTED" "$MODEL_DIR"
    rm -f "$MODEL_ZIP"
    rmdir /tmp/vosk-extract/ 2>/dev/null || true
    echo "    Modelo instalado en $MODEL_DIR"
fi

# ── 3. Daemon voice-commands ──────────────────────────────────────────────────

echo "==> [3/5] Instalando $BIN_DIR/voice-commands..."

cat > "$BIN_DIR/voice-commands" << 'PYEOF'
#!/usr/bin/env python3
"""
voice-commands: daemon de reconocimiento de voz offline con Vosk.
Escucha el micrófono y ejecuta comandos de shell al reconocer frases.

Configuración: ~/.config/voice-commands/commands.conf
Modelo:        ~/.local/share/vosk/model-es/
"""

import json
import subprocess
import sys
from pathlib import Path

MODEL_PATH    = Path.home() / ".local/share/vosk/model-es"
COMMANDS_FILE = Path.home() / ".config/voice-commands/commands.conf"
SAMPLE_RATE   = 16000
BLOCK_SIZE    = 8000


def load_commands():
    commands = {}
    try:
        with open(COMMANDS_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                phrase, sep, cmd = line.partition('=')
                if sep:
                    commands[phrase.strip().lower()] = cmd.strip()
    except FileNotFoundError:
        sys.exit(f"ERROR: Archivo de comandos no encontrado: {COMMANDS_FILE}")
    return commands


def notify(title, body, icon="audio-input-microphone"):
    subprocess.Popen(
        ['notify-send', title, body, f'--icon={icon}', '-t', '2000'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def main():
    try:
        import vosk
        import pyaudio
    except ImportError as e:
        sys.exit(f"ERROR: Dependencia faltante — {e}\nEjecuta: setup-voice-commands.sh")

    if not MODEL_PATH.exists():
        sys.exit(
            f"ERROR: Modelo Vosk no encontrado en {MODEL_PATH}\n"
            f"Ejecuta: setup-voice-commands.sh"
        )

    commands = load_commands()
    if not commands:
        sys.exit("ERROR: No hay comandos definidos en el archivo de configuración.")

    vosk.SetLogLevel(-1)
    model = vosk.Model(str(MODEL_PATH))

    # Gramática limitada a las frases conocidas → más rápido y preciso
    grammar = json.dumps(list(commands.keys()) + ["[unk]"])
    rec = vosk.KaldiRecognizer(model, SAMPLE_RATE, grammar)

    print(f"Escuchando — {len(commands)} comandos activos. Ctrl+C para detener.")
    notify("Comandos de voz", f"🎤 Escuchando — {len(commands)} comandos activos")

    pa = pyaudio.PyAudio()
    stream = pa.open(
        format=pyaudio.paInt16,
        channels=1,
        rate=SAMPLE_RATE,
        input=True,
        frames_per_buffer=BLOCK_SIZE
    )
    stream.start_stream()

    try:
        while True:
            data = stream.read(BLOCK_SIZE, exception_on_overflow=False)
            if rec.AcceptWaveform(data):
                text = json.loads(rec.Result()).get('text', '').strip().lower()
                if text and text != '[unk]' and text in commands:
                    print(f"  → {text}")
                    notify("Comando de voz", f"🎤 {text}")
                    subprocess.Popen(['bash', '-c', commands[text]])
    except KeyboardInterrupt:
        print("\nDetenido.")
        notify("Comandos de voz", "Desactivado 🔇", icon="audio-input-microphone-muted")
    finally:
        stream.stop_stream()
        stream.close()
        pa.terminate()


if __name__ == '__main__':
    main()
PYEOF

chmod +x "$BIN_DIR/voice-commands"
echo "  ✓ $BIN_DIR/voice-commands"

# ── 4. Script de alternancia voice-commands-toggle ───────────────────────────

echo "==> [4/5] Instalando $BIN_DIR/voice-commands-toggle..."

cat > "$BIN_DIR/voice-commands-toggle" << 'EOF'
#!/usr/bin/env bash
# voice-commands-toggle: activa o desactiva el daemon de comandos de voz.

PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voice-commands.pid"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    notify-send "Comandos de voz" "Desactivado 🔇" --icon=audio-input-microphone-muted -t 2000
else
    voice-commands &
    echo $! > "$PID_FILE"
fi
EOF

chmod +x "$BIN_DIR/voice-commands-toggle"
echo "  ✓ $BIN_DIR/voice-commands-toggle"

# ── 5. Archivo de comandos ────────────────────────────────────────────────────

echo "==> [5/5] Configurando comandos y atajos de teclado..."

if [[ -f "$CONF_DIR/commands.conf" ]]; then
    echo "    $CONF_DIR/commands.conf ya existe, sin cambios."
else
    cat > "$CONF_DIR/commands.conf" << 'EOF'
# Comandos de voz en español
# Formato: frase = comando shell
#
# Las frases deben estar en minúsculas y sin acentos.
# Vosk normaliza la salida del modelo (quita acentos y convierte a minúsculas),
# así que escribe las frases exactamente como el modelo las devolvería.
#
# Para añadir o modificar comandos, edita este archivo y reinicia el daemon
# con el atajo Super+Alt+V (dos veces: off → on).

ejecutar comando         = omarchy-launch-walker
abrir twitter            = omarchy-launch-webapp "https://x.com/"
abrir navegador          = omarchy-launch-browser
abrir terminal           = xdg-terminal-exec
abrir visual studio code = code
EOF
    echo "    $CONF_DIR/commands.conf creado."
fi

# ── Keybindings ───────────────────────────────────────────────────────────────

if grep -q 'voice-commands-toggle' "$HYPR_BINDINGS" 2>/dev/null; then
    echo "    Keybindings de voz ya presentes, sin cambios."
else
    cat >> "$HYPR_BINDINGS" << 'BIND'

# Ctrl+Return: abrir Walker (lanzador de aplicaciones / "Ejecutar comando")
bindd = CTRL, RETURN, Launch apps, exec, omarchy-launch-walker

# Super+Shift+V: abrir Visual Studio Code
bindd = SUPER SHIFT, V, Visual Studio Code, exec, uwsm-app -- code

# Super+Alt+V: activar / desactivar comandos de voz
bindd = SUPER ALT, V, Toggle voice commands, exec, voice-commands-toggle
BIND
    echo "    Keybindings añadidos (Ctrl+Return, Super+Shift+V, Super+Alt+V)."
fi

# ── Propiedad de los archivos ─────────────────────────────────────────────────

chown -R "$REAL_USER:" "$BIN_DIR/voice-commands" \
                       "$BIN_DIR/voice-commands-toggle" \
                       "$CONF_DIR" \
                       "$MODEL_DIR"

# ── Recargar Hyprland ─────────────────────────────────────────────────────────

if [[ -n "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl keyword input:kb_layout us,latam &>/dev/null || true
    sudo -u "$REAL_USER" hyprctl reload &>/dev/null || true
fi

echo ""
echo "Configuración completada."
echo ""
echo "  Super+Alt+V    → activar/desactivar reconocimiento de voz"
echo "  Ctrl+Return    → abrir Walker (ejecutar comando)"
echo "  Super+Shift+V  → abrir Visual Studio Code"
echo ""
echo "  Edita ~/.config/voice-commands/commands.conf para cambiar los comandos."
echo "  NOTA: recarga Hyprland (hyprctl reload) para activar los nuevos atajos."
