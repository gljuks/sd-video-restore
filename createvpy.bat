@ECHO OFF

:: INSTRUCTIONS (VapourSynth version of createavs.bat):
:: 1. Create a VapourSynth script (.vpy)
:: 2. Use [CLIP] and/or [CLIP-NO-EXTENSION] as placeholders in the script.
::    [CLIP] is inserted into the source line, e.g.  core.lsmas.LWLibavSource(r"[CLIP]")
::    [CLIP-NO-EXTENSION] excludes the extension (handy for matching subtitle/sidecar files).
:: 3. Place the master .vpy in a folder called "VapourSynth Templates", beneath the folder containing this .BAT
:: 4. Drag and drop video files onto this BAT; each gets a .vpy with the same name in Source\
::    The placeholders are filled with the full absolute path of the dropped file.
:: NOTE: paths land inside r"..." raw strings in the .vpy, so Windows backslashes are fine.

SET TemplateName=masterpaldvcTOP.vpy
SET TemplatePath=%~dp0VapourSynth Templates\%TemplateName%
SET Outpath=%~dp0Source

echo Creating VPY scripts from master template %TemplatePath%...

:: Loop through every file dropped onto the .BAT
FOR %%A IN (%*) DO (

    REM ::    %%~A     - full path to the dropped video, no surrounding quotes
    REM ::    %%~dpnA  - full path with drive+path+name but NO extension (no quotes)
    REM ::    %%~nA    - just the base name, used for the output .vpy filename
    echo Creating "%Outpath%\%%~nA.vpy"
    powershell -Command "(Get-Content '%TemplatePath%').replace('[CLIP]', \"%%~A\").replace('[CLIP-NO-EXTENSION]', \"%%~dpnA\") | Out-File -encoding UTF8 \"%Outpath%/%%~nA.vpy\""

)

ECHO.
ECHO VPY script creation finished.
ECHO.

PAUSE
