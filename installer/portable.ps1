#INSTALLER#
# Runs from the portable single file (AIUsageWidget.cmd). No installation, no shortcuts:
# the app files are unpacked quietly to a cache folder the first time (WebView2 needs its DLLs on disk)
# and the widget starts right away. A newer file replaces the cached copy; sign-ins are kept.
param($Self, $Payload)

$Data = Join-Path $env:LOCALAPPDATA 'AIUsageWidget'
$App = Join-Path $Data 'app'
$VerFile = Join-Path $App 'version.txt'

try {
    $ErrorActionPreference = 'Stop'
    $sha = New-Object Security.Cryptography.SHA256Managed
    $ver = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($Payload)))).Replace('-', '').Substring(0, 16)
    $cached = ''
    if (Test-Path $VerFile) { $cached = (Get-Content $VerFile -Raw).Trim() }

    if ($cached -ne $ver) {
        # a different version is running from the cache: stop it so the files can be replaced
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*AIUsageWidget.ps1*' -and $_.ProcessId -ne $PID })
        foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        if ($procs.Count -gt 0) { Start-Sleep -Seconds 2 }

        New-Item -ItemType Directory -Force $Data | Out-Null
        $zip = Join-Path $env:TEMP ("AIUsageWidget_" + $ver + ".zip")
        [IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String($Payload))
        if (Test-Path $App) { Remove-Item $App -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $App -Force
        Remove-Item $zip -Force
        Set-Content $VerFile $ver
    }

    # Start the widget. If it is already running, the widget itself just brings its window back.
    $script = Join-Path $App 'AIUsageWidget.ps1'
    Start-Process "$env:WINDIR\System32\conhost.exe" -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"$script`"" -WorkingDirectory $App
} catch {
    Add-Type -AssemblyName PresentationFramework
    $ko = ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ko')
    $msg = if ($ko) { "AI 사용량 위젯을 시작하지 못했습니다.`n`n" } else { "Could not start AI Usage Widget.`n`n" }
    [System.Windows.MessageBox]::Show($msg + $_.Exception.Message, 'AI Usage Widget', 'OK', 'Error') | Out-Null
}
