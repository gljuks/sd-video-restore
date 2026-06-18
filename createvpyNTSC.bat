@ECHO OFF

:: NTSC DV VapourSynth create harness
:: Drag video files onto this .bat -> fills [CLIP] in "NTSC DV VapourSynth template -> writes Source\name.vpy

SET TemplateName=masterntscdv.vpy
SET TemplatePath=%~dp0VapourSynth Templates\%TemplateName%
SET Outpath=%~dp0Source

echo Creating VPY scripts from master template %TemplatePath%...

FOR %%A IN (%*) DO (
    echo Creating "%Outpath%\%%~nA.vpy"
    powershell -Command "(Get-Content '%TemplatePath%').replace('[CLIP]', "%%~A").replace('[CLIP-NO-EXTENSION]', "%%~dpnA") | Out-File -encoding UTF8 "%Outpath%/%%~nA.vpy"
)

ECHO.
echo VPY script creation finished.
ECHO.

PAUSE
