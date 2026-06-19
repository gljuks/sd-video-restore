# Analog Video Restoration on Google Colab — VapourSynth R76

Colab port of the Windows VapourSynth pipeline. Handles VHS, DV, Video8, Hi8.

## Files

- `Dockerfile` — build oven for the portable VS bundle
- `build_plugins.sh` — compiles all plugin .so files + downloads vs-mlrt AI upscale
- `export_bundle.sh` — patchelf + tar the bundle into `out/vs-portable-linux-py312.tar.zst`
- `build_notebook.py` — generates `Analog_Restore_Colab.ipynb`
- `Analog_Restore_Colab.ipynb` — upload to Colab
- `patch_havsfunc.py` — EEDI3CL compatibility fix for havsfunc
- `out/` — tarball output (gitignored)

## Notebook cells

1. GPU probe: nvidia-smi + clinfo, sets `VS_GPU_MODE=opencl`, `cuda`, or `ai`
2. Bundle: download + unpack prebuilt tarball (~20s)
3. Fail-fast: verify all required plugins load, abort if missing
4. Drive: mount, list source files in `Source_in/`
5. VPY: write GPU-mode-aware `master.vpy` (GPU/CPU/AI upscale paths)
6. Encode: `vspipe | ffmpeg` with audio mux, DAR and DURATION params
7. Verify: ffprobe check on output

## GPU Modes

| Mode | Upscale | Denoise | Notes |
|------|---------|---------|-------|
| `opencl` | nnedi3cl 2x | KNLMeansCL | Full GPU pipeline |
| `cuda` | znedi3 2x | hqdn3d | CPU fallback |
| `ai` | RealCUGAN-pro 2x | hqdn3d | NCNN/Vulkan, ~4x slower, highest quality |

AI upscale uses [vs-mlrt](https://github.com/AmusementClub/vs-mlrt) with the
RealCUGAN-pro model (`pro-no-denoise3x-up2x.onnx`, noise=-1, scale=2, version=2).

## Bundle

Release tarball at:

    https://github.com/gljuks/sd-video-restore/releases/download/v0.1-ai/vs-portable-linux-py312.tar.zst

(or a specific version tag). Cell 2 is pre-filled with this URL.
Rebuild only when plugins change:

    docker build -t vs-oven:r76 .
    docker run --rm -v "${PWD}/out:/out" vs-oven:r76

## Why the 2021 notebook failed

The 2021 notebook used `apt install vapoursynth`, which pulls a `vspipe` linked against `libpython3.6m`. Colab bumped Python -> vspipe broke. The symlink hack produced `undefined symbol: getVSScriptAPI`. On failure it silently fell back to `ffmpeg yadif+hqdn3d` — wrong pipeline.

The 2026 fix: VS R76 ships an **abi3** wheel (stable ABI across CPython >= 3.12). We bundle our own Python 3.12 in the tarball so Colab's interpreter doesn't matter. Cell 3 fails fast if plugins are missing — no silent fallback.

## Drive layout

```
/content/drive/MyDrive/avis/
  Source_in/      <-- drop source files here (.avi, .mov)
  Target_out/     <-- restored .mp4 output
```

## Known risks

- OpenCL on Colab: not guaranteed. Falls back to CPU znedi3 + hqdn3d if `clinfo` finds no NVIDIA device.
- AI upscale: requires Vulkan (NCNN_VK backend). Works on Colab T4/V100/A100 GPUs.
- Bundle relocatability: patchelf'd to `$ORIGIN/../lib`, extract to `/opt/vs` on Colab.
- Drive throughput: huffyuv sources stream fine over Drive. Long renders benefit from paid GPU runtime.
