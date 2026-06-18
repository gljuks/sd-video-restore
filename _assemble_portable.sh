#!/usr/bin/env bash
# Build vs-portable-win/ using Python embeddable (mirrors Colab approach).
# Run from WSL. Output: /mnt/e/avis/vs-portable-win/
set -euo pipefail

DEST="/mnt/e/avis/vs-portable-win"
PLUGIN_SRC="/mnt/c/Users/gatis/AppData/Local/Programs/Python/Python312/Lib/site-packages/vapoursynth/plugins/vsrepo"
PY_EMBED_URL="https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
WHEEL_SRC="/mnt/e/avis/_install/VapourSynth64-Portable-R76.zip"

echo "=== Cleaning ==="
cmd.exe /c "rmdir /s /q E:\\avis\\vs-portable-win" 2>/dev/null || true
mkdir -p "$DEST"/{python,plugins64,scripts,tmp}

# --- Download Python embeddable ---
echo "=== Downloading Python embeddable ==="
if [ ! -f "$DEST/tmp/python-embed.zip" ]; then
    wget -q -O "$DEST/tmp/python-embed.zip" "$PY_EMBED_URL"
fi

echo "=== Extracting Python ==="
unzip -qo "$DEST/tmp/python-embed.zip" -d "$DEST/python"

# Enable pip: uncomment 'import site' in python312._pth
echo "=== Enabling pip ==="
sed -i 's/^#import site/import site/' "$DEST/python/python312._pth"

# Download get-pip.py and install pip (must run via cmd.exe so paths are Windows-native)
echo "=== Installing pip ==="
wget -q -O "$DEST/tmp/get-pip.py" "https://bootstrap.pypa.io/get-pip.py"
WGETPIP="E:\\avis\\vs-portable-win\\tmp\\get-pip.py"
PYEXE="E:\\avis\\vs-portable-win\\python\\python.exe"
cmd.exe /c "$PYEXE $WGETPIP --no-warn-script-location" 2>&1 | tail -5

# --- pip install VS + Python dependencies (all via cmd.exe, Windows paths) ---
echo "=== Installing vapoursynth + packages ==="
PYEXE="E:\\avis\\vs-portable-win\\python\\python.exe"
PIP="$PYEXE -m pip"

echo "--- vapoursynth ---"
cmd.exe /c "$PIP install vapoursynth==76" 2>&1 | tail -3
echo "--- vsdehalo + friends ---"
cmd.exe /c "$PIP install --no-warn-script-location vsdehalo vsjetpack vsutil vstools" 2>&1 | tail -3
# Copy havsfunc/mvsfunc from existing working Windows install (no git build needed)
echo "=== Copying Python packages from existing install ==="
cp -r "/mnt/c/Users/gatis/AppData/Roaming/Python/Python312/site-packages/havsfunc"* "$DEST/python/Lib/site-packages/" 2>/dev/null && echo "  havsfunc OK" || echo "  havsfunc NOT FOUND (will need pip install)"
cp -r "/mnt/c/Users/gatis/AppData/Roaming/Python/Python312/site-packages/mvsfunc"* "$DEST/python/Lib/site-packages/" 2>/dev/null && echo "  mvsfunc OK" || echo "  mvsfunc NOT FOUND"

# --- nnedi3_rpow2 (not on PyPI) ---
echo "=== Copying plugin DLLs ==="
cp "$PLUGIN_SRC"/*.dll "$DEST/plugins64/" 2>/dev/null || true
cp "$PLUGIN_SRC"/*.bin "$DEST/plugins64/" 2>/dev/null || true

# --- nnedi3_rpow2 (not on PyPI) ---
cp /mnt/e/avis/colab/nnedi3_rpow2.py "$DEST/python/Lib/site-packages/" 2>/dev/null || true

# --- adjust.py (raw module, no package) ---
echo "=== Installing adjust.py ==="
wget -q -O "$DEST/python/Lib/site-packages/adjust.py" \
    "https://raw.githubusercontent.com/dubhater/vapoursynth-adjust/master/adjust.py" 2>/dev/null || true

# --- Scripts (templates + bats) ---
echo "=== Copying scripts ==="
cp "/mnt/e/avis/VapourSynth Templates"/*.vpy "$DEST/scripts/"
cp /mnt/e/avis/createvpy.bat /mnt/e/avis/createvpyGPU.bat "$DEST/scripts/"
cp /mnt/e/avis/convertvpy.bat /mnt/e/avis/convertvpyNV.bat "$DEST/scripts/"
cp /mnt/e/avis/_vpy_getsrc.ps1 "$DEST/scripts/"

# --- run.bat launcher ---
cat > "$DEST/run.bat" << 'BATEOF'
@ECHO OFF
SET VSROOT=%~dp0
SET PATH=%VSROOT%python;%VSROOT%python\Scripts;%VSROOT%;%PATH%
SET PYTHONPATH=%VSROOT%python\Lib\site-packages
SET VAPOURSYNTH_PLUGIN_PATH=%VSROOT%plugins64

IF "%1"=="" (
    ECHO VapourSynth portable ready.
    ECHO   vspipe: %VSROOT%vspipe.exe
    ECHO   plugins: %VSROOT%plugins64\
    ECHO   python:  %VSROOT%python\python.exe
    ECHO.
    ECHO Drop a video on createvpy.bat, then run convertvpy.bat
    CMD /K
) ELSE (
    %*
)
BATEOF

# --- clean tmp ---
rm -rf "$DEST/tmp"

echo ""
echo "=== Done: $DEST ==="
du -sh "$DEST"
echo ""
echo "Key files:"
ls -la "$DEST"/vspipe.exe "$DEST"/python/python.exe "$DEST"/run.bat 2>/dev/null
echo ""
echo "Plugin count: $(ls "$DEST/plugins64/"*.dll 2>/dev/null | wc -l) DLLs"
echo ""
echo "Smoke test (on Windows):  cd $DEST && run.bat vspipe --version"
