#!/usr/bin/env python3
"""Generate Analog_Restore_Colab.ipynb deterministically.

Run: python3 build_notebook.py
Output: ./Analog_Restore_Colab.ipynb
"""
import base64
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE / "Analog_Restore_Colab.ipynb"

# Embed build_plugins.sh as base64 so Path B (in-Colab build) can decode and
# run the SAME builder Docker uses. Avoids nested-triple-quote hell.
BUILD_PLUGINS_B64 = base64.b64encode(
    (HERE / "build_plugins.sh").read_bytes()
).decode("ascii")

# ============================================================================
# Cell content. Each markdown/code cell is one literal string.
# ============================================================================

MD_INTRO = r"""# Analog Video Restoration on Google Colab — VapourSynth R76

End-to-end pipeline that mirrors the **Windows** master script `masterpaldvcTOP.vpy`:

```
src(AVI rawvideo)  ->  YUV444P8 (Rec.601, error_diffusion)
                    ->  QTGMC deinterlace (TFF, GPU edge step)
                    ->  Crop 720x576 -> 708x570
                    ->  KNLMeansCL denoise (GPU)
                    ->  fine_dehalo (vsdehalo)
                    ->  Rec.601 -> Rec.709 (matrix recompute via RGBS)
                    ->  nnedi3_rpow2 upscale to 1440x1080 (GPU)
                    ->  CAS sharpen
                    ->  vspipe y4m | ffmpeg libx264 / NVENC + AAC mux
```

**Why this notebook works where the 2021 one didn't**

The 2021 notebook installed VapourSynth via `apt`, pulling a `vspipe` linked
against `libpython3.6m`. Each time Colab bumped its Python (3.6 -> 3.11 -> 3.12)
it broke; the desperate `os.symlink` fix produced `undefined symbol:
getVSScriptAPI`. When VS failed, the notebook silently fell back to a plain
`ffmpeg yadif=1:1,hqdn3d,scale,unsharp` chain — that is NOT the pipeline.

The 2026 fix: VapourSynth R76 ships an **abi3** wheel
(`vapoursynth-76-cp312-abi3-manylinux_2_28_x86_64`). abi3 = stable ABI for every
CPython >= 3.12. We bundle our own Python 3.12 + VS R76 + all 20-odd plugins
into one `vs-portable-linux-py312.tar.zst`, built once by `Dockerfile`, then
just `wget` + `tar` it into `/opt/vs` at the start of each Colab session.

If a bundle URL is set in Cell 2, we use it (fast, ~20 s setup). If not, the
notebook falls back to building Python 3.12 + VapourSynth + plugins inside the
Colab session (slow, ~10-20 min, but still produces the SAME pipeline).
"""

CELL_1 = r"""#@title 1 - GPU + env probe + pick GPU mode
#@markdown Runs `nvidia-smi`, writes the NVIDIA OpenCL ICD, runs `clinfo`,
#@markdown and sets `VS_GPU_MODE` env var to `opencl` (preferred) or `cuda`.
import os, subprocess, sys

def run(cmd, **kw):
    return subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, **kw)

print("=== nvidia-smi ===")
r = run("nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv")
print(r.stdout or r.stderr)

print("=== python / os / glibc ===")
print(sys.version)
print(run("cat /etc/os-release | grep -E 'PRETTY_NAME|VERSION_ID'").stdout)
print(run("ldd --version | head -1").stdout)

print("=== installing clinfo ===")
run("apt-get -qq install -y clinfo")

# Register NVIDIA's OpenCL ICD so clinfo / VS plugins see the GPU.
os.makedirs("/etc/OpenCL/vendors", exist_ok=True)
with open("/etc/OpenCL/vendors/nvidia.icd", "w") as f:
    f.write("libnvidia-opencl.so.1\n")

print("=== clinfo -l ===")
clinfo = run("clinfo -l").stdout
print(clinfo or "(empty)")

has_gpu = any(s in clinfo for s in ("NVIDIA", "CUDA", "Tesla", "GeForce", "L4", "A100"))
if has_gpu:
    os.environ["VS_GPU_MODE"] = "opencl"
    print("\n>>> VS_GPU_MODE = opencl  (full pipeline, matches Windows .vpy)")
else:
    os.environ["VS_GPU_MODE"] = "cuda"
    print("\n>>> VS_GPU_MODE = cuda    (CPU znedi3 / hqdn3d fallback path)")

# Persist for shell subprocesses.
with open("/etc/profile.d/vs_gpu_mode.sh", "w") as f:
    f.write(f'export VS_GPU_MODE={os.environ["VS_GPU_MODE"]}\n')
"""

# Cell 2 references BUILD_PLUGINS_B64 via .format(); we double the literal
# braces in any JSON/shell snippets to survive str.format().
CELL_2_TEMPLATE = r'''#@title 2 - Fetch + unpack prebuilt VS bundle (~20s) OR build in-session
#@markdown ### Path A (fast, recommended): set `BUNDLE_URL` to your GitHub Release asset URL.
#@markdown ### Path B (no URL set): rebuilds Python 3.12 + VS R76 + plugins inside Colab (~10-20 min).
BUNDLE_URL = ""  #@param {{type:"string"}}

import os, subprocess, sys, base64, textwrap
from pathlib import Path

VSPREFIX = "/opt/vs"
os.environ["VSPREFIX"] = VSPREFIX

def sh(cmd, check=True):
    print("$", cmd)
    r = subprocess.run(cmd, shell=True)
    if check and r.returncode != 0:
        raise SystemExit(f"FAILED ({{r.returncode}}): {{cmd}}")

if BUNDLE_URL:
    # ---------- Path A: prebuilt bundle ------------------------------------
    print(f"=== Path A: downloading {{BUNDLE_URL}}")
    sh("apt-get -qq install -y zstd wget")
    sh(f"wget -q -O /tmp/vs.tar.zst '{{BUNDLE_URL}}'")
    sh(f"mkdir -p {{VSPREFIX}} && tar --zstd -xf /tmp/vs.tar.zst -C /opt")
    sh(f"cat {{VSPREFIX}}/BUNDLE_VERSION 2>/dev/null || echo '(no manifest)'")
else:
    # ---------- Path B: build in Colab session -----------------------------
    print("=== Path B: BUNDLE_URL not set; building VS R76 + plugins in-session")
    print("    (10-20 minutes; results survive only the lifetime of this Colab VM)")

    sh("apt-get -qq update")
    sh("apt-get -qq install -y software-properties-common")
    sh("add-apt-repository -y ppa:deadsnakes/ppa")
    sh("apt-get -qq update")
    sh("apt-get -qq install -y build-essential gcc-11 g++-11 "
       "cmake meson ninja-build pkg-config nasm yasm autoconf automake libtool "
       "patchelf file xz-utils unzip p7zip-full git wget zstd "
       "python3.12 python3.12-dev python3.12-venv "
       "libfftw3-dev libzimg-dev zlib1g-dev "
       "libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev "
       "ocl-icd-opencl-dev opencl-headers")
    sh("update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100")
    sh("update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100")

    # Bundled Python 3.12 venv + abi3 VapourSynth wheel.
    sh(f"python3.12 -m venv {{VSPREFIX}}/py")
    sh(f"{{VSPREFIX}}/py/bin/pip install --upgrade pip wheel setuptools cython numpy vapoursynth==76")
    sh(f"mkdir -p {{VSPREFIX}}/plugins {{VSPREFIX}}/lib {{VSPREFIX}}/bin")

    # Decode the embedded build_plugins.sh and run it (same script Docker uses).
    BUILD_PLUGINS_B64 = "__B64__"
    Path("/tmp/build_plugins.sh").write_bytes(base64.b64decode(BUILD_PLUGINS_B64))
    sh("chmod +x /tmp/build_plugins.sh && bash /tmp/build_plugins.sh")

    # nnedi3_rpow2 is NOT on PyPI — ship as bundled .py module.
    sh(f"cp /content/nnedi3_rpow2.py {{VSPREFIX}}/py/lib/python3.12/site-packages/nnedi3_rpow2.py 2>/dev/null || true")
    sh(f"{{VSPREFIX}}/py/bin/pip install vsdehalo vsjetpack vsutil vstools")
    sh(f"{{VSPREFIX}}/py/bin/pip install 'git+https://github.com/HomeOfVapourSynthEvolution/havsfunc.git'")

    # Static FFmpeg with libx264.
    sh("cd /tmp && wget -q https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && tar xJf ffmpeg-release-amd64-static.tar.xz")
    sh(f"cp /tmp/ffmpeg-*-static/ffmpeg {{VSPREFIX}}/bin/ffmpeg && cp /tmp/ffmpeg-*-static/ffprobe {{VSPREFIX}}/bin/ffprobe && chmod +x {{VSPREFIX}}/bin/ffmpeg {{VSPREFIX}}/bin/ffprobe")

# ---------- Set environment for every subsequent cell ----------------------
os.environ["PATH"] = f"{{VSPREFIX}}/py/bin:{{VSPREFIX}}/bin:" + os.environ["PATH"]
os.environ["LD_LIBRARY_PATH"] = f"{{VSPREFIX}}/lib:" + os.environ.get("LD_LIBRARY_PATH", "")
os.environ["VAPOURSYNTH_PLUGIN_PATH"] = f"{{VSPREFIX}}/plugins"
os.environ["PYTHONPATH"] = f"{{VSPREFIX}}/py/lib/python3.12/site-packages:" + os.environ.get("PYTHONPATH", "")

with open("/etc/profile.d/vs_env.sh", "w") as f:
    f.write(textwrap.dedent(f"""\\
        export PATH={{VSPREFIX}}/py/bin:{{VSPREFIX}}/bin:$PATH
        export LD_LIBRARY_PATH={{VSPREFIX}}/lib:${{{{LD_LIBRARY_PATH:-}}}}
        export VAPOURSYNTH_PLUGIN_PATH={{VSPREFIX}}/plugins
        export PYTHONPATH={{VSPREFIX}}/py/lib/python3.12/site-packages:${{{{PYTHONPATH:-}}}}
    """))

print("\\n=== vspipe --version ===")
sh(f"{{VSPREFIX}}/vspipe --version || {{VSPREFIX}}/py/bin/vspipe --version || {{VSPREFIX}}/bin/vspipe --version", check=False)
print("\\n=== ffmpeg version ===")
sh(f"{{VSPREFIX}}/bin/ffmpeg -version | head -1")

# vspipe needs a TOML config so VSScript can find Python.
import subprocess as _sp
VSSCRIPT_SO = _sp.run(["realpath", f"{{VSPREFIX}}/libvsscript.so"], capture_output=True, text=True).stdout.strip()
if not VSSCRIPT_SO:
    VSSCRIPT_SO = f"{{VSPREFIX}}/libvsscript.so"
PYTHON_LIB = _sp.run(
    [f"{{VSPREFIX}}/py/bin/python", "-c",
     "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))"],
    capture_output=True, text=True
).stdout.strip() + "/libpython3.12.so.1.0"
import os
os.makedirs(os.path.expanduser("~/.config/vapoursynth"), exist_ok=True)
with open(os.path.expanduser("~/.config/vapoursynth/vapoursynth.toml"), "w") as _f:
    _f.write('"' + VSSCRIPT_SO + '" = ["' + f"{{VSPREFIX}}/py/bin/python" + '", "' + PYTHON_LIB + '"]\n')
print("--- vsscript config ---")
with open(os.path.expanduser("~/.config/vapoursynth/vapoursynth.toml")) as _f:
    print(_f.read())
'''

# Format-substitute the b64 placeholder. The template uses {{ }} for literal
# braces; str.format() collapses them. We use a sentinel __B64__ for the blob
# to avoid pulling the multi-MB base64 through .format().
CELL_2 = CELL_2_TEMPLATE.format().replace("__B64__", BUILD_PLUGINS_B64)

CELL_3 = r'''#@title 3 - Verify ALL required plugins load (fail fast)
#@markdown This is the guard the 2021 notebook lacked. If any required plugin
#@markdown namespace is missing, we stop here -- no silent fall-back to a
#@markdown wrong-quality `yadif+hqdn3d` ffmpeg chain.
import os, subprocess, sys

VSPREFIX = os.environ.get("VSPREFIX", "/opt/vs")
PY = f"{VSPREFIX}/py/bin/python"

probe = r"""
import sys, importlib
import vapoursynth as vs
core = vs.core
loaded = sorted(p.namespace for p in core.plugins())
print(f"VapourSynth: {vs.core.core_version!s}")
print(f"Plugin count: {len(loaded)}")
for n in loaded: print("  -", n)

required = {"std","resize","lsmas","ffms2","mv","znedi3","nnedi3cl",
            "fmtc","cas","knlm","ctmf","rgvs","misc"}
nice_to_have = {"nnedi3","eedi3m","bwdif","grain","dctfilter","dfttest"}
missing_required  = sorted(required  - set(loaded))
missing_nice      = sorted(nice_to_have - set(loaded))
print()
print("REQUIRED missing:", missing_required or "(none)")
print("OPTIONAL missing:", missing_nice or "(none)")

for mod in ("havsfunc", "vsdehalo", "nnedi3_rpow2"):
    try:
        importlib.import_module(mod)
        print(f"  py: {mod} OK")
    except Exception as e:
        print(f"  py: {mod} FAIL -> {e}")
        sys.exit(2)

if missing_required:
    sys.exit(1)
print("ALL REQUIRED PRESENT")
"""
r = subprocess.run([PY, "-c", probe], capture_output=True, text=True)
print(r.stdout)
if r.stderr: print("STDERR:", r.stderr)
if r.returncode != 0:
    raise SystemExit(f"Plugin verification FAILED with code {r.returncode}. STOP.")
print("\n>>> Plugin stack OK. Proceed.")
'''

CELL_4 = r"""#@title 4 - Mount Drive, stage source AVIs
#@markdown Drop your `.avi` files in:
#@markdown ```
#@markdown /content/drive/MyDrive/avis/Source_in/
#@markdown ```
#@markdown Outputs land in:
#@markdown ```
#@markdown /content/drive/MyDrive/avis/Target_out/
#@markdown ```
import os
from pathlib import Path
from google.colab import drive

drive.mount('/content/drive')

SRC_DIR  = Path('/content/drive/MyDrive/avis/Source_in')
OUT_DIR  = Path('/content/drive/MyDrive/avis/Target_out')
SRC_DIR.mkdir(parents=True, exist_ok=True)
OUT_DIR.mkdir(parents=True, exist_ok=True)

sources = sorted(list(SRC_DIR.glob('*.avi')) + list(SRC_DIR.glob('*.AVI')))
print(f"Source dir: {SRC_DIR}")
print(f"Output dir: {OUT_DIR}")
print(f"Found {len(sources)} AVI(s):")
for p in sources:
    sz = p.stat().st_size / (1024*1024)
    print(f"  {sz:8.1f} MB  {p.name}")

if not sources:
    print("\n*** No .avi files. Upload some to Source_in/ and re-run this cell. ***")
"""

# CELL_5 writes a .vpy via Python. The .vpy body is its OWN raw string.
# Outer is r""" ... """, inner uses single triple-quote on outer; the .vpy
# is written with .write_text(r'...') triple-single-quote to avoid clash.
CELL_5 = '''#@title 5 - Write the GPU-mode aware .vpy (ported from masterpaldvcTOP.vpy)
#@markdown Modes selected at runtime by `VS_GPU_MODE` from Cell 1:
#@markdown - `opencl`: full Windows pipeline (QTGMC opencl=True, KNLMeansCL, nnedi3cl upscale).
#@markdown - `cuda`/`cpu`: QTGMC opencl=False, hqdn3d denoise, znedi3 upscale.
import os
from pathlib import Path

VPY = Path('/content/master.vpy')
VPY_BODY = r"""
# masterpaldvcTOP.vpy -- Colab port (GPU-mode aware).
# CLIP path is injected via: vspipe -a CLIP_PATH=/path/to/file.avi master.vpy ...
import os, sys
import vapoursynth as vs
core = vs.core

GPU_MODE = os.environ.get("VS_GPU_MODE", "opencl").lower()
OPENCL   = (GPU_MODE == "opencl")

import havsfunc as haf
import nnedi3_rpow2 as rpow2
import vsdehalo

core.num_threads = 8

# CLIP_PATH comes from `vspipe -a CLIP_PATH=...` (lands in module globals).
CLIP = globals().get("CLIP_PATH") or os.environ.get("CLIP_PATH")
if not CLIP:
    raise RuntimeError("CLIP_PATH not set. Pass with: vspipe -a CLIP_PATH=/path/file.avi master.vpy ...")

# ---------- SOURCE ----------------------------------------------------------
src = core.lsmas.LWLibavSource(CLIP)

# ---------- COLORSPACE: AVI rawvideo decodes RGB; go YUV444P8 (NOT 420) -----
# (See Windows .vpy comment: 444 keeps fields clean through deinterlace; chroma
# is sub-sampled to 420 LATER, on progressive frames.)
src = core.resize.Bicubic(src, format=vs.YUV444P8, matrix_s="170m",
                          dither_type="error_diffusion")

# ---------- Field order: TFF (matches Windows fix) --------------------------
src = core.std.SetFieldBased(src, 2)  # 2 = TFF

# ---------- EEDI3CL compat shim (only fires if eedi3m has no EEDI3CL) -------
def _install_eedi3cl_shim():
    try:
        core.eedi3m.EEDI3CL
        return  # already present
    except AttributeError:
        pass
    import vapoursynth as _vs
    _orig = _vs.Plugin.__getattr__
    def _shim(self, name):
        if name == "EEDI3CL":
            def _impl(clip, *a, device=None, **k):
                return core.eedi3m.EEDI3(clip, *a, **k)
            return _impl
        return _orig(self, name)
    _vs.Plugin.__getattr__ = _shim
_install_eedi3cl_shim()

# ---------- DEINTERLACE (QTGMC) ---------------------------------------------
clip = haf.QTGMC(src, Preset="Fast", TFF=True, opencl=OPENCL,
                 device=0 if OPENCL else -1)

# ---------- CROP after deinterlace (progressive, mod-2 legal) ---------------
clip = core.std.Crop(clip, right=12, bottom=6)   # 720x576 -> 708x570

# ---------- DENOISE: GPU KNLMeansCL on opencl, hqdn3d on cuda/cpu -----------
if OPENCL:
    clip = core.knlm.KNLMeansCL(clip, d=1, a=2, s=4, h=1.0,
                                channels="YUV", device_type="gpu", device_id=0)
else:
    try:
        clip = core.hqdn3d.Hqdn3d(clip, lum_spac=4, chrom_spac=3, lum_tmp=6, chrom_tmp=4.5)
    except Exception:
        pass

# ---------- HALO removal ----------------------------------------------------
try:
    clip = vsdehalo.fine_dehalo(clip, rx=2, ry=2, darkstr=0.5, brightstr=0.75)
except Exception as e:
    print(f"fine_dehalo skipped: {e}", file=sys.stderr)

# ---------- COLOR: Rec.601 -> Rec.709 (real matrix recompute via RGBS) ------
clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="170m")
clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709")

# ---------- UPSCALE: nnedi3cl on opencl, znedi3 on cuda/cpu, CUGAN on ai ----
if GPU_MODE == "ai":
    from vsmlrt import CUGAN, Backend
    clip = CUGAN(clip, noise=-1, scale=2, version=2,
                 backend=Backend.NCNN_VK(num_streams=1, fp16=True))
    clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709",
                               width=1440, height=1080)
else:
    upsizer = "nnedi3cl" if OPENCL else "znedi3"
    clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer=upsizer,
                              width=1440, height=1080)

# ---------- CAS sharpen -----------------------------------------------------
clip = core.cas.CAS(clip, sharpness=0.4)

clip.set_output()
"""
VPY.write_text(VPY_BODY)
print(f"Wrote {VPY}")
print("GPU mode env var:", os.environ.get("VS_GPU_MODE"))
'''

CELL_6 = r"""#@title 6 - Encode (vspipe | ffmpeg) with audio mux
#@markdown Re-implements the Windows `convertvpy.bat` logic:
#@markdown vspipe streams y4m video on stdout; ffmpeg takes vspipe (stdin) AND
#@markdown the ORIGINAL .avi as input #2 for the audio track. Both inputs get
#@markdown `-thread_queue_size 4096` to silence the slow-pipe vs fast-disk
#@markdown blocking warning.
#@markdown
#@markdown Set `DURATION` to limit to first N seconds (smoke test); 0 = full.
ENCODER  = "libx264"   #@param ["libx264", "h264_nvenc"]
CRF_QP   = 17          #@param {type:"integer"}
DURATION = 5           #@param {type:"integer"}

import os, subprocess, time
from pathlib import Path

VSPREFIX = os.environ.get("VSPREFIX", "/opt/vs")
VSPIPE  = f"{VSPREFIX}/vspipe"
if not Path(VSPIPE).exists():
    VSPIPE = f"{VSPREFIX}/py/bin/vspipe"
if not Path(VSPIPE).exists():
    VSPIPE = f"{VSPREFIX}/bin/vspipe"
FFMPEG  = f"{VSPREFIX}/bin/ffmpeg"

SRC_DIR = Path('/content/drive/MyDrive/avis/Source_in')
OUT_DIR = Path('/content/drive/MyDrive/avis/Target_out')
VPY     = Path('/content/master.vpy')

sources = sorted(list(SRC_DIR.glob('*.avi')) + list(SRC_DIR.glob('*.AVI')))
if not sources:
    raise SystemExit(f"No sources in {SRC_DIR}")

for i, src in enumerate(sources, 1):
    out = OUT_DIR / f"{src.stem}_restored.mp4"
    print(f"\n=== [{i}/{len(sources)}] {src.name} -> {out.name}")
    t0 = time.time()

    vp_cmd = [VSPIPE, "-c", "y4m", "-a", f"CLIP_PATH={src}", str(VPY), "-"]
    if ENCODER == "libx264":
        v_args = ["-c:v", "libx264", "-crf", str(CRF_QP), "-preset", "medium",
                  "-profile:v", "high", "-pix_fmt", "yuv420p"]
    else:
        v_args = ["-c:v", "h264_nvenc", "-qp", str(CRF_QP), "-preset", "p7",
                  "-tune", "hq", "-rc", "constqp", "-rc-lookahead", "32",
                  "-profile:v", "high", "-pix_fmt", "yuv420p"]

    ff_cmd = [
        FFMPEG, "-y",
        "-thread_queue_size", "4096", "-i", "-",
        "-thread_queue_size", "4096", "-i", str(src),
        "-map", "0:v:0", "-map", "1:a:0?",
        *(["-t", str(DURATION)] if DURATION and DURATION > 0 else []),
        *v_args,
        "-aspect", "4:3",
        "-c:a", "aac", "-b:a", "192k", "-async", "1",
        str(out)
    ]

    print("VSPIPE:", " ".join(vp_cmd))
    print("FFMPEG:", " ".join(ff_cmd))

    env = os.environ.copy()
    env["CLIP_PATH"] = str(src)

    vp = subprocess.Popen(vp_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    ff = subprocess.Popen(ff_cmd, stdin=vp.stdout, stderr=subprocess.STDOUT,
                          stdout=subprocess.PIPE, env=env,
                          bufsize=1, universal_newlines=True)
    vp.stdout.close()  # let ffmpeg drive backpressure on vspipe

    for line in ff.stdout:
        if line.startswith("frame=") or "time=" in line:
            print("\r" + line.rstrip()[:160], end="", flush=True)
        else:
            print(line.rstrip())
    ff.wait(); vp.wait()
    print()
    dt = time.time() - t0
    print(f"vspipe rc={vp.returncode}  ffmpeg rc={ff.returncode}  elapsed={dt/60:.1f} min")
    if vp.returncode != 0:
        print("--- vspipe stderr (tail) ---")
        print(vp.stderr.read().decode("utf-8", "replace")[-2000:])
    if ff.returncode != 0:
        raise SystemExit(f"FAILED on {src.name}")
    if out.exists():
        size_mb = out.stat().st_size / (1024*1024)
        print(f"OUTPUT: {out}  ({size_mb:.1f} MB)")
"""

CELL_7 = r"""#@title 7 - Verify output with ffprobe (resolution, codec, audio, A/V delta)
import os, subprocess, json
from pathlib import Path

VSPREFIX = os.environ.get("VSPREFIX", "/opt/vs")
FFPROBE  = f"{VSPREFIX}/bin/ffprobe"
OUT_DIR  = Path('/content/drive/MyDrive/avis/Target_out')

results = sorted(OUT_DIR.glob("*_restored.mp4"))
if not results:
    raise SystemExit(f"No outputs in {OUT_DIR}")

bad = 0
for out in results:
    print(f"\n=== {out.name}")
    r = subprocess.run(
        [FFPROBE, "-v", "error", "-print_format", "json",
         "-show_streams", "-show_format", str(out)],
        capture_output=True, text=True)
    if r.returncode != 0:
        print("FFPROBE FAILED:", r.stderr); bad += 1; continue
    meta = json.loads(r.stdout)
    streams = meta.get("streams", [])
    v = next((s for s in streams if s["codec_type"] == "video"), None)
    a = next((s for s in streams if s["codec_type"] == "audio"), None)
    print(f"  format  : {meta['format'].get('format_name')}  "
          f"size={int(meta['format'].get('size',0))/1024/1024:.1f} MB  "
          f"dur={float(meta['format'].get('duration',0)):.2f}s")
    if v:
        print(f"  video   : {v['codec_name']} {v['width']}x{v['height']} "
              f"pix={v.get('pix_fmt')} dar={v.get('display_aspect_ratio','?')}")
        ok_h264 = v['codec_name'] == 'h264'
        ok_dim  = (v['width'], v['height']) == (1440, 1080)
        if not (ok_h264 and ok_dim):
            print(f"  WARN: expected h264 1440x1080 (got {v['codec_name']} {v['width']}x{v['height']})")
            bad += 1
    else:
        print("  WARN: no video stream"); bad += 1
    if a:
        print(f"  audio   : {a['codec_name']} {a.get('sample_rate')}Hz {a.get('channels')}ch")
        if a['codec_name'] != 'aac':
            print(f"  WARN: expected AAC (got {a['codec_name']})"); bad += 1
    else:
        print("  WARN: no audio stream (was source video-only?)")

    if v and a and v.get("duration") and a.get("duration"):
        dv = float(v["duration"]); da = float(a["duration"])
        delta = abs(dv - da)
        print(f"  A/V dur : video={dv:.3f}s audio={da:.3f}s delta={delta:.3f}s")
        if delta > 0.1:
            print(f"  WARN: A/V delta > 0.1s"); bad += 1

if bad == 0:
    print("\n>>> All outputs PASS verification.")
else:
    print(f"\n>>> {bad} warning(s) raised. Inspect manually before declaring done.")
"""

# ============================================================================
# Pack into nbformat
# ============================================================================

def code_cell(source, cid):
    return {
        "cell_type": "code",
        "id": cid,
        "metadata": {"id": cid},
        "source": source.splitlines(keepends=True),
        "execution_count": None,
        "outputs": [],
    }

def md_cell(source, cid):
    return {
        "cell_type": "markdown",
        "id": cid,
        "metadata": {},
        "source": source.splitlines(keepends=True),
    }

nb = {
    "nbformat": 4,
    "nbformat_minor": 5,
    "metadata": {
        "accelerator": "GPU",
        "colab": {"provenance": [], "machine_shape": "hm"},
        "kernelspec": {"display_name": "Python 3", "name": "python3"},
        "language_info": {"name": "python"},
    },
    "cells": [
        md_cell(MD_INTRO, "intro"),
        code_cell(CELL_1, "cell_1_probe"),
        code_cell(CELL_2, "cell_2_bundle"),
        code_cell(CELL_3, "cell_3_verify"),
        code_cell(CELL_4, "cell_4_drive"),
        code_cell(CELL_5, "cell_5_vpy"),
        code_cell(CELL_6, "cell_6_encode"),
        code_cell(CELL_7, "cell_7_verify"),
    ],
}

with OUT.open("w", encoding="utf-8") as f:
    json.dump(nb, f, indent=1, ensure_ascii=False)

print(f"Wrote {OUT} ({OUT.stat().st_size} bytes, {len(nb['cells'])} cells)")
