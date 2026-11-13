#INSTALLER#
# Runs from the single-file installer (AIUsageWidget-Setup.cmd).
# Unpacks the app to %LOCALAPPDATA%\AIUsageWidget\app, creates shortcuts with the app icon and starts the widget.
# Running a newer installer updates the app; sign-in data (outside the app folder) is kept.
param($Self, $Payload)
Add-Type -AssemblyName PresentationFramework

$ko = ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ko')
$Title = if ($ko) { 'AI 사용량 위젯' } else { 'AI Usage Widget' }
function Msg($text, $icon = 'Information') { [System.Windows.MessageBox]::Show($text, $Title, 'OK', $icon) | Out-Null }

$Data = Join-Path $env:LOCALAPPDATA 'AIUsageWidget'
$App = Join-Path $Data 'app'
$VerFile = Join-Path $App 'version.txt'
$ShortcutName = 'AI Usage Widget.lnk'

try {
    $ErrorActionPreference = 'Stop'
    $sha = New-Object Security.Cryptography.SHA256Managed
    $ver = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($Payload)))).Replace('-', '').Substring(0, 16)
    $installed = ''
    if (Test-Path $VerFile) { $installed = (Get-Content $VerFile -Raw).Trim() }
    $fresh = -not (Test-Path (Join-Path $App 'AIUsageWidget.ps1'))
    $updated = $false

    if ($installed -ne $ver) {
        # stop a running widget (any copy) so its files can be replaced
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
        $updated = -not $fresh
    }

    # shortcuts with the app icon
    $script = Join-Path $App 'AIUsageWidget.ps1'
    $ico = Join-Path $App 'app.ico'
    $launchArgs = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"$script`""
    $ws = New-Object -ComObject WScript.Shell
    function Make-Shortcut($path) {
        $l = $ws.CreateShortcut($path)
        $l.TargetPath = "$env:WINDIR\System32\conhost.exe"
        $l.Arguments = $launchArgs
        $l.WorkingDirectory = $App
        $l.IconLocation = $ico
        $l.Description = 'AI Usage Widget'
        $l.Save()
    }
    $startup = Join-Path ([Environment]::GetFolderPath('Startup')) $ShortcutName
    # shortcuts made by v1.0 used a Korean name; replace them
    $oldName = 'AI ' + [char]0xC0AC + [char]0xC6A9 + [char]0xB7C9 + ' ' + [char]0xC704 + [char]0xC82F + '.lnk'
    $oldStartup = Join-Path ([Environment]::GetFolderPath('Startup')) $oldName
    if (Test-Path $oldStartup) { Remove-Item $oldStartup -Force; Make-Shortcut $startup }
    Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) $oldName) -Force -ErrorAction SilentlyContinue

    Make-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName)
    Make-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) $ShortcutName)
    if (Test-Path $startup) { Make-Shortcut $startup }

    $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*AIUsageWidget.ps1*' -and $_.ProcessId -ne $PID }).Count -gt 0
    if (-not $running) { Start-Process "$env:WINDIR\System32\conhost.exe" -ArgumentList $launchArgs -WorkingDirectory $App }

    if ($fresh) {
        if ($ko) { Msg "설치가 끝났습니다.`n`n바탕화면과 시작 메뉴에 [AI Usage Widget] 아이콘을 만들었습니다.`n다음부터는 그 아이콘으로 실행하세요.`n`n이 설치 파일은 지워도 됩니다." }
        else { Msg "Installation complete.`n`nAn [AI Usage Widget] icon was added to your desktop and Start menu.`nUse it to start the widget from now on.`n`nYou can delete this installer file." }
    } elseif ($updated) {
        if ($ko) { Msg '새 버전으로 업데이트했습니다. 로그인 정보는 그대로 유지됩니다.' }
        else { Msg 'Updated to the new version. Your sign-ins are kept.' }
    } elseif ($running) {
        if ($ko) { Msg '이미 최신 버전이 설치되어 실행 중입니다.' }
        else { Msg 'The latest version is already installed and running.' }
    }
} catch {
    if ($ko) { Msg ("설치 중 문제가 생겼습니다.`n`n" + $_.Exception.Message) 'Error' }
    else { Msg ("Installation failed.`n`n" + $_.Exception.Message) 'Error' }
}
