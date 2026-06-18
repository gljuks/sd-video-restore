param($template, $outpath, $files, $fieldVal, $tffVal, $cropVal, $denoiseVal, $upscale, $upsizer, $ow, $oh)

$templateContent = (Get-Content $template -Raw)
foreach ($f in $files.Split(',')) {
    $c = $templateContent  # fresh copy each iteration
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f)
    $outFile = Join-Path $outpath "$baseName.vpy"

    if ($upscale -eq 'ai') {
        $import = 'from vsmlrt import CUGAN, Backend'
        $up = 'clip = CUGAN(clip, noise=-1, scale=2, version=2, backend=Backend.NCNN_VK(num_streams=1, fp16=True))'
    } else {
        $import = ''
        $up = "clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer=`"$upsizer`")"
    }

    $reps = @{
        '[CLIP]' = $f
        '[CLIP-NO-EXTENSION]' = [System.IO.Path]::ChangeExtension($f, $null)
        '[FIELD]' = $fieldVal
        '[TFF]' = $tffVal
        '[CROP]' = $cropVal
        '[DENOISE]' = $denoiseVal
        '[IMPORT_MLRT]' = $import
        '[UPSCALE]' = $up
        '[WIDTH]' = $ow
        '[HEIGHT]' = $oh
    }
    foreach ($k in $reps.Keys) {
        $c = $c.Replace($k, $reps[$k])
    }
    [System.IO.File]::WriteAllText($outFile, $c, [System.Text.Encoding]::UTF8)
    Write-Host "Created: Source\$baseName.vpy ($ow`x$oh)"
}
