@ECHO OFF

:: PAL VHS VapourSynth create harness

SET TemplateName=masterpalvhs.vpy
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
