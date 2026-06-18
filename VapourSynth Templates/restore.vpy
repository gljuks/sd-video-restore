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

# eedi3m shim -- save original BEFORE overwriting
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

# Field order: _FieldBased 1=BFF, 2=TFF. DV is BFF, VHS is TFF.
# If motion judders, flip this and TFF together.
src = core.std.SetFieldBased(src, [FIELD])

clip = haf.QTGMC(src, Preset="Fast", TFF=[TFF], opencl=False)

# Crop black edges after deinterlace (progressive = mod2 legal)
[CROP]

# Spatial denoise (CPU -- KNLMeansCL is broken on 581.57)
[DENOISE]

# clip = vsdehalo.fine_dehalo(clip, rx=2, ry=2, darkstr=0.5, brightstr=0.75)

clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="170m")
clip = core.resize.Bicubic(clip, format=vs.YUV420P8, matrix_s="709")

clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2,
                          upsizer="[UPSIZER]",  # nnedi3cl=GPU, znedi3=CPU
                          width=[WIDTH], height=[HEIGHT])

clip = core.cas.CAS(clip, sharpness=0.4)

clip.set_output()
