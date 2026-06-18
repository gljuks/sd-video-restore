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

# eedi3m shim — save original BEFORE overwriting
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

src = core.lsmas.LWLibavSource(r"[CLIP]")

src = core.resize.Bicubic(src, format=vs.YUV420P8,
                          matrix_in_s="170m", matrix_s="170m",
                          chromaloc=0, dither_type="error_diffusion")

# Field order: SD interlaced captures are almost always BFF.
# _FieldBased: 1=BFF, 2=TFF. Set to 2=TFF (matches original AssumeTFF).
# Flip both to 1/TFF=False if motion judders.
src = core.std.SetFieldBased(src, 2)

clip = haf.QTGMC(src, Preset="Fast", TFF=True, opencl=False)

clip = core.std.Crop(clip, right=12, bottom=6)   # 720x576 -> 708x570

# CPU path: KNLMeansCL (OpenCL) dropped. QTGMC's MVTools core already does
# temporal denoise on analog grain. Re-add spatial denoise later if needed:
#   clip = core.hqdn3d.Hqdn3d(clip)   # libhqdn3d.dll, CPU

# clip = vsdehalo.fine_dehalo(clip, rx=2, ry=2, darkstr=0.5, brightstr=0.75)

clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="170m")
clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709")

clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer="znedi3",
                          width=1440, height=1080)

clip = core.cas.CAS(clip, sharpness=0.4)

clip.set_output()
#
# PER-CLIP NOTES:
#   Untitled 02.mov: non-standard capture stretch — correct DAR is 81:50, not 4:3.
#   Use -aspect 81:50 in ffmpeg (verified via globe + street signs).
