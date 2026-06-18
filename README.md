# sd-video-restore

Restore SD interlaced video (VHS, DV, Video8, Hi8) to progressive HD.
VapourSynth pipeline with GPU acceleration. Windows native + Google Colab.

## Quickstart (Windows)

Drop `.mov` or `.avi` files on `create_dialog.bat`.

A dialog opens with sensible defaults per format. Preset sets field order and
crop; you can override everything:

- **Preset** — PAL DV, PAL VHS, or NTSC DV
- **Field** — TFF or BFF
- **Crop** — none, edges (all 4 sides), VHS (Crop + AddBorders with optional
  "add borders" checkbox), or custom expression
- **Denoise** — hqdn3d CPU denoise (on by default)
- **Upscale** — GPU (nnedi3cl) or CPU (znedi3)
- **DAR** — 4:3 → 1440x1080, 16:9 → 1920x1080

Generates per-clip scripts in `Source/`. Then run `convert.bat` (edit `ENCODER`
and `DAR` vars at top first).

For headless or scripted use: edit vars at the top of `create.bat`, then drop
files on it. VHS crop via dialog for full Crop + AddBorders; headless VHS does
Crop only.

Set `DURATION=` in `convert.bat` to blank for full render, `120` for a smoke test.

## Structure

```
VapourSynth Templates/   restore.vpy (single template with placeholders)
create_dialog.bat        drag-drop → dialog → Source scripts
create.ps1               dialog (PowerShell)
create.bat               headless (SET vars at top, drop files)
convert.bat              vspipe | ffmpeg encode (nvenc or x264)
Source/                  generated per-clip scripts (gitignored)
Target/                  rendered output (gitignored)
colab/                   Colab portable bundle + notebook
_assemble_portable.sh    build Windows portable VS bundle
```

## Colab

Prebuilt bundle at:

    https://github.com/gljuks/sd-video-restore/releases/download/v0.1/vs-portable-linux-py312.tar.zst

Upload `colab/Analog_Restore_Colab.ipynb` to Colab. `BUNDLE_URL` is pre-filled.
Drop source files in Drive at `avis/Source_in/`, run all cells.

## GPU notes (RTX 3050 Laptop, 4GB)

nnedi3cl upscale works (1.41x over CPU znedi3). KNLMeansCL is broken on this
driver. QTGMC stays opencl=False.
