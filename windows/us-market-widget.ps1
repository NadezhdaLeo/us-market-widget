<#
    US Market Widget
    Always-on-top desktop indicator of US stock market sessions (NYSE / Nasdaq) for Windows.

    Phases (ET = New York time):
      04:00 - 09:30  Pre-market
      09:30 - 16:00  Regular session (open)
      16:00 - 20:00  After-hours
      otherwise      Closed (incl. weekends and NYSE holidays)
    Early-close days: close at 13:00, after-hours until 17:00.

    Start:  Start-Widget.cmd   (or: powershell -ExecutionPolicy Bypass -File us-market-widget.ps1)
    Stop:   Stop-Widget.cmd    (or: tray icon -> Exit)
    Logic self-test without UI:  powershell -ExecutionPolicy Bypass -File us-market-widget.ps1 -Test
#>
[CmdletBinding()]
param(
    [switch]$Test
)

$ErrorActionPreference = 'Stop'

# ============================ SETTINGS ======================================

# Regular NYSE holidays and early-close days are COMPUTED from the official rules
# (see "NYSE CALENDAR RULES" below) - nothing to maintain.
#
# Unscheduled closures (national days of mourning etc.) cannot be predicted by any rule.
# Add them here, format yyyy-MM-dd, e.g. '2025-01-09'.
$ExtraClosures = @(
)

# Phase colors
$Colors = @{
    Closed = '#8A8F98'
    Pre    = '#F2B01E'
    Open   = '#2ECC71'
    After  = '#3B8BEB'
}

# Phase labels
$PhaseTitle = @{
    Closed = 'CLOSED'
    Pre    = 'PRE-MARKET'
    Open   = 'OPEN'
    After  = 'AFTER-HOURS'
}

# Name of the transition INTO a phase
$TransitionTitle = @{
    Pre    = 'Pre-market'
    Open   = 'Open'
    After  = 'Close'
    Closed = 'After-hours end'
}

# Start blinking this many minutes before the regular open
$BlinkBeforeOpenMinutes = 5

# Saved window position
$PosFile = Join-Path $env:APPDATA 'USMarketWidget\position.json'

# ============================ LOGIC =========================================

$Tz = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
$Inv = [Globalization.CultureInfo]::InvariantCulture

# ---------------------------- NYSE CALENDAR RULES ---------------------------

function Get-Easter([int]$y) {
    # Gregorian Easter Sunday (anonymous algorithm)
    $a = $y % 19
    $b = [int][math]::Floor($y / 100); $c = $y % 100
    $d = [int][math]::Floor($b / 4);   $e = $b % 4
    $f = [int][math]::Floor(($b + 8) / 25)
    $g = [int][math]::Floor(($b - $f + 1) / 3)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [int][math]::Floor($c / 4);   $k = $c % 4
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    $m = [int][math]::Floor(($a + 11 * $h + 22 * $l) / 451)
    $month = [int][math]::Floor(($h + $l - 7 * $m + 114) / 31)
    $day = (($h + $l - 7 * $m + 114) % 31) + 1
    return New-Object DateTime $y, $month, $day
}

function Get-NthWeekday([int]$y, [int]$m, [DayOfWeek]$wd, [int]$n) {
    $first = New-Object DateTime $y, $m, 1
    $off = ([int]$wd - [int]$first.DayOfWeek + 7) % 7
    return $first.AddDays($off + 7 * ($n - 1))
}

function Get-LastWeekday([int]$y, [int]$m, [DayOfWeek]$wd) {
    $last = (New-Object DateTime $y, $m, 1).AddMonths(1).AddDays(-1)
    $off = ([int]$last.DayOfWeek - [int]$wd + 7) % 7
    return $last.AddDays(-$off)
}

function Get-Observed([DateTime]$d) {
    # Saturday -> Friday before, Sunday -> Monday after
    if ($d.DayOfWeek -eq 'Saturday') { return $d.AddDays(-1) }
    if ($d.DayOfWeek -eq 'Sunday')   { return $d.AddDays(1) }
    return $d
}

$script:HolidayCache = @{}
$script:EarlyCache = @{}

function Get-NyseHolidays([int]$y) {
    if ($script:HolidayCache.ContainsKey($y)) { return $script:HolidayCache[$y] }
    $h = New-Object System.Collections.Generic.HashSet[string]
    $ny = New-Object DateTime $y, 1, 1
    # NYSE rule: when New Year's Day falls on Saturday the market stays open on Friday Dec 31.
    if ($ny.DayOfWeek -eq 'Sunday') { [void]$h.Add($ny.AddDays(1).ToString('yyyy-MM-dd')) }
    elseif ($ny.DayOfWeek -ne 'Saturday') { [void]$h.Add($ny.ToString('yyyy-MM-dd')) }
    [void]$h.Add((Get-NthWeekday $y 1 Monday 3).ToString('yyyy-MM-dd'))            # Martin Luther King Jr. Day
    [void]$h.Add((Get-NthWeekday $y 2 Monday 3).ToString('yyyy-MM-dd'))            # Presidents' Day
    [void]$h.Add((Get-Easter $y).AddDays(-2).ToString('yyyy-MM-dd'))               # Good Friday
    [void]$h.Add((Get-LastWeekday $y 5 Monday).ToString('yyyy-MM-dd'))             # Memorial Day
    if ($y -ge 2022) { [void]$h.Add((Get-Observed (New-Object DateTime $y, 6, 19)).ToString('yyyy-MM-dd')) }  # Juneteenth
    [void]$h.Add((Get-Observed (New-Object DateTime $y, 7, 4)).ToString('yyyy-MM-dd'))   # Independence Day
    [void]$h.Add((Get-NthWeekday $y 9 Monday 1).ToString('yyyy-MM-dd'))            # Labor Day
    [void]$h.Add((Get-NthWeekday $y 11 Thursday 4).ToString('yyyy-MM-dd'))         # Thanksgiving
    [void]$h.Add((Get-Observed (New-Object DateTime $y, 12, 25)).ToString('yyyy-MM-dd'))  # Christmas
    $script:HolidayCache[$y] = $h
    return $h
}

function Get-NyseEarlyCloses([int]$y) {
    if ($script:EarlyCache.ContainsKey($y)) { return $script:EarlyCache[$y] }
    $e = New-Object System.Collections.Generic.HashSet[string]
    $hol = Get-NyseHolidays $y
    [void]$e.Add((Get-NthWeekday $y 11 Thursday 4).AddDays(1).ToString('yyyy-MM-dd'))  # day after Thanksgiving
    foreach ($d in @((New-Object DateTime $y, 7, 3), (New-Object DateTime $y, 12, 24))) {  # eve of Independence Day / Christmas
        $key = $d.ToString('yyyy-MM-dd')
        if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday' -and -not $hol.Contains($key)) { [void]$e.Add($key) }
    }
    $script:EarlyCache[$y] = $e
    return $e
}

function Test-TradingDay([DateTime]$d) {
    if ($d.DayOfWeek -eq 'Saturday' -or $d.DayOfWeek -eq 'Sunday') { return $false }
    $key = $d.ToString('yyyy-MM-dd')
    if ((Get-NyseHolidays $d.Year).Contains($key)) { return $false }
    if ($ExtraClosures -contains $key) { return $false }
    return $true
}

function Test-EarlyClose([DateTime]$d) {
    return (Get-NyseEarlyCloses $d.Year).Contains($d.ToString('yyyy-MM-dd'))
}

# Phase boundaries for a given date (ET). Empty list on a non-trading day.
function Get-DayBoundaries([DateTime]$d) {
    $day = $d.Date
    if (-not (Test-TradingDay $day)) { return @() }
    $closeH = 16; $ahEndH = 20
    if (Test-EarlyClose $day) { $closeH = 13; $ahEndH = 17 }
    return @(
        @{ At = $day.AddHours(4);                Phase = 'Pre' },
        @{ At = $day.AddHours(9).AddMinutes(30); Phase = 'Open' },
        @{ At = $day.AddHours($closeH);          Phase = 'After' },
        @{ At = $day.AddHours($ahEndH);          Phase = 'Closed' }
    )
}

function Get-NextTradingDay([DateTime]$d) {
    $x = $d.Date.AddDays(1)
    while (-not (Test-TradingDay $x)) { $x = $x.AddDays(1) }
    return $x
}

# Market state at $nowEt (ET wall-clock time, Kind = Unspecified)
function Get-MarketState([DateTime]$nowEt) {
    $phase = 'Closed'
    $nextAt = $null
    $nextPhase = $null

    foreach ($b in (Get-DayBoundaries $nowEt)) {
        if ($b.At -le $nowEt) {
            $phase = $b.Phase
        } elseif ($null -eq $nextAt) {
            $nextAt = $b.At
            $nextPhase = $b.Phase
        }
    }
    if ($null -eq $nextAt) {
        $nd = Get-NextTradingDay $nowEt
        $nextAt = $nd.AddHours(4)
        $nextPhase = 'Pre'
    }

    # Nearest regular-session open
    $openAt = $null
    $probe = $nowEt.Date
    for ($i = 0; $i -lt 15 -and $null -eq $openAt; $i++) {
        foreach ($b in (Get-DayBoundaries $probe)) {
            if ($b.Phase -eq 'Open' -and $b.At -gt $nowEt) { $openAt = $b.At; break }
        }
        $probe = $probe.AddDays(1)
    }

    $isWeekday = ($nowEt.DayOfWeek -ne 'Saturday' -and $nowEt.DayOfWeek -ne 'Sunday')
    return @{
        Phase        = $phase
        NextAt       = $nextAt
        NextPhase    = $nextPhase
        OpenAt       = $openAt
        IsHoliday    = ($isWeekday -and -not (Test-TradingDay $nowEt))
        IsEarlyClose = (Test-EarlyClose $nowEt)
    }
}

function Get-NowEt {
    return [TimeZoneInfo]::ConvertTime([DateTime]::Now, $Tz)
}

function ConvertTo-Local([DateTime]$et) {
    $u = [DateTime]::SpecifyKind($et, 'Unspecified')
    return [TimeZoneInfo]::ConvertTime($u, $Tz, [TimeZoneInfo]::Local)
}

function Format-Span([TimeSpan]$ts) {
    if ($ts.Ticks -lt 0) { $ts = [TimeSpan]::Zero }
    if ($ts.TotalDays -ge 1) {
        return ('{0}d {1}h {2:D2}m' -f [int][math]::Floor($ts.TotalDays), $ts.Hours, $ts.Minutes)
    }
    if ($ts.TotalHours -ge 1) {
        return ('{0}h {1:D2}m' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes)
    }
    return ('{0}m {1:D2}s' -f $ts.Minutes, $ts.Seconds)
}

# "09:30 ET / 15:30 local" (+ weekday and date when not today)
function Format-When([DateTime]$et, [DateTime]$nowEt) {
    $loc = ConvertTo-Local $et
    $s = '{0} ET / {1} local' -f $et.ToString('HH:mm'), $loc.ToString('HH:mm')
    if ($et.Date -ne $nowEt.Date) {
        $s = '{0} {1}, {2}' -f $et.ToString('ddd', $Inv), $et.ToString('dd MMM', $Inv), $s
    }
    return $s
}

# ============================ SELF-TEST =====================================

if ($Test) {
    $samples = @(
        (Get-NowEt),
        [DateTime]'2026-09-23 03:59',
        [DateTime]'2026-09-23 04:00',
        [DateTime]'2026-09-23 09:29',
        [DateTime]'2026-09-23 09:30',
        [DateTime]'2026-09-23 15:59',
        [DateTime]'2026-09-23 16:00',
        [DateTime]'2026-09-23 19:59',
        [DateTime]'2026-09-23 20:00',
        [DateTime]'2026-09-25 21:00',   # Friday evening -> Monday
        [DateTime]'2026-09-26 12:00',   # Saturday
        [DateTime]'2026-11-26 12:00',   # Thanksgiving
        [DateTime]'2026-11-27 12:59',   # early close
        [DateTime]'2026-11-27 13:00',
        [DateTime]'2026-12-24 17:00'    # early close, after-hours end -> Mon 28 Dec
    )
    'Now ET: {0}   local: {1}' -f (Get-NowEt).ToString('yyyy-MM-dd HH:mm:ss'), (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ''
    foreach ($y in 2024..2028) {
        $hl = @(Get-NyseHolidays $y | Sort-Object | ForEach-Object { ([DateTime]$_).ToString('ddd dd MMM', $Inv) })
        $el = @(Get-NyseEarlyCloses $y | Sort-Object | ForEach-Object { ([DateTime]$_).ToString('ddd dd MMM', $Inv) })
        '{0} holidays:      {1}' -f $y, ($hl -join ', ')
        '{0} early closes:  {1}' -f $y, ($el -join ', ')
    }
    ''
    '{0,-18} {1,-8} {2,-30} {3,-18} {4}' -f 'ET now', 'Phase', 'Next', 'At (ET)', 'Flags'
    foreach ($s in $samples) {
        $st = Get-MarketState $s
        $flags = @()
        if ($st.IsHoliday) { $flags += 'holiday' }
        if ($st.IsEarlyClose) { $flags += 'early' }
        '{0,-18} {1,-8} {2,-30} {3,-18} {4}' -f $s.ToString('ddd dd.MM HH:mm', $Inv), $st.Phase, ($TransitionTitle[$st.NextPhase] + ' in ' + (Format-Span ($st.NextAt - $s))), $st.NextAt.ToString('ddd dd.MM HH:mm', $Inv), ($flags -join ',')
    }
    exit 0
}

# ============================ SINGLE INSTANCE ===============================

$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\USMarketWidget')
if (-not $script:Mutex.WaitOne(0, $false)) {
    # Another instance is already running - do nothing.
    exit 0
}

# ============================ UI ============================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="US Market" Width="290" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Border x:Name="Root" CornerRadius="10" Background="#F0202124" Padding="14,12,14,12"
          BorderBrush="#40FFFFFF" BorderThickness="1" Cursor="SizeAll">
    <Border.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="MenuHide" Header="Hide to tray"/>
        <MenuItem x:Name="MenuTop"  Header="Always on top" IsCheckable="True" IsChecked="True"/>
        <Separator/>
        <MenuItem x:Name="MenuExit" Header="Exit"/>
      </ContextMenu>
    </Border.ContextMenu>
    <StackPanel>
      <DockPanel LastChildFill="True">
        <TextBlock x:Name="CloseBtn" DockPanel.Dock="Right" Text="✕" FontSize="12"
                   Foreground="#80FFFFFF" Cursor="Hand" VerticalAlignment="Center"
                   Margin="8,0,0,0" ToolTip="Hide to tray"/>
        <Ellipse x:Name="Dot" Width="14" Height="14" Fill="#8A8F98" VerticalAlignment="Center" Margin="0,0,10,0"/>
        <TextBlock x:Name="PhaseText" Text="…" FontSize="17" FontWeight="SemiBold" Foreground="White" VerticalAlignment="Center"/>
      </DockPanel>
      <TextBlock x:Name="NextText" Foreground="#E0FFFFFF" FontSize="12.5" Margin="0,9,0,0" TextWrapping="Wrap"/>
      <TextBlock x:Name="OpenText" Foreground="#A0FFFFFF" FontSize="11.5" Margin="0,3,0,0" TextWrapping="Wrap"/>
      <TextBlock x:Name="NoteText" Foreground="#F2B01E" FontSize="11.5" Margin="0,5,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
      <TextBlock x:Name="ClockText" Foreground="#70FFFFFF" FontSize="11" Margin="0,8,0,0"/>
    </StackPanel>
  </Border>
</Window>
"@

$script:Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $Xaml))
$script:Ui = @{}
foreach ($n in 'Root','Dot','PhaseText','NextText','OpenText','NoteText','ClockText','CloseBtn','MenuHide','MenuTop','MenuExit') {
    $script:Ui[$n] = $script:Window.FindName($n)
}

function ConvertTo-Brush([string]$hex) {
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}
$script:Brushes = @{}
foreach ($k in $Colors.Keys) { $script:Brushes[$k] = ConvertTo-Brush $Colors[$k] }

# --- Tray icon ----------------------------------------------------------------
function New-DotIcon([string]$hex) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex))
    $g.FillEllipse($brush, 1, 1, 14, 14)
    $g.Dispose(); $brush.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $bmp.Dispose()
    return $icon
}

$script:Tray = New-Object System.Windows.Forms.NotifyIcon
$script:Tray.Text = 'US Market'
$script:Tray.Icon = New-DotIcon $Colors.Closed
$script:Tray.Visible = $true

function Show-Widget {
    $script:Window.Show()
    $script:Window.Activate() | Out-Null
}
function Hide-Widget { $script:Window.Hide() }
function Toggle-Widget {
    if ($script:Window.IsVisible) { Hide-Widget } else { Show-Widget }
}
function Exit-Widget {
    $script:Exiting = $true
    $script:Window.Close()
}

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miToggle = $trayMenu.Items.Add('Show / hide')
$miToggle.Add_Click({ Toggle-Widget })
$trayMenu.Items.Add('-') | Out-Null
$miExit = $trayMenu.Items.Add('Exit')
$miExit.Add_Click({ Exit-Widget })
$script:Tray.ContextMenuStrip = $trayMenu
$script:Tray.Add_MouseClick({ if ($args[1].Button -eq 'Left') { Toggle-Widget } })

# --- Refresh -------------------------------------------------------------------
$script:LastPhase = $null

function Update-Ui {
    $nowEt = Get-NowEt
    $st = Get-MarketState $nowEt
    $phase = $st.Phase

    $ui = $script:Ui
    $ui.PhaseText.Text = $PhaseTitle[$phase]

    $untilNext = $st.NextAt - $nowEt
    $ui.NextText.Text = '{0} in {1}  ({2})' -f $TransitionTitle[$st.NextPhase], (Format-Span $untilNext), (Format-When $st.NextAt $nowEt)

    if ($phase -eq 'Open' -or $null -eq $st.OpenAt) {
        $ui.OpenText.Visibility = 'Collapsed'
    } else {
        $ui.OpenText.Visibility = 'Visible'
        if ($st.NextPhase -eq 'Open') {
            $closeH = 16
            if (Test-EarlyClose $st.OpenAt) { $closeH = 13 }
            $ui.OpenText.Text = 'Regular session until {0}' -f (Format-When ($st.OpenAt.Date.AddHours($closeH)) $nowEt)
        } else {
            $ui.OpenText.Text = 'Next open: {0}' -f (Format-When $st.OpenAt $nowEt)
        }
    }

    $note = $null
    if ($st.IsHoliday) { $note = 'NYSE holiday today - market closed' }
    elseif ($st.IsEarlyClose) { $note = 'Early close today: 13:00 ET, after-hours until 17:00' }
    if ($note) { $ui.NoteText.Text = $note; $ui.NoteText.Visibility = 'Visible' } else { $ui.NoteText.Visibility = 'Collapsed' }

    $ui.ClockText.Text = 'New York {0}   ·   local {1}' -f $nowEt.ToString('HH:mm:ss'), (Get-Date).ToString('HH:mm:ss')

    # Blink shortly before the open
    $blink = ($st.NextPhase -eq 'Open' -and $untilNext.TotalMinutes -le $BlinkBeforeOpenMinutes -and $untilNext.Ticks -gt 0)
    if ($blink) {
        if ($nowEt.Second % 2 -eq 0) { $ui.Dot.Opacity = 1.0 } else { $ui.Dot.Opacity = 0.25 }
    } else {
        $ui.Dot.Opacity = 1.0
    }

    if ($phase -ne $script:LastPhase) {
        $ui.Dot.Fill = $script:Brushes[$phase]
        $old = $script:Tray.Icon
        $script:Tray.Icon = New-DotIcon $Colors[$phase]
        if ($old) { $old.Dispose() }
        $script:LastPhase = $phase
    }

    $tip = 'US Market: {0} · {1} in {2}' -f $PhaseTitle[$phase], $TransitionTitle[$st.NextPhase], (Format-Span $untilNext)
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $script:Tray.Text = $tip
}

# --- Window position -------------------------------------------------------------
function Save-Position {
    try {
        $dir = Split-Path $PosFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        @{ Left = $script:Window.Left; Top = $script:Window.Top; Topmost = $script:Window.Topmost } | ConvertTo-Json | Set-Content -Path $PosFile -Encoding UTF8
    } catch { }
}

function Restore-Position {
    $placed = $false
    try {
        if (Test-Path $PosFile) {
            $p = Get-Content $PosFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $va = [System.Windows.SystemParameters]::VirtualScreenWidth
            if ($p.Left -ge -50 -and $p.Left -lt $va -and $p.Top -ge -50) {
                $script:Window.Left = $p.Left
                $script:Window.Top = $p.Top
                $placed = $true
            }
            if ($null -ne $p.Topmost) {
                $script:Window.Topmost = [bool]$p.Topmost
                $script:Ui.MenuTop.IsChecked = [bool]$p.Topmost
            }
        }
    } catch { }
    if (-not $placed) {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $script:Window.Left = $wa.Right - $script:Window.ActualWidth - 16
        $script:Window.Top = $wa.Bottom - $script:Window.ActualHeight - 16
    }
}

# --- Events -------------------------------------------------------------------------
$script:Exiting = $false

$script:Window.Add_MouseLeftButtonDown({ try { $script:Window.DragMove() } catch { } })
$script:Ui.CloseBtn.Add_PreviewMouseLeftButtonDown({ $args[1].Handled = $true; Hide-Widget })
$script:Ui.MenuHide.Add_Click({ Hide-Widget })
$script:Ui.MenuExit.Add_Click({ Exit-Widget })
$script:Ui.MenuTop.Add_Click({ $script:Window.Topmost = $script:Ui.MenuTop.IsChecked })

$script:Window.Add_Loaded({
    Update-Ui
    $script:Window.UpdateLayout()
    Restore-Position
})

$script:Window.Add_Closing({
    if (-not $script:Exiting) {
        # Closing the window (Alt+F4) just hides it to the tray
        $args[1].Cancel = $true
        Hide-Widget
        return
    }
    Save-Position
})

$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromSeconds(1)
$script:Timer.Add_Tick({ try { Update-Ui } catch { } })
$script:Timer.Start()

$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$script:Window.Add_Closed({
    $script:Timer.Stop()
    $script:Tray.Visible = $false
    $script:Tray.Dispose()
    $script:Mutex.ReleaseMutex()
    $app.Shutdown()
})
$script:Window.Show()
$app.Run() | Out-Null
