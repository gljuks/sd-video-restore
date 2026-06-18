@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

SET ENCODER=nvenc
SET DAR=16/9
SET DURATION=

IF /I "%ENCODER%"=="nvenc" (
    SET VCODEC=-c:v h264_nvenc -qp 18 -preset p5 -pix_fmt yuv420p
) ELSE (
    SET VCODEC=-c:v libx264 -crf 17 -preset medium -profile:v high -pix_fmt yuv420p
)
IF "%DURATION%"=="" (SET TLIMIT=) ELSE (SET TLIMIT=-t %DURATION%)

FOR %%a IN ("./Source/*.vpy") DO (
    echo Converting "%%a"
    SET "SRCFILE="
    FOR /F "usebackq delims=" %%P IN (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_vpy_getsrc.ps1" "./Source/%%a"`) DO SET "SRCFILE=%%P"

    IF DEFINED SRCFILE (
        echo   audio from: "!SRCFILE!"
        vspipe -c y4m "./Source/%%a" - | ffmpeg -y -thread_queue_size 4096 -i - -thread_queue_size 4096 -i "!SRCFILE!" -map 0:v:0 -map 1:a:0? %TLIMIT% %VCODEC% -aspect %DAR% -c:a aac -b:a 192k -async 1 "Target\%%~na.mp4"
    ) ELSE (
        echo   WARNING: no audio source found, video only
        vspipe -c y4m "./Source/%%a" - | ffmpeg -y -thread_queue_size 4096 -i - %TLIMIT% %VCODEC% -aspect %DAR% "Target\%%~na.mp4"
    )
)

ECHO Done.
PAUSE
