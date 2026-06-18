@ECHO OFF

:: GPU VARIANT of createvpy.bat — uses masterpaldvcTOP_gpu.vpy template.
:: GPU stages: KNLMeansCL denoise + nnedi3cl upscale (QTGMC stays CPU; this box
:: has no EEDI3CL). See masterpaldvcTOP_gpu.vpy header. SMOKE-TEST before batch:
::     vspipe -c y4m -e 49 "Source\<name>.vpy" NUL
:: Drag & drop video files onto this BAT; each gets a .vpy of the same name in Source\

SET TemplateName=masterpaldvcTOP_gpu.vpy
SET TemplatePath=%~dp0VapourSynth Templates\%TemplateName%
SET Outpath=%~dp0Source

echo Creating VPY scripts from GPU master template %TemplatePath%...

FOR %%A IN (%*) DO (
    echo Creating "%Outpath%\%%~nA.vpy"
    powershell -Command "(Get-Content '%TemplatePath%').replace('[CLIP]', \"%%~A\").replace('[CLIP-NO-EXTENSION]', \"%%~dpnA\") | Out-File -encoding UTF8 \"%Outpath%/%%~nA.vpy\""
)

ECHO.
ECHO GPU VPY script creation finished.
ECHO.

PAUSE
