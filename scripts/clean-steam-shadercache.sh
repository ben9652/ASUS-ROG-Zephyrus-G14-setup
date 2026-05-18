#!/usr/bin/env bash
# clean-steam-shadercache.sh
# Removes Steam shader caches only when they exceed a size threshold.

set -euo pipefail

APPID_FILTER="${1:-}"
THRESHOLD_GIB="${2:-2}"
STEAM_HOME="${STEAM_HOME:-$HOME/.local/share/Steam}"
SHADERCACHE_DIR="$STEAM_HOME/steamapps/shadercache"

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }

if [[ ! -d "$SHADERCACHE_DIR" ]]; then
    info "No Steam shader cache directory found."
    exit 0
fi

threshold_bytes=$((THRESHOLD_GIB * 1024 * 1024 * 1024))

info "Threshold: ${THRESHOLD_GIB} GiB"

shopt -s nullglob
for cache_dir in "$SHADERCACHE_DIR"/*; do
    [[ -d "$cache_dir" ]] || continue

    appid=$(basename "$cache_dir")
    if [[ -n "$APPID_FILTER" && "$appid" != "$APPID_FILTER" ]]; then
        continue
    fi

    size_bytes=$(du -sb "$cache_dir" | awk '{print $1}')
    info "Cache size for appid $appid: $size_bytes bytes"

    if (( size_bytes < threshold_bytes )); then
        info "Keeping cache: below threshold."
        continue
    fi

    warn "Removing cache: above threshold."
    rm -rf -- "$cache_dir"
    info "Removed $cache_dir"
done