SetMemoryMax(2000)
SetFilterMTMode("FFVideoSource", 3)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

video_org=FFMPEGSource2("[CLIP]", atrack=-1)


## SD interlaced captures -> planar YV12
video_org = video_org.ConvertToYV12(ChromaOutPlacement="MPEG2", interlaced=true)

### Deinterlacing -- feed the FULL 720x576 frame.
### Interlaced YV12 SeparateFields needs height MOD 4 (each field is a legal 4:2:0 frame of half height).
### 576 is mod4 so QTGMC is happy. Do NOT crop the bottom before this or it errors.
deinterlaced = video_org.AssumeTFF().QTGMC()  # analog captures are usually BFF -> AssumeBFF if motion judders

### Drop the black edges AFTER deint. Now progressive -> YV12 only needs MOD 2, so 6 is legal (5 is not). No AddBorders.
deinterlaced = deinterlaced.Crop(0, 0, -12, -6)   # 708x570, both borders gone, no padding

### Remove halo
haloRemoved = FineDehalo(deinterlaced, rx=3.0, ry=2.0, darkstr=.5, brightstr=.75)

### change color matrix to broadcast
rec709d =haloRemoved.Colormatrix("Rec.601->Rec.709")

### upscale x2 (square pixels)
upscaled=rec709d.nnedi3_rpow2(rfactor=2, nns=4, qual=2, threads=3, cshift="Spline36Resize", fwidth=1280, fheight=960)
upscaled=upscaled.Sharpen(0.3)

### upscale x2 (square pixels)
upscaled2=upscaled.nnedi3_rpow2(rfactor=2, nns=4, qual=2, threads=3, cshift="Spline36Resize", fwidth=1440, fheight=1080).prefetch(7) 
upscaled2=upscaled2.Sharpen(0.3)


return upscaled2
