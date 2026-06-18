SetMemoryMax(2000)
SetFilterMTMode("FFVideoSource", 3)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

video_org=FFMPEGSource2("[CLIP]", atrack=-1)

## Fix color space for DV
video_org = video_org.ConvertToYV12(ChromaOutPlacement="MPEG2", interlaced=true)

### Deinterlacing
deinterlaced = video_org.AssumeBFF().QTGMC()  # change to BFF if needed

### Remove halo
haloRemoved = FineDehalo(deinterlaced, rx=3.0, ry=2.0, darkstr=.5, brightstr=.75)

### change color matrix to broadcast
rec709d =haloRemoved.Colormatrix("Rec.601->Rec.709")

### upscale x2 (square pixels)
upscaled=rec709d.nnedi3_rpow2(rfactor=2, nns=4, qual=2, threads=3, cshift="Spline36Resize", fwidth=1440, fheight=1080).prefetch(7) 

return upscaled
