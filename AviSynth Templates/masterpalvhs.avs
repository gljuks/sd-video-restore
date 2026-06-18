SetMemoryMax(3000)
SetFilterMTMode("FFVideoSource", 3)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

video_org=FFMS2("[CLIP]",atrack=-1)

## Fix color space for DV
video_org = video_org.ConvertToYV12(interlaced=true)
video_org = video_org.Crop(8, 10 ,-8,-10).AddBorders(8, 10, 8, 10)
### Deinterlacing
deinterlaced = video_org.AssumeTFF().QTGMC()  # change to BFF if needed

### Remove halo
haloRemoved = FineDehalo(deinterlaced, rx=3.0, ry=2.0, darkstr=.5, brightstr=.75)

### change color matrix to broadcast
rec709d =haloRemoved.Colormatrix("Rec.601->Rec.709")

### upscale x2 (square pixels)
upscaled=rec709d.nnedi3_rpow2(rfactor=2, nns=4, qual=2, threads=3, cshift="Spline36Resize", fwidth=1440, fheight=1080)
upscaled=upscaled.Sharpen(0.2)

### upscale x2 (square pixels)
#upscaled2=upscaled.nnedi3_rpow2(rfactor=2, nns=4, qual=2, threads=3, cshift="Spline36Resize", fwidth=1440, fheight=1080).prefetch(7) 
#upscaled2=upscaled2.Sharpen(0.2)

return upscaled

