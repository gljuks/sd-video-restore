# =============================================================================
# VapourSynth R76 portable bundle "oven"
# =============================================================================
# Builds Python 3.12 + VapourSynth R76 + the full plugin stack used by
# masterpaldvcTOP.vpy, into /opt/vs, then export_bundle.sh tars it for Colab.
#
# Why "oven" and not Colab runtime: Colab does not allow custom runtime images.
# So Docker builds the artifact ONCE; Colab downloads + extracts the tarball.
#
# Python 3.12 is required so the abi3 VapourSynth wheel
# (vapoursynth-76-cp312-abi3-manylinux_2_28_x86_64) loads. abi3 = stable ABI
# across all CPython >= 3.12, so the 2021 libpython3.6m symlink hack is gone.
#
# glibc requirement: VapourSynth abi3 wheel needs >= 2.28. Colab is Ubuntu 22.04
# (glibc 2.35). We build on Ubuntu 22.04 to match.
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    VSPREFIX=/opt/vs \
    PATH=/opt/vs/py/bin:/usr/local/bin:/usr/bin:/bin

# -- 1. Toolchain + Python 3.12 (deadsnakes PPA) ------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates gnupg curl wget git zstd \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc-11 g++-11 \
        cmake meson ninja-build pkg-config \
        nasm yasm autoconf automake libtool \
        patchelf file xz-utils unzip p7zip-full \
        python3.12 python3.12-dev python3.12-venv \
        python3-pip \
        libfftw3-dev libzimg-dev zlib1g-dev \
        libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
        ocl-icd-opencl-dev opencl-headers \
        libboost-dev libboost-system-dev libboost-filesystem-dev \
        libxml2-dev liblzma-dev libbz2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Pin gcc-11 as default (some plugins miscompile on gcc-12).
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100 \
 && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100

# -- 2. Bundled relocatable Python 3.12 (the Colab interpreter we ship) -------
# CRITICAL: we use python-build-standalone (Astral), NOT `python3.12 -m venv`.
# A venv only SYMLINKS bin/python3.12 -> /usr/bin/python3.12 (the deadsnakes
# interpreter that exists ONLY in this oven). On a clean Colab runtime that
# target is absent, so the extracted bundle's python fails with exit 127 and
# Path A (download+extract) is dead on arrival. python-build-standalone ships a
# REAL relocatable interpreter + libpython + full stdlib that runs from any
# path on any glibc>=2.17 box. THIS is what actually makes the bundle
# self-contained and the 2021 ABI bug structurally impossible.
#
# Pinned to 3.12.13 (release 20260602); install_only = runtime+headers, no build junk.
ARG PBS_URL=https://github.com/astral-sh/python-build-standalone/releases/download/20260602/cpython-3.12.13%2B20260602-x86_64-unknown-linux-gnu-install_only.tar.gz
RUN cd /tmp \
 && wget -qO pbs.tar.gz "${PBS_URL}" \
 && mkdir -p ${VSPREFIX} \
 && tar xzf pbs.tar.gz \
 && mv python ${VSPREFIX}/py \
 && rm -f pbs.tar.gz \
 && ${VSPREFIX}/py/bin/python -m pip install --upgrade pip wheel setuptools \
 && ${VSPREFIX}/py/bin/python -m pip install --upgrade "meson>=1.3" cython numpy \
 && ${VSPREFIX}/py/bin/python -c "import sys; print('bundled python', sys.version)"

# -- 2b. zimg from source (R76 needs >=3.0.5, Ubuntu 22.04 has 3.0.3) --------
# Static build because VS R76's meson asks for `static: true`.
RUN cd /tmp && git clone --depth 1 --branch release-3.0.5 https://github.com/sekrit-twc/zimg.git zimg \
 && cd zimg \
 && ./autogen.sh \
 && ./configure --prefix=${VSPREFIX} --libdir=${VSPREFIX}/lib --enable-static --with-pic \
 && make -j"$(nproc)" \
 && make install

# -- 2c. VS R76 C++ libs + vspipe: source build, native-file → our Python 3.12 -
# The PyPI abi3 wheel installs the Python bindgen module only. Plugins and
# vspipe need libvapoursynth.so + libvapoursynth-script.so at compile/RT. So
# we build the C/C++ parts from upstream source (R76 tag), the standard Linux
# install. meson >= 1.3 from pip (apt's 0.61 is too old for `license_files`).
#
# ORDER MATTER: pip install the abi3 wheel FIRST, then build from source.
# `pip install vapoursynth` puts vapoursynth.abi3.so into site-packages only.
# `meson install` (source build) puts libvapoursynth.so, libvapoursynth-script.so,
# vspipe, headers, .pc files into $prefix. The abi3 wheel does NOT overwrite
# those C libraries. Building source LAST ensures the C libs are correct.
#
# VS R76's meson.build hardcodes install_dir = py.get_install_dir() / 'vapoursynth'
# which puts vspipe + .pc files + plugins dir inside the Python package. We
# override to $prefix so everything lands in /opt/vs/bin, /opt/vs/lib, etc.
RUN printf "[binaries]\npython = '%s/py/bin/python'\n" "${VSPREFIX}" > /tmp/vs-native.ini \
 && cat /tmp/vs-native.ini

ENV PKG_CONFIG_PATH=/opt/vs/pkgconfig:/opt/vs/lib/pkgconfig
ENV LD_LIBRARY_PATH=/opt/vs/lib

# Install abi3 wheel FIRST (Python module only).
RUN ${VSPREFIX}/py/bin/pip install --upgrade vapoursynth==76

# Now build from source — installs C libs, vspipe, headers, .pc.
RUN cd /tmp && git clone --depth 1 --branch R76 https://github.com/vapoursynth/vapoursynth.git vs-src \
 && cd vs-src \
 && sed -i "s|install_dir = py.get_install_dir() / 'vapoursynth'|install_dir = '${VSPREFIX}'|" meson.build \
 && head -45 meson.build | grep install_dir \
 && ${VSPREFIX}/py/bin/meson setup build \
        --buildtype=release \
        --prefix=${VSPREFIX} \
        --libdir=${VSPREFIX}/lib \
        -Dpython.platlibdir=${VSPREFIX}/py/lib/python3.12/site-packages \
        -Dpython.purelibdir=${VSPREFIX}/py/lib/python3.12/site-packages \
        --native-file=/tmp/vs-native.ini \
 && ${VSPREFIX}/py/bin/meson compile -C build \
 && ${VSPREFIX}/py/bin/meson install -C build

# -- Sanity: the abi3 wheel loaded cleanly inside bundled interpreter. --------
RUN ${VSPREFIX}/py/bin/python -c \
    "import vapoursynth as vs; print('VapourSynth import OK:', vs.__version__, '/ core', vs.core.core_version)"

# Sanity: vspipe runs — it lands directly in $prefix (/opt/vs).
# vspipe (via VSScript) needs ~/.config/vapoursynth/vapoursynth.toml mapping the
# libvsscript.so path → [python_exe, python_lib].
# NOTE: the library is named libvsscript.so (not libvapoursynth-script.so).
RUN VSSCRIPT_SO=$(realpath ${VSPREFIX}/libvsscript.so) \
 && PYTHON_LIB=$(find ${VSPREFIX}/py/lib -maxdepth 1 -name 'libpython3.12.so.1.0' | head -1) \
 && PYTHON_LIB=${PYTHON_LIB:-${VSPREFIX}/py/lib/libpython3.12.so.1.0} \
 && mkdir -p /root/.config/vapoursynth \
 && printf '"%s" = ["%s", "%s"]\n' "$VSSCRIPT_SO" "${VSPREFIX}/py/bin/python" "$PYTHON_LIB" > /root/.config/vapoursynth/vapoursynth.toml \
 && echo "--- vsscript config ---" && cat /root/.config/vapoursynth/vapoursynth.toml \
 && echo "--- ls /opt/vs ---" && ls -la ${VSPREFIX}/vspipe ${VSPREFIX}/libvapoursynth* ${VSPREFIX}/libvsscript* \
 && echo "--- vspipe version ---" && ${VSPREFIX}/vspipe --version

# -- 3b. Install legacy API3 headers (R76 meson excludes them) ---------------
# VS R76's meson.build excludes VapourSynth.h and VSHelper.h from install
# because they're API3 (deprecated). But CAS, CTMF, NNEDI3CL etc. still use
# them. Copy them from the source tree manually.
RUN cp -v /tmp/vs-src/include/VapourSynth.h ${VSPREFIX}/include/ \
 && cp -v /tmp/vs-src/include/VSHelper.h ${VSPREFIX}/include/ \
 && cp -v /tmp/vs-src/include/VSScript4.h ${VSPREFIX}/include/VSScript.h 2>/dev/null || ln -sf VSScript4.h ${VSPREFIX}/include/VSScript.h \
 && ls -la ${VSPREFIX}/include/

# -- 3. Build the plugin .so set into ${VSPREFIX}/plugins --------------------
RUN mkdir -p ${VSPREFIX}/plugins ${VSPREFIX}/lib ${VSPREFIX}/bin
COPY build_plugins.sh /usr/local/bin/build_plugins.sh
RUN chmod +x /usr/local/bin/build_plugins.sh && bash /usr/local/bin/build_plugins.sh

# -- 4. Python helpers (havsfunc, vsdehalo, nnedi3_rpow2, vsjetpack) ---------
# nnedi3_rpow2 is NOT on PyPI — ship it as a bundled .py module.
COPY nnedi3_rpow2.py ${VSPREFIX}/py/lib/python3.12/site-packages/nnedi3_rpow2.py
# CRITICAL: pin havsfunc==33 (classic). havsfunc 34 / git-master REMOVED the
# top-level QTGMC (it became the vsjetpack `QTempGaussMC` class with a totally
# different API). The .vpy ports call classic `haf.QTGMC(Preset=,TFF=,opencl=,
# device=)` — proven against the 2026-06-08 run that failed with
# `module 'havsfunc' has no attribute 'QTGMC'` on v34. v33 needs mvsfunc
# (git-only) + adjust (single raw .py, no setup.py). vsdehalo still provides
# fine_dehalo for the .vpy halo step.
RUN ${VSPREFIX}/py/bin/pip install --upgrade \
        vsdehalo \
        vsjetpack \
        vsutil \
        vstools \
 && ${VSPREFIX}/py/bin/pip install --upgrade \
        "git+https://github.com/HomeOfVapourSynthEvolution/mvsfunc.git" \
 && ${VSPREFIX}/py/bin/python -c "import urllib.request as u; open('${VSPREFIX}/py/lib/python3.12/site-packages/adjust.py','wb').write(u.urlopen('https://raw.githubusercontent.com/dubhater/vapoursynth-adjust/master/adjust.py').read())" \
 && ${VSPREFIX}/py/bin/pip install "havsfunc==33" \
 && ${VSPREFIX}/py/bin/python -c "import havsfunc as h; assert hasattr(h,'QTGMC'), 'classic QTGMC missing'; print('havsfunc classic QTGMC OK')"

# -- 4a. Patch havsfunc.py: pass explicit nnedi3 weights path -----------------
# znedi3 C plugin cannot find weights via env var alone. Patch the direct
# nnedi3() call in QTGMC_Interpolate to pass x_nnedi3_weights_bin explicitly.
COPY patch_havsfunc.py /usr/local/bin/patch_havsfunc.py
RUN ${VSPREFIX}/py/bin/python /usr/local/bin/patch_havsfunc.py

# -- 5. Static FFmpeg (libx264) ----------------------------------------------
RUN cd /tmp && wget -q https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz \
 && tar xJf ffmpeg-release-amd64-static.tar.xz \
 && cp ffmpeg-*-static/ffmpeg ${VSPREFIX}/bin/ffmpeg \
 && cp ffmpeg-*-static/ffprobe ${VSPREFIX}/bin/ffprobe \
 && chmod +x ${VSPREFIX}/bin/ffmpeg ${VSPREFIX}/bin/ffprobe \
 && rm -rf /tmp/ffmpeg-*-static /tmp/ffmpeg-release-amd64-static.tar.xz

# -- 6. Vendor the FULL runtime .so dependency closure into /opt/vs/lib ------
# Also symlink nnedi3_weights.bin where znedi3 can find it at runtime.
# znedi3 looks for $NNEDI3CL/nnedi3_weights.bin — we set NNEDI3CL in each .vpy,
# but also create a well-known fallback path to handle edge cases.
# A clean Colab runtime does NOT have libboost (nnedi3cl), the ffmpeg shared
# libs (lsmas.LWLibavSource needs libavcodec.so.58 et al.), etc. The 2026-06-08
# relocation test proved nnedi3cl + lsmas fail to load without these. So we
# resolve the ldd closure of every plugin + vspipe + the VS core libs and copy
# each resolved lib into /opt/vs/lib — EXCEPT the glibc core and the GPU driver
# libs, which MUST come from the host (vendoring glibc breaks the loader;
# vendoring libcuda/libnvidia would shadow Colab's actual GPU driver).
# patchelf in export_bundle.sh then sets RPATH so they resolve relative to the
# bundle, and the notebook also puts /opt/vs/lib on LD_LIBRARY_PATH.
RUN set -eu; \
    DENY='ld-linux|/libc\.so|/libm\.so|/libpthread\.so|/librt\.so|/libdl\.so|/libresolv\.so|/libutil\.so|/libnsl\.so|linux-vdso|libcuda|libnvidia|/libGL|/libGLX|/libGLdispatch|/libEGL|/libOpenGL|/libstdc\+\+\.so|/libgcc_s\.so'; \
    : > /tmp/vendor.list; \
    for f in "${VSPREFIX}"/plugins/*.so "${VSPREFIX}"/vspipe "${VSPREFIX}"/libvapoursynth*.so* "${VSPREFIX}"/libvsscript*.so*; do \
        [ -e "$f" ] || continue; \
        ldd "$f" 2>/dev/null | awk '/=> \//{print $3}'; \
    done | sort -u | grep -Ev "${DENY}" | grep -v "^${VSPREFIX}/" >> /tmp/vendor.list || true; \
    echo "=== vendoring $(wc -l < /tmp/vendor.list) libs into ${VSPREFIX}/lib ==="; \
    while read -r lib; do \
        [ -n "$lib" ] && [ -e "$lib" ] || continue; \
        cp -Lv "$lib" "${VSPREFIX}/lib/" 2>/dev/null || true; \
    done < /tmp/vendor.list; \
    cp -Lv /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 "${VSPREFIX}/lib/" 2>/dev/null || true; \
    echo "=== /opt/vs/lib now has $(ls -1 ${VSPREFIX}/lib/*.so* 2>/dev/null | wc -l) libs ==="; \
    ln -sf "${VSPREFIX}/share/NNEDI3CL/nnedi3_weights.bin" /nnedi3_weights.bin || true

# -- 6a. Re-verify the closure is satisfied USING ONLY the bundle's own libs --
# Run ldd with LD_LIBRARY_PATH limited to /opt/vs/lib (plus host glibc/driver)
# and assert no plugin reports "not found". Fails the build if a dep is missing.
RUN set -eu; \
    MISSING=0; \
    for f in "${VSPREFIX}"/plugins/*.so; do \
        out=$(LD_LIBRARY_PATH="${VSPREFIX}/lib" ldd "$f" 2>/dev/null | grep "not found" || true); \
        if [ -n "$out" ]; then echo "STILL MISSING for $(basename $f):"; echo "$out"; MISSING=1; fi; \
    done; \
    if [ "$MISSING" -ne 0 ]; then echo "FATAL: unvendored plugin deps remain"; exit 1; fi; \
    echo "OK: all plugin deps satisfied by bundle libs (modulo host glibc/GPU driver)"

# -- 7. Plugin autoload config (the REAL fix) --------------------------------
# VapourSynth R76 on Linux reads NO vapoursynth.conf and has NO
# VAPOURSYNTH_PLUGIN_PATH. Per src/core/vscore.cpp the core autoloads from
# exactly two places: <dir-of-libvapoursynth.so>/plugins  and
# $VAPOURSYNTH_EXTRA_PLUGIN_PATH. Our libs live in /opt/vs/lib but plugins in
# /opt/vs/plugins, so the first path misses — VAPOURSYNTH_EXTRA_PLUGIN_PATH is
# the correct knob and is honored by BOTH `import vapoursynth` and vspipe.
ENV VAPOURSYNTH_EXTRA_PLUGIN_PATH=/opt/vs/plugins

# -- 7a. Smoke test inside the oven (fail fast at build time) -----------------
# ffms2 intentionally NOT required: the .vpy uses lsmas.LWLibavSource; ffms2 is
# only a commented-out alternative source filter.
RUN ${VSPREFIX}/py/bin/python - <<'PY'
import vapoursynth as vs
core = vs.core
plugins = sorted(p.namespace for p in core.plugins())
print("Plugins autoloaded:", len(plugins))
for ns in plugins:
    print("  -", ns)
required = {"std","resize","lsmas","mv","znedi3","nnedi3cl",
            "fmtc","cas","knlm","ctmf","rgvs","misc"}
have = set(plugins)
missing = required - have
if missing:
    raise SystemExit(f"MISSING required plugins: {sorted(missing)}")
print("OK: all required plugin namespaces present")

# Helper modules:
import havsfunc, vsdehalo, nnedi3_rpow2
print("OK: havsfunc / vsdehalo / nnedi3_rpow2 import")
PY

# -- 8. Export script copied last so changes don't bust earlier layers -------
COPY export_bundle.sh /usr/local/bin/export_bundle.sh
RUN chmod +x /usr/local/bin/export_bundle.sh

CMD ["bash", "/usr/local/bin/export_bundle.sh"]
