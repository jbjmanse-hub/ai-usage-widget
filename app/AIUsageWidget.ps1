# AI 사용량 위젯 (PowerShell 판)
# 구독형 AI 도구의 사용 한도를 내장 브라우저(WebView2) 로그인으로 조회합니다.
# AI 도구는 providers 폴더의 .js 파일 하나가 도구 하나입니다.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ScriptPath = $PSCommandPath
$Lib = Join-Path $Root 'lib'
$DataDir = Join-Path $env:LOCALAPPDATA 'AIUsageWidget'
$UserProviders = Join-Path $DataDir 'providers'
$SettingsPath = Join-Path $DataDir 'settings.json'
$LogPath = Join-Path $DataDir 'error.log'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Write-Log($msg) {
    try { Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}
$script:debug = Test-Path (Join-Path $DataDir 'debug')
function Trace($m) { if ($script:debug) { Write-Log "TRACE $m" } }

# ---------------- 중복 실행 방지 ----------------
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\AIUsageWidget_ps', [ref]$created)
if (-not $created) {
    # 재시작 직후라면 이전 프로세스가 끝날 때까지 잠깐 기다린다
    try { $created = $script:mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $created = $true }
    if (-not $created) {
        [System.Windows.MessageBox]::Show("AI 사용량 위젯이 이미 실행 중입니다.`n작업 표시줄 오른쪽 트레이 아이콘을 확인하세요.", 'AI 사용량 위젯') | Out-Null
        exit
    }
}

# ---------------- WebView2 불러오기 ----------------
try {
    Add-Type -Path (Join-Path $Lib 'Microsoft.Web.WebView2.Core.dll')
    Add-Type -Path (Join-Path $Lib 'Microsoft.Web.WebView2.Wpf.dll')
    $arch = 'x64'; if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
    [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath((Join-Path $Lib $arch))
} catch {
    Write-Log $_
    [System.Windows.MessageBox]::Show("WebView2 구성 파일을 불러오지 못했습니다.`nlib 폴더가 함께 있는지 확인하세요.`n`n$($_.Exception.Message)", 'AI 사용량 위젯') | Out-Null
    exit
}
$script:envTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, (Join-Path $DataDir 'WebView'), $null)
$script:env = $null

# ---------------- 설정 ----------------
function Load-Settings {
    $d = [ordered]@{ left = -1; top = -1; opacity = 0.92; topmost = $true; refresh_seconds = 60; hidden = @(); known = @(); links = @() }
    $s = $null
    if (Test-Path $SettingsPath) { try { $s = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    if (-not $s) { $s = [pscustomobject]@{} }
    foreach ($k in $d.Keys) { if (-not ($s.PSObject.Properties.Name -contains $k)) { $s | Add-Member -NotePropertyName $k -NotePropertyValue $d[$k] } }
    # 이전 버전 설정 옮기기
    $h = @($s.hidden | Where-Object { $_ })
    if ($s.PSObject.Properties.Name -contains 'show_chatgpt') { if (-not $s.show_chatgpt) { $h += 'chatgpt' }; $s.PSObject.Properties.Remove('show_chatgpt') }
    if ($s.PSObject.Properties.Name -contains 'show_claude') { if (-not $s.show_claude) { $h += 'claude' }; $s.PSObject.Properties.Remove('show_claude') }
    $s.hidden = @($h | Select-Object -Unique)
    $s.known = @($s.known | Where-Object { $_ } | Select-Object -Unique)
    $s.links = @($s.links | Where-Object { $_ -and $_.url })
    return $s
}
function Save-Settings { try { $script:cfg | ConvertTo-Json | Set-Content $SettingsPath -Encoding UTF8 } catch {} }
$script:cfg = Load-Settings

# ---------------- AI 도구(provider) 불러오기 ----------------
function New-Site($id, $meta, $js) {
    $hostUrl = $meta['host']
    $homeUrl = $meta['home']; if (-not $homeUrl) { $homeUrl = ([Uri]$hostUrl).GetLeftPart('Authority') + '/' }
    $loginUrl = $meta['login']; if (-not $loginUrl) { $loginUrl = $homeUrl }
    $color = $meta['color']; if (-not $color) { $color = '#8AB4F8' }
    # 로그아웃할 때 지울 도메인 (기본: host의 기본 도메인, 예: www.perplexity.ai → perplexity.ai)
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

# 바로가기 카드: 사용량 조회 없이 사이트만 열어주는 카드 (코드 불필요)
function New-LinkSite($id, $name, $color, $url, $note, $builtin, $reason) {
    if (-not $color) { $color = '#8AB4F8' }
    if (-not $note) { $note = '바로가기' }
    if (-not $reason) { $reason = '사용량 조회 기능이 없음' }
    return @{
        type = 'link'; builtin = [bool]$builtin; reason = $reason
        id = $id; name = $name; color = $color; url = $url; note = $note
        phase = 'idle'; rendered = $false; everOk = $false
        box = $null; title = $null; rows = $null; resets = @(); spinner = $null; ctl = $null; core = $null
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
                if (-not $meta['name'] -or -not $meta['host']) { Write-Log "AI 도구 건너뜀 (@name/@host 없음): $($f.FullName)"; continue }
                [void][Uri]$meta['host']
                $site = New-Site $id $meta $text
                $site.builtin = ($dir -eq $builtinDir)
                $list[$id] = $site
            } catch { Write-Log "AI 도구 불러오기 실패: $($f.FullName) - $($_.Exception.Message)" }
        }
    }
    # 기본 바로가기 카드
    $lj = Join-Path $builtinDir 'links.json'
    if (Test-Path $lj) {
        try {
            # PowerShell 5.1의 ConvertFrom-Json은 배열을 한 덩어리로 넘기므로 변수에 담은 뒤 하나씩 꺼낸다
            $arr = [IO.File]::ReadAllText($lj, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($l in $arr) {
                if (-not $l.id -or $l.id -isnot [string]) { continue }
                if (-not $list.Contains($l.id)) { $list[$l.id] = New-LinkSite $l.id $l.name $l.color $l.url $l.note $true $l.reason }
            }
        } catch { Write-Log "links.json 읽기 실패: $($_.Exception.Message)" }
    }
    # 사용자가 추가한 바로가기 카드
    foreach ($l in @($script:cfg.links)) {
        if ($l.id -and -not $list.Contains($l.id)) { $list[$l.id] = New-LinkSite $l.id $l.name $l.color $l.url '' $false }
    }
    return $list
}
$script:sites = Load-Providers

# 처음 보는 기본 도구는 ChatGPT·Claude만 표시하고 나머지는 숨김 (우클릭 → 표시할 AI에서 켜기)
$DefaultShown = @('chatgpt', 'claude')
$changed = $false
foreach ($s in $script:sites.Values) {
    if (@($script:cfg.known) -contains $s.id) { continue }
    if ($s.builtin -and -not ($DefaultShown -contains $s.id)) { $script:cfg.hidden = @($script:cfg.hidden) + $s.id }
    $script:cfg.known = @($script:cfg.known) + $s.id
    $changed = $true
}
if ($changed) { Save-Settings }

function Is-Shown($s) {
    if ($s.type -eq 'link') { return $false }   # 사용량 조회 기능이 없는 서비스는 표시하지 않음
    return -not (@($script:cfg.hidden) -contains $s.id)
}

# ---------------- UI ----------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI 사용량 위젯" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight" ShowInTaskbar="False"
        FontFamily="Segoe UI, Malgun Gothic">
  <Border Name="Card" CornerRadius="12" Background="#E61B1D24" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="14,10,14,10">
    <StackPanel Width="250">
      <DockPanel Margin="0,0,0,2" LastChildFill="True">
        <Border Name="RefreshBtn" DockPanel.Dock="Right" Width="22" Height="22" CornerRadius="11" Background="#00FFFFFF"
                Cursor="Hand" ToolTip="지금 새로고침" Margin="6,-2,-4,0">
          <TextBlock Name="RefreshIcon" Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#BBFFFFFF"
                     HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
            <TextBlock.RenderTransform><RotateTransform Angle="0"/></TextBlock.RenderTransform>
          </TextBlock>
        </Border>
        <TextBlock Name="Updated" DockPanel.Dock="Right" Foreground="#88FFFFFF" FontSize="10" VerticalAlignment="Center"/>
        <TextBlock Text="AI 구독 사용량" Foreground="#FFFFFF" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
      </DockPanel>
      <StackPanel Name="Services"/>
      <TextBlock Name="EmptyHint" Text="표시할 AI가 없습니다.&#x0a;우클릭 → [표시할 AI]에서 골라주세요." Foreground="#99FFFFFF"
                 FontSize="11" Margin="0,8,0,2" TextWrapping="Wrap" Visibility="Collapsed"/>
    </StackPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Card', 'Updated', 'RefreshBtn', 'RefreshIcon', 'Services', 'EmptyHint') { $ui[$n] = $win.FindName($n) }
$ui.RefreshRot = $ui.RefreshIcon.RenderTransform

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

function Add-Box($s) {
    $box = New-Object System.Windows.Controls.StackPanel
    $title = TB $s.name $s.color 12
    $title.FontWeight = 'SemiBold'; $title.Margin = '0,10,0,2'
    $rows = New-Object System.Windows.Controls.StackPanel
    [void]$box.Children.Add($title); [void]$box.Children.Add($rows)
    [void]$ui.Services.Children.Add($box)
    $s.box = $box; $s.title = $title; $s.rows = $rows
}

function Build-Boxes {
    $ui.Services.Children.Clear()
    foreach ($s in $script:sites.Values) { Add-Box $s }
    Apply-Visibility
}

function Render-Link($s) {
    $s.rows.Children.Clear()
    $s.rendered = $true
    $row = New-Object System.Windows.Controls.DockPanel
    $row.Margin = '0,2,0,0'
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = '열기'; $btn.Padding = '10,1,10,1'; $btn.FontSize = 11; $btn.Tag = $s.url
    $btn.Add_Click({ param($b, $e) try { Start-Process $b.Tag } catch { Write-Log $_ } })
    [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
    [void]$row.Children.Add($btn)
    $tb = TB $s.note '#99FFFFFF' 10.5
    $tb.VerticalAlignment = 'Center'; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,0,6,0'
    [void]$row.Children.Add($tb)
    [void]$s.rows.Children.Add($row)
}

function Apply-Visibility {
    $first = $true
    foreach ($s in $script:sites.Values) {
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
    if ($ts.TotalSeconds -le 0) { return '곧 리셋' }
    if ($ts.TotalDays -ge 1) { return ('리셋 {0}일 {1}시간 후  ({2:M/d HH:mm})' -f [int][math]::Floor($ts.TotalDays), $ts.Hours, $dt) }
    if ($ts.TotalHours -ge 1) { return ('리셋 {0}시간 {1}분 후  ({2:HH:mm})' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $dt) }
    return ('리셋 {0}분 후  ({1:HH:mm})' -f [math]::Max(1, $ts.Minutes), $dt)
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
    $lb = TB '불러오는 중…' '#BBFFFFFF' 11
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
        $btn.Content = '로그인'; $btn.Padding = '10,1,10,1'; $btn.FontSize = 11; $btn.Tag = $s.id
        $btn.Add_Click({ param($b, $e) Open-Login $script:sites[$b.Tag] })
        [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
        [void]$row.Children.Add($btn)
        $tb = TB '로그인이 필요합니다' '#BBFFFFFF' 11
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
        [void]$panel.Children.Add((TB '표시할 한도 정보가 없습니다' '#99FFFFFF' 11))
        return
    }
    foreach ($r in $res.rows) {
        if ($null -eq $r.pct) {
            # 퍼센트 없이 값만 있는 줄 (예: 남음 23회)
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
        $p = TB ('남음 {0}%  (사용 {1}%)' -f [math]::Round(100 - $pct), [math]::Round($pct)) $color 11
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

# ---------------- 조회 상태 머신 (타이머가 틱마다 진행) ----------------
$script:helper = New-Object System.Windows.Window
$script:helperHwnd = (New-Object System.Windows.Interop.WindowInteropHelper $script:helper).EnsureHandle()
$script:lastFetch = [datetime]::MinValue
$script:roundActive = $false

function Set-RoundActive {
    if ($script:roundActive) { return }
    $script:roundActive = $true
    $script:lastFetch = Get-Date
    $ui.Updated.Text = '갱신 중…'
    $ui.RefreshIcon.Foreground = Brush '#66FFFFFF'
}

function Start-Site($s, [bool]$showLoading = $false) {
    if (-not $s -or -not (Is-Shown $s)) { return }
    if ($s.type -eq 'link') { if (-not $s.rendered) { Render-Link $s }; return }
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
        # 쓰던 중에 로그인이 풀렸을 때만 알림
        $s.notified = $true
        try { $tray.ShowBalloonTip(8000, 'AI 사용량 위젯', "$($s.name) 로그인이 만료됐습니다. 위젯의 [로그인] 버튼으로 다시 로그인하세요.", 'Info') } catch {}
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
                if ($script:envTask.IsFaulted) { Finish-Site $s @{ ok = $false; err = 'WebView2 런타임이 없습니다. Microsoft Edge WebView2를 설치하세요.' }; return }
                if ($script:envTask.IsCompleted) { $script:env = $script:envTask.Result } else { return }
            }
            if (-not $s.ctl) {
                $s.ctlTask = $script:env.CreateCoreWebView2ControllerAsync($script:helperHwnd)
                $s.phase = 'creating'; return
            }
            # 처음 시작할 때 / 보안확인 필요할 때 / 12시간마다: 메인 페이지를 열어 보안확인 통과 + 로그인 연장
            if ($s.needHome -or ($s.everOk -and ((Get-Date) - $s.lastHome).TotalHours -ge 12)) { Nav $s $s.home 'home'; return }
            if (-not $s.ready) { Nav $s $s.host 'navigating'; return }
            $arg = @{ expression = $s.js; awaitPromise = $true; returnByValue = $true } | ConvertTo-Json -Compress
            $s.evalTask = $s.core.CallDevToolsProtocolMethodAsync('Runtime.evaluate', $arg)
            $s.t0 = Get-Date
            $s.phase = 'evaluating'
        }
        'creating' {
            if (-not $s.ctlTask.IsCompleted) { return }
            if ($s.ctlTask.IsFaulted) { Write-Log $s.ctlTask.Exception; Finish-Site $s @{ ok = $false; err = '내장 브라우저를 만들지 못했습니다' }; return }
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
                if ($elapsed -gt 25) { Finish-Site $s @{ ok = $false; err = '응답 시간 초과' } }
                return
            }
            if ($s.evalTask.IsFaulted) { Write-Log $s.evalTask.Exception; Finish-Site $s @{ ok = $false; err = '불러오기 실패' }; return }
            try {
                $o = $s.evalTask.Result | ConvertFrom-Json
                if ($o.exceptionDetails -or -not $o.result.value) {
                    Write-Log ("{0} 스크립트 오류: {1}" -f $s.name, $s.evalTask.Result)
                    Finish-Site $s @{ ok = $false; err = '조회 스크립트 오류 (error.log 참고)' }; return
                }
                $v = $o.result.value | ConvertFrom-Json
                if ($v.cf) {
                    if ($s.cfRetry -lt 1) { $s.cfRetry++; $s.needHome = $true; $s.ready = $false; $s.phase = 'start'; return }
                    Finish-Site $s @{ ok = $false; err = '사이트 보안 확인을 통과하지 못했습니다. 잠시 후 다시 시도합니다.' }; return
                }
                if ($v.login) { Finish-Site $s @{ ok = $false; login = $true; why = "$($v.why)" }; return }
                if ($v.err) { Finish-Site $s @{ ok = $false; err = "$($v.err)" }; return }
                Finish-Site $s @{ ok = $true; plan = "$($v.plan)"; rows = @($v.rows) }
            } catch { Write-Log $_; Finish-Site $s @{ ok = $false; err = '응답을 해석하지 못했습니다' } }
        }
    }
}

$script:spin = 0
$script:lastCountdown = Get-Date
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    try {
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
                $ui.Updated.Text = (Get-Date).ToString('HH:mm') + ' 갱신'
            }
        }

        if (((Get-Date) - $script:lastFetch).TotalSeconds -ge [math]::Max(30, [double]$script:cfg.refresh_seconds)) { Start-Refresh }

        if (((Get-Date) - $script:lastCountdown).TotalSeconds -ge 1) {
            $script:lastCountdown = Get-Date
            foreach ($s in $script:sites.Values) { foreach ($x in @($s.resets)) { if ($x) { $x[0].Text = Format-Reset $x[1] } } }
        }
    } catch { Write-Log $_ }
})

# ---------------- 새로고침 버튼 ----------------
$ui.RefreshBtn.Add_MouseEnter({ $ui.RefreshBtn.Background = Brush '#22FFFFFF' })
$ui.RefreshBtn.Add_MouseLeave({ $ui.RefreshBtn.Background = Brush '#00FFFFFF' })
$ui.RefreshBtn.Add_MouseLeftButtonDown({ param($b, $e) $e.Handled = $true })
$ui.RefreshBtn.Add_MouseLeftButtonUp({ param($b, $e) $e.Handled = $true; Start-Refresh })

# ---------------- 로그인 창 ----------------
$script:loginWin = $null
function Open-Login($site) {
    if (-not $site) { return }
    if ($script:loginWin) { $script:loginWin.Activate(); return }
    if (-not $script:env) {
        if ($script:envTask.IsCompleted -and -not $script:envTask.IsFaulted) { $script:env = $script:envTask.Result }
        else { [System.Windows.MessageBox]::Show('내장 브라우저 준비 중입니다. 잠시 후 다시 눌러주세요.', 'AI 사용량 위젯') | Out-Null; return }
    }
    $w = New-Object System.Windows.Window
    $w.Title = "$($site.name) 로그인"; $w.Width = 500; $w.Height = 760; $w.WindowStartupLocation = 'CenterScreen'
    $ico = Join-Path $Root 'app.ico'; if (Test-Path $ico) { try { $w.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$ico) } catch {} }
    $dock = New-Object System.Windows.Controls.DockPanel
    $bar = New-Object System.Windows.Controls.DockPanel
    $bar.Background = Brush '#1B1D24'
    $done = New-Object System.Windows.Controls.Button
    $done.Content = '로그인 완료'; $done.Padding = '14,4,14,4'; $done.Margin = '8'; $done.FontWeight = 'SemiBold'
    $done.Add_Click({ $script:loginWin.Close() })
    [System.Windows.Controls.DockPanel]::SetDock($done, 'Right')
    [void]$bar.Children.Add($done)
    $msg = TB "아래에서 $($site.name)에 로그인한 뒤 [로그인 완료]를 누르세요." '#FFFFFF' 12
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
        # 로그인한 도구를 바로 다시 조회하고, 그동안 "불러오는 중" 표시
        $s = $script:loginSite
        $s.ready = $false; $s.cfRetry = 0
        Start-Site $s $true
    })
    $script:loginWin = $w
    $w.Show()
}

# 비동기 작업 완료 대기 목록 (타이머가 완료된 것을 처리)
$script:pending = New-Object System.Collections.ArrayList
function When($task, [scriptblock]$then, $state) { [void]$script:pending.Add(@{ t = $task; f = $then; s = $state }) }

function Logout-Site($id) {
    $s = $script:sites[$id]
    if (-not $s -or -not $s.core) { return }
    $r = [System.Windows.MessageBox]::Show("위젯에 저장된 $($s.name) 로그인 정보를 지울까요?`n(다른 AI 도구의 로그인은 그대로 유지됩니다)", "$($s.name) 로그아웃", 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    When ($s.core.CallDevToolsProtocolMethodAsync('Network.getAllCookies', '{}')) {
        param($t, $s)
        if ($t.IsFaulted) { Write-Log $t.Exception; return }
        $n = 0
        foreach ($c in @(($t.Result | ConvertFrom-Json).cookies)) {
            if (-not $c) { continue }
            $dom = "$($c.domain)".TrimStart('.')
            $match = $false
            foreach ($d in $s.domains) { if ($dom -eq $d -or $dom.EndsWith('.' + $d)) { $match = $true } }
            if (-not $match) { continue }
            $arg = @{ name = $c.name; domain = $c.domain; path = $c.path } | ConvertTo-Json -Compress
            [void]$s.core.CallDevToolsProtocolMethodAsync('Network.deleteCookies', $arg)
            $n++
        }
        foreach ($o in $s.origins) {
            [void]$s.core.CallDevToolsProtocolMethodAsync('Storage.clearDataForOrigin', (@{ origin = $o; storageTypes = 'all' } | ConvertTo-Json -Compress))
        }
        Trace ("{0} 로그아웃: 쿠키 {1}개 삭제" -f $s.name, $n)
        $s.ready = $false; $s.needHome = $true; $s.everOk = $false; $s.notified = $true; $s.rendered = $false
        Start-Site $s $true
    } $s
}

function Logout-All {
    $r = [System.Windows.MessageBox]::Show('이 PC의 위젯에 저장된 모든 AI 도구의 로그인 정보를 지울까요?', '모든 계정 로그아웃', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $core = $null
    foreach ($s in $script:sites.Values) { if ($s.core) { $core = $s.core } }
    if ($core) {
        try { [void]$core.Profile.ClearBrowsingDataAsync() } catch { Write-Log $_ }
    }
    foreach ($s in $script:sites.Values) { $s.ready = $false; $s.needHome = $true; $s.everOk = $false; $s.rendered = $false }
    Start-Refresh
}

# ---------------- AI 도구 관리 ----------------
function Toggle-Provider($id) {
    $h = @($script:cfg.hidden | Where-Object { $_ })
    if ($h -contains $id) { $h = @($h | Where-Object { $_ -ne $id }) } else { $h += $id }
    $script:cfg.hidden = $h
    Save-Settings
    Apply-Visibility
    $s = $script:sites[$id]
    if (Is-Shown $s) { Start-Site $s $true }
}

function Add-Tool {
    New-Item -ItemType Directory -Force -Path $UserProviders | Out-Null
    $tpl = Join-Path $Root 'providers\_template.js'
    $dst = Join-Path $UserProviders '_template.js'
    if ((Test-Path $tpl) -and -not (Test-Path $dst)) { Copy-Item $tpl $dst }
    Start-Process explorer.exe $UserProviders
    $guide = Join-Path $Root 'AI도구_추가방법.txt'
    if (Test-Path $guide) { Start-Process notepad.exe $guide }
}

function Add-Link {
    $w = New-Object System.Windows.Window
    $w.Title = '바로가기 카드 추가'; $w.Width = 400; $w.SizeToContent = 'Height'
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'; $w.Topmost = $true
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '16'
    $info = New-Object System.Windows.Controls.TextBlock
    $info.Text = "사용량은 표시되지 않고, 위젯에서 [열기]를 누르면 해당 사이트가 열리는 카드입니다."
    $info.TextWrapping = 'Wrap'; $info.Margin = '0,0,0,12'; $info.Foreground = [System.Windows.Media.Brushes]::DimGray
    [void]$sp.Children.Add($info)
    $l1 = New-Object System.Windows.Controls.TextBlock; $l1.Text = '이름 (예: Gemini)'
    $nameBox = New-Object System.Windows.Controls.TextBox; $nameBox.Margin = '0,4,0,10'; $nameBox.Padding = '4'
    $l2 = New-Object System.Windows.Controls.TextBlock; $l2.Text = '열 주소 (예: https://gemini.google.com)'
    $urlBox = New-Object System.Windows.Controls.TextBox; $urlBox.Margin = '0,4,0,14'; $urlBox.Padding = '4'
    foreach ($c in $l1, $nameBox, $l2, $urlBox) { [void]$sp.Children.Add($c) }
    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = '추가'; $ok.Padding = '16,4,16,4'; $ok.IsDefault = $true
    $cancel = New-Object System.Windows.Controls.Button; $cancel.Content = '취소'; $cancel.Padding = '16,4,16,4'; $cancel.Margin = '8,0,0,0'; $cancel.IsCancel = $true
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($cancel)
    [void]$sp.Children.Add($btns)
    $w.Content = $sp
    $script:linkDlg = @{ w = $w; name = $nameBox; url = $urlBox }
    $ok.Add_Click({
        $d = $script:linkDlg
        $n = $d.name.Text.Trim(); $u = $d.url.Text.Trim()
        if (-not $n) { [System.Windows.MessageBox]::Show('이름을 입력하세요.', '바로가기 카드 추가') | Out-Null; return }
        if ($u -and $u -notmatch '^https?://') { $u = 'https://' + $u }
        $uri = $null
        if (-not [Uri]::TryCreate($u, 'Absolute', [ref]$uri)) { [System.Windows.MessageBox]::Show('주소가 올바르지 않습니다.', '바로가기 카드 추가') | Out-Null; return }
        $id = 'link-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:cfg.links = @($script:cfg.links) + [pscustomobject]@{ id = $id; name = $n; url = $uri.AbsoluteUri }
        $script:cfg.known = @($script:cfg.known) + $id
        Save-Settings
        $s = New-LinkSite $id $n '' $uri.AbsoluteUri '' $false
        $script:sites[$id] = $s
        Add-Box $s
        Apply-Visibility
        Render-Link $s
        $d.w.Close()
    })
    [void]$w.ShowDialog()
}

function Remove-Link($id) {
    $s = $script:sites[$id]
    if (-not $s) { return }
    $r = [System.Windows.MessageBox]::Show("'$($s.name)' 바로가기 카드를 삭제할까요?", '바로가기 카드 삭제', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $script:cfg.links = @($script:cfg.links | Where-Object { $_.id -ne $id })
    Save-Settings
    [void]$ui.Services.Children.Remove($s.box)
    $script:sites.Remove($id)
    Apply-Visibility
}

function Restart-App {
    $script:relaunch = $true
    Exit-App
}

# ---------------- 자동 실행 / 바로가기 ----------------
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'AI 사용량 위젯.lnk'
$DesktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AI 사용량 위젯.lnk'
function New-Shortcut($path) {
    $ws = New-Object -ComObject WScript.Shell
    $l = $ws.CreateShortcut($path)
    $l.TargetPath = "$env:WINDIR\System32\conhost.exe"
    $l.Arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"$script:ScriptPath`""
    $l.WorkingDirectory = $Root
    $ico = Join-Path $Root 'app.ico'; if (Test-Path $ico) { $l.IconLocation = $ico }
    $l.Save()
}
function Toggle-AutoStart { if (Test-Path $StartupLnk) { Remove-Item $StartupLnk -Force } else { New-Shortcut $StartupLnk } }

# ---------------- 메뉴 (우클릭 / 트레이 공용) ----------------
function Get-MenuDefs {
    $loginSub = @()
    $showSub = @()
    $disabledSub = @()
    foreach ($s in $script:sites.Values) {
        if ($s.type -eq 'link') {
            # 사용량 조회 기능이 없는 서비스: 회색으로 이유와 함께 표시, 선택 불가
            $disabledSub += @{ t = "$($s.name)  —  $($s.reason)"; dis = $true; tip = "$($s.name)은(는) $($s.reason) 위젯에 표시할 수 없습니다." }
            continue
        }
        $loginSub += @{ t = "$($s.name)"; a = [scriptblock]::Create("Open-Login `$script:sites['$($s.id)']") }
        $showSub += @{ t = "$($s.name)"; c = (Is-Shown $s); a = [scriptblock]::Create("Toggle-Provider '$($s.id)'") }
    }
    if ($disabledSub.Count -gt 0) {
        $showSub += @{ sep = $true }
        $showSub += @{ t = '사용량 조회 불가'; dis = $true }
        $showSub += $disabledSub
    }
    if ($loginSub.Count -eq 0) { $loginSub = @(@{ t = '(로그인할 AI 도구 없음)'; dis = $true }) }
    # 지금 로그인돼 있는 도구만 하나씩 로그아웃
    $logoutSub = @()
    foreach ($s in $script:sites.Values) {
        if ($s.type -eq 'usage' -and $s.everOk -and $s.core) {
            $logoutSub += @{ t = "$($s.name)"; a = [scriptblock]::Create("Logout-Site '$($s.id)'") }
        }
    }
    if ($logoutSub.Count -eq 0) { $logoutSub = @(@{ t = '(로그인된 AI 도구 없음)'; dis = $true }) }
    $showSub += @{ sep = $true }
    $showSub += @{ t = 'AI 도구 파일 추가하기 (고급)…'; a = { Add-Tool } }
    $showSub += @{ t = 'AI 도구 목록 다시 불러오기'; a = { Restart-App } }

    $op = [double]$script:cfg.opacity
    return @(
        @{ t = '지금 새로고침'; a = { Start-Refresh } },
        @{ t = '로그인'; sub = $loginSub },
        @{ t = '표시할 AI'; sub = $showSub },
        @{ sep = $true },
        @{ t = '항상 위에 표시'; c = [bool]$script:cfg.topmost; a = { $script:cfg.topmost = -not $script:cfg.topmost; $win.Topmost = $script:cfg.topmost; Save-Settings } },
        @{ t = '투명도'; sub = @(
            @{ t = '진하게'; c = ([math]::Abs($op - 1.0) -lt 0.01); a = { $script:cfg.opacity = 1.0; $win.Opacity = 1.0; Save-Settings } },
            @{ t = '보통'; c = ([math]::Abs($op - 0.92) -lt 0.01); a = { $script:cfg.opacity = 0.92; $win.Opacity = 0.92; Save-Settings } },
            @{ t = '연하게'; c = ([math]::Abs($op - 0.7) -lt 0.01); a = { $script:cfg.opacity = 0.7; $win.Opacity = 0.7; Save-Settings } }
        ) },
        @{ t = 'Windows 시작 시 자동 실행'; c = (Test-Path $StartupLnk); a = { Toggle-AutoStart } },
        @{ t = '바탕화면에 바로가기 만들기'; a = { New-Shortcut $DesktopLnk } },
        @{ sep = $true },
        @{ t = '위젯 숨기기/보이기'; a = { Toggle-Shown } },
        @{ t = '모든 계정 로그아웃'; a = { Logout-All } },
        @{ t = '로그아웃'; sub = $logoutSub },
        @{ t = '종료'; a = { Exit-App } }
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
$tray.Text = 'AI 사용량 위젯'
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
    $script:cfg.left = [int]$win.Left; $script:cfg.top = [int]$win.Top; Save-Settings
    $timer.Stop()
    $tray.Visible = $false; $tray.Dispose()
    if ($script:loginWin) { try { $script:loginWin.Close() } catch {} }
    # 내장 브라우저를 정상 종료해 로그인 쿠키가 디스크에 확실히 기록되게 한다
    foreach ($s in $script:sites.Values) { if ($s.ctl) { try { $s.ctl.Close() } catch {} } }
    Start-Sleep -Milliseconds 800
    $win.Close()
}

# ---------------- 시작 ----------------
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
