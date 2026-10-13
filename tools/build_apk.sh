#!/usr/bin/env bash
# Compila los APK de Villa Hojarasca (debug y release) con Godot sin el Android SDK completo.
# Uso: ./tools/build_apk.sh [debug|release|all]   (por defecto: all)
set -euo pipefail

MODE="${1:-all}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/opt/godot/Godot_v4.5.1-stable_linux.x86_64}"
cd "$REPO"

"$REPO/tools/setup_android_env.sh" >/dev/null
[ -d assets/audio ] && [ "$(ls assets/audio | wc -l)" -gt 40 ] || python3 tools/gen_audio.py
[ -f icon.png ] || python3 tools/gen_icon.py

echo ">> Importando recursos…"
timeout 600 "$GODOT" --headless --import >/dev/null 2>&1 || true
mkdir -p build

if [ "$MODE" = "debug" ] || [ "$MODE" = "all" ]; then
  echo ">> Exportando APK DEBUG…"
  "$GODOT" --headless --export-debug "Android" build/VillaHojarasca-debug.apk 2>&1 | grep -E "ERROR|error|Exportando|savepack" || true
  apksigner verify --print-certs build/VillaHojarasca-debug.apk | head -2
fi

if [ "$MODE" = "release" ] || [ "$MODE" = "all" ]; then
  # Clave de release: se genera una vez y NO se sube al repositorio (ver .gitignore).
  if [ ! -f keys/release.keystore ]; then
    PASS="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
    keytool -genkeypair -keystore keys/release.keystore -storepass "$PASS" -keypass "$PASS" \
      -alias villahojarasca -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Villa Hojarasca,O=Villa Hojarasca,C=ES" >/dev/null 2>&1
    printf 'alias=villahojarasca\npassword=%s\n' "$PASS" > keys/release.properties
  fi
  PASS="$(grep '^password=' keys/release.properties | cut -d= -f2)"
  echo ">> Exportando APK RELEASE…"
  GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$REPO/keys/release.keystore" \
  GODOT_ANDROID_KEYSTORE_RELEASE_USER="villahojarasca" \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PASS" \
    "$GODOT" --headless --export-release "Android" build/VillaHojarasca-release.apk 2>&1 | grep -E "ERROR|error" || true
  apksigner verify --print-certs build/VillaHojarasca-release.apk | head -2
fi

ls -lh build/*.apk
