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
import nnedi3_rpow2 as rpow2
import vsdehalo
core.num_threads = 8

src = core.lsmas.LWLibavSource(r"[CLIP]")

# PAL VHS: YUV420P8, Rec.601
src = core.resize.Bicubic(src, format=vs.YUV420P8,
                          matrix_in_s="170m", matrix_s="170m",
                          chromaloc=0, dither_type="error_diffusion")

# PAL VHS: TFF (original .avs uses AssumeTFF)
src = core.std.SetFieldBased(src, 2)

# Crop + AddBorders (faithful to original .avs Crop(8,10,-8,-10).AddBorders(8,10,8,10))
# Crop first: 720x576 -> 704x556, then pad back to 720x576
# Combined this is equivalent to: left+8, top+10 border, right+8, bottom+10 border
# with the interior cropped. Net effect: the frame content shifts by +8,+10 and
# the outer 8/10px border on each side is black padding.
# We do it as two explicit calls to match the .avs exactly.
src = core.std.Crop(src, left=8, top=10, right=8, bottom=10)   # 704x556
src = core.std.AddBorders(src, left=8, top=10, right=8, bottom=10)  # back to 720x576

clip = haf.QTGMC(src, Preset="Fast", TFF=True, opencl=True, device=0)

clip = core.knlm.KNLMeansCL(clip, d=1, a=2, s=4, h=1.0,
                            channels="YUV", device_type="gpu", device_id=0)

# clip = vsdehalo.fine_dehalo(clip, rx=3, ry=2, darkstr=0.5, brightstr=0.75)  # needs akarin plugin

clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="170m")
clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709")

# Single upscale: 720x576 -> 1440x1080
clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer="nnedi3cl",
                          width=1440, height=1080)

clip = core.cas.CAS(clip, sharpness=0.2)

clip.set_output()
