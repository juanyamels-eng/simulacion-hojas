#!/usr/bin/env bash
# Prepara un entorno mínimo para exportar APKs con Godot sin el Android SDK completo.
# Usa las plantillas Android precompiladas de Godot y apksigner de los paquetes de Ubuntu.
set -euo pipefail

GODOT_VERSION="4.5.1"
GODOT_DIR="${GODOT_DIR:-/opt/godot}"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
TPZ="${TPZ:-/root/godot/templates.tpz}"
SDK_DIR="${SDK_DIR:-$HOME/android-sdk-lite}"
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
CFG_DIR="$HOME/.config/godot"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$GODOT_BIN" ]; then
  mkdir -p "$GODOT_DIR"
  curl -sSL -o "$GODOT_DIR/editor.zip" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -oq "$GODOT_DIR/editor.zip" -d "$GODOT_DIR" && rm "$GODOT_DIR/editor.zip"
fi

if [ ! -f "$TPL_DIR/android_debug.apk" ]; then
  if [ ! -f "$TPZ" ]; then
    mkdir -p "$(dirname "$TPZ")"
    curl -sSL -o "$TPZ" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  fi
  mkdir -p "$TPL_DIR"
  unzip -oqj "$TPZ" 'templates/android_debug.apk' 'templates/android_release.apk' 'templates/version.txt' -d "$TPL_DIR"
fi

command -v apksigner >/dev/null || apt-get install -y -q apksigner

# SDK "ligero": Godot solo necesita encontrar adb y build-tools/*/apksigner.
mkdir -p "$SDK_DIR/platform-tools" "$SDK_DIR/build-tools/35.0.0"
cat > "$SDK_DIR/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
if command -v /usr/bin/adb >/dev/null 2>&1; then exec /usr/bin/adb "$@"; fi
echo "List of devices attached"
EOF
chmod +x "$SDK_DIR/platform-tools/adb"
cat > "$SDK_DIR/build-tools/35.0.0/apksigner" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/apksigner "$@"
EOF
chmod +x "$SDK_DIR/build-tools/35.0.0/apksigner"

# Keystore de depuración (versionado en el repo para que las actualizaciones se instalen encima).
DEBUG_KS="$REPO_DIR/keys/debug.keystore"
if [ ! -f "$DEBUG_KS" ]; then
  mkdir -p "$REPO_DIR/keys"
  keytool -genkeypair -v -keystore "$DEBUG_KS" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
mkdir -p "$CFG_DIR"
cat > "$CFG_DIR/editor_settings-4.5.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK_DIR"
export/android/java_sdk_path = "$JAVA_HOME_DIR"
export/android/debug_keystore = "$DEBUG_KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF

echo "Godot: $GODOT_BIN"
echo "Plantillas: $(ls "$TPL_DIR")"
echo "SDK ligero: $SDK_DIR"
