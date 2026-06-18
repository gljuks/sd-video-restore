# Drop video files on create_dialog.bat. A dialog lets you pick settings.
param([Parameter(ValueFromRemainingArguments=$true)]$files)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "sd-video-restore"
$form.Size = New-Object System.Drawing.Size(380, 330)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false; $form.MinimizeBox = $false

$y = 12
function Label($text, $x, $w=80) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $script:y)
    $l.Size = New-Object System.Drawing.Size($w, 20)
    $script:form.Controls.Add($l)
}

# Format preset
Label "Preset:" 15
$fmt = New-Object System.Windows.Forms.ComboBox
$fmt.Location = New-Object System.Drawing.Point(100, $y)
$fmt.Size = New-Object System.Drawing.Point(250, 20)
$fmt.DropDownStyle = "DropDownList"
$fmt.Items.AddRange(@(
    "PAL DV / Video8 / Hi8",
    "PAL VHS",
    "NTSC DV"
))
$fmt.SelectedIndex = 0
$form.Controls.Add($fmt)
$y += 28

# Field order
Label "Field:" 15
$field = New-Object System.Windows.Forms.ComboBox
$field.Location = New-Object System.Drawing.Point(100, $y)
$field.Size = New-Object System.Drawing.Point(80, 20)
$field.DropDownStyle = "DropDownList"
$field.Items.AddRange(@("TFF", "BFF"))
$form.Controls.Add($field)
$y += 28

# Crop mode
Label "Crop:" 15
$crop = New-Object System.Windows.Forms.ComboBox
$crop.Location = New-Object System.Drawing.Point(100, $y)
$crop.Size = New-Object System.Drawing.Point(80, 20)
$crop.DropDownStyle = "DropDownList"
$crop.Items.AddRange(@("none", "edges", "VHS", "custom"))
$form.Controls.Add($crop)

# Add borders (optional, shown when crop is active)
$addBorders = New-Object System.Windows.Forms.CheckBox
$addBorders.Text = "add borders"
$addBorders.Location = New-Object System.Drawing.Point(185, $y)
$addBorders.Size = New-Object System.Drawing.Point(100, 20)
$addBorders.Checked = $true
$addBorders.Visible = $true
$form.Controls.Add($addBorders)

# Custom crop text
$cropCustom = New-Object System.Windows.Forms.TextBox
$cropCustom.Location = New-Object System.Drawing.Point(185, $y)
$cropCustom.Size = New-Object System.Drawing.Point(170, 20)
$cropCustom.Text = "4, 2, -4, -2"
$cropCustom.Visible = $false
$form.Controls.Add($cropCustom)
$y += 28

$crop.Add_SelectedIndexChanged({
    $cropCustom.Visible = ($crop.SelectedIndex -eq 3)
    $addBorders.Visible = ($crop.SelectedIndex -eq 1 -or $crop.SelectedIndex -eq 2)
})

# Denoise
$denoise = New-Object System.Windows.Forms.CheckBox
$denoise.Text = "hqdn3d denoise"
$denoise.Location = New-Object System.Drawing.Point(100, $y)
$denoise.Size = New-Object System.Drawing.Point(130, 20)
$denoise.Checked = $true
$form.Controls.Add($denoise)

$y += 28

# Upscale (GPU/CPU/AI)
Label "Upscale:" 15
$gpu = New-Object System.Windows.Forms.RadioButton
$gpu.Text = "GPU"; $gpu.Location = New-Object System.Drawing.Point(100, $y)
$gpu.Size = New-Object System.Drawing.Point(55, 20); $envUpscale = $env:UPSCALE
if ($envUpscale -eq 'ai') { $ai.Checked = $true }
elseif ($envUpscale -eq 'cpu') { $cpu.Checked = $true }
else { $gpu.Checked = $true }
$cpu = New-Object System.Windows.Forms.RadioButton
$cpu.Text = "CPU"; $cpu.Location = New-Object System.Drawing.Point(160, $y)
$cpu.Size = New-Object System.Drawing.Point(55, 20)
$ai = New-Object System.Windows.Forms.RadioButton
$ai.Text = "AI (CUGAN, ~3fps)"; $ai.Location = New-Object System.Drawing.Point(220, $y)
$ai.Size = New-Object System.Drawing.Point(140, 20)
$form.Controls.Add($gpu); $form.Controls.Add($cpu); $form.Controls.Add($ai)
$y += 28

# DAR
Label "DAR:" 15
$dar = New-Object System.Windows.Forms.ComboBox
$dar.Location = New-Object System.Drawing.Point(100, $y)
$dar.Size = New-Object System.Drawing.Point(80, 20)
$dar.DropDownStyle = "DropDownList"
$dar.Items.AddRange(@("4:3", "16:9"))
$dar.SelectedIndex = 0
$form.Controls.Add($dar)
$y += 32

# Buttons
$ok = New-Object System.Windows.Forms.Button
$ok.Text = "Generate"; $ok.Location = New-Object System.Drawing.Point(75, $y)
$ok.Size = New-Object System.Drawing.Point(75, 28); $ok.DialogResult = "OK"
$form.AcceptButton = $ok; $form.Controls.Add($ok)

$genConv = New-Object System.Windows.Forms.Button
$genConv.Text = "Gen + Convert"; $genConv.Location = New-Object System.Drawing.Point(155, $y)
$genConv.Size = New-Object System.Drawing.Point(100, 28)
$genConv.Add_Click({ $script:doConvert = $true; $form.DialogResult = "OK"; $form.Close() })
$form.Controls.Add($genConv)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = "Cancel"; $cancel.Location = New-Object System.Drawing.Point(260, $y)
$cancel.Size = New-Object System.Drawing.Point(100, 28); $cancel.DialogResult = "Cancel"
$form.Controls.Add($cancel)

# Preset defaults — applied on first load and on change
function Set-PresetDefaults {
    switch ($fmt.SelectedIndex) {
        0 { $field.SelectedIndex = 0; $crop.SelectedIndex = 0 }  # PAL DV: TFF, no crop
        1 { $field.SelectedIndex = 0; $crop.SelectedIndex = 2 }  # VHS: TFF, VHS crop
        2 { $field.SelectedIndex = 1; $crop.SelectedIndex = 0 }  # NTSC: BFF, no crop
    }
}
$fmt.Add_SelectedIndexChanged({ Set-PresetDefaults })
Set-PresetDefaults

# Show dialog
if (-not $files -or $files.Count -eq 0) {
    $result = $form.ShowDialog()
    if ($result -ne "OK") { exit }
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "Video files (*.mov;*.avi;*.mp4;*.mkv)|*.mov;*.avi;*.mp4;*.mkv"
    $fd.Multiselect = $true
    if ($fd.ShowDialog() -ne "OK") { exit }
    $files = $fd.FileNames
} else {
    $result = $form.ShowDialog()
    if ($result -ne "OK") { exit }
}

# Compute placeholders
$fieldVal = if ($field.SelectedIndex -eq 0) { 2 } else { 1 }
$tffVal = if ($field.SelectedIndex -eq 0) { "True" } else { "False" }

switch ($crop.SelectedIndex) {
    0 { $cropVal = '' }
    1 { $cropVal = 'clip = core.std.Crop(clip, 4, 2, -4, -2)' }
    2 { $cropVal = 'clip = core.std.Crop(clip, 8, 10, -8, -10)' }
    3 { $cropVal = "clip = core.std.Crop(clip, $($cropCustom.Text))" }
}
if ($addBorders.Checked -and $cropVal) {
    # Extract crop params and mirror them for AddBorders
    $cropVal += "`nclip = core.std.AddBorders(clip, " + $cropVal -replace '.*Crop\(clip,\s*', '' -replace '\)', '' + ")"
}

$denoiseVal = if ($denoise.Checked) { 'clip = core.hqdn3d.Hqdn3d(clip)' } else { '' }

# Upscale: AI uses CUGAN at fixed 2x, then resize handles the final width.
# nnedi3cl/znedi3 do everything in one nnedi3_rpow2 call.
if ($ai.Checked) {
    $importMlrt = 'from vsmlrt import CUGAN, Backend'
    $upscaleVal = 'clip = CUGAN(clip, noise=-1, scale=2, version=2, backend=Backend.NCNN_VK(num_streams=1, fp16=True))'
} else {
    $importMlrt = ''
    $upsizer = if ($gpu.Checked) { "nnedi3cl" } else { "znedi3" }
    $upscaleVal = "clip = rpow2.nnedi3_rpow2(clip, rfactor=2, nns=4, qual=2, upsizer=`"$upsizer`")"
}
$darVal = $dar.SelectedItem.ToString()
if ($darVal -eq "16:9") { $w = 1920; $h = 1080 } else { $w = 1440; $h = 1080 }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $scriptDir "Source"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$upsizer = if ($gpu.Checked) { "nnedi3cl" } elseif ($cpu.Checked) { "znedi3" } else { "" }
$upscaleMode = if ($ai.Checked) { "ai" } elseif ($gpu.Checked) { "gpu" } else { "cpu" }

foreach ($f in $files) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f)
    & "$scriptDir\gen.ps1" -template "$scriptDir\VapourSynth Templates
estore.vpy" `
        -outpath $outDir -files $f `
        -fieldVal $fieldVal -tffVal $tffVal -cropVal $cropVal `
        -denoiseVal $denoiseVal -upscale $upscaleMode `
        -upsizer $upsizer -ow $w -oh $h
}

Write-Host "Done. Run convert.bat to encode."
if ($script:doConvert) {
    $convertBat = Join-Path $scriptDir "convert.bat"
    $darArg = $darVal -replace ':', '/'
    Write-Host "Running convert.bat with DAR=$darArg..."
    $env:TEMP_DAR = $darArg
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "cd /d `"$scriptDir`" && set DAR=$darArg && call convert.bat" -Wait -NoNewWindow
}
if ($files.Count -eq 1) { Start-Sleep -Seconds 1 }
