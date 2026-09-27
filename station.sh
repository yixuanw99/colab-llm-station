#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - Local Workstation Launcher
# Zero-Browser Headless CLI Interface
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] Python 3 is required to run station launcher."
    exit 1
fi

exec python3 "$DIR/tools/station_ctl.py" "$@"
