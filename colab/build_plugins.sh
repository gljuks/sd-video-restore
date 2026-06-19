#!/usr/bin/env bash
# =============================================================================
# build_plugins.sh -- build VapourSynth plugin .so set into ${VSPREFIX}/plugins
# =============================================================================
# Two-tier policy:
#   REQUIRED plugins -- the pipeline cannot run without them. Failure stops
#                       the entire build with non-zero exit.
#   OPTIONAL plugins -- nice-to-have helpers (mostly QTGMC corner-cases or
#                       fallback denoisers). Failures are logged but the build
#                       continues. The bundle is still useful.
#
# Smart clone: try `master`, then `main`, then default HEAD. Repos move.
# =============================================================================
set -uo pipefail

: "${VSPREFIX:=/opt/vs}"
PLUGINDIR="${VSPREFIX}/plugins"
LOGDIR="/tmp/plugin-logs"
mkdir -p "${PLUGINDIR}" "${LOGDIR}"

export PKG_CONFIG_PATH="${VSPREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CFLAGS="-O3 -fPIC ${CFLAGS:-}"
export CXXFLAGS="-O3 -fPIC ${CXXFLAGS:-}"
export LD_LIBRARY_PATH="${VSPREFIX}/lib:${LD_LIBRARY_PATH:-}"

WORK=/tmp/vsbuild
mkdir -p "${WORK}"
cd "${WORK}"

FAILED_REQUIRED=()
FAILED_OPTIONAL=()
BUILT=()

# ---- helpers ----------------------------------------------------------------

# Smart clone: gclone REPO_URL DIRNAME -- tries git clone (master, main,
# default), then falls back to wget + tar (git clone fails in restricted
# network environments e.g. Docker behind corporate proxy).
gclone() {
    local url="$1" dst="$2"
    [ -d "${dst}" ] && rm -rf "${dst}"
    # Extract owner/repo from GitHub URL for archive fallback
    local repo_path
    repo_path=$(echo "$url" | sed -E 's|https?://github.com/||; s|\.git$||')
    local archive_url="https://github.com/${repo_path}/archive/refs/heads/master.tar.gz"
    git clone --depth 1 --branch master "${url}" "${dst}" 2>/dev/null \
      || git clone --depth 1 --branch main "${url}" "${dst}" 2>/dev/null \
      || git clone --depth 1 "${url}" "${dst}" 2>/dev/null \
      || { wget -qO /tmp/_gclone.tar.gz "${archive_url}" 2>/dev/null \
           && tar xzf /tmp/_gclone.tar.gz \
           && rm -f /tmp/_gclone.tar.gz \
           && mv "${repo_path##*/}-master" "${dst}" 2>/dev/null; }
}

# Copy any built .so files in a directory tree into ${PLUGINDIR}.
inst_so() {
    find "$1" -name '*.so' -type f -exec cp -v {} "${PLUGINDIR}/" \; 2>/dev/null || true
}

meson_build() {
    local src="$1"; shift
    rm -rf "${src}/build"
    meson setup "${src}/build" "${src}" --buildtype=release \
        --prefix="${VSPREFIX}" --libdir="${VSPREFIX}/lib" "$@" \
      && ninja -C "${src}/build" -j"$(nproc)" \
      && (ninja -C "${src}/build" install 2>/dev/null || true) \
      && inst_so "${src}/build"
}

cmake_build() {
    local src="$1"; shift
    rm -rf "${src}/build"
    cmake -S "${src}" -B "${src}/build" -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${VSPREFIX}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        "$@" \
      && cmake --build "${src}/build" -j"$(nproc)" \
      && (cmake --install "${src}/build" 2>/dev/null || true) \
      && inst_so "${src}/build"
}

# build NAME REQUIRED_FLAG  CMD ...
#   NAME:           label used in logs
#   REQUIRED_FLAG:  "req" or "opt"
#   CMD ...:        the actual build commands (run as bash subshell)
build() {
    local name="$1" tier="$2"; shift 2
    local before after delta logf="${LOGDIR}/${name}.log"
    before=$(ls -1 "${PLUGINDIR}" 2>/dev/null | wc -l)
    echo
    echo "============================================================"
    echo "[${tier^^}] ${name}"
    echo "============================================================"
    if ( set -e; "$@" ) > "${logf}" 2>&1; then
        after=$(ls -1 "${PLUGINDIR}" 2>/dev/null | wc -l)
        delta=$((after - before))
        if [ "${delta}" -gt 0 ]; then
            echo "  OK  (added ${delta} .so files)"
            BUILT+=("${name}")
        else
            echo "  WARN: build succeeded but no .so installed -- check ${logf}"
            BUILT+=("${name} (no-so)")
        fi
    else
        echo "  FAIL -- last 20 lines of log:"
        tail -20 "${logf}" | sed 's/^/    /'
        if [ "${tier}" = "req" ]; then
            FAILED_REQUIRED+=("${name}")
        else
            FAILED_OPTIONAL+=("${name}")
        fi
    fi
}

# ============================================================================
# REQUIRED PLUGINS (pipeline cannot run without these)
# ============================================================================

build_fmtconv() {
    gclone https://github.com/EleonoreMizo/fmtconv.git fmtconv
    cd fmtconv/build/unix
    ./autogen.sh
    ./configure --prefix="${VSPREFIX}" --libdir="${VSPREFIX}/lib"
    make -j"$(nproc)"
    inst_so .
}
build fmtconv req build_fmtconv

build_ffms2() {
    gclone https://github.com/FFMS/ffms2.git ffms2
    cd ffms2
    ./autogen.sh
    ./configure --prefix="${VSPREFIX}" --libdir="${VSPREFIX}/lib" --enable-shared
    make -j"$(nproc)"
    make install
    # ffms2 installs its VS plugin .so into the prefix; also stage to plugindir.
    find "${VSPREFIX}" -name 'libffms2*.so*' -exec cp -v {} "${PLUGINDIR}/" \; 2>/dev/null || true
    inst_so .
}
build ffms2 req build_ffms2

build_lsmash() {
    gclone https://github.com/l-smash/l-smash.git l-smash
    cd l-smash
    ./configure --prefix="${VSPREFIX}" --enable-shared
    make -j"$(nproc)" lib
    make install-lib
}
build lsmash req build_lsmash

build_lsmas() {
    gclone https://github.com/AkarinVS/L-SMASH-Works.git lsmas-akarin
    cd lsmas-akarin/VapourSynth
    meson setup build --buildtype=release --prefix="${VSPREFIX}" --libdir="${VSPREFIX}/lib"
    ninja -C build -j"$(nproc)"
    inst_so build
}
build lsmas req build_lsmas

build_mvtools() {
    gclone https://github.com/dubhater/vapoursynth-mvtools.git mvtools
    meson_build mvtools
}
build mvtools req build_mvtools

build_znedi3() {
    # znedi3 uses a plain Makefile (no meson). Build from root; the .so lands
    # in the repo root as vsznedi3.so.
    gclone https://github.com/sekrit-twc/znedi3.git znedi3
    cd znedi3
    git submodule update --init --recursive
    make -j"$(nproc)"
    # The VS plugin .so is built into the repo root
    inst_so .
}
build znedi3 req build_znedi3

build_nnedi3cl() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-NNEDI3CL.git nnedi3cl
    meson_build nnedi3cl
}
build nnedi3cl req build_nnedi3cl

build_knlm() {
    gclone https://github.com/Khanattila/KNLMeansCL.git knlm
    meson_build knlm
}
build knlm req build_knlm

build_cas() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-CAS.git cas
    meson_build cas
}
build cas req build_cas

build_ctmf() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-CTMF.git ctmf
    meson_build ctmf
}
build ctmf req build_ctmf

build_rgvs() {
    gclone https://github.com/vapoursynth/vs-removegrain.git rgvs
    meson_build rgvs
}
build rgvs req build_rgvs

build_miscfilters() {
    gclone https://github.com/vapoursynth/vs-miscfilters-obsolete.git misc
    meson_build misc
}
build miscfilters req build_miscfilters

build_temporalsoften2() {
    # focus2.TemporalSoften2 — REQUIRED by classic havsfunc 33 QTGMC (the
    # default Preset path calls bobbed.focus2.TemporalSoften2). Without it the
    # whole deinterlace step dies with "no attribute or namespace named focus2".
    gclone https://github.com/dubhater/vapoursynth-temporalsoften2.git temporalsoften2
    meson_build temporalsoften2
}
build temporalsoften2 req build_temporalsoften2

# ============================================================================
# OPTIONAL PLUGINS (failures logged, build continues)
# ============================================================================

build_eedi3() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-EEDI3.git eedi3
    meson_build eedi3 -Dopencl=true || meson_build eedi3
}
build eedi3m opt build_eedi3

build_nnedi3() {
    gclone https://github.com/dubhater/vapoursynth-nnedi3.git vsnnedi3
    meson_build vsnnedi3
}
build nnedi3 opt build_nnedi3

build_bwdif() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-Bwdif.git bwdif
    meson_build bwdif
}
build bwdif opt build_bwdif

build_addgrain() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-AddGrain.git addgrain
    meson_build addgrain
}
build addgrain opt build_addgrain

build_dctfilter() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-DCTFilter.git dctfilter
    meson_build dctfilter
}
build dctfilter opt build_dctfilter

build_dfttest() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-DFTTest.git dfttest
    meson_build dfttest
}
build dfttest opt build_dfttest

build_ttempsmooth() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-TTempSmooth.git ttempsmooth
    meson_build ttempsmooth
}
build ttempsmooth opt build_ttempsmooth

build_fluxsmooth() {
    gclone https://github.com/dubhater/vapoursynth-fluxsmooth.git fluxsmooth
    meson_build fluxsmooth
}
build fluxsmooth opt build_fluxsmooth

build_hqdn3d() {
    gclone https://github.com/Hinterwaeldlers/vapoursynth-hqdn3d.git hqdn3d
    meson_build hqdn3d
}
build hqdn3d opt build_hqdn3d

build_deblock() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-Deblock.git deblock
    meson_build deblock
}
build deblock opt build_deblock

build_sangnom() {
    gclone https://github.com/dubhater/vapoursynth-sangnom.git sangnom
    meson_build sangnom
}
build sangnom opt build_sangnom

build_awarpsharp2() {
    gclone https://github.com/dubhater/vapoursynth-awarpsharp2.git awarpsharp2
    meson_build awarpsharp2
}
build awarpsharp2 opt build_awarpsharp2

build_eedi2() {
    gclone https://github.com/HomeOfVapourSynthEvolution/VapourSynth-EEDI2.git eedi2
    meson_build eedi2
}
build eedi2 opt build_eedi2

# ============================================================================
# AI UPSCALE (vs-mlrt: prebuilt Linux binaries, no compilation needed)
# ============================================================================

build_vsmlrt() {
    local VER="v15.16"
    local BASE="https://github.com/AmusementClub/vs-mlrt/releases/download/${VER}"

    # vsncnn.so + libncnn.so
    wget -qO /tmp/vsncnn.7z "${BASE}/VSNCNN-Linux-x64.${VER}.7z"
    7z x -o/tmp/vsncnn /tmp/vsncnn.7z -y >/dev/null 2>&1
    find /tmp/vsncnn -name '*.so' -exec cp -v {} "${PLUGINDIR}/" \; 2>/dev/null
    rm -rf /tmp/vsncnn /tmp/vsncnn.7z

    # vsmlrt.py
    wget -qO /tmp/vsmlrt.7z "${BASE}/scripts.${VER}.7z"
    7z x -o/tmp/vsmlrt /tmp/vsmlrt.7z -y >/dev/null 2>&1
    cp /tmp/vsmlrt/vsmlrt.py "${VSPREFIX}/py/lib/python3.12/site-packages/"
    rm -rf /tmp/vsmlrt /tmp/vsmlrt.7z

    # CUGAN models
    wget -qO /tmp/models.7z "${BASE}/models.${VER}.7z"
    7z x -o/tmp/models /tmp/models.7z -y >/dev/null 2>&1
    mkdir -p "${PLUGINDIR}/models"
    # Only copy cugan models (not rife, dpir, etc) to save ~700MB
    cp -r /tmp/models/models/cugan "${PLUGINDIR}/models/" 2>/dev/null
    rm -rf /tmp/models /tmp/models.7z

    echo "  vs-mlrt ${VER} installed"
}
build vsmlrt opt build_vsmlrt

# ============================================================================
# Summary
# ============================================================================
echo
echo "############################################################"
echo "## BUILD SUMMARY"
echo "############################################################"
echo "Built plugins (${#BUILT[@]}): ${BUILT[*]}"
echo
echo "Optional failures (${#FAILED_OPTIONAL[@]}): ${FAILED_OPTIONAL[*]:-none}"
echo "Required failures (${#FAILED_REQUIRED[@]}): ${FAILED_REQUIRED[*]:-none}"
echo
echo "Installed .so files in ${PLUGINDIR}:"
ls -1 "${PLUGINDIR}" | sed 's/^/  /'
echo "Total: $(ls -1 "${PLUGINDIR}" | wc -l) .so files"

if [ "${#FAILED_REQUIRED[@]}" -gt 0 ]; then
    echo
    echo "FATAL: ${#FAILED_REQUIRED[@]} REQUIRED plugin(s) failed: ${FAILED_REQUIRED[*]}"
    echo "Per-plugin logs in ${LOGDIR}/"
    exit 1
fi
echo "OK: all required plugins built."
exit 0
