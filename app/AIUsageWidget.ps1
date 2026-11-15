# AI Usage Widget (Windows PowerShell 5.1 + WPF + WebView2)
# Shows remaining subscription usage of AI services on the desktop.
# Each AI service is one .js file in the providers folder.
# https://github.com/jbjmanse-hub/ai-usage-widget  (MIT License)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$AppVersion = '1.2.1'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ScriptPath = $PSCommandPath
$Lib = Join-Path $Root 'lib'
$DataDir = Join-Path $env:LOCALAPPDATA 'AIUsageWidget'
$UserProviders = Join-Path $DataDir 'providers'
$SettingsPath = Join-Path $DataDir 'settings.json'
$LogPath = Join-Path $DataDir 'error.log'
$ShortcutName = 'AI Usage Widget.lnk'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Write-Log($msg) {
    try { Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}
$script:debug = Test-Path (Join-Path $DataDir 'debug')
function Trace($m) { if ($script:debug) { Write-Log "TRACE $m" } }

# ---------------- Settings ----------------
function Load-Settings {
    $d = [ordered]@{ left = -1; top = -1; opacity = 0.92; topmost = $true; refresh_seconds = 60; hidden = @(); known = @(); lang = 'auto' }
    $s = $null
    if (Test-Path $SettingsPath) { try { $s = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    if (-not $s) { $s = [pscustomobject]@{} }
    foreach ($k in $d.Keys) { if (-not ($s.PSObject.Properties.Name -contains $k)) { $s | Add-Member -NotePropertyName $k -NotePropertyValue $d[$k] } }
    # migrate settings from older versions
    $h = @($s.hidden | Where-Object { $_ })
    if ($s.PSObject.Properties.Name -contains 'show_chatgpt') { if (-not $s.show_chatgpt) { $h += 'chatgpt' }; $s.PSObject.Properties.Remove('show_chatgpt') }
    if ($s.PSObject.Properties.Name -contains 'show_claude') { if (-not $s.show_claude) { $h += 'claude' }; $s.PSObject.Properties.Remove('show_claude') }
    if ($s.PSObject.Properties.Name -contains 'links') { $s.PSObject.Properties.Remove('links') }
    $s.hidden = @($h | Select-Object -Unique)
    $s.known = @($s.known | Where-Object { $_ } | Select-Object -Unique)
    return $s
}
function Save-Settings { try { $script:cfg | ConvertTo-Json | Set-Content $SettingsPath -Encoding UTF8 } catch {} }
$script:cfg = Load-Settings

# ---------------- Language ----------------
function Resolve-Lang {
    if ($script:cfg.lang -eq 'ko' -or $script:cfg.lang -eq 'en') { return $script:cfg.lang }
    if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ko') { return 'ko' }
    return 'en'
}
$script:lang = Resolve-Lang
Trace "start v$AppVersion lang=$script:lang (setting: $($script:cfg.lang))"

$Strings = @{
    ko = @{
        title = 'AI 구독 사용량'; updating = '갱신 중…'; updated = '{0} 갱신'; refreshTip = '지금 새로고침'
        empty = "표시할 AI가 없습니다.`n우클릭 → [표시할 AI]에서 골라주세요."
        loading = '불러오는 중…'; signIn = '로그인'; needLogin = '로그인이 필요합니다'; noRows = '표시할 한도 정보가 없습니다'
        left = '남음 {0}%  (사용 {1}%)'
        resetSoon = '곧 리셋'; resetD = '리셋 {0}일 {1}시간 후  ({2})'; resetH = '리셋 {0}시간 {1}분 후  ({2})'; resetM = '리셋 {0}분 후  ({1})'
        errNoRuntime = 'WebView2 런타임이 없습니다. Microsoft Edge WebView2를 설치하세요.'
        errBrowser = '내장 브라우저를 만들지 못했습니다'; errTimeout = '응답 시간 초과'; errFetch = '불러오기 실패'
        errScript = '조회 스크립트 오류 (error.log 참고)'; errCf = '사이트 보안 확인을 통과하지 못했습니다. 잠시 후 다시 시도합니다.'
        errParse = '응답을 해석하지 못했습니다'
        expired = '{0} 로그인이 만료됐습니다. 위젯의 [로그인] 버튼으로 다시 로그인하세요.'
        loginTitle = '{0} 로그인'; loginDone = '로그인 완료'; loginHint = '아래에서 {0}에 로그인한 뒤 [로그인 완료]를 누르세요.'
        otherAccount = '다른 계정으로 로그인'; otherAccountTip = '저장된 Google·Microsoft 등의 로그인을 지우고 처음부터 로그인합니다 (회사 계정으로 바꿀 때)'
        running = "AI 사용량 위젯이 이미 실행 중입니다.`n작업 표시줄 오른쪽 트레이 아이콘을 확인하세요."
        libFail = "WebView2 구성 파일을 불러오지 못했습니다.`nlib 폴더가 함께 있는지 확인하세요."
        browserWait = '내장 브라우저 준비 중입니다. 잠시 후 다시 눌러주세요.'
        logoutAllQ = '이 PC의 위젯에 저장된 모든 AI 도구의 로그인 정보를 지울까요?'; logoutAllT = '모든 계정 로그아웃'
        logoutQ = "위젯에 저장된 {0} 로그인 정보를 지울까요?`n(Google 등 로그인에 쓴 계정 정보도 함께 지워집니다. 다른 AI 도구의 로그인은 그대로 유지됩니다)"; logoutT = '{0} 로그아웃'
        autoFail = '자동 실행 설정에 실패했습니다.'
        uninstallQ = "AI 사용량 위젯을 이 PC에서 삭제할까요?`n`n프로그램, 바로가기, 저장된 로그인 정보가 모두 지워집니다."
        uninstallT = '프로그램 삭제'; uninstallDone = '삭제를 시작합니다. 잠시 후 모든 파일이 지워집니다.'
        mRefresh = '지금 새로고침'; mSignIn = '로그인'; mShow = '표시할 AI'; mUnavailable = '사용량 조회 불가'
        mAddTool = 'AI 도구 파일 추가하기 (고급)…'; mReload = 'AI 도구 목록 다시 불러오기'
        mTop = '항상 위에 표시'; mOpacity = '투명도'; mOpSolid = '진하게'; mOpNormal = '보통'; mOpLight = '연하게'
        mAutostart = 'Windows 시작 시 자동 실행'; mDesktop = '바탕화면에 바로가기 만들기'
        mLang = '언어 (Language)'; mLangAuto = '자동 (시스템 언어)'
        mHide = '위젯 숨기기/보이기'; mLogoutAll = '모든 계정 로그아웃'; mLogout = '로그아웃'
        mNoTools = '(로그인할 AI 도구 없음)'; mNoLogged = '(로그인된 AI 도구 없음)'
        mHelp = '사용법 보기'; mUninstall = '프로그램 삭제…'; mExit = '종료'
        cantShow = '{0}: {1}. 위젯에 표시할 수 없습니다.'
        trayText = 'AI 사용량 위젯'
    }
    en = @{
        title = 'AI Subscription Usage'; updating = 'Updating…'; updated = 'Updated {0}'; refreshTip = 'Refresh now'
        empty = "No AI service selected.`nRight-click → [Show AI] to choose."
        loading = 'Loading…'; signIn = 'Sign in'; needLogin = 'Sign-in required'; noRows = 'No usage limits to show'
        left = '{0}% left  ({1}% used)'
        resetSoon = 'Resets soon'; resetD = 'Resets in {0}d {1}h  ({2})'; resetH = 'Resets in {0}h {1}m  ({2})'; resetM = 'Resets in {0}m  ({1})'
        errNoRuntime = 'WebView2 Runtime is missing. Please install Microsoft Edge WebView2.'
        errBrowser = 'Could not start the built-in browser'; errTimeout = 'Request timed out'; errFetch = 'Failed to load'
        errScript = 'Provider script error (see error.log)'; errCf = 'Could not pass the site security check. Will retry shortly.'
        errParse = 'Could not read the response'
        expired = '{0} sign-in has expired. Use the [Sign in] button on the widget to sign in again.'
        loginTitle = 'Sign in to {0}'; loginDone = 'Done'; loginHint = 'Sign in to {0} below, then click [Done].'
        otherAccount = 'Use another account'; otherAccountTip = 'Forget saved Google, Microsoft and other sign-ins and start over (e.g. to switch to a work account)'
        running = "AI Usage Widget is already running.`nCheck the tray icon at the right of the taskbar."
        libFail = "Could not load the WebView2 files.`nMake sure the lib folder is next to the script."
        browserWait = 'The built-in browser is starting. Please try again in a moment.'
        logoutAllQ = 'Remove the sign-in data of all AI services stored by this widget?'; logoutAllT = 'Sign out of all'
        logoutQ = "Remove the {0} sign-in data stored by this widget?`n(Saved Google and other account sign-ins used to log in are removed too. Other AI services stay signed in.)"; logoutT = 'Sign out of {0}'
        autoFail = 'Could not change the startup setting.'
        uninstallQ = "Uninstall AI Usage Widget from this PC?`n`nThe program, its shortcuts and all saved sign-in data will be removed."
        uninstallT = 'Uninstall'; uninstallDone = 'Uninstalling. All files will be removed in a few seconds.'
        mRefresh = 'Refresh now'; mSignIn = 'Sign in'; mShow = 'Show AI'; mUnavailable = 'Usage not available'
        mAddTool = 'Add AI tool file (advanced)…'; mReload = 'Reload AI tools'
        mTop = 'Always on top'; mOpacity = 'Opacity'; mOpSolid = 'Solid'; mOpNormal = 'Normal'; mOpLight = 'Light'
        mAutostart = 'Start with Windows'; mDesktop = 'Create desktop shortcut'
        mLang = 'Language (언어)'; mLangAuto = 'Auto (system language)'
        mHide = 'Hide/show widget'; mLogoutAll = 'Sign out of all'; mLogout = 'Sign out'
        mNoTools = '(no AI services)'; mNoLogged = '(not signed in to any service)'
        mHelp = 'Help'; mUninstall = 'Uninstall…'; mExit = 'Exit'
        cantShow = '{0}: {1}. It cannot be shown on the widget.'
        trayText = 'AI Usage Widget'
    }
}
function T($key) {
    $v = $Strings[$script:lang][$key]
    if (-not $v) { $v = $Strings['en'][$key] }
    if ($args.Count -gt 0) { return ($v -f $args) }
    return $v
}

# ---------------- Single instance ----------------
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\AIUsageWidget_ps', [ref]$created)
if (-not $created) {
    # Already running: ask that instance to show its window, then quit quietly.
    $evt = $null
    if ([System.Threading.EventWaitHandle]::TryOpenExisting('Local\AIUsageWidget_show', [ref]$evt)) { [void]$evt.Set(); exit }
    # No running window yet (e.g. right after a restart): wait briefly for the previous process to exit.
    try { $created = $script:mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $created = $true }
    if (-not $created) {
        [System.Windows.MessageBox]::Show((T 'running'), (T 'trayText')) | Out-Null
        exit
    }
}
# Another launch sets this event to bring the widget back on screen.
$script:showEvt = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\AIUsageWidget_show')

# ---------------- WebView2 ----------------
try {
    Add-Type -Path (Join-Path $Lib 'Microsoft.Web.WebView2.Core.dll')
    Add-Type -Path (Join-Path $Lib 'Microsoft.Web.WebView2.Wpf.dll')
    $arch = 'x64'; if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
    [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath((Join-Path $Lib $arch))
} catch {
    Write-Log $_
    [System.Windows.MessageBox]::Show(("{0}`n`n{1}" -f (T 'libFail'), $_.Exception.Message), (T 'trayText')) | Out-Null
    exit
}
# All WebViews share one environment, i.e. one profile with the sign-in cookies.
$script:envTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, (Join-Path $DataDir 'WebView'), $null)
$script:env = $null

# ---------------- Providers ----------------
function New-Site($id, $meta, $js) {
    $hostUrl = $meta['host']
    $homeUrl = $meta['home']; if (-not $homeUrl) { $homeUrl = ([Uri]$hostUrl).GetLeftPart('Authority') + '/' }
    $loginUrl = $meta['login']; if (-not $loginUrl) { $loginUrl = $homeUrl }
    $color = $meta['color']; if (-not $color) { $color = '#8AB4F8' }
    # domains whose cookies are removed on sign-out (default: base domain of host)
    $domains = @()
    if ($meta['domains']) { $domains = @($meta['domains'] -split '[\s,]+' | Where-Object { $_ }) }
    else {
        $parts = ([Uri]$hostUrl).Host.Split('.')
        $domains = @(($parts | Select-Object -Last ([math]::Min(2, $parts.Count))) -join '.')
    }
    $origins = @(@(([Uri]$homeUrl).GetLeftPart('Authority'), ([Uri]$loginUrl).GetLeftPart('Authority')) | Select-Object -Unique)
    return @{
        type = 'usage'; builtin = $false; domains = $domains; origins = $origins
        id = $id; name = $meta['name']; color = $color; host = $hostUrl; home = $homeUrl; login = $loginUrl; js = $js
        ctl = $null; core = $null; ctlTask = $null; evalTask = $null
        ready = $false; navDone = $false; needHome = $true; cfRetry = 0
        phase = 'idle'; lastPhase = ''; t0 = [datetime]::MinValue
        everOk = $false; notified = $false; lastHome = (Get-Date); rendered = $false
        box = $null; title = $null; rows = $null; resets = @(); spinner = $null
    }
}

function Load-Providers {
    $list = [ordered]@{}
    $builtinDir = Join-Path $Root 'providers'
    foreach ($dir in @($builtinDir, $UserProviders)) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in (Get-ChildItem $dir -Filter '*.js' | Sort-Object Name)) {
            if ($f.Name.StartsWith('_')) { continue }
            try {
                $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
                $meta = @{}
                foreach ($m in [regex]::Matches($text, '(?m)^\s*//\s*@(\w+)\s+(.+?)\s*$')) {
                    $k = $m.Groups[1].Value.ToLower()
                    if (-not $meta.ContainsKey($k)) { $meta[$k] = $m.Groups[2].Value }
                }
                $id = $meta['id']; if (-not $id) { $id = [IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower() }
                if (-not $meta['name'] -or -not $meta['host']) { Write-Log "Provider skipped (missing @name/@host): $($f.FullName)"; continue }
                [void][Uri]$meta['host']
                $site = New-Site $id $meta $text
                $site.builtin = ($dir -eq $builtinDir)
                $list[$id] = $site
            } catch { Write-Log "Provider load failed: $($f.FullName) - $($_.Exception.Message)" }
        }
    }
    # services without a usage API: listed greyed out in the menu with the reason
    $lj = Join-Path $builtinDir 'unavailable.json'
    if (Test-Path $lj) {
        try {
            # PowerShell 5.1 passes a JSON array down the pipeline as one object, so assign first
            $arr = [IO.File]::ReadAllText($lj, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($l in $arr) {
                if (-not $l.id -or $l.id -isnot [string] -or $list.Contains($l.id)) { continue }
                $reason = $l.reason_en; if ($script:lang -eq 'ko' -and $l.reason_ko) { $reason = $l.reason_ko }
                $list[$l.id] = @{ type = 'unavailable'; builtin = $true; id = $l.id; name = $l.name; reason = $reason; phase = 'idle' }
            }
        } catch { Write-Log "unavailable.json read failed: $($_.Exception.Message)" }
    }
    return $list
}
$script:sites = Load-Providers

# Only ChatGPT and Claude are shown by default; other built-in services are opt-in.
$DefaultShown = @('chatgpt', 'claude')
$changed = $false
foreach ($s in $script:sites.Values) {
    if ($s.type -ne 'usage' -or @($script:cfg.known) -contains $s.id) { continue }
    if ($s.builtin -and -not ($DefaultShown -contains $s.id)) { $script:cfg.hidden = @($script:cfg.hidden) + $s.id }
    $script:cfg.known = @($script:cfg.known) + $s.id
    $changed = $true
}
if ($changed) { Save-Settings }

function Is-Shown($s) {
    if ($s.type -ne 'usage') { return $false }
    return -not (@($script:cfg.hidden) -contains $s.id)
}

# ---------------- UI ----------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Usage Widget" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight" ShowInTaskbar="False"
        FontFamily="Segoe UI, Malgun Gothic">
  <Border Name="Card" CornerRadius="12" Background="#E61B1D24" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="14,10,14,10">
    <StackPanel Width="250">
      <DockPanel Margin="0,0,0,2" LastChildFill="True">
        <Border Name="RefreshBtn" DockPanel.Dock="Right" Width="22" Height="22" CornerRadius="11" Background="#00FFFFFF"
                Cursor="Hand" Margin="6,-2,-4,0">
          <TextBlock Name="RefreshIcon" Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#BBFFFFFF"
                     HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
            <TextBlock.RenderTransform><RotateTransform Angle="0"/></TextBlock.RenderTransform>
          </TextBlock>
        </Border>
        <TextBlock Name="Updated" DockPanel.Dock="Right" Foreground="#88FFFFFF" FontSize="10" VerticalAlignment="Center"/>
        <TextBlock Name="Title" Foreground="#FFFFFF" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
      </DockPanel>
      <StackPanel Name="Services"/>
      <TextBlock Name="EmptyHint" Foreground="#99FFFFFF" FontSize="11" Margin="0,8,0,2" TextWrapping="Wrap" Visibility="Collapsed"/>
    </StackPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Card', 'Updated', 'Title', 'RefreshBtn', 'RefreshIcon', 'Services', 'EmptyHint') { $ui[$n] = $win.FindName($n) }
$ui.RefreshRot = $ui.RefreshIcon.RenderTransform
$ui.Title.Text = T 'title'
$ui.EmptyHint.Text = T 'empty'
$ui.RefreshBtn.ToolTip = T 'refreshTip'

$win.Opacity = [double]$script:cfg.opacity
$win.Topmost = [bool]$script:cfg.topmost
$wa = [System.Windows.SystemParameters]::WorkArea
$win.WindowStartupLocation = 'Manual'
if ($script:cfg.left -ge ($wa.Left - 50) -and $script:cfg.left -lt ($wa.Right - 50) -and $script:cfg.top -ge ($wa.Top - 50) -and $script:cfg.top -lt ($wa.Bottom - 50)) {
    $win.Left = $script:cfg.left; $win.Top = $script:cfg.top
} else { $win.Left = $wa.Right - 300; $win.Top = $wa.Top + 20 }

$bc = New-Object System.Windows.Media.BrushConverter
function Brush($hex) {
    try { return $bc.ConvertFromString($hex) } catch { return $bc.ConvertFromString('#8AB4F8') }
}

function TB($text, $color, $size) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text; $t.Foreground = Brush $color; $t.FontSize = $size
    return $t
}

function Build-Boxes {
    $ui.Services.Children.Clear()
    foreach ($s in $script:sites.Values) {
        if ($s.type -ne 'usage') { continue }
        $box = New-Object System.Windows.Controls.StackPanel
        $title = TB $s.name $s.color 12
        $title.FontWeight = 'SemiBold'; $title.Margin = '0,10,0,2'
        $rows = New-Object System.Windows.Controls.StackPanel
        [void]$box.Children.Add($title); [void]$box.Children.Add($rows)
        [void]$ui.Services.Children.Add($box)
        $s.box = $box; $s.title = $title; $s.rows = $rows
    }
    Apply-Visibility
}

function Apply-Visibility {
    $first = $true
    foreach ($s in $script:sites.Values) {
        if ($s.type -ne 'usage') { continue }
        if (Is-Shown $s) {
            $s.box.Visibility = 'Visible'
            $top = 10; if ($first) { $top = 6 }
            $s.title.Margin = "0,$top,0,2"
            $first = $false
        } else { $s.box.Visibility = 'Collapsed' }
    }
    $ui.EmptyHint.Visibility = if ($first) { 'Visible' } else { 'Collapsed' }
}

function Format-Reset($dt) {
    $ts = $dt - (Get-Date)
    if ($ts.TotalSeconds -le 0) { return (T 'resetSoon') }
    if ($ts.TotalDays -ge 1) { return (T 'resetD' ([int][math]::Floor($ts.TotalDays)) $ts.Hours $dt.ToString('M/d HH:mm')) }
    if ($ts.TotalHours -ge 1) { return (T 'resetH' ([int][math]::Floor($ts.TotalHours)) $ts.Minutes $dt.ToString('HH:mm')) }
    return (T 'resetM' ([math]::Max(1, $ts.Minutes)) $dt.ToString('HH:mm'))
}

function Render-Loading($s) {
    $s.rows.Children.Clear()
    $s.resets = @()
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'; $sp.Margin = '0,4,0,4'
    $ic = TB ([string][char]0xE72C) '#CCFFFFFF' 11
    $ic.FontFamily = 'Segoe MDL2 Assets'; $ic.VerticalAlignment = 'Center'
    $ic.RenderTransformOrigin = '0.5,0.5'
    $rot = New-Object System.Windows.Media.RotateTransform
    $ic.RenderTransform = $rot
    $lb = TB (T 'loading') '#BBFFFFFF' 11
    $lb.Margin = '7,0,0,0'; $lb.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($ic); [void]$sp.Children.Add($lb)
    [void]$s.rows.Children.Add($sp)
    $s.spinner = $rot
}

function Render($s, $res) {
    $panel = $s.rows
    $panel.Children.Clear()
    $s.resets = @()
    $s.spinner = $null
    $s.rendered = $true
    $s.title.Text = $s.name
    if ($res.ok -and $res.plan) { $s.title.Text = "$($s.name)  ·  $($res.plan)" }

    if ($res.login) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,2,0,0'
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = T 'signIn'; $btn.Padding = '10,1,10,1'; $btn.FontSize = 11; $btn.Tag = $s.id
        $btn.Add_Click({ param($b, $e) Open-Login $script:sites[$b.Tag] })
        [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
        [void]$row.Children.Add($btn)
        $tb = TB (T 'needLogin') '#BBFFFFFF' 11
        $tb.VerticalAlignment = 'Center'
        [void]$row.Children.Add($tb)
        [void]$panel.Children.Add($row)
        return
    }
    if (-not $res.ok) {
        $tb = TB "⚠ $($res.err)" '#F0A0A0' 10.5
        $tb.TextWrapping = 'Wrap'
        [void]$panel.Children.Add($tb)
        return
    }
    if (@($res.rows).Count -eq 0) {
        [void]$panel.Children.Add((TB (T 'noRows') '#99FFFFFF' 11))
        return
    }
    foreach ($r in $res.rows) {
        if ($null -eq $r.pct) {
            # a row with a value but no percentage, e.g. "12 left"
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = '0,3,0,2'
            [void]$g.Children.Add((TB "$($r.label)" '#DDFFFFFF' 11))
            $v = TB "$($r.value)" '#8FD6FF' 11
            $v.HorizontalAlignment = 'Right'
            [void]$g.Children.Add($v)
            [void]$panel.Children.Add($g)
            continue
        }
        $pct = [math]::Max(0, [math]::Min(100, [double]$r.pct))
        $color = '#3FB950'; if ($pct -ge 60) { $color = '#E3B341' }; if ($pct -ge 85) { $color = '#F85149' }

        $g = New-Object System.Windows.Controls.Grid
        $g.Margin = '0,3,0,0'
        [void]$g.Children.Add((TB "$($r.label)" '#DDFFFFFF' 11))
        $p = TB (T 'left' ([math]::Round(100 - $pct)) ([math]::Round($pct))) $color 11
        $p.HorizontalAlignment = 'Right'
        [void]$g.Children.Add($p)
        [void]$panel.Children.Add($g)

        $track = New-Object System.Windows.Controls.Border
        $track.Height = 6; $track.CornerRadius = 3; $track.Background = Brush '#22FFFFFF'; $track.Margin = '0,3,0,0'
        $fill = New-Object System.Windows.Controls.Border
        $fill.Height = 6; $fill.CornerRadius = 3; $fill.Background = Brush $color; $fill.HorizontalAlignment = 'Left'
        $fill.Width = 250 * $pct / 100
        $track.Child = $fill
        [void]$panel.Children.Add($track)

        $rs = TB '' '#77FFFFFF' 10
        $rs.Margin = '0,1,0,0'
        if ([double]$r.reset -gt 0) {
            $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64][double]$r.reset).LocalDateTime
            $rs.Text = Format-Reset $dt
            $s.resets += , @($rs, $dt)
        }
        [void]$panel.Children.Add($rs)
    }
}

# ---------------- Fetch state machine (advanced by the timer) ----------------
$script:helper = New-Object System.Windows.Window
$script:helperHwnd = (New-Object System.Windows.Interop.WindowInteropHelper $script:helper).EnsureHandle()
$script:lastFetch = [datetime]::MinValue
$script:roundActive = $false

function Set-RoundActive {
    if ($script:roundActive) { return }
    $script:roundActive = $true
    $script:lastFetch = Get-Date
    $ui.Updated.Text = T 'updating'
    $ui.RefreshIcon.Foreground = Brush '#66FFFFFF'
}

function Start-Site($s, [bool]$showLoading = $false) {
    if (-not $s -or -not (Is-Shown $s)) { return }
    if ($showLoading -or -not $s.rendered) { Render-Loading $s }
    if ($s.phase -eq 'idle') { $s.phase = 'start'; $s.cfRetry = 0 }
    Set-RoundActive
}

function Start-Refresh {
    foreach ($s in $script:sites.Values) { if (Is-Shown $s) { Start-Site $s } }
    $script:lastFetch = Get-Date
}

function Finish-Site($s, $res) {
    Trace ("{0} finish ok={1} login={2} err={3} why={4}" -f $s.name, $res.ok, $res.login, $res.err, $res.why)
    $s.phase = 'idle'
    if (-not $res.ok) { $s.ready = $false }
    if ($res.ok) { $s.everOk = $true; $s.notified = $false }
    elseif ($res.login -and $s.everOk -and -not $s.notified) {
        # notify only when a working sign-in expires
        $s.notified = $true
        try { $tray.ShowBalloonTip(8000, (T 'trayText'), (T 'expired' $s.name), 'Info') } catch {}
    }
    try { Render $s $res } catch { Write-Log $_ }
}

function On-NavCompleted($sender) {
    foreach ($s in $script:sites.Values) { if ($s.core -eq $sender) { $s.navDone = $true } }
}

function Nav($s, $url, $phase) {
    $s.navDone = $false; $s.t0 = Get-Date
    $s.core.Navigate($url)
    $s.phase = $phase
}

function Step-Site($s) {
    $elapsed = ((Get-Date) - $s.t0).TotalSeconds
    if ($s.lastPhase -ne $s.phase) { Trace ("{0} phase={1}" -f $s.name, $s.phase); $s.lastPhase = $s.phase }
    switch ($s.phase) {
        'start' {
            if (-not $script:env) {
                if ($script:envTask.IsFaulted) { Finish-Site $s @{ ok = $false; err = (T 'errNoRuntime') }; return }
                if ($script:envTask.IsCompleted) { $script:env = $script:envTask.Result } else { return }
            }
            if (-not $s.ctl) {
                $s.ctlTask = $script:env.CreateCoreWebView2ControllerAsync($script:helperHwnd)
                $s.phase = 'creating'; return
            }
            # first run / security check needed / every 12h: open the home page to pass checks and extend the session
            if ($s.needHome -or ($s.everOk -and ((Get-Date) - $s.lastHome).TotalHours -ge 12)) { Nav $s $s.home 'home'; return }
            if (-not $s.ready) { Nav $s $s.host 'navigating'; return }
            $expr = "var LANG = '" + $script:lang + "';`n" + $s.js
            $arg = @{ expression = $expr; awaitPromise = $true; returnByValue = $true } | ConvertTo-Json -Compress
            $s.evalTask = $s.core.CallDevToolsProtocolMethodAsync('Runtime.evaluate', $arg)
            $s.t0 = Get-Date
            $s.phase = 'evaluating'
        }
        'creating' {
            if (-not $s.ctlTask.IsCompleted) { return }
            if ($s.ctlTask.IsFaulted) { Write-Log $s.ctlTask.Exception; Finish-Site $s @{ ok = $false; err = (T 'errBrowser') }; return }
            $s.ctl = $s.ctlTask.Result
            $s.ctl.IsVisible = $false
            $s.ctl.Bounds = New-Object System.Drawing.Rectangle 0, 0, 1024, 768
            $s.core = $s.ctl.CoreWebView2
            $s.core.Settings.AreDevToolsEnabled = $false
            $s.core.Settings.IsStatusBarEnabled = $false
            $s.core.add_NavigationCompleted({ param($sender, $e) On-NavCompleted $sender })
            $s.phase = 'start'
        }
        'home' {
            if (($s.navDone -and $elapsed -gt 4) -or $elapsed -gt 30) {
                $s.needHome = $false; $s.lastHome = Get-Date; $s.ready = $false; $s.phase = 'start'
            }
        }
        'navigating' {
            if ($s.navDone -or $elapsed -gt 20) { $s.t0 = Get-Date; $s.phase = 'settle' }
        }
        'settle' {
            if ($elapsed -gt 1) { $s.ready = $true; $s.phase = 'start' }
        }
        'evaluating' {
            if (-not $s.evalTask.IsCompleted) {
                if ($elapsed -gt 25) { Finish-Site $s @{ ok = $false; err = (T 'errTimeout') } }
                return
            }
            if ($s.evalTask.IsFaulted) { Write-Log $s.evalTask.Exception; Finish-Site $s @{ ok = $false; err = (T 'errFetch') }; return }
            try {
                $o = $s.evalTask.Result | ConvertFrom-Json
                if ($o.exceptionDetails -or -not $o.result.value) {
                    Write-Log ("{0} script error: {1}" -f $s.name, $s.evalTask.Result)
                    Finish-Site $s @{ ok = $false; err = (T 'errScript') }; return
                }
                $v = $o.result.value | ConvertFrom-Json
                if ($v.cf) {
                    if ($s.cfRetry -lt 1) { $s.cfRetry++; $s.needHome = $true; $s.ready = $false; $s.phase = 'start'; return }
                    Finish-Site $s @{ ok = $false; err = (T 'errCf') }; return
                }
                if ($v.login) { Finish-Site $s @{ ok = $false; login = $true; why = "$($v.why)" }; return }
                if ($v.err) { Finish-Site $s @{ ok = $false; err = "$($v.err)" }; return }
                Finish-Site $s @{ ok = $true; plan = "$($v.plan)"; rows = @($v.rows) }
            } catch { Write-Log $_; Finish-Site $s @{ ok = $false; err = (T 'errParse') } }
        }
    }
}

# pending async tasks, completed ones are handled by the timer
$script:pending = New-Object System.Collections.ArrayList
function When($task, [scriptblock]$then, $state) { [void]$script:pending.Add(@{ t = $task; f = $then; s = $state }) }

$script:spin = 0
$script:lastCountdown = Get-Date
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    try {
        if ($script:showEvt.WaitOne(0)) { $win.Show(); $win.Activate(); [void]$win.Focus() }
        if ($script:pending.Count -gt 0) {
            foreach ($p in @($script:pending)) {
                if (-not $p.t.IsCompleted) { continue }
                $script:pending.Remove($p)
                try { & $p.f $p.t $p.s } catch { Write-Log $_ }
            }
        }
        foreach ($s in $script:sites.Values) { if ($s.phase -ne 'idle') { Step-Site $s } }

        if ($script:roundActive) {
            $script:spin = ($script:spin + 24) % 360
            $ui.RefreshRot.Angle = $script:spin
            foreach ($s in $script:sites.Values) { if ($s.spinner) { $s.spinner.Angle = $script:spin } }
            $busy = $false
            foreach ($s in $script:sites.Values) { if ($s.phase -ne 'idle') { $busy = $true } }
            if (-not $busy) {
                $script:roundActive = $false
                $ui.RefreshRot.Angle = 0
                $ui.RefreshIcon.Foreground = Brush '#BBFFFFFF'
                $ui.Updated.Text = T 'updated' ((Get-Date).ToString('HH:mm'))
            }
        }

        if (((Get-Date) - $script:lastFetch).TotalSeconds -ge [math]::Max(30, [double]$script:cfg.refresh_seconds)) { Start-Refresh }

        if (((Get-Date) - $script:lastCountdown).TotalSeconds -ge 1) {
            $script:lastCountdown = Get-Date
            foreach ($s in $script:sites.Values) { foreach ($x in @($s.resets)) { if ($x) { $x[0].Text = Format-Reset $x[1] } } }
        }
    } catch { Write-Log $_ }
})

# ---------------- Refresh button ----------------
$ui.RefreshBtn.Add_MouseEnter({ $ui.RefreshBtn.Background = Brush '#22FFFFFF' })
$ui.RefreshBtn.Add_MouseLeave({ $ui.RefreshBtn.Background = Brush '#00FFFFFF' })
$ui.RefreshBtn.Add_MouseLeftButtonDown({ param($b, $e) $e.Handled = $true })
$ui.RefreshBtn.Add_MouseLeftButtonUp({ param($b, $e) $e.Handled = $true; Start-Refresh })

# ---------------- Sign-in window ----------------
$script:loginWin = $null
function Open-Login($site) {
    if (-not $site) { return }
    if ($script:loginWin) { $script:loginWin.Activate(); return }
    if (-not $script:env) {
        if ($script:envTask.IsCompleted -and -not $script:envTask.IsFaulted) { $script:env = $script:envTask.Result }
        else { [System.Windows.MessageBox]::Show((T 'browserWait'), (T 'trayText')) | Out-Null; return }
    }
    $w = New-Object System.Windows.Window
    $w.Title = T 'loginTitle' $site.name; $w.Width = 500; $w.Height = 760; $w.WindowStartupLocation = 'CenterScreen'
    $ico = Join-Path $Root 'app.ico'; if (Test-Path $ico) { try { $w.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$ico) } catch {} }
    $dock = New-Object System.Windows.Controls.DockPanel
    $bar = New-Object System.Windows.Controls.DockPanel
    $bar.Background = Brush '#1B1D24'
    $done = New-Object System.Windows.Controls.Button
    $done.Content = T 'loginDone'; $done.Padding = '14,4,14,4'; $done.Margin = '8'; $done.FontWeight = 'SemiBold'
    $done.Add_Click({ $script:loginWin.Close() })
    [System.Windows.Controls.DockPanel]::SetDock($done, 'Right')
    [void]$bar.Children.Add($done)
    # Start over with no saved account (Google etc.), e.g. to use a work account instead of a personal one
    $other = New-Object System.Windows.Controls.Button
    $other.Content = T 'otherAccount'; $other.ToolTip = T 'otherAccountTip'
    $other.Padding = '10,4,10,4'; $other.Margin = '0,8,0,8'
    $other.Add_Click({
        $core = $script:loginWv.CoreWebView2
        if (-not $core) { return }
        Clear-SiteAuth $core $script:loginSite { param($s) try { $script:loginWv.CoreWebView2.Navigate($s.login) } catch { Write-Log $_ } }
    })
    [System.Windows.Controls.DockPanel]::SetDock($other, 'Right')
    [void]$bar.Children.Add($other)
    $msg = TB (T 'loginHint' $site.name) '#FFFFFF' 12
    $msg.VerticalAlignment = 'Center'; $msg.Margin = '12,0,0,0'; $msg.TextWrapping = 'Wrap'
    [void]$bar.Children.Add($msg)
    [System.Windows.Controls.DockPanel]::SetDock($bar, 'Top')
    [void]$dock.Children.Add($bar)
    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    [void]$dock.Children.Add($wv)
    $w.Content = $dock
    $script:loginWv = $wv
    $script:loginSite = $site
    $w.Add_Loaded({
        $script:loginInit = $script:loginWv.EnsureCoreWebView2Async($script:env)
        $script:loginNavTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:loginNavTimer.Interval = [TimeSpan]::FromMilliseconds(100)
        $script:loginNavTimer.Add_Tick({
            if (-not $script:loginInit.IsCompleted) { return }
            $script:loginNavTimer.Stop()
            if ($script:loginInit.IsFaulted) { Write-Log $script:loginInit.Exception; return }
            $script:loginWv.CoreWebView2.Navigate($script:loginSite.login)
        })
        $script:loginNavTimer.Start()
    })
    $w.Add_Closed({
        try { $script:loginWv.Dispose() } catch {}
        $script:loginWin = $null
        # re-check the service right away and show "Loading…" meanwhile
        $s = $script:loginSite
        $s.ready = $false; $s.cfRetry = 0
        Start-Site $s $true
    })
    $script:loginWin = $w
    $w.Show()
}

# ---------------- Sign-out ----------------
# Sign-in pages often use another account provider (Google, Microsoft, Apple, a company SSO).
# If that provider's cookies stay, signing in again picks the same account automatically.
# So clearing a service removes its own cookies AND every cookie that does not belong to
# another AI service; the other services stay signed in.
$SsoOrigins = @('https://accounts.google.com', 'https://login.microsoftonline.com', 'https://login.live.com', 'https://appleid.apple.com')

function Domain-Match($dom, $list) {
    foreach ($d in $list) { if ($dom -eq $d -or $dom.EndsWith('.' + $d)) { return $true } }
    return $false
}

function Clear-SiteAuth($core, $s, [scriptblock]$after) {
    $keep = @()
    foreach ($o in $script:sites.Values) { if ($o.type -eq 'usage' -and $o.id -ne $s.id) { $keep += $o.domains } }
    When ($core.CallDevToolsProtocolMethodAsync('Network.getAllCookies', '{}')) {
        param($t, $st)
        $s = $st.s; $core = $st.core
        if ($t.IsFaulted) { Write-Log $t.Exception }
        else {
            $n = 0
            foreach ($c in @(($t.Result | ConvertFrom-Json).cookies)) {
                if (-not $c) { continue }
                $dom = "$($c.domain)".TrimStart('.')
                $mine = Domain-Match $dom $s.domains
                if (-not $mine -and (Domain-Match $dom $st.keep)) { continue }   # another AI service: keep
                $arg = @{ name = $c.name; domain = $c.domain; path = $c.path } | ConvertTo-Json -Compress
                [void]$core.CallDevToolsProtocolMethodAsync('Network.deleteCookies', $arg)
                $n++
            }
            foreach ($o in @($s.origins) + $SsoOrigins) {
                [void]$core.CallDevToolsProtocolMethodAsync('Storage.clearDataForOrigin', (@{ origin = $o; storageTypes = 'all' } | ConvertTo-Json -Compress))
            }
            Trace ("{0} sign-in cleared: {1} cookies removed" -f $s.name, $n)
        }
        $s.ready = $false; $s.needHome = $true; $s.everOk = $false; $s.notified = $true; $s.rendered = $false
        if ($st.after) { & $st.after $s }
    } @{ s = $s; core = $core; keep = $keep; after = $after }
}

function Logout-Site($id) {
    $s = $script:sites[$id]
    if (-not $s -or -not $s.core) { return }
    $r = [System.Windows.MessageBox]::Show((T 'logoutQ' $s.name), (T 'logoutT' $s.name), 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Clear-SiteAuth $s.core $s { param($s) Start-Site $s $true }
}

function Logout-All {
    $r = [System.Windows.MessageBox]::Show((T 'logoutAllQ'), (T 'logoutAllT'), 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $core = $null
    foreach ($s in $script:sites.Values) { if ($s.core) { $core = $s.core } }
    if ($core) { try { [void]$core.Profile.ClearBrowsingDataAsync() } catch { Write-Log $_ } }
    foreach ($s in $script:sites.Values) { if ($s.type -eq 'usage') { $s.ready = $false; $s.needHome = $true; $s.everOk = $false; $s.rendered = $false } }
    Start-Refresh
}

# ---------------- Provider management ----------------
function Toggle-Provider($id) {
    $h = @($script:cfg.hidden | Where-Object { $_ })
    if ($h -contains $id) { $h = @($h | Where-Object { $_ -ne $id }) } else { $h += $id }
    $script:cfg.hidden = $h
    Save-Settings
    Apply-Visibility
    $s = $script:sites[$id]
    if (Is-Shown $s) { Start-Site $s $true }
}

function Doc-Path($base) {
    $p = Join-Path $Root ("docs\{0}.{1}.txt" -f $base, $script:lang)
    if (-not (Test-Path $p)) { $p = Join-Path $Root ("docs\{0}.en.txt" -f $base) }
    return $p
}

function Add-Tool {
    New-Item -ItemType Directory -Force -Path $UserProviders | Out-Null
    $tpl = Join-Path $Root 'providers\_template.js'
    $dst = Join-Path $UserProviders '_template.js'
    if ((Test-Path $tpl) -and -not (Test-Path $dst)) { Copy-Item $tpl $dst }
    Start-Process explorer.exe $UserProviders
    $guide = Doc-Path 'adding-ai-tools'
    if (Test-Path $guide) { Start-Process notepad.exe $guide }
}

function Show-Help {
    $p = Doc-Path 'guide'
    if (Test-Path $p) { Start-Process notepad.exe $p }
}

function Set-Lang($l) {
    $script:cfg.lang = $l
    Save-Settings
    Restart-App
}

function Restart-App {
    $script:relaunch = $true
    Exit-App
}

# ---------------- Shortcuts / startup / uninstall ----------------
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) $ShortcutName
$DesktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName
$ProgramsLnk = Join-Path ([Environment]::GetFolderPath('Programs')) $ShortcutName
function New-Shortcut($path) {
    $ws = New-Object -ComObject WScript.Shell
    $l = $ws.CreateShortcut($path)
    $l.TargetPath = "$env:WINDIR\System32\conhost.exe"
    $l.Arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"$script:ScriptPath`""
    $l.WorkingDirectory = $Root
    $l.Description = 'AI Usage Widget'
    $ico = Join-Path $Root 'app.ico'; if (Test-Path $ico) { $l.IconLocation = $ico }
    $l.Save()
}
function Toggle-AutoStart {
    try { if (Test-Path $StartupLnk) { Remove-Item $StartupLnk -Force } else { New-Shortcut $StartupLnk } }
    catch { Write-Log $_; [System.Windows.MessageBox]::Show((T 'autoFail'), (T 'trayText')) | Out-Null }
}

function Uninstall-App {
    $r = [System.Windows.MessageBox]::Show((T 'uninstallQ'), (T 'uninstallT'), 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    foreach ($p in @($StartupLnk, $DesktopLnk, $ProgramsLnk)) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    [System.Windows.MessageBox]::Show((T 'uninstallDone'), (T 'uninstallT')) | Out-Null
    # Delete the data folder after this process has exited. The installer puts the app in
    # %LOCALAPPDATA%\AIUsageWidget\app, so this removes the program and the sign-in data together.
    Start-Process cmd.exe -ArgumentList "/c timeout /t 6 /nobreak >nul & rmdir /s /q `"$DataDir`"" -WindowStyle Hidden
    $script:noSave = $true
    Exit-App
}

# ---------------- Menu (shared by right-click and tray) ----------------
function Get-MenuDefs {
    $loginSub = @(); $showSub = @(); $disabledSub = @(); $logoutSub = @()
    foreach ($s in $script:sites.Values) {
        if ($s.type -eq 'unavailable') {
            $disabledSub += @{ t = "$($s.name)  —  $($s.reason)"; dis = $true; tip = (T 'cantShow' $s.name $s.reason) }
            continue
        }
        $loginSub += @{ t = "$($s.name)"; a = [scriptblock]::Create("Open-Login `$script:sites['$($s.id)']") }
        $showSub += @{ t = "$($s.name)"; c = (Is-Shown $s); a = [scriptblock]::Create("Toggle-Provider '$($s.id)'") }
        if ($s.everOk -and $s.core) { $logoutSub += @{ t = "$($s.name)"; a = [scriptblock]::Create("Logout-Site '$($s.id)'") } }
    }
    if ($loginSub.Count -eq 0) { $loginSub = @(@{ t = (T 'mNoTools'); dis = $true }) }
    if ($logoutSub.Count -eq 0) { $logoutSub = @(@{ t = (T 'mNoLogged'); dis = $true }) }
    if ($disabledSub.Count -gt 0) {
        $showSub += @{ sep = $true }
        $showSub += @{ t = (T 'mUnavailable'); dis = $true }
        $showSub += $disabledSub
    }
    $showSub += @{ sep = $true }
    $showSub += @{ t = (T 'mAddTool'); a = { Add-Tool } }
    $showSub += @{ t = (T 'mReload'); a = { Restart-App } }

    $op = [double]$script:cfg.opacity
    $cl = "$($script:cfg.lang)"
    return @(
        @{ t = (T 'mRefresh'); a = { Start-Refresh } },
        @{ t = (T 'mSignIn'); sub = $loginSub },
        @{ t = (T 'mShow'); sub = $showSub },
        @{ sep = $true },
        @{ t = (T 'mTop'); c = [bool]$script:cfg.topmost; a = { $script:cfg.topmost = -not $script:cfg.topmost; $win.Topmost = $script:cfg.topmost; Save-Settings } },
        @{ t = (T 'mOpacity'); sub = @(
            @{ t = (T 'mOpSolid'); c = ([math]::Abs($op - 1.0) -lt 0.01); a = { $script:cfg.opacity = 1.0; $win.Opacity = 1.0; Save-Settings } },
            @{ t = (T 'mOpNormal'); c = ([math]::Abs($op - 0.92) -lt 0.01); a = { $script:cfg.opacity = 0.92; $win.Opacity = 0.92; Save-Settings } },
            @{ t = (T 'mOpLight'); c = ([math]::Abs($op - 0.7) -lt 0.01); a = { $script:cfg.opacity = 0.7; $win.Opacity = 0.7; Save-Settings } }
        ) },
        @{ t = (T 'mLang'); sub = @(
            @{ t = (T 'mLangAuto'); c = ($cl -ne 'ko' -and $cl -ne 'en'); a = { Set-Lang 'auto' } },
            @{ t = '한국어'; c = ($cl -eq 'ko'); a = { Set-Lang 'ko' } },
            @{ t = 'English'; c = ($cl -eq 'en'); a = { Set-Lang 'en' } }
        ) },
        @{ t = (T 'mAutostart'); c = (Test-Path $StartupLnk); a = { Toggle-AutoStart } },
        @{ t = (T 'mDesktop'); a = { New-Shortcut $DesktopLnk } },
        @{ sep = $true },
        @{ t = (T 'mHide'); a = { Toggle-Shown } },
        @{ t = (T 'mLogoutAll'); a = { Logout-All } },
        @{ t = (T 'mLogout'); sub = $logoutSub },
        @{ sep = $true },
        @{ t = (T 'mHelp'); a = { Show-Help } },
        @{ t = (T 'mUninstall'); a = { Uninstall-App } },
        @{ t = (T 'mExit'); a = { Exit-App } }
    )
}

function Add-WpfItems($items, $defs) {
    foreach ($d in $defs) {
        if ($d.sep) { [void]$items.Add((New-Object System.Windows.Controls.Separator)); continue }
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $d.t
        if ($d.sub) { Add-WpfItems $mi.Items $d.sub; [void]$items.Add($mi); continue }
        if ($d.tip) { $mi.ToolTip = $d.tip; [System.Windows.Controls.ToolTipService]::SetShowOnDisabled($mi, $true) }
        if ($d.dis) { $mi.IsEnabled = $false; [void]$items.Add($mi); continue }
        if ($d.ContainsKey('c')) { $mi.IsCheckable = $true; $mi.IsChecked = $d.c }
        $mi.Tag = $d.a
        $mi.Add_Click({ param($m, $e) try { & $m.Tag } catch { Write-Log $_ } })
        [void]$items.Add($mi)
    }
}
function Build-WpfMenu {
    $m = New-Object System.Windows.Controls.ContextMenu
    Add-WpfItems $m.Items (Get-MenuDefs)
    return $m
}

function Add-TrayItems($items, $defs) {
    foreach ($d in $defs) {
        if ($d.sep) { [void]$items.Add((New-Object System.Windows.Forms.ToolStripSeparator)); continue }
        $it = New-Object System.Windows.Forms.ToolStripMenuItem $d.t
        if ($d.sub) { Add-TrayItems $it.DropDownItems $d.sub; [void]$items.Add($it); continue }
        if ($d.tip) { $it.ToolTipText = $d.tip }
        if ($d.dis) { $it.Enabled = $false; [void]$items.Add($it); continue }
        if ($d.ContainsKey('c')) { $it.Checked = $d.c }
        $it.Tag = $d.a
        $it.Add_Click({ param($m, $e) try { & $m.Tag } catch { Write-Log $_ } })
        [void]$items.Add($it)
    }
}

function Toggle-Shown { if ($win.IsVisible) { $win.Hide() } else { $win.Show(); $win.Activate() } }

$ui.Card.ContextMenu = Build-WpfMenu
$ui.Card.Add_ContextMenuOpening({ $ui.Card.ContextMenu = Build-WpfMenu })

$tray = New-Object System.Windows.Forms.NotifyIcon
$icoPath = Join-Path $Root 'app.ico'
if (Test-Path $icoPath) { $tray.Icon = New-Object System.Drawing.Icon $icoPath } else { $tray.Icon = [System.Drawing.SystemIcons]::Information }
$tray.Text = T 'trayText'
$tray.ContextMenuStrip = New-Object System.Windows.Forms.ContextMenuStrip
$tray.ContextMenuStrip.Add_Opening({
    $tray.ContextMenuStrip.Items.Clear()
    Add-TrayItems $tray.ContextMenuStrip.Items (Get-MenuDefs)
})
$tray.Add_MouseClick({ param($t, $e) if ($e.Button -eq 'Left') { Toggle-Shown } })
$tray.Visible = $true

function Exit-App {
    if ($script:quit) { return }
    $script:quit = $true
    if (-not $script:noSave) { $script:cfg.left = [int]$win.Left; $script:cfg.top = [int]$win.Top; Save-Settings }
    $timer.Stop()
    $tray.Visible = $false; $tray.Dispose()
    if ($script:loginWin) { try { $script:loginWin.Close() } catch {} }
    # close the browsers properly so the sign-in cookies are flushed to disk
    foreach ($s in $script:sites.Values) { if ($s.ctl) { try { $s.ctl.Close() } catch {} } }
    Start-Sleep -Milliseconds 800
    $win.Close()
}

# ---------------- Start ----------------
Build-Boxes
$win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$win.Add_LocationChanged({ $script:cfg.left = [int]$win.Left; $script:cfg.top = [int]$win.Top })
$win.Add_Closing({ param($w, $e) if (-not $script:quit) { $e.Cancel = $true; $win.Hide() } })
$win.Add_Loaded({ Start-Refresh; $timer.Start() })

$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$app.Add_SessionEnding({ Exit-App })
$win.Add_Closed({ $app.Shutdown() })
$win.Show()
[void]$app.Run()
try { $script:mutex.ReleaseMutex() } catch {}

if ($script:relaunch) {
    Start-Process "$env:WINDIR\System32\conhost.exe" -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"$script:ScriptPath`""
}
