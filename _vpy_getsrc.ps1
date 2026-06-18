param([Parameter(Mandatory=$true)][string]$Vpy)
$line = Get-Content -LiteralPath $Vpy |
    Where-Object { $_ -notmatch '^\s*#' -and ($_ -match 'Source\s*\(') } |
    Select-Object -First 1
if ($line) {
    $m = [regex]::Match($line, '"([^"]+)"')
    if ($m.Success) { $m.Groups[1].Value }
}
