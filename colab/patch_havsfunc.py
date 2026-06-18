#!/usr/bin/env python3
"""Patch havsfunc.py to pass explicit nnedi3 weights path via partial."""
import os

vsprefix = os.environ.get("VSPREFIX", "/opt/vs")
f = os.path.join(vsprefix, "py/lib/python3.12/site-packages/havsfunc.py")

with open(f) as fh:
    src = fh.read()

# The partial creation line that wraps core.znedi3.nnedi3
old = "        nnedi3 = partial(core.znedi3.nnedi3, field=field, **nnedi3_args)"

new_lines = [
    "        import os as _hnos",
    "        _hnw = _hnos.path.join(_hnos.environ.get('VSPREFIX','/opt/vs'),'share','NNEDI3CL','nnedi3_weights.bin')",
    "        if not _hnos.path.exists(_hnw): _hnw = '/opt/vs/share/NNEDI3CL/nnedi3_weights.bin'",
    "        nnedi3 = partial(core.znedi3.nnedi3, field=field, x_nnedi3_weights_bin=_hnw.encode(), **nnedi3_args)",
]
new = "\n".join(new_lines)

if old in src:
    src = src.replace(old, new)
    with open(f, "w") as fh:
        fh.write(src)
    print("OK: havsfunc.py patched at partial creation")
else:
    print("ERROR: target not found")
    idx = src.find("nnedi3 = partial")
    if idx >= 0:
        print(repr(src[idx:idx+200]))
    else:
        print("partial not found at all")
