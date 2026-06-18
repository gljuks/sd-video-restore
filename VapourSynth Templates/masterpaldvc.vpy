import os
# CRITICAL: znedi3 reads NNEDI3CL env var at C-level module load time.
# Must be set BEFORE any vapoursynth import. Put this FIRST.
_w = os.path.join(os.environ.get('VSPREFIX', ''), 'share', 'NNEDI3CL')
if os.path.isdir(_w):
    os.environ['NNEDI3CL'] = _w
elif os.path.isdir('/opt/vs/share/NNEDI3CL'):
    os.environ['NNEDI3CL'] = '/opt/vs/share/NNEDI3CL'

import os
_w = os.path.join(os.environ.get('VSPREFIX', ''), 'share', 'NNEDI3CL')
if os.path.isdir(_w): os.environ['NNEDI3CL'] = _w
elif os.path.isdir('/opt/vs/share/NNEDI3CL'): os.environ['NNEDI3CL'] = '/opt/vs/share/NNEDI3CL'

import vapoursynth as vs
core = vs.core

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
import nnedi3_rpow2 as rpow2   # standalone module; havsfunc no longer bundles it
import vsdehalo               # FineDehalo moved here (havsfunc dropped it)

core.num_threads = 8          # tune to your CPU core count

# [CLIP] is replaced by your batch harness, same idea as the .avs [CLIP] token.
src = core.lsmas.LWLibavSource(r"[CLIP]")

# Match the original .avs: ConvertToYV12(interlaced=true) = YUV420P8, Rec.601.
src = core.resize.Bicubic(src, format=vs.YUV420P8,
                          matrix_in_s="170m", matrix_s="170m",
                          chromaloc=0, dither_type="error_diffusion")

# Field order. DV is BFF.
# _FieldBased frame prop: 1 = BFF, 2 = TFF.  SET TO 1 = BFF.
src = core.std.SetFieldBased(src, 1)

# QTGMC(opencl=True) eagerly references core.eedi3m.EEDI3CL, but the
# public EEDI3m r8 build ships only CPU EEDI3 (no OpenCL function). With
# Preset='Fast' EdiMode is 'nnedi3', so EEDI3 is NEVER executed - the crash is
# purely the eager attribute lookup. We alias EEDI3CL -> EEDI3 on the Core
# namespace so the lookup succeeds; NNEDI3CL still does the edge step on GPU.
import vapoursynth as _vs
class _EEDI3MProxy:
    def __init__(self, real):
        self._real = real
    def __getattr__(self, name):
        if name in ("EEDI3CL", "EEDI3"):
            return getattr(self._real, "EEDI3", None) or getattr(_vs.core.eedi2, "EEDI3")
        return getattr(self._real, name)
_orig_core_getattr = _vs.Core.__getattr__
def _shimmed_core_getattr(self, name):
    if name == "eedi3m":
        return _EEDI3MProxy(_vs.core.eedi2)
    return _orig_core_getattr(self, name)
_vs.Core.__getattr__ = _shimmed_core_getattr

# No crop before deint — feed the FULL 720x576 frame (mod4 height for SeparateFields).
clip = haf.QTGMC(src, Preset="Fast", TFF=False, opencl=True, device=0)

# Original .avs: no Crop/AddBorders. The full 720x576 frame goes straight through.

clip = core.knlm.KNLMeansCL(clip, d=1, a=2, s=4, h=1.0,
                            channels="YUV", device_type="gpu", device_id=0)

# clip = vsdehalo.fine_dehalo(clip, rx=3, ry=2, darkstr=0.5, brightstr=0.75)  # needs akarin plugin

clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="170m")
clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709")

clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer="nnedi3cl",
                          width=1280, height=960)

clip = core.cas.CAS(clip, sharpness=0.2)

clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer="nnedi3cl",
                          width=1440, height=1080)

clip = core.cas.CAS(clip, sharpness=0.2)

clip.set_output()
