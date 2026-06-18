import os
# CRITICAL: znedi3 reads NNEDI3CL env var at C-level module load time.
# Must be set BEFORE any vapoursynth import. Put this FIRST.
_w = os.path.join(os.environ.get('VSPREFIX', ''), 'share', 'NNEDI3CL')
if os.path.isdir(_w):
    os.environ['NNEDI3CL'] = _w
elif os.path.isdir('/opt/vs/share/NNEDI3CL'):
    os.environ['NNEDI3CL'] = '/opt/vs/share/NNEDI3CL'

import vapoursynth as vs
core = vs.core

# eedi3m shim — save original BEFORE overwriting.
# NOTE: on this Windows box the shim is a NO-OP for QTGMC, because EEDI3m.dll
# IS installed (so core.eedi3m resolves and __getattr__ never fires). The shim
# only matters on a box where eedi3m is absent (e.g. Colab). Left in for parity.
import vapoursynth as _vs2
class _EEDI3Func:
    def __call__(self, clip, *args, **kwargs):
        field = kwargs.get('field', args[0] if args else 0)
        return _vs2.core.eedi2.EEDI2(clip, field=field)
class _EEDI3MProxy:
    def __getattr__(self, name):
        if name in ('EEDI3CL', 'EEDI3'): return _EEDI3Func()
        raise AttributeError(name)
_orig_getattr = _vs2.Core.__getattr__
def _shimmed_getattr(self, name):
    if name == 'eedi3m': return _EEDI3MProxy()
    return _orig_getattr(self, name)
_vs2.Core.__getattr__ = _shimmed_getattr

import havsfunc as haf
import nnedi3_rpow2 as rpow2
import vsdehalo
core.num_threads = 8

# ============================================================================
# GPU VARIANT of masterpaldvcTOP.vpy  — VERIFIED WORKING on this box (RTX 3050)
# GPU stage: NNEDI3CL.dll -> nnedi3cl upscale (the bottleneck; this is the win).
# Smoke-tested: 10/10 frames, exit 0.
#
# KNLMeansCL is DELIBERATELY NOT USED: KNLMeansCL.dll (2024 build) throws
# "knlm.KNLMeansCL: fatal error!" at frame 0 on this driver (581.57) at ANY
# settings — even d=0,a=1,s=2 — while nnedi3cl (same OpenCL) works fine. So it's
# the KNLMeansCL DLL, not OpenCL/VRAM. Denoise is done on CPU via hqdn3d instead
# (QTGMC's MVTools already temporal-denoises; hqdn3d adds cheap spatial cleanup).
#
# QTGMC stays opencl=False: this box's EEDI3m.dll has NO EEDI3CL variant, so
# QTGMC(opencl=True) crashes at havsfunc:1616. QTGMC barely benefits from GPU
# anyway (MVTools core is CPU-only). To enable QTGMC GPU edge-interp you must
# first install an EEDI3CL-capable eedi3m build (vsrepo update && vsrepo install
# eedi3m), THEN switch the QTGMC line below to the opencl=True version.
#
# Smoke-test ALWAYS before a full run:
#     vspipe -c y4m -e 49 "Source\<name>.vpy" NUL
# ============================================================================

src = core.lsmas.LWLibavSource(r"[CLIP]")

src = core.resize.Bicubic(src, format=vs.YUV420P8,
                          matrix_in_s="170m", matrix_s="170m",
                          chromaloc=0, dither_type="error_diffusion")

# Field order: SD interlaced captures are almost always BFF.
# _FieldBased: 1=BFF, 2=TFF. Set to 2=TFF (matches original AssumeTFF).
# Flip both to 1/TFF=False if motion judders.
src = core.std.SetFieldBased(src, 2)

clip = haf.QTGMC(src, Preset="Fast", TFF=True, opencl=False)
# GPU edge-interp (requires EEDI3CL-capable eedi3m build — NOT present here):
# clip = haf.QTGMC(src, Preset="Fast", TFF=True, opencl=True, device=0)

clip = core.std.Crop(clip, right=12, bottom=6)   # 720x576 -> 708x570

clip = core.hqdn3d.Hqdn3d(clip)

# clip = vsdehalo.fine_dehalo(clip, rx=2, ry=2, darkstr=0.5, brightstr=0.75)

clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="170m")
clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709")

clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer="nnedi3cl",
                          width=1440, height=1080)

clip = core.cas.CAS(clip, sharpness=0.4)

clip.set_output()
