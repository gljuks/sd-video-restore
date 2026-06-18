@ECHO OFF

:: SET DURATION to limit conversion to first N seconds (e.g. 120 for 2 minutes)
:: Leave empty to convert the full video
SET DURATION=

IF DEFINED DURATION (
    echo Trimming to first %DURATION% seconds
    for %%a in ("./Source/*.avs") do ( ffmpeg -i "./Source/%%a" -t %DURATION% -n -c:a aac -async 1 -c:v libx264 -aspect 4:3 -profile:v high -pix_fmt yuv420p -crf 17 "Target\%%~na.mp4")
) ELSE (
    for %%a in ("./Source/*.avs") do ( ffmpeg -i "./Source/%%a" -n -c:a aac -async 1 -c:v libx264 -aspect 4:3 -profile:v high -pix_fmt yuv420p -crf 17 "Target\%%~na.mp4")
)
pause
