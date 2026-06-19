#!/usr/bin/env python3
"""Patch havsfunc.py to pass explicit nnedi3 weights path via partial,
and fix eedi3m EEDI3CL -> EEDI3 rename."""
import os

vsprefix = os.environ.get("VSPREFIX", "/opt/vs")
f = os.path.join(vsprefix, "py/lib/python3.12/site-packages/havsfunc.py")

with open(f) as fh:
    src = fh.read()

# Fix 1: znedi3 weights path
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
    znedi3_ok = True
else:
    znedi3_ok = False

# Fix 2: eedi3m renamed EEDI3CL -> EEDI3
eedi3_count = src.count("core.eedi3m.EEDI3CL")
src = src.replace("core.eedi3m.EEDI3CL", "core.eedi3m.EEDI3")

with open(f, "w") as fh:
    fh.write(src)

parts = []
if znedi3_ok:
    parts.append("znedi3 weights")
if eedi3_count:
    parts.append(f"EEDI3CL x{eedi3_count}")
if parts:
    print(f"OK: havsfunc.py patched ({', '.join(parts)})")
else:
    print("WARNING: neither patch target found in havsfunc.py")
