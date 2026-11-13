# Builds the single-file releases:
#   dist\AIUsageWidget.cmd        portable: double-click to run, nothing installed
#   dist\AIUsageWidget-Setup.cmd  installer: adds desktop and Start menu shortcuts with the app icon
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $root 'app'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# 1) zip the app folder
$tmp = Join-Path $env:TEMP ('aiuw-build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
$zip = Join-Path $tmp 'app.zip'
Compress-Archive -Path (Join-Path $app '*') -DestinationPath $zip -CompressionLevel Optimal

# 2) base64, wrapped so the file stays readable in editors
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
$sb = New-Object Text.StringBuilder
for ($i = 0; $i -lt $b64.Length; $i += 1000) { [void]$sb.AppendLine($b64.Substring($i, [Math]::Min(1000, $b64.Length - $i))) }
$payload = $sb.ToString()
Remove-Item $tmp -Recurse -Force

# 3) header (cmd) + script (PowerShell) + payload; CRLF line endings, UTF-8 without BOM (a BOM breaks cmd.exe)
$enc = [Text.Encoding]::UTF8
$header = [IO.File]::ReadAllText((Join-Path $root 'installer\header.cmd'), $enc)
$targets = [ordered]@{ 'AIUsageWidget.cmd' = 'portable.ps1'; 'AIUsageWidget-Setup.cmd' = 'installer.ps1' }
foreach ($name in $targets.Keys) {
    $script = [IO.File]::ReadAllText((Join-Path $root ('installer\' + $targets[$name])), $enc)
    $text = ($header.TrimEnd() + "`n" + $script.TrimEnd() + "`n#PAYLOAD#`n" + $payload) -replace "`r?`n", "`r`n"
    $out = Join-Path $dist $name
    [IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding $false))
    "Built $out ({0:N0} KB)" -f ((Get-Item $out).Length / 1KB)
}
