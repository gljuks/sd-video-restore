@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:: ==== SETTINGS (edit these, then drop files) ====
SET UPSCALE=gpu           :: gpu (nnedi3cl), cpu (znedi3), or ai (CUGAN ~3fps)
IF NOT DEFINED UPSCALE SET UPSCALE=gpu
SET FIELD=TFF             :: TFF or BFF
SET CROP=none             :: none, edges, vhs, or custom
SET CROP_CUSTOM=4, 2, -4, -2   :: used when CROP=custom
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
IF "%DAR%"=="16:9" (SET OW=1920) ELSE (SET OW=1440)
SET OH=1080

:: Upscale: set UPSIZER for gpu/cpu; AI is handled in PowerShell
IF "%UPSCALE%"=="gpu" SET UPSIZER=nnedi3cl
IF "%UPSCALE%"=="cpu" SET UPSIZER=znedi3

SET TemplatePath=%~dp0VapourSynth Templates\restore.vpy
SET Outpath=%~dp0Source

IF NOT EXIST "%TemplatePath%" (
    ECHO ERROR: template not found: %TemplatePath%
    PAUSE & EXIT /B 1
)

IF "%~1"=="" (
    ECHO === sd-video-restore ===
    ECHO Field: %FIELD%  Crop: %CROP%  Upscale: %UPSCALE%  DAR: %DAR%  Denoise: %DENOISE%
    ECHO.
    ECHO Drop .mov/.avi files on this bat to generate Source scripts.
    PAUSE & EXIT /B 0
)

echo Using restore.vpy (field=%FIELD%, crop=%CROP%, upscale=%UPSCALE%, dar=%DAR%, %OW%x%OH%)

FOR %%A IN (%*) DO (
    echo Creating "Source\%%~nA.vpy"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gen.ps1" -template "!TemplatePath!" -outpath "!Outpath!" -files "%%~A" -fieldVal "!FIELD_VAL!" -tffVal "!TFF_VAL!" -cropVal "!CROP_VAL!" -denoiseVal "!DENOISE_VAL!" -upscale "!UPSCALE!" -upsizer "!UPSIZER!" -ow "!OW!" -oh "!OH!"
)

ECHO.
ECHO Done. Now run convert.bat to encode.
PAUSE
