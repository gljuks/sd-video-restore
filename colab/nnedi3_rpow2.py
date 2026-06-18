"""
nnedi3_rpow2 — VapourSynth helper for power-of-2 upscaling via nnedi3.

Ported for VapourSynth R76 (API R4). Supports both CPU (znedi3) and
OpenCL (nnedi3cl) upsizers.

Usage:
    import nnedi3_rpow2 as rpow2
    upscaled = rpow2.nnedi3_rpow2(clip, rfactor=2, width=1440, height=1080,
                                   upsizer="nnedi3cl", nns=4, qual=2)
"""
import vapoursynth as vs

core = vs.core


def _nnedi3(clip, field, dh, nsize, nns, qual, etype, pscrn, device=None, opencl=False):
    if opencl:
        return core.nnedi3cl.NNEDI3CL(clip, field=field, dh=dh,
                                       nsize=nsize, nns=nns, qual=qual,
                                       device=device or 0)
    else:
        # znedi3 needs explicit weights path — env var NNEDI3CL is not
        # reliably picked up inside embedded/bundled Python.
        import os
        wpath = os.path.join(os.environ.get("VSPREFIX", "/opt/vs"),
                             "share", "NNEDI3CL", "nnedi3_weights.bin")
        if not os.path.exists(wpath):
            wpath = "/opt/vs/share/NNEDI3CL/nnedi3_weights.bin"
        return core.znedi3.nnedi3(clip, field=field, dh=dh,
                                   nsize=nsize, nns=nns, qual=qual,
                                   x_nnedi3_weights_bin=wpath.encode())


def nnedi3_rpow2(clip, rfactor=2, width=None, height=None, correct_shift=True,
                 kernel="spline36", nsize=0, nns=3, qual=None, etype=None,
                 pscrn=None, device=-1, upsizer=None):
    if rfactor < 2 or rfactor > 1024:
        raise ValueError("nnedi3_rpow2: rfactor must be between 2 and 1024")

    tmp = 1
    times = 0
    while tmp < rfactor:
        tmp *= 2
        times += 1
    if tmp != rfactor:
        raise ValueError("nnedi3_rpow2: rfactor must be a power of 2")

    if width is None:
        width = clip.width * rfactor
    if height is None:
        height = clip.height * rfactor

    if upsizer is None:
        try:
            core.nnedi3cl.NNEDI3CL
            upsizer = "nnedi3cl"
        except AttributeError:
            upsizer = "znedi3"

    use_opencl = (upsizer == "nnedi3cl")

    hshift = 0.0
    vshift = -0.5

    pkdnnedi = dict(dh=True, nsize=nsize, nns=nns, qual=qual,
                    etype=etype, pscrn=pscrn)
    if use_opencl:
        pkdnnedi["device"] = device

    # For YUV/RGB: process luma with nnedi3, chroma with fmtconv or Bicubic
    if clip.format.color_family == vs.GRAY:
        c = clip
        for _ in range(times):
            c = _nnedi3(c, field=0, opencl=use_opencl, **pkdnnedi)
            c = core.std.Transpose(c)
            c = _nnedi3(c, field=0, opencl=use_opencl, **pkdnnedi)
            c = core.std.Transpose(c)
        if correct_shift:
            c = core.resize.Bicubic(c, width, height,
                                     filter_param_a=hshift, filter_param_b=0.25)
        else:
            c = core.resize.Bicubic(c, width, height)
        return c

    # Extract planes using std.ShufflePlanes (VS4 API)
    # Plane 0 = Y/R, Plane 1 = U/G, Plane 2 = V/B
    plane0 = core.std.ShufflePlanes(clip, planes=0, colorfamily=vs.GRAY)
    plane1 = core.std.ShufflePlanes(clip, planes=1, colorfamily=vs.GRAY)
    plane2 = core.std.ShufflePlanes(clip, planes=2, colorfamily=vs.GRAY)

    # Upscale luma (plane 0) with nnedi3
    y = plane0
    for _ in range(times):
        y = _nnedi3(y, field=0, opencl=use_opencl, **pkdnnedi)
        y = core.std.Transpose(y)
        y = _nnedi3(y, field=0, opencl=use_opencl, **pkdnnedi)
        y = core.std.Transpose(y)

    if correct_shift:
        y = core.resize.Bicubic(y, width, height,
                                 filter_param_a=hshift, filter_param_b=0.25)
    else:
        y = core.resize.Bicubic(y, width, height)

    # Upscale chroma — try fmtconv first, fall back to Bicubic
    try:
        u = core.fmtconv.resample(plane1, width, height,
                                   kernel=kernel, sy=-0.5, planes=[2, 3, 3])
        v = core.fmtconv.resample(plane2, width, height,
                                   kernel=kernel, sy=-0.5, planes=[2, 3, 3])
    except AttributeError:
        u = core.resize.Bicubic(plane1, width, height)
        v = core.resize.Bicubic(plane2, width, height)

    # Recombine planes
    return core.std.ShufflePlanes([y, u, v], planes=[0, 0, 0],
                                   colorfamily=clip.format.color_family)
