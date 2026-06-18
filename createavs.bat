@ECHO OFF

:: INSTRUCTIONS:
:: 1. Create an AviSynth script 
:: 2. Use [CLIP] and/or [CLIP-NO-EXTENSION] as placeholders in the script. 
::    [CLIP-NO-EXTENSION] will exclude the file-extension in case you want to use it for including subtitles or other files that use the same base name.
::    e.g. AviSource("[CLIP]")
:: 3. Place the master .avs script in a folder called "AviSynth Templates", immediately beneath the folder containing this .BAT
:: 4. Drag and drop video files onto this BAT and each will be given an AVS file with the same name (video1.avi.avs will be created for video1.avi)
::    The placeholders will be filled in with the full absolute path of the dropped files.

SET TemplateName=masterpaldvcTOP.avs
SET TemplatePath=%~dp0AviSynth Templates\%TemplateName%
SET Outpath=%~dp0Source

echo Creating AVS scripts from master template %TemplatePath%...

:: Loop through every file dropped onto the .BAT
FOR %%A IN (%*) DO (

    REM :: Here we create a .AVS file for each video dropped onto the bat
    REM :: We read in the master script, replace the placeholders and then write the output to a text file using the video's filename and .avs extension
    REM ::
    REM ::    %%A - this contains the full path to the video file, including surrounding double-quotes
    REM ::    %%~A - this contains the full path to the video file, without surrounding double-quotes
    REM ::    %%~dpnA - this contains the full path to the video file, with drive, path and name (dpn) but no file extension (without quotes)
    echo Creating "%%~A.avs"
    powershell -Command "(Get-Content '%TemplatePath%').replace('[CLIP]', \"%%~A\").replace('[CLIP-NO-EXTENSION]', \"%%~dpnA\") | Out-File -encoding ASCII \"%Outpath%/%%~nA.avs\""

    REM :: If you want to then run ffmpeg to render and transcode the AVS file you could run it here
    REM :: e.g. ffmpeg -i "%%~A.avs" "%%~dpnA.h264.mp4"

)

ECHO.
ECHO Script creation finished.
ECHO.

PAUSE