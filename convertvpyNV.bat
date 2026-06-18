@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

:: VapourSynth NVENC version -- WITH AUDIO.
:: vspipe -c y4m streams VIDEO ONLY (y4m carries no audio), so we hand ffmpeg a
:: SECOND input -- the original media file -- and map its audio track.
:: The original path is baked into each .vpy's Source(...) line; helper
:: _vpy_getsrc.ps1 extracts it. Audio is encoded to AAC.
::
:: -thread_queue_size 4096 on BOTH inputs: the video pipe (vspipe) is SLOW (GPU
:: filtering), the audio file is FAST off disk. Default queue is 8 -> "Thread
:: message queue blocking" warning. 4096 gives plenty of headroom.
::
:: NOTE: Do NOT use -hwaccel cuda on the vspipe input -- frames arrive already
:: decoded over stdin. Only the NVENC ENCODER runs on GPU.

:: SET DURATION to limit conversion to first N seconds (e.g. 120 for 2 minutes)
:: Leave empty to convert the full video.
SET DURATION=120

FOR %%a IN ("./Source/*.vpy") DO (
    echo Converting "%%a"
    SET "SRCFILE="
    FOR /F "usebackq delims=" %%P IN (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_vpy_getsrc.ps1" "./Source/%%a"`) DO SET "SRCFILE=%%P"

    IF DEFINED SRCFILE (
        echo   audio from: "!SRCFILE!"
        IF DEFINED DURATION (
            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -thread_queue_size 4096 -i "!SRCFILE!" -map 0:v:0 -map 1:a:0? -t %DURATION% -n -c:v h264_nvenc -qp 18 -preset p5 -pix_fmt yuv420p -aspect 4:3 -c:a aac -b:a 192k -async 1 "Target\%%~na.mp4"
        ) ELSE (
            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -thread_queue_size 4096 -i "!SRCFILE!" -map 0:v:0 -map 1:a:0? -n -c:v h264_nvenc -qp 18 -preset p5 -pix_fmt yuv420p -aspect 4:3 -c:a aac -b:a 192k -async 1 "Target\%%~na.mp4"
        )
    ) ELSE (
        echo   WARNING: no source media found in .vpy -- encoding VIDEO ONLY
        IF DEFINED DURATION (
            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -t %DURATION% -n -c:v h264_nvenc -qp 18 -preset p5 -pix_fmt yuv420p -aspect 4:3 "Target\%%~na.mp4"
        ) ELSE (
            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -n -c:v h264_nvenc -qp 18 -preset p5 -pix_fmt yuv420p -aspect 4:3 "Target\%%~na.mp4"
        )
    )
)
pause
