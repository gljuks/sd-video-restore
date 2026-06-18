# Analog Video Restoration on Google Colab — VapourSynth R76

Colab port of the Windows VapourSynth pipeline. Handles VHS, DV, Video8, Hi8.

## Files

- `Dockerfile` — build oven for the portable VS bundle
- `build_plugins.sh` — compiles all plugin .so files
- `export_bundle.sh` — patchelf + tar the bundle into `out/vs-portable-linux-py312.tar.zst`
- `build_notebook.py` — generates `Analog_Restore_Colab.ipynb`
- `Analog_Restore_Colab.ipynb` — upload to Colab
- `out/` — tarball output (gitignored)

## Notebook cells

1. GPU probe: nvidia-smi + clinfo, sets `VS_GPU_MODE=opencl` or `cuda`
2. Bundle: fetch prebuilt tarball (~20s) or build in-session (~10-20 min)
3. Fail-fast: verify all required plugins load, abort if missing
4. Drive: mount, list source files in `Source_in/`
5. VPY: write GPU-mode-aware `master.vpy`
6. Encode: `vspipe | ffmpeg` with audio mux, DAR and DURATION params
7. Verify: ffprobe check on output

## Two-path bundle strategy

**Path A (fast):** build tarball once, upload to GitHub Release, set `BUNDLE_URL` in Cell 2. ~20s per session.

```
docker build -t vs-oven:r76 .
docker run --rm -v "${PWD}\out:/out" vs-oven:r76
```

**Path B (slow):** leave `BUNDLE_URL` empty. Rebuilds everything inside Colab. ~10-20 min, fully self-contained.

## Why the 2021 notebook failed

The 2021 notebook used `apt install vapoursynth`, which pulls a `vspipe` linked against `libpython3.6m`. Colab bumped Python → vspipe broke. The symlink hack produced `undefined symbol: getVSScriptAPI`. On failure it silently fell back to `ffmpeg yadif+hqdn3d` — wrong pipeline.

The 2026 fix: VS R76 ships an **abi3** wheel (stable ABI across CPython >= 3.12). We bundle our own Python 3.12 in the tarball so Colab's interpreter doesn't matter. Cell 3 fails fast if plugins are missing — no silent fallback.

## Drive layout

```
/content/drive/MyDrive/avis/
  Source_in/      <-- drop source files here (.avi, .mov)
  Target_out/     <-- restored .mp4 output
```

## Regenerating the notebook

```
cd colab
python3 build_notebook.py
```

## Pinned versions

Ubuntu 22.04, Python 3.12, VapourSynth R76 (abi3), FFmpeg static 7.x (libx264), plugin revisions in `build_plugins.sh`.

## Known risks

- OpenCL on Colab: not guaranteed. Falls back to CPU znedi3 + hqdn3d if `clinfo` finds no NVIDIA device.
- Bundle relocatability: patchelf'd to `$ORIGIN/../lib`, extract to `/opt/vs` on Colab.
- Drive throughput: huffyuv sources stream fine over Drive. Long renders benefit from paid GPU runtime.
