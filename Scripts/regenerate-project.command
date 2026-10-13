#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  echo "XcodeGen не найден. Установите его командой: brew install xcodegen"
  read -r -p "Нажмите Enter, чтобы закрыть окно…"
  exit 1
fi

xcodegen generate
# XcodeGen issue #1549: link the vendored local package to its product
# dependencies, otherwise the Xcode GUI reports "Missing package product".
python3 Scripts/patch-xcodeproj.py
open Luma.xcodeproj
