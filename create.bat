@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:: ==== SETTINGS (edit these, then drop files) ====
SET GPU=1                 :: 1=GPU (nnedi3cl), 0=CPU (znedi3)
SET FIELD=TFF             :: TFF or BFF
SET CROP=none             :: none, edges, vhs, or custom
SET CROP_CUSTOM=right=12, bottom=6   :: used when CROP=custom
SET DAR=4:3               :: 4:3 (1440x1080) or 16:9 (1920x1080)
SET DENOISE=1             :: 1=on, 0=off

:: Compute placeholders
IF /I "%FIELD%"=="TFF" (SET FIELD_VAL=2& SET TFF_VAL=True) ELSE (SET FIELD_VAL=1& SET TFF_VAL=False)

IF /I "%CROP%"=="none"   (SET CROP_VAL=)
IF /I "%CROP%"=="edges"  (SET CROP_VAL=clip = core.std.Crop(clip, 4, 2, -4, -2))
:: VHS crop: Crop + AddBorders (backtick-n = PowerShell newline)
IF /I "%CROP%"=="vhs"    (SET CROP_VAL=clip = core.std.Crop(clip, 8, 10, -8, -10)`nclip = core.std.AddBorders(clip, 8, 10, 8, 10))
IF /I "%CROP%"=="custom" (SET CROP_VAL=clip = core.std.Crop(clip, %CROP_CUSTOM%))

IF "%DENOISE%"=="1" (SET DENOISE_VAL=clip = core.hqdn3d.Hqdn3d(clip)) ELSE (SET DENOISE_VAL=)
IF "%GPU%"=="1" (SET UPSIZER=nnedi3cl) ELSE (SET UPSIZER=znedi3)
IF "%DAR%"=="16:9" (SET OW=1920) ELSE (SET OW=1440)
SET OH=1080

SET TemplatePath=%~dp0VapourSynth Templates\restore.vpy
SET Outpath=%~dp0Source

IF NOT EXIST "%TemplatePath%" (
    ECHO ERROR: template not found: %TemplatePath%
    PAUSE & EXIT /B 1
)

IF "%~1"=="" (
    ECHO === sd-video-restore ===
    ECHO Field: %FIELD%  Crop: %CROP%  GPU: %GPU%  DAR: %DAR%  Denoise: %DENOISE%
    ECHO.
    ECHO Drop .mov/.avi files on this bat to generate Source scripts.
    PAUSE & EXIT /B 0
)

echo Using restore.vpy (field=%FIELD%, crop=%CROP%, gpu=%GPU%, dar=%DAR%, %OW%x%OH%)

FOR %%A IN (%*) DO (
    echo Creating "Source\%%~nA.vpy"
    powershell -Command "$c=(Get-Content '%TemplatePath%' -Raw) -replace '\[CLIP\]','%%~A' -replace '\[CLIP-NO-EXTENSION\]','%%~dpnA' -replace '\[FIELD\]','%FIELD_VAL%' -replace '\[TFF\]','%TFF_VAL%' -replace '\[CROP\]','%CROP_VAL%' -replace '\[DENOISE\]','%DENOISE_VAL%' -replace '\[UPSIZER\]','%UPSIZER%' -replace '\[WIDTH\]','%OW%' -replace '\[HEIGHT\]','%OH%'; [IO.File]::WriteAllText('%Outpath%/%%~nA.vpy', $c, [Text.Encoding]::UTF8)"
)

ECHO.
ECHO Done. Now run convert.bat to encode.
PAUSE
