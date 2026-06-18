#!/usr/bin/env bash
# =============================================================================
# export_bundle.sh -- make /opt/vs relocatable and tar it for Colab.
# =============================================================================
# Run inside the oven image:
#   docker run --rm -v "$PWD/out:/out" vs-oven:r76
# (Dockerfile CMD calls this script; -v mounts a host dir for the output.)
#
# Output: /out/vs-portable-linux-py312.tar.zst  (~150-300 MB).
#
# Relocation strategy:
#   - patchelf sets RPATH = $ORIGIN/../lib on every binary + plugin .so so they
#     find libs RELATIVE to the bundle's eventual location. No hard-coded
#     /opt/vs paths in ELF headers. Colab can extract to /opt/vs (same path)
#     OR anywhere else; both work.
#   - The bundled python's shebang ALREADY contains /opt/vs/py/bin/python from
#     the venv. We don't try to rewrite Python script shebangs; instead the
#     Colab cell extracts to /opt/vs (the same path used at build time), so
#     no rewrite is needed. If you ever extract elsewhere, run:
#       sed -i "s|/opt/vs|${NEWPREFIX}|g" $NEWPREFIX/py/bin/*
# =============================================================================
set -euo pipefail

: "${VSPREFIX:=/opt/vs}"
OUT="${OUT:-/out}"
TARBALL="${OUT}/vs-portable-linux-py312.tar.zst"

mkdir -p "${OUT}"

echo "==> RPATH-fixing binaries"
# vspipe is at ${VSPREFIX} root; libvapoursynth.so / libvsscript.so also at root.
patchelf --set-rpath '$ORIGIN' "${VSPREFIX}/vspipe" || true
patchelf --set-rpath '$ORIGIN' "${VSPREFIX}/libvapoursynth.so" || true
patchelf --set-rpath '$ORIGIN' "${VSPREFIX}/libvapoursynth.so.4" || true
patchelf --set-rpath '$ORIGIN' "${VSPREFIX}/libvsscript.so" || true
# Plugin .so files live in ${VSPREFIX}/plugins; libs at ${VSPREFIX} root.
for f in "${VSPREFIX}/plugins"/*.so; do
    [ -f "${f}" ] || continue
    patchelf --set-rpath '$ORIGIN/..' "${f}" || true
done
# Also symlink libvapoursynth.so and libvsscript.so into lib/ so LD_LIBRARY_PATH works.
ln -sf "${VSPREFIX}/libvapoursynth.so" "${VSPREFIX}/lib/libvapoursynth.so" 2>/dev/null || true
ln -sf "${VSPREFIX}/libvsscript.so" "${VSPREFIX}/lib/libvsscript.so" 2>/dev/null || true
# Also vendor any host .so we copied into lib.
for f in "${VSPREFIX}/lib"/*.so*; do
    [ -f "${f}" ] && [ ! -L "${f}" ] || continue
    file "${f}" | grep -q ELF || continue
    patchelf --set-rpath '$ORIGIN' "${f}" || true
done

# Strip down the venv: drop pip caches, *.pyc, tests/, __pycache__/, etc.
echo "==> shrinking Python venv"
find "${VSPREFIX}/py" -name '__pycache__' -type d -exec rm -rf {} + || true
find "${VSPREFIX}/py" -name '*.pyc' -delete || true
find "${VSPREFIX}/py" -path '*/tests/*' -delete || true
find "${VSPREFIX}/py" -path '*/test/*' -delete || true
rm -rf "${VSPREFIX}/py/share/man" "${VSPREFIX}/py/share/doc" || true

# Write a version manifest so Cell 2 can verify the right bundle landed.
cat >"${VSPREFIX}/BUNDLE_VERSION" <<EOF
bundle: vs-portable-linux-py312
vapoursynth: $(${VSPREFIX}/py/bin/python -c "import vapoursynth; print(vapoursynth.__version__)" 2>/dev/null || echo unknown)
python: $(${VSPREFIX}/py/bin/python --version 2>&1)
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
plugins: $(ls -1 ${VSPREFIX}/plugins | wc -l)
EOF
cat "${VSPREFIX}/BUNDLE_VERSION"

echo
echo "==> tar + zstd -> ${TARBALL}"
cd /opt
tar --zstd -cf "${TARBALL}" vs
ls -lh "${TARBALL}"
echo "==> DONE. Upload as GitHub Release asset and copy URL into the notebook."
