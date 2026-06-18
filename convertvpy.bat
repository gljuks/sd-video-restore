@ECHO OFF

SETLOCAL ENABLEDELAYEDEXPANSION



:: VapourSynth version of convert.bat (CPU x264) -- WITH AUDIO.

:: vspipe -c y4m streams VIDEO ONLY (y4m carries no audio), so we hand ffmpeg a

:: SECOND input -- the original media file -- and map its audio track.

:: The original path is baked into each .vpy's Source(...) line; helper

:: _vpy_getsrc.ps1 extracts it. Audio is encoded to AAC like the old .avs pipeline.

::

:: -thread_queue_size 4096 on BOTH inputs: the video pipe (vspipe) is SLOW (GPU

:: filtering), the audio file is FAST off disk, so the audio reader thread fills its

:: input queue waiting for video. Default queue is 8 -> "Thread message queue

:: blocking" warning. 4096 gives plenty of headroom and silences it.



:: SET DURATION to limit conversion to first N seconds (e.g. 120 for 2 minutes)

:: Leave empty to convert the full video.

SET DURATION=



FOR %%a IN ("./Source/*.vpy") DO (

    echo Converting "%%a"

    SET "SRCFILE="

    FOR /F "usebackq delims=" %%P IN (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_vpy_getsrc.ps1" "./Source/%%a"`) DO SET "SRCFILE=%%P"



    IF DEFINED SRCFILE (

        echo   audio from: "!SRCFILE!"

        IF DEFINED DURATION (

            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -thread_queue_size 4096 -i "!SRCFILE!" -map 0:v:0 -map 1:a:0? -t %DURATION% -n -c:v libx264 -aspect 4:3 -profile:v high -pix_fmt yuv420p -crf 17 -c:a aac -b:a 192k -async 1 "Target\%%~na.mp4"

        ) ELSE (

            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -thread_queue_size 4096 -i "!SRCFILE!" -map 0:v:0 -map 1:a:0? -n -c:v libx264 -aspect 4:3 -profile:v high -pix_fmt yuv420p -crf 17 -c:a aac -b:a 192k -async 1 "Target\%%~na.mp4"

        )

    ) ELSE (

        echo   WARNING: no source media found in .vpy -- encoding VIDEO ONLY

        IF DEFINED DURATION (

            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -t %DURATION% -n -c:v libx264 -aspect 4:3 -profile:v high -pix_fmt yuv420p -crf 17 "Target\%%~na.mp4"

        ) ELSE (

            vspipe -c y4m "./Source/%%a" - | ffmpeg -thread_queue_size 4096 -i - -n -c:v libx264 -aspect 4:3 -profile:v high -pix_fmt yuv420p -crf 17 "Target\%%~na.mp4"

        )

    )

)

pause

