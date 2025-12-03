#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# CaptureKit Unified Build Script (Linux & macOS)
# Combines modern CMake with legacy manual bundling logic.
# -----------------------------------------------------------------------------

OS=$(uname)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$DIR/build"
DIST_DIR="$DIR/dist"
QT_VERSION="6.6.0"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
err() { echo -e "${RED}[ERR] $1${NC}"; }

# --- 1. Clean Command ---
if [ "$1" == "clean" ]; then
    log "Cleaning build and dist directories..."
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    log "Clean finished."
    exit 0
fi

# --- 2. Qt Path Detection (Sophisticated) ---
log "Detecting Qt configuration..."
QT_PLUGIN_SRC=""
QT_LIB_SRC=""

if [ "$OS" == "Darwin" ]; then
    # macOS: Rely on qmake
    if ! command -v qmake &> /dev/null; then
        err "qmake not found. Ensure Qt is in your PATH."
        exit 1
    fi
    QMAKE_CMD="qmake"
else
    # Linux: Try qmake6 first, then qmake, then check local aqt
    if command -v qmake6 &> /dev/null; then
        QMAKE_CMD="qmake6"
    elif command -v qmake &> /dev/null; then
        QMAKE_CMD="qmake"
    elif [ -d "$HOME/Qt/$QT_VERSION/gcc_64/bin" ]; then
        QMAKE_CMD="$HOME/Qt/$QT_VERSION/gcc_64/bin/qmake"
    else
        err "Qt not found. Please install Qt6 or run 'aqt install-qt linux desktop 6.6.0 gcc_64'."
        exit 1
    fi
fi

# Query Qt Paths
QT_PLUGIN_SRC=$($QMAKE_CMD -query QT_INSTALL_PLUGINS)
QT_LIB_SRC=$($QMAKE_CMD -query QT_INSTALL_LIBS)
QT_BIN_PATH=$($QMAKE_CMD -query QT_INSTALL_BINS)

log "Using Qt Plugins: $QT_PLUGIN_SRC"

# --- 3. Build (Unified) ---
log "--- Starting Build ---"
mkdir -p "$BUILD_DIR"

cmake -S "$DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$($QMAKE_CMD -query QT_INSTALL_PREFIX)"

# Use generic build command (works for Make or Ninja)
cmake --build "$BUILD_DIR" --config Release --parallel

log "--- Build Finished ---"

# --- 4. Staging & Wrappers ---
log "--- Staging Distribution ---"
mkdir -p "$DIST_DIR"
mkdir -p "$DIST_DIR/bin"
mkdir -p "$DIST_DIR/libs"
mkdir -p "$DIST_DIR/plugins"

# Determine Binary Name (from CMakeLists.txt)
if [ "$OS" == "Darwin" ]; then
    APP_BUNDLE="$BUILD_DIR/capturekit_ui.app"
    if [ ! -d "$APP_BUNDLE" ]; then err "App bundle not found!"; exit 1; fi
else
    # Linux Binary
    BIN_NAME="capturekit-bin" # Name defined in CMake set_target_properties
    SRC_BIN="$BUILD_DIR/$BIN_NAME"
    
    # Fallback if CMake target name differs
    if [ ! -f "$SRC_BIN" ]; then SRC_BIN="$BUILD_DIR/capturekit_ui"; fi
    
    if [ ! -f "$SRC_BIN" ]; then err "Compiled binary not found at $SRC_BIN"; exit 1; fi

    cp "$SRC_BIN" "$DIST_DIR/bin/$BIN_NAME"
    chmod +x "$DIST_DIR/bin/$BIN_NAME"
fi

# --- 5. Dependency Bundling (The Hard Part) ---

if [ "$OS" == "Darwin" ]; then
    # --- macOS: macdeployqt ---
    log "Running macdeployqt..."
    MACDEPLOYQT="$QT_BIN_PATH/macdeployqt"
    
    cp -R "$APP_BUNDLE" "$DIST_DIR/"
    "$MACDEPLOYQT" "$DIST_DIR/capturekit_ui.app" -dmg -always-overwrite -verbose=1
    
    log "macOS Deployment Complete."

else
    # --- Linux: Manual Bundling (Legacy Logic) ---
    
    # 5a. Copy Plugins
    log "Copying Qt Plugins..."
    PLUGIN_LIST=("platforms" "imageformats" "xcbglintegrations" "platformthemes" "wayland-decoration-client" "wayland-graphics-integration-client")
    
    for p in "${PLUGIN_LIST[@]}"; do
        if [ -d "$QT_PLUGIN_SRC/$p" ]; then
            cp -rL "$QT_PLUGIN_SRC/$p" "$DIST_DIR/plugins/"
        else
            warn "Plugin category '$p' not found."
        fi
    done

    # 5b. Create Wrapper Script
    log "Creating Runner Script..."
    cat << EOF > "$DIST_DIR/capturekit"
#!/bin/bash
DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
export LD_LIBRARY_PATH="\$DIR/libs:\$DIR/lib:\$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="\$DIR/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="\$DIR/plugins/platforms"
export QML2_IMPORT_PATH="\$DIR/qml"

# Force XCB if needed, or let Qt decide
# export QT_QPA_PLATFORM=xcb 

exec "\$DIR/bin/$BIN_NAME" "\$@"
EOF
    chmod +x "$DIST_DIR/capturekit"

    # 5c. Manual Library Dependency Copying (ldd loop)
    log "Resolving Shared Libraries (ldd)..."
    
    # Libraries to skip (System libs)
    SKIP_LIBS="linux-vdso|libstdc++|libgcc_s|libc.so|libm.so|ld-linux|libpthread|librt|libdl"

    copy_deps() {
        local file="$1"
        if [ ! -f "$file" ]; then return; fi
        
        ldd "$file" | grep "=>" | awk '{print $3}' | while read -r lib; do
            if [ -n "$lib" ] && [ -f "$lib" ]; then
                local lib_name=$(basename "$lib")
                
                # Check skip list
                if echo "$lib_name" | grep -qE "$SKIP_LIBS"; then continue; fi
                
                # Copy if not exists
                if [ ! -f "$DIST_DIR/libs/$lib_name" ]; then
                    echo "  Bundling: $lib_name"
                    cp -L "$lib" "$DIST_DIR/libs/"
                fi
            fi
        done
    }

    # Scan the Main Binary
    copy_deps "$DIST_DIR/bin/$BIN_NAME"

    # Scan Plugins (Important! Plugins depend on libs the binary might not use)
    find "$DIST_DIR/plugins" -name "*.so" | while read -r plugin; do
        copy_deps "$plugin"
    done

    # 5d. XCB/DBus specific handling (From Legacy Script)
    # The legacy script forced specific XCB libs that ldd might miss if they are dynamically loaded plugins
    # We copy them if we can find them in the system or Qt dir.
    log "Scanning for extra XCB dependencies..."
    
    XCB_DIR=""
    # Try to find where libxcb-cursor is to guess the system lib path
    if [ -f "/usr/lib/x86_64-linux-gnu/libxcb-cursor.so.0" ]; then
        XCB_DIR="/usr/lib/x86_64-linux-gnu"
    elif [ -f "/usr/lib64/libxcb-cursor.so.0" ]; then
        XCB_DIR="/usr/lib64"
    fi

    if [ -n "$XCB_DIR" ]; then
        EXTRA_LIBS=(
            "libxcb-cursor.so.0" "libxcb-icccm.so.4" "libxcb-image.so.0" 
            "libxcb-keysyms.so.1" "libxcb-randr.so.0" "libxcb-render-util.so.0"
            "libxcb-shm.so.0" "libxcb-sync.so.1" "libxcb-xinerama.so.0"
            "libxcb-xkb.so.1" "libxkbcommon-x11.so.0"
        )
        for lib in "${EXTRA_LIBS[@]}"; do
            if [ -f "$XCB_DIR/$lib" ] && [ ! -f "$DIST_DIR/libs/$lib" ]; then
                 cp -L "$XCB_DIR/$lib" "$DIST_DIR/libs/"
            fi
        done
    fi

    # 5e. Configs
    echo "[Paths]" > "$DIST_DIR/qt.conf"
    echo "Prefix = ." >> "$DIST_DIR/qt.conf"
    echo "Plugins = plugins" >> "$DIST_DIR/qt.conf"

    # Copy fonts config if exists
    mkdir -p "$DIST_DIR/fonts"
    if [ -f /etc/fonts/fonts.conf ]; then
        cp /etc/fonts/fonts.conf "$DIST_DIR/fonts/"
    fi

    log "Linux Distribution Ready at $DIST_DIR"
    log "Run with: ./dist/capturekit"
fi