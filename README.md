# sd-video-restore

Restore SD interlaced video (VHS, DV, Video8, Hi8) to clean progressive HD.
VapourSynth pipeline with GPU acceleration. Windows native + Google Colab.

## Quickstart (Windows)

Drop a `.mov` or `.avi` onto `createvpy.bat` (CPU) or `createvpyGPU.bat` (GPU),
then run `convertvpy.bat` (x264) or `convertvpyNV.bat` (NVENC).

Output lands in `Target/`.

## Structure

```
VapourSynth Templates/   vpy templates (CPU + GPU, PAL/NTSC/VHS)
AviSynth Templates/      avs templates (legacy)
createvpy*.bat           drag-drop source script generators
convertvpy*.bat          vspipe | ffmpeg encode (x264 / NVENC)
Source/                  generated per-clip scripts (gitignored)
Target/                  rendered output (gitignored)
colab/                   Colab portable bundle + notebook
_assemble_portable.sh    build Windows portable VS bundle
```

## Colab

See `colab/README.md`. Requires the prebuilt `vs-portable-linux-py312.tar.zst`
tarball (build with `Dockerfile`, upload to GitHub Release).

## GPU notes (RTX 3050 Laptop, 4GB)

nnedi3cl upscale works (1.41x over CPU znedi3). KNLMeansCL is broken on this
driver — use CPU hqdn3d. QTGMC stays opencl=False (no EEDI3CL in eedi3m build).

## DAR override

Default output DAR is 4:3. For 16:9 anamorphic captures, change `-aspect 4:3`
to `-aspect 16:9` in the convert bat. The Colab notebook has a DAR dropdown.
