#!/bin/bash
# Generates the app icon, then assembles Mole.app.
# Usage: ./Scripts/make-app.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources
echo "==> Generating AppIcon.icns"
swift Scripts/make-icon.swift || echo "(icon generation skipped)"
echo "==> Building app bundle"
./Scripts/build-app.sh "${1:-}"
