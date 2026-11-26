#APPSTART
# ---------- keep helper console windows hidden (needed for the .exe version) ----------
try {
  Add-Type -Namespace PCOpt -Name Con -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("kernel32.dll")] public static extern bool AllocConsole();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
  if ([PCOpt.Con]::GetConsoleWindow() -eq [IntPtr]::Zero) { [void][PCOpt.Con]::AllocConsole() }
  [void][PCOpt.Con]::ShowWindow([PCOpt.Con]::GetConsoleWindow(), 0)
} catch { }
# ===================== PC OPTIMIZER (WPF) =====================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# ---------- shared state between window and background tasks ----------
$sync = [hashtable]::Synchronized(@{ Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]' })
$App  = [hashtable]::Synchronized(@{ Busy = $false; Job = $null })

# ---------- code available inside every background task ----------
$Prelude = @'
$ErrorActionPreference = 'SilentlyContinue'
function W([string]$t = '', [string]$c = 'Text') { $sync.Queue.Enqueue(@($t, $c)) }
function Head([string]$t) { W ''; W ("  ===== $t =====") 'Cyan' }
function SizeMB($paths) {
  $t = 0
  foreach ($p in $paths) {
    if ($p -and (Test-Path -LiteralPath $p)) {
      $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      if ($s) { $t += $s }
    }
  }
  [math]::Round($t / 1MB)
}
function Clear-Folder($p) {
  if (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
}
function Run-Cmd([string]$exe, [string[]]$a) {
  & $exe @a 2>&1 | ForEach-Object {
    $l = ("$_" -replace "`0", '').Trim()
    if ($l -and $l -notmatch '^\[=*\s*[\d\.]+%') { W ('  ' + $l) }
  }
}
function Fmt-Dur([double]$sec) {
  $ts = [TimeSpan]::FromSeconds($sec)
  if ($ts.TotalHours -ge 1) { return ('{0}h {1:00}m' -f [math]::Floor($ts.TotalHours), $ts.Minutes) }
  return ('{0}m' -f [math]::Floor($ts.TotalMinutes))
}
'@

# ===================== TASKS =====================
$T = @{}

$T.Temp = {
  Head 'CLEANING TEMP FILES'
  $paths = @($env:TEMP, "$env:SystemRoot\Temp")
  $b = SizeMB $paths
  foreach ($p in $paths) { Clear-Folder $p }
  $a = SizeMB $paths
  W ('  Freed about {0} MB.' -f [math]::Max(0, $b - $a)) 'Green'
  W '  Files still in use by open apps were skipped - that is normal.' 'Dim'
}

$T.Recycle = {
  Head 'EMPTYING RECYCLE BIN'
  Clear-RecycleBin -Force -ErrorAction SilentlyContinue
  W '  Done. Recycle Bin emptied.' 'Green'
}

$T.WU = {
  Head 'CLEANING WINDOWS UPDATE LEFTOVERS'
  $p = "$env:SystemRoot\SoftwareDistribution\Download"
  $b = SizeMB @($p)
  Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
  Clear-Folder $p
  Start-Service bits, wuauserv -ErrorAction SilentlyContinue
  $a = SizeMB @($p)
  W ('  Freed about {0} MB of old update downloads.' -f [math]::Max(0, $b - $a)) 'Green'
}

$T.DNS = {
  Head 'FLUSHING DNS'
  Run-Cmd 'ipconfig' @('/flushdns')
}

$T.RAM = {
  Head 'FREE UP RAM'
  W '  Trimming memory held by running apps. Please wait...' 'Dim'
  if (-not ('PCOptMem' -as [type])) {
    Add-Type -Namespace '' -Name PCOptMem -MemberDefinition @"
[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);
"@
  }
  $before = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB
  $count = 0
  foreach ($p in Get-Process) {
    try { $h = $p.Handle; if ($h -ne [IntPtr]::Zero) { [void][PCOptMem]::EmptyWorkingSet($h); $count++ } } catch { }
  }
  Start-Sleep -Milliseconds 900
  $after = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB
  $freed = [math]::Round($after - $before)
  W ('  Trimmed {0} running apps.' -f $count) 'Green'
  if ($freed -gt 0) { W ('  About {0} MB of RAM is now free that was in use before.' -f $freed) 'Green' }
  else { W '  RAM was already lean - little to free right now.' 'Dim' }
  W ('  Free memory now: {0:N0} MB' -f $after)
  W ''
  W '  How it works: it asks each app to release memory it is not actively using,' 'Dim'
  W '  so Windows can hand it to other apps. Apps may be slightly slow for a second' 'Dim'
  W '  afterwards as they reload what they need. Windows manages RAM well on its own,' 'Dim'
  W '  so use this when something felt heavy, not constantly.' 'Dim'
}

$T.Quick = {
  Head 'QUICK OPTIMIZE'
  W '  Step 1 of 3: temp files...' 'Dim'
  $paths = @($env:TEMP, "$env:SystemRoot\Temp")
  $b = SizeMB $paths; foreach ($p in $paths) { Clear-Folder $p }; $a = SizeMB $paths
  $f1 = [math]::Max(0, $b - $a)
  W ('  Temp files: freed {0} MB' -f $f1) 'Green'
  W '  Step 2 of 3: Windows Update leftovers...' 'Dim'
  $p = "$env:SystemRoot\SoftwareDistribution\Download"
  $b = SizeMB @($p)
  Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
  Clear-Folder $p
  Start-Service bits, wuauserv -ErrorAction SilentlyContinue
  $a = SizeMB @($p)
  $f2 = [math]::Max(0, $b - $a)
  W ('  Update leftovers: freed {0} MB' -f $f2) 'Green'
  W '  Step 3 of 3: DNS...' 'Dim'
  ipconfig /flushdns | Out-Null
  W '  DNS cache flushed' 'Green'
  W ''
  W ('  QUICK OPTIMIZE FINISHED - total freed about {0} MB' -f ($f1 + $f2)) 'Green'
}

$T.Ultimate = {
  Head 'ULTIMATE PERFORMANCE POWER PLAN'
  $g = $null
  $line = powercfg /list | Select-String 'Ultimate' | Select-Object -First 1
  if ($line -and ("$line" -match '([0-9a-fA-F\-]{36})')) { $g = $Matches[1] }
  if (-not $g) {
    $o = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
    if ("$o" -match '([0-9a-fA-F\-]{36})') { $g = $Matches[1] }
  }
  if ($g) {
    powercfg /setactive $g
    W '  Done. Ultimate Performance is now ON.' 'Green'
    W '  It uses more electricity. Use "Balanced power plan" to go back.' 'Dim'
  } else {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-cf48f0e6e5f2
    W '  Ultimate plan not available on this PC - switched to High Performance instead.' 'Yellow'
  }
}

$T.Balanced = {
  Head 'BALANCED POWER PLAN'
  powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
  W '  Done. Back to Balanced.' 'Green'
}

$T.Startup = {
  Head 'APPS THAT START WITH WINDOWS'
  $items = Get-CimInstance Win32_StartupCommand | Sort-Object Name
  if (-not $items) { W '  None found.' 'Dim' }
  foreach ($i in $items) { W ('  {0,-40} {1}' -f $i.Name, $i.Location) }
  W ''
  W '  Task Manager is opening - go to the Startup apps tab,' 'Yellow'
  W '  right-click anything you do not need and choose Disable.' 'Yellow'
  Start-Process taskmgr -ArgumentList '/0 /startup'
}

$T.Drives = {
  Head 'OPTIMIZING DRIVES'
  W '  SSDs get TRIM, hard drives get defragmented. Please wait...' 'Dim'
  $vols = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
  foreach ($v in $vols) {
    W ('  Drive {0}: working...' -f $v.DriveLetter)
    try { Optimize-Volume -DriveLetter $v.DriveLetter -ErrorAction Stop; W ('  Drive {0}: done' -f $v.DriveLetter) 'Green' }
    catch { W ('  Drive {0}: skipped ({1})' -f $v.DriveLetter, $_.Exception.Message) 'Yellow' }
  }
}

$T.Repair = {
  Head 'REPAIRING WINDOWS FILES'
  W '  This can take 10-30 minutes. You can keep using the PC.' 'Dim'
  W ''
  W '  Step 1 of 2: DISM (needs internet)' 'Cyan'
  Run-Cmd 'DISM.exe' @('/Online', '/Cleanup-Image', '/RestoreHealth')
  W ''
  W '  Step 2 of 2: System File Checker' 'Cyan'
  Run-Cmd 'sfc.exe' @('/scannow')
  W ''
  W '  Done. Restart your PC to finish any repairs.' 'Green'
}

$T.Restore = {
  Head 'CREATING A RESTORE POINT'
  Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
  try {
    Checkpoint-Computer -Description 'Before TuneBox PC' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    W '  Restore point created.' 'Green'
  } catch {
    W ('  Could not create it: ' + $_.Exception.Message) 'Red'
    W '  Note: Windows only allows one restore point every 24 hours.' 'Dim'
  }
}

$T.Health = {
  Head 'PC HEALTH CHECK'
  $o = Get-CimInstance Win32_OperatingSystem
  $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
  W ('  Windows : ' + $o.Caption)
  W ('  CPU     : ' + "$cpu".Trim())
  W ('  RAM     : {0:N1} GB free of {1:N1} GB' -f ($o.FreePhysicalMemory / 1MB), ($o.TotalVisibleMemorySize / 1MB))
  $up = (Get-Date) - $o.LastBootUpTime
  W ('  Uptime  : {0} days {1} hours' -f $up.Days, $up.Hours)
  W ''
  W '  DISKS' 'Cyan'
  Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    $pct = if ($_.Size) { [math]::Round(($_.Size - $_.FreeSpace) / $_.Size * 100) } else { 0 }
    $c = if ($pct -ge 90) { 'Red' } elseif ($pct -ge 75) { 'Yellow' } else { 'Green' }
    W ('  {0}  {1:N1} GB free of {2:N1} GB  ({3}% used)' -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB), $pct) $c
  }
  W ''
  W '  TOP 8 APPS USING RAM' 'Cyan'
  Get-Process | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; MB = [int](($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB) }
  } | Sort-Object MB -Descending | Select-Object -First 8 | ForEach-Object { W ('  {0,-32} {1,7} MB' -f $_.Name, $_.MB) }
  if ($up.Days -ge 3) { W ''; W '  Tip: the PC has not restarted in a while. A restart often speeds things up.' 'Yellow' }
}

$T.Disk = {
  Head 'DRIVE HEALTH CHECK'
  $disks = Get-PhysicalDisk | Sort-Object { [int]$_.DeviceId }
  if (-not $disks) { W '  Could not read drive info.' 'Red'; return }
  $TYPICAL_YEARS = 5
  $sysDisk = (Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1))).DiskNumber
  $osInstall = (Get-CimInstance Win32_OperatingSystem).InstallDate

  foreach ($d in $disks) {
    $r = $d | Get-StorageReliabilityCounter
    $type = "$($d.MediaType)"; $bus = "$($d.BusType)"
    $isSSD = ($type -eq 'SSD') -or ($bus -eq 'NVMe'); $isHDD = ($type -eq 'HDD')
    $problems = @()
    $hs = "$($d.HealthStatus)"
    $t = $null; if ($r.Temperature) { $t = [int]$r.Temperature }
    if ($isHDD) { $lim = 50 } else { $lim = 70 }
    $poh = $null; if ($r.PowerOnHours) { $poh = [int64]$r.PowerOnHours }
    $wear = $null; if ($isSSD -and $r.Wear -ne $null) { $wear = [int]$r.Wear }
    $re = [int64]$r.ReadErrorsUncorrected; $we = [int64]$r.WriteErrorsUncorrected

    $score = 100
    if ($wear -ne $null) { $score = 100 - $wear }
    if ($hs -eq 'Warning') { $score = [math]::Min($score, 60) } elseif ($hs -ne 'Healthy') { $score = [math]::Min($score, 20) }
    $score -= [math]::Min(40, ($re + $we) * 5)
    if ($t -ne $null -and $t -ge $lim) { $score -= 10 }
    $score = [math]::Max(0, [math]::Min(100, $score))
    if ($hs -eq 'Warning') { $problems += 'Windows says WARNING' } elseif ($hs -ne 'Healthy') { $problems += "Windows says $hs" }
    if ($score -ge 90) { $hc = 'Green' } elseif ($score -ge 50) { $hc = 'Yellow' } else { $hc = 'Red'; $problems += "low health ($score%)" }

    $ageDays = $null; $ageFrom = ''
    if ($poh) { $ageDays = $poh / 24; $ageFrom = 'power-on time' }
    elseif ($d.DeviceId -eq "$sysDisk" -and $osInstall) { $ageDays = ((Get-Date) - $osInstall).TotalDays; $ageFrom = 'Windows install date' }
    $daysLeft = $null; $how = ''
    if ($ageDays -ne $null -and $wear -ne $null -and $wear -gt 0) { $daysLeft = $ageDays * (100 - $wear) / $wear; $how = "based on wear so far + $ageFrom" }
    elseif ($ageDays -ne $null) { $daysLeft = ($TYPICAL_YEARS * 365) - $ageDays; $how = "typical $TYPICAL_YEARS-year life minus age from $ageFrom" }
    if ($daysLeft -ne $null) { $daysLeft = [math]::Max(0, [math]::Round($daysLeft)); if ($daysLeft -lt 180) { $problems += 'near end of life' } }

    W ''
    W ('  Disk {0}: {1}   ({2} GB, {3}, {4})' -f $d.DeviceId, "$($d.FriendlyName)".Trim(), [math]::Round($d.Size / 1GB), $type, $bus) 'White'
    W ('  Health status   : {0}%  ({1})' -f $score, $hs) $hc
    if ($t -ne $null) {
      if ($t -ge $lim) { $tc = 'Red'; $problems += "too hot ($t C)" } elseif ($t -ge ($lim - 8)) { $tc = 'Yellow' } else { $tc = 'Green' }
      W ('  Temperature     : {0} C   (too hot is {1} C+)' -f $t, $lim) $tc
    } else { W '  Temperature     : not reported by this drive' 'Dim' }
    if ($daysLeft -ne $null) {
      if ($daysLeft -ge 730) { $lsc = 'Green' } elseif ($daysLeft -ge 180) { $lsc = 'Yellow' } else { $lsc = 'Red' }
      W ('  Lifespan        : about {0:N0} days left  (~{1:N1} years)' -f $daysLeft, ($daysLeft / 365)) $lsc
      W ('                    estimate: {0}' -f $how) 'Dim'
    } else { W '  Lifespan        : not enough data from this drive to estimate' 'Dim' }
    if ($isSSD) {
      if ($wear -ne $null) {
        $left = 100 - $wear
        if ($left -ge 50) { $lc = 'Green' } elseif ($left -ge 20) { $lc = 'Yellow' } else { $lc = 'Red'; $problems += "only $left% lifetime left" }
        W ('  Lifetime left   : {0}%  (used {1}%)' -f $left, $wear) $lc
      } else { W '  Lifetime left   : not reported by this drive' 'Dim' }
    } else { W '  Lifetime left   : n/a for hard drives - go by lifespan and errors' 'Dim' }
    if (($re + $we) -gt 0) { $ec = 'Red'; $problems += 'has uncorrected read/write errors' } else { $ec = 'Green' }
    W ('  Bad errors      : read {0}, write {1}   (should be 0)' -f $re, $we) $ec

    $letter = (Get-Partition -DiskNumber $d.DeviceId | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
    if ($letter) {
      W ('  Performance     : testing drive {0}: ...' -f $letter) 'Dim'
      $out = winsat disk -seq -read -drive $letter 2>$null
      $line = $out | Select-String 'MB/s' | Select-Object -First 1
      if ($line -and ("$line" -match '([\d\.]+)\s*MB/s')) {
        $mbs = [double]$Matches[1]
        if ($bus -eq 'NVMe') { $exp = 1500 } elseif ($isSSD) { $exp = 450 } elseif ($bus -eq 'USB') { $exp = 80 } else { $exp = 100 }
        $pct = [math]::Min(100, [math]::Round($mbs / $exp * 100))
        if ($pct -ge 80) { $pc = 'Green' } elseif ($pct -ge 50) { $pc = 'Yellow' } else { $pc = 'Red'; $problems += 'slow read speed' }
        W ('  Performance     : about {0}%  ({1:N0} MB/s read, normal for this type is {2}+ MB/s)' -f $pct, $mbs, $exp) $pc
      } else { W '  Performance     : speed test did not run on this drive' 'Dim' }
    } else { W '  Performance     : no drive letter, speed test skipped' 'Dim' }

    if ($problems.Count -eq 0) { W '  VERDICT         : GOOD' 'Green' }
    else { W ('  VERDICT         : CHECK THIS DRIVE - ' + ($problems -join ', ')) 'Red' }
  }
  W ''
  W '  Health % and lifespan are estimates from what Windows can read.' 'Dim'
  W '  For exact numbers and bad-sector counts, use HD Sentinel or CrystalDiskInfo.' 'Dim'
}

$T.History = {
  function Rot13([string]$s) {
    -join ($s.ToCharArray() | ForEach-Object {
      $c = [int]$_
      if ($c -ge 65 -and $c -le 90) { [char](65 + (($c - 65 + 13) % 26)) }
      elseif ($c -ge 97 -and $c -le 122) { [char](97 + (($c - 97 + 13) % 26)) }
      else { $_ }
    })
  }
  function Clean-Name([string]$n) {
    if ($n -like '*!*') { $n = $n.Split('!')[0]; $n = $n.Split('_')[0]; $n = $n.Split('.')[-1] }
    $n = $n.Split('\')[-1]
    $n = $n -replace '\.(exe|lnk)$', ''
    return $n.Trim()
  }
  function Cut([string]$s, [int]$w) { if ($s.Length -gt $w) { return $s.Substring(0, $w - 2) + '..' } return $s }

  Head 'HOW LONG THIS PC HAS BEEN RUNNING'
  $os = Get-CimInstance Win32_OperatingSystem
  $boot = $os.LastBootUpTime
  $up = (Get-Date) - $boot
  W ('  Last full start : {0:ddd dd MMM yyyy, h:mm tt}' -f $boot)
  W ('  Running for     : {0} days {1} hours {2} minutes' -f $up.Days, $up.Hours, $up.Minutes)
  $fast = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled
  if ($fast -eq 1) { W '  Fast Startup is ON, so Shut down does not reset this. Only Restart does.' 'Dim' }

  $since = (Get-Date).Date.AddDays(-6)
  $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Id = 1, 12, 13, 42, 107, 6008 }
  $list = @()
  foreach ($e in $ev) {
    $p = $e.ProviderName; $st = $null; $txt = $null
    if ($p -eq 'Microsoft-Windows-Kernel-General' -and $e.Id -eq 12) { $st = 'ON'; $txt = 'Started up' }
    elseif ($p -eq 'Microsoft-Windows-Kernel-General' -and $e.Id -eq 13) { $st = 'OFF'; $txt = 'Shut down / restart' }
    elseif ($p -eq 'Microsoft-Windows-Kernel-Power' -and $e.Id -eq 42) { $st = 'OFF'; $txt = 'Sleep / shut down' }
    elseif ($p -eq 'Microsoft-Windows-Kernel-Power' -and $e.Id -eq 107) { $st = 'ON'; $txt = 'Woke up / started' }
    elseif ($p -eq 'Microsoft-Windows-Power-Troubleshooter' -and $e.Id -eq 1) { $st = 'ON'; $txt = 'Woke up from sleep' }
    elseif ($p -eq 'EventLog' -and $e.Id -eq 6008) { $st = 'X'; $txt = 'Last shutdown was NOT clean (crash or power cut)' }
    if ($st) { $list += [pscustomobject]@{ Time = $e.TimeCreated; State = $st; Text = $txt } }
  }
  $list = @($list | Sort-Object Time)

  $sessions = @(); $start = $null; $lastOn = $null
  foreach ($x in $list) {
    if ($x.State -eq 'ON') {
      if ($start -ne $null -and $lastOn -ne $null -and ($x.Time - $lastOn).TotalMinutes -le 3) { continue }
      $start = $x.Time; $lastOn = $x.Time
    } elseif ($x.State -eq 'OFF') {
      if ($start -eq $null -and $sessions.Count -eq 0) { $start = $since }
      if ($start -ne $null) { $sessions += [pscustomobject]@{ Start = $start; End = $x.Time }; $start = $null }
    }
  }
  if ($start -ne $null) { $sessions += [pscustomobject]@{ Start = $start; End = (Get-Date) } }
  if ($sessions.Count -eq 0 -and $list.Count -eq 0) { $sessions += [pscustomobject]@{ Start = [datetime]([math]::Max($boot.Ticks, $since.Ticks)); End = (Get-Date) } }

  Head 'TIME THE PC WAS ON (LAST 7 DAYS)'
  $total = 0
  for ($i = 0; $i -lt 7; $i++) {
    $d0 = $since.AddDays($i); $d1 = $d0.AddDays(1); $sec = 0
    foreach ($s in $sessions) {
      $a = if ($s.Start -gt $d0) { $s.Start } else { $d0 }
      $b = if ($s.End -lt $d1) { $s.End } else { $d1 }
      if ($b -gt $a) { $sec += ($b - $a).TotalSeconds }
    }
    $total += $sec
    $bar = [string]([char]0x2588) * [math]::Min(48, [math]::Round($sec / 1800))
    $label = '{0:ddd dd MMM}' -f $d0
    if ($d0 -eq (Get-Date).Date) { $label += ' (today)' }
    W ('  {0,-18} {1,8}  {2}' -f $label, (Fmt-Dur $sec), $bar) 'Green'
  }
  W ('  Total this week: {0}   (each block = 30 minutes)' -f (Fmt-Dur $total))

  Head 'RECENT ON / OFF EVENTS'
  $recent = $list | Select-Object -Last 12
  if (-not $recent) { W '  No power events found.' 'Dim' }
  foreach ($x in $recent) {
    $col = if ($x.State -eq 'ON') { 'Green' } elseif ($x.State -eq 'X') { 'Red' } else { 'Yellow' }
    W ('  {0:ddd dd MMM  h:mm tt}   {1}' -f $x.Time, $x.Text) $col
  }

  Head 'MOST USED APPS (time on screen)'
  $raw = @()
  Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' | ForEach-Object {
    $k = Get-Item ($_.PSPath + '\Count')
    if ($k) {
      foreach ($n in $k.GetValueNames()) {
        $b = $k.GetValue($n)
        if ($b -is [byte[]] -and $b.Length -ge 68) {
          $name = Clean-Name (Rot13 $n)
          if (-not $name -or $name -like 'UEME_*') { continue }
          $runs = [BitConverter]::ToInt32($b, 4)
          $focus = [BitConverter]::ToUInt32($b, 12)
          $ft = [BitConverter]::ToInt64($b, 60)
          $last = $null; if ($ft -gt 0) { $last = [DateTime]::FromFileTime($ft) }
          if ($runs -gt 0 -or $focus -gt 0) { $raw += [pscustomobject]@{ Name = $name; Runs = $runs; Focus = [double]$focus; Last = $last } }
        }
      }
    }
  }
  $apps = $raw | Group-Object { $_.Name.ToLower() } | ForEach-Object {
    [pscustomobject]@{
      Name  = $_.Group[0].Name
      Runs  = ($_.Group | Measure-Object Runs -Sum).Sum
      Focus = ($_.Group | Measure-Object Focus -Sum).Sum
      Last  = ($_.Group | Where-Object { $_.Last } | Sort-Object Last -Descending | Select-Object -First 1).Last
    }
  } | Sort-Object Focus, Runs -Descending | Select-Object -First 15
  if (-not $apps) { W '  No app usage records found for this user.' 'Dim' }
  else {
    W ('  {0,-28} {1,8} {2,12}   {3}' -f 'APP', 'OPENED', 'TIME USED', 'LAST OPENED') 'White'
    foreach ($a in $apps) {
      $lastTxt = if ($a.Last) { '{0:ddd dd MMM, h:mm tt}' -f $a.Last } else { '-' }
      W ('  {0,-28} {1,7}x {2,12}   {3}' -f (Cut $a.Name 28), $a.Runs, (Fmt-Dur ($a.Focus / 1000)), $lastTxt)
    }
  }

  Head 'RECENTLY OPENED APPS'
  $skip = 'SVCHOST','DLLHOST','RUNTIMEBROKER','BACKGROUNDTASKHOST','CONHOST','SEARCHPROTOCOLHOST','SEARCHFILTERHOST','WMIPRVSE','TASKHOSTW','SMARTSCREEN','SPPSVC','WUAUCLT','MUSNOTIFICATION','COMPATTELRUNNER','CONSENT','SIHCLIENT','TRUSTEDINSTALLER','TIWORKER','MPCMDRUN','MSMPENG','AUDIODG','WERFAULT','CMD','POWERSHELL','WINSAT','DEFRAG','FLTMC','NET','NET1','IPCONFIG','POWERCFG','FINDSTR','TIMEOUT','REG','ROBOCOPY','TASKLIST','FIND','WHOAMI','SC','RUNDLL32','SDIAGNHOST','MOBSYNC','USOCLIENT','MOUSOCOREWORKER','UPFC','DEVICECENSUS','DISMHOST','DISM','SFC','SEARCHINDEXER','SECURITYHEALTHSERVICE','SGRMBROKER','SIHOST','CTFMON','FONTDRVHOST','WUDFHOST','LOGONUI','USERINIT','WININIT','WINLOGON','CSRSS','SMSS','LSASS','SERVICES'
  $pf = Get-ChildItem "$env:SystemRoot\Prefetch\*.pf" | ForEach-Object {
    [pscustomobject]@{ Name = ($_.BaseName -replace '\.EXE-[0-9A-F]{8}$', '' -replace '-[0-9A-F]{8}$', ''); Last = $_.LastWriteTime }
  } | Where-Object { $skip -notcontains $_.Name.ToUpper() } |
    Group-Object Name | ForEach-Object { $_.Group | Sort-Object Last -Descending | Select-Object -First 1 } |
    Sort-Object Last -Descending | Select-Object -First 20
  if (-not $pf) { W '  No records found (Windows Prefetch may be turned off on this PC).' 'Dim' }
  else { foreach ($x in $pf) { W ('  {0:ddd dd MMM, h:mm tt}   {1}' -f $x.Last, $x.Name.ToLower()) } }

  W ''
  W '  On-time is worked out from Windows power records, so treat it as an estimate.' 'Dim'
  W '  "Time used" = time the app was the active window, for apps opened from Start,' 'Dim'
  W '  the taskbar or the desktop. Windows does not log every app.' 'Dim'
}


# ===================== DEBLOAT CATALOG =====================
# (used by the checklist window AND by the background task)
$CatalogCode = @'
$IFEO = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$CDM  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ADV  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$WUUX = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$ODP  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
$PCO  = Join-Path $env:ProgramData 'TuneBoxPC'

function Set-Reg($path, $name, $value, $type = 'DWord') {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}
function Del-Reg($path, $name) { Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue }

function Block-Exe([string[]]$exes) {
  if (-not (Test-Path $PCO)) { New-Item -ItemType Directory -Path $PCO -Force | Out-Null }
  $bp = Join-Path $PCO 'blocked.ps1'
  $msg = 'Add-Type -AssemblyName PresentationFramework; $n = if ($args) { [IO.Path]::GetFileName("$($args[0])".Trim([char]34)) } else { "This app" }; [void][System.Windows.MessageBox]::Show("$n is blocked on this PC.`n`nTo allow it again: open TuneBox PC > Debloat & block apps, untick it and click Apply.", "Blocked by TuneBox PC", "OK", "Information")'
  Set-Content -LiteralPath $bp -Value $msg -Encoding UTF8
  $dbg = '"' + $env:SystemRoot + '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bp + '"'
  foreach ($e in $exes) {
    Set-Reg "$IFEO\$e" 'Debugger' $dbg 'String'
    Stop-Process -Name ([IO.Path]::GetFileNameWithoutExtension($e)) -Force -ErrorAction SilentlyContinue
  }
}
function Unblock-Exe([string[]]$exes) { foreach ($e in $exes) { Del-Reg "$IFEO\$e" 'Debugger' } }
function Test-Blocked([string[]]$exes) {
  foreach ($e in $exes) { $v = (Get-ItemProperty -Path "$IFEO\$e" -ErrorAction SilentlyContinue).Debugger; if ("$v" -like '*TuneBoxPC*') { return $true } }
  return $false
}

function I($id, $group, $label, $note, $rec, $win, $data, $do, $undo, $test) {
  [pscustomobject]@{ Id = $id; Group = $group; Label = $label; Note = $note; Rec = $rec; Win = $win; Data = $data; Do = $do; Undo = $undo; Test = $test }
}

$Catalog = @(
  # ---------- REMOVE JUNK APPS ----------
  (I 'r_news'    'remove' 'Microsoft News'             '' $true  'all' @('Microsoft.BingNews') $null $null $null),
  (I 'r_weather' 'remove' 'Weather'                    '' $false 'all' @('Microsoft.BingWeather') $null $null $null),
  (I 'r_tips'    'remove' 'Tips'                       '' $true  'all' @('Microsoft.Getstarted') $null $null $null),
  (I 'r_help'    'remove' 'Get Help'                   '' $true  'all' @('Microsoft.GetHelp') $null $null $null),
  (I 'r_sol'     'remove' 'Solitaire Collection'       '' $true  'all' @('Microsoft.MicrosoftSolitaireCollection') $null $null $null),
  (I 'r_candy'   'remove' 'Candy Crush and King games' '' $true  'all' @('king.com.*') $null $null $null),
  (I 'r_disney'  'remove' 'Disney+'                    '' $true  'all' @('Disney.*') $null $null $null),
  (I 'r_spotify' 'remove' 'Spotify (preinstalled)'     '' $false 'all' @('SpotifyAB.SpotifyMusic') $null $null $null),
  (I 'r_office'  'remove' 'Microsoft 365 / Office hub' 'Only the ad app - does not touch real Office' $true 'all' @('Microsoft.MicrosoftOfficeHub') $null $null $null),
  (I 'r_clip'    'remove' 'Clipchamp'                  '' $true  'all' @('Clipchamp.Clipchamp') $null $null $null),
  (I 'r_feed'    'remove' 'Feedback Hub'               '' $true  'all' @('Microsoft.WindowsFeedbackHub') $null $null $null),
  (I 'r_maps'    'remove' 'Maps'                       '' $true  'all' @('Microsoft.WindowsMaps') $null $null $null),
  (I 'r_movies'  'remove' 'Movies and TV'              '' $true  'all' @('Microsoft.ZuneVideo') $null $null $null),
  (I 'r_people'  'remove' 'People'                     '' $true  'all' @('Microsoft.People') $null $null $null),
  (I 'r_skype'   'remove' 'Skype'                      '' $true  'all' @('Microsoft.SkypeApp') $null $null $null),
  (I 'r_mixed'   'remove' 'Mixed Reality Portal'       '' $true  'all' @('Microsoft.MixedReality.Portal') $null $null $null),
  (I 'r_pad'     'remove' 'Power Automate'             '' $true  'all' @('Microsoft.PowerAutomateDesktop') $null $null $null),
  (I 'r_dev'     'remove' 'Dev Home'                   '' $true  'all' @('Microsoft.Windows.DevHome') $null $null $null),
  (I 'r_family'  'remove' 'Microsoft Family'           '' $true  'all' @('MicrosoftCorporationII.MicrosoftFamily') $null $null $null),
  (I 'r_bing'    'remove' 'Bing Search app'            '' $true  'all' @('Microsoft.BingSearch') $null $null $null),
  (I 'r_cortana' 'remove' 'Cortana app'                '' $true  'all' @('Microsoft.549981C3F5F10') $null $null $null),
  (I 'r_teams'   'remove' 'Teams (personal)'           'Skip if you use Teams' $false 'all' @('MicrosoftTeams', 'MSTeams') $null $null $null),
  (I 'r_todo'    'remove' 'Microsoft To Do'            '' $false 'all' @('Microsoft.Todos') $null $null $null),
  (I 'r_outlook' 'remove' 'Outlook (new)'              'Skip if you use it for email' $false 'all' @('Microsoft.OutlookForWindows') $null $null $null),
  (I 'r_phone'   'remove' 'Phone Link'                 'Skip if you link your phone' $false 'all' @('Microsoft.YourPhone') $null $null $null),
  (I 'r_copilot' 'remove' 'Copilot app'                '' $false 'all' @('Microsoft.Copilot') $null $null $null),
  (I 'r_xbox'    'remove' 'Xbox app'                   'Skip if you play PC Game Pass games' $false 'all' @('Microsoft.GamingApp', 'Microsoft.XboxApp') $null $null $null),

  # ---------- ADS & SUGGESTIONS ----------
  (I 'a_start' 'ads' 'Start menu suggestions and recommended apps' '' $true 'all' $null `
    { Set-Reg $CDM 'SystemPaneSuggestionsEnabled' 0; Set-Reg $CDM 'SubscribedContent-338388Enabled' 0; Set-Reg $ADV 'Start_IrisRecommendations' 0; Set-Reg $ADV 'Start_AccountNotifications' 0 } `
    { Set-Reg $CDM 'SystemPaneSuggestionsEnabled' 1; Set-Reg $CDM 'SubscribedContent-338388Enabled' 1; Set-Reg $ADV 'Start_IrisRecommendations' 1; Set-Reg $ADV 'Start_AccountNotifications' 1 } $null),
  (I 'a_tips' 'ads' 'Tips and "get even more out of Windows" pop-ups' '' $true 'all' $null `
    { Set-Reg $CDM 'SoftLandingEnabled' 0; Set-Reg $CDM 'SubscribedContent-338389Enabled' 0; Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 } `
    { Set-Reg $CDM 'SoftLandingEnabled' 1; Set-Reg $CDM 'SubscribedContent-338389Enabled' 1; Del-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' } $null),
  (I 'a_lock' 'ads' 'Lock screen ads and fun facts' '' $true 'all' $null `
    { Set-Reg $CDM 'RotatingLockScreenOverlayEnabled' 0; Set-Reg $CDM 'SubscribedContent-338387Enabled' 0 } `
    { Set-Reg $CDM 'RotatingLockScreenOverlayEnabled' 1; Set-Reg $CDM 'SubscribedContent-338387Enabled' 1 } $null),
  (I 'a_settings' 'ads' 'Suggested content in Settings' '' $true 'all' $null `
    { Set-Reg $CDM 'SubscribedContent-338393Enabled' 0; Set-Reg $CDM 'SubscribedContent-353694Enabled' 0; Set-Reg $CDM 'SubscribedContent-353696Enabled' 0 } `
    { Set-Reg $CDM 'SubscribedContent-338393Enabled' 1; Set-Reg $CDM 'SubscribedContent-353694Enabled' 1; Set-Reg $CDM 'SubscribedContent-353696Enabled' 1 } $null),
  (I 'a_silent' 'ads' 'Auto-installing promoted apps (Candy Crush etc.)' '' $true 'all' $null `
    { Set-Reg $CDM 'SilentInstalledAppsEnabled' 0; Set-Reg $CDM 'PreInstalledAppsEnabled' 0; Set-Reg $CDM 'OemPreInstalledAppsEnabled' 0 } `
    { Set-Reg $CDM 'SilentInstalledAppsEnabled' 1; Set-Reg $CDM 'PreInstalledAppsEnabled' 1; Set-Reg $CDM 'OemPreInstalledAppsEnabled' 1 } $null),
  (I 'a_explorer' 'ads' 'File Explorer ads (OneDrive / Microsoft 365 promos)' '' $true 'all' $null `
    { Set-Reg $ADV 'ShowSyncProviderNotifications' 0 } `
    { Set-Reg $ADV 'ShowSyncProviderNotifications' 1 } $null),
  (I 'a_adid' 'ads' 'Advertising ID (personalised ads in apps)' '' $true 'all' $null `
    { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 } `
    { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 1 } $null),

  # ---------- BACKGROUND STUFF ----------
  (I 'b_widgets' 'bg' 'Widgets and news feed' 'Shows after sign out / restart' $true '11' $null `
    { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 } `
    { Del-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' } $null),
  (I 'b_news10' 'bg' 'News and Interests on the taskbar' 'Shows after sign out / restart' $true '10' $null `
    { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 } `
    { Del-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' } $null),
  (I 'b_bing' 'bg' 'Bing web results in Start menu search' 'Search only shows your PC files and apps' $true 'all' $null `
    { Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 } `
    { Del-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' } $null),
  (I 'b_copilot' 'bg' 'Built-in Copilot button' '' $true '11' $null `
    { Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 } `
    { Del-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'; Del-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' } $null),
  (I 'b_cortana' 'bg' 'Cortana' '' $true '10' $null `
    { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0 } `
    { Del-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' } $null),
  (I 'b_tele' 'bg' 'Reduce telemetry (usage data sent to Microsoft)' 'Sets it to the lowest level Windows allows' $true 'all' $null `
    { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0; Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue; Set-Service DiagTrack -StartupType Disabled } `
    { Del-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'; Set-Service DiagTrack -StartupType Automatic; Start-Service DiagTrack -ErrorAction SilentlyContinue } $null),
  (I 'b_gamedvr' 'bg' 'Xbox Game Bar background recording' 'Helps FPS. Turn back on if you record gameplay' $true 'all' $null `
    { Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0; Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 } `
    { Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1; Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1 } $null),
  (I 'b_bgapps' 'bg' 'Stop all apps running in the background' 'Some apps will stop sending notifications' $false 'all' $null `
    { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 } `
    { Del-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' } $null),

  # ---------- BLOCK APPS (ticked = blocked) ----------
  (I 'k_calc' 'block' 'Calculator' '' $false 'all' @('calc.exe', 'Calculator.exe', 'CalculatorApp.exe') $null $null $null),
  (I 'k_photos' 'block' 'Photos' '' $false 'all' @('Microsoft.Photos.exe', 'Photos.exe') $null $null $null),
  (I 'k_camera' 'block' 'Camera' '' $false 'all' @('WindowsCamera.exe') $null $null $null),
  (I 'k_snip' 'block' 'Snipping Tool' 'Also blocks Win+Shift+S' $false 'all' @('SnippingTool.exe', 'ScreenClippingHost.exe') $null $null $null),
  (I 'k_notepad' 'block' 'Notepad' '' $false 'all' @('notepad.exe') $null $null $null),
  (I 'k_store' 'block' 'Microsoft Store' 'Installed apps keep working, just no new installs' $false 'all' @('WinStore.App.exe') $null $null $null),
  (I 'k_edge' 'block' 'Microsoft Edge' 'Set another default browser first - some Windows links open in Edge' $false 'all' @('msedge.exe') $null $null $null),
  (I 'k_onedrive' 'block' 'OneDrive' 'Uses the official Windows switch. Your files stay on the PC' $false 'all' $null `
    { Set-Reg $ODP 'DisableFileSyncNGSC' 1; Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue } `
    { Del-Reg $ODP 'DisableFileSyncNGSC' } `
    { (Get-ItemProperty -Path $ODP -ErrorAction SilentlyContinue).DisableFileSyncNGSC -eq 1 }),
  (I 'k_wu' 'block' 'Windows Update - pause for 5 weeks' 'Longest pause Windows allows. Security updates wait too' $false 'all' $null `
    { $now = (Get-Date).ToUniversalTime(); $s = $now.ToString('yyyy-MM-ddTHH:mm:ssZ'); $e = $now.AddDays(35).ToString('yyyy-MM-ddTHH:mm:ssZ')
      foreach ($n in 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesStartTime') { Set-Reg $WUUX $n $s 'String' }
      foreach ($n in 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesExpiryTime') { Set-Reg $WUUX $n $e 'String' } } `
    { foreach ($n in 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesExpiryTime') { Del-Reg $WUUX $n } } `
    { $v = (Get-ItemProperty -Path $WUUX -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime; $d = [datetime]::MinValue; ($v -and [datetime]::TryParse("$v", [ref]$d) -and $d -gt (Get-Date)) })
)

function Is-On($it) {
  if ($it.Group -ne 'block') { return $false }
  if ($it.Test) { return [bool](& $it.Test) }
  return (Test-Blocked $it.Data)
}
function Do-Block($it)   { if ($it.Do)   { & $it.Do }   else { Block-Exe $it.Data } }
function Do-Unblock($it) { if ($it.Undo) { & $it.Undo } else { Unblock-Exe $it.Data } }
'@
iex $CatalogCode

# ===================== AUTO POWER OFF WATCHER =====================
# Runs hidden in the background. Windows tells it when the screen turns off;
# it then starts a 60 second shutdown. Screen back on (mouse/keyboard) = cancel.
$WatcherCode = @'
try { $mtx = New-Object System.Threading.Mutex($false, 'Local\TuneBoxPCAutoOff'); if (-not $mtx.WaitOne(0)) { exit } } catch { }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class PCOptAutoOff : Form {
  [DllImport("user32.dll")]
  static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid PowerSettingGuid, int Flags);
  static Guid DISPLAY = new Guid("6FE69556-704A-47A0-8F24-C28D936FDA47");
  bool pending = false;
  public PCOptAutoOff() {
    ShowInTaskbar = false;
    FormBorderStyle = FormBorderStyle.FixedToolWindow;
    StartPosition = FormStartPosition.Manual;
    Location = new System.Drawing.Point(-3000, -3000);
    Size = new System.Drawing.Size(1, 1);
    Opacity = 0;
  }
  protected override void OnHandleCreated(EventArgs e) {
    base.OnHandleCreated(e);
    Guid g = DISPLAY;
    RegisterPowerSettingNotification(this.Handle, ref g, 0);
  }
  static void Run(string args) {
    try {
      ProcessStartInfo p = new ProcessStartInfo("shutdown.exe", args);
      p.CreateNoWindow = true;
      p.UseShellExecute = false;
      Process.Start(p);
    } catch { }
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x0218 && m.WParam.ToInt64() == 0x8013) {
      Guid g = (Guid)Marshal.PtrToStructure(m.LParam, typeof(Guid));
      if (g == DISPLAY) {
        int state = Marshal.ReadInt32(m.LParam, 20);
        if (state == 0 && !pending) {
          pending = true;
          Run("/s /t 60 /c \"TuneBox PC: screen has been off. Shutting down in 60 seconds. Move the mouse to cancel.\"");
        } else if (state == 1 && pending) {
          pending = false;
          Run("/a");
        }
      }
    }
    base.WndProc(ref m);
  }
}
"@
[System.Windows.Forms.Application]::Run((New-Object PCOptAutoOff))
'@

$T.AutoOff = {
  $A = $sync.Args
  $dir = Join-Path $env:ProgramData 'TuneBoxPC'
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $file = Join-Path $dir 'AutoOff.ps1'
  $taskName = 'TuneBox PC Auto Power Off'
  $psArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $file + '"'

  # stop any running watcher first
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*TuneBoxPC\AutoOff.ps1*' } | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }

  if ($A.Enabled) {
    Head 'AUTO POWER OFF - TURNING ON'
    Set-Content -LiteralPath $file -Value $sync.WatcherCode -Encoding UTF8
    $users = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-545').Translate([System.Security.Principal.NTAccount]).Value
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
    $trg = New-ScheduledTaskTrigger -AtLogOn
    $prn = New-ScheduledTaskPrincipal -GroupId $users -RunLevel Limited
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    try {
      Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trg -Principal $prn -Settings $set -Force -ErrorAction Stop | Out-Null
      W '  Background watcher installed (starts every time someone signs in).' 'Green'
    } catch { W ('  Could not create the scheduled task: ' + $_.Exception.Message) 'Red'; return }
    $m = [int]$A.Minutes
    powercfg /change monitor-timeout-ac $m
    powercfg /change monitor-timeout-dc $m
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    W ("  Screen turns off after $m minutes of no mouse/keyboard use.") 'Green'
    W '  Sleep is set to Never, so the PC shuts down instead of sleeping.' 'Green'
    Start-Process powershell.exe -ArgumentList $psArgs -WindowStyle Hidden
    W '  Watcher is running now.' 'Green'
    W ''
    W ("  How it works: no activity for $m min -> screen off -> 60 seconds later -> shut down.") 'Cyan'
    W '  If someone moves the mouse or presses a key in those 60 seconds, the shutdown is cancelled.' 'Dim'
    W '  Videos, games and presentations keep the screen on, so the PC will not shut down during them.' 'Dim'
    W '  Note: the screen timer is set on the current power plan. If you switch plans, turn this on again.' 'Dim'
  } else {
    Head 'AUTO POWER OFF - TURNING OFF'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    shutdown /a 2>$null | Out-Null
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    powercfg /change monitor-timeout-ac 10
    powercfg /change monitor-timeout-dc 5
    powercfg /change standby-timeout-ac 30
    powercfg /change standby-timeout-dc 15
    W '  Auto power off removed.' 'Green'
    W '  Screen and sleep timers set back to Windows defaults (screen 10 min, sleep 30 min).' 'Dim'
  }
  $cfg = @{ Enabled = [bool]$A.Enabled; Minutes = [int]$A.Minutes } | ConvertTo-Json
  Set-Content -LiteralPath (Join-Path $dir 'autooff.json') -Value $cfg -Encoding UTF8
}

$T.Debloat = {
  iex $sync.Catalog
  $A = $sync.Args
  function Find-Item($id) { $Catalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1 }
  Head 'DEBLOAT AND BLOCK APPS'

  if ($A.RestorePoint) {
    W '  Creating a restore point first...' 'Dim'
    Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
    try { Checkpoint-Computer -Description 'Before TuneBox PC debloat' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; W '  Restore point created.' 'Green' }
    catch { W '  Restore point skipped (Windows allows only one every 24 hours).' 'Yellow' }
  }

  if ($A.Remove.Count) {
    W ''; W '  REMOVING APPS' 'White'
    foreach ($id in $A.Remove) {
      $it = Find-Item $id; $done = $false
      foreach ($pat in $it.Data) {
        $pk = @(Get-AppxPackage -AllUsers -Name $pat)
        if (-not $pk.Count) { $pk = @(Get-AppxPackage -Name $pat) }
        foreach ($p in $pk) {
          try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; $done = $true }
          catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; $done = $true } catch { } }
        }
      }
      if ($done) { W ('  Removed: ' + $it.Label) 'Green' } else { W ('  Could not remove: ' + $it.Label) 'Yellow' }
    }
  }

  if ($A.Settings.Count) {
    W ''; W '  TURNING OFF' 'White'
    foreach ($id in $A.Settings) {
      $it = Find-Item $id
      try { & $it.Do; W ('  Off: ' + $it.Label) 'Green' } catch { W ('  Failed: ' + $it.Label + ' - ' + $_.Exception.Message) 'Yellow' }
    }
  }

  if ($A.Undo.Count) {
    W ''; W '  PUTTING SETTINGS BACK' 'White'
    foreach ($id in $A.Undo) {
      $it = Find-Item $id
      try { & $it.Undo; W ('  Back to normal: ' + $it.Label) 'Green' } catch { W ('  Failed: ' + $it.Label) 'Yellow' }
    }
  }

  if ($A.Block.Count -or $A.Unblock.Count) {
    W ''; W '  BLOCKED APPS' 'White'
    foreach ($id in $A.Block)   { $it = Find-Item $id; try { Do-Block $it;   W ('  Blocked: ' + $it.Label) 'Red' }   catch { W ('  Failed to block: ' + $it.Label) 'Yellow' } }
    foreach ($id in $A.Unblock) { $it = Find-Item $id; try { Do-Unblock $it; W ('  Allowed again: ' + $it.Label) 'Green' } catch { W ('  Failed to unblock: ' + $it.Label) 'Yellow' } }
  }

  W ''
  W '  Done. Sign out or restart the PC so every change shows.' 'Cyan'
  W '  Removed apps can be reinstalled from the Microsoft Store.' 'Dim'
}

# ===================== DIALOG: DEBLOAT & BLOCK =====================
function Show-Debloat {
  [xml]$dx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Debloat and block apps" Width="760" Height="720" WindowStartupLocation="CenterOwner"
        Background="#14161B" FontFamily="Segoe UI">
  <Grid Margin="22,18,22,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0">
      <TextBlock Text="Debloat and block apps" Foreground="White" FontSize="20" FontWeight="Bold"/>
      <TextBlock x:Name="ver" Foreground="#7D8594" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <Border Grid.Row="1" Background="#1B1F26" CornerRadius="10" Margin="0,14,0,14">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16,6,16,12">
        <StackPanel x:Name="list"/>
      </ScrollViewer>
    </Border>
    <Grid Grid.Row="2">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="bRec" Content="Recommended" Width="120" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
        <Button x:Name="bNone" Content="Untick all" Width="100" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
        <Button x:Name="bUndo" Content="Undo all settings" Width="140" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="bCancel" Content="Close" Width="90" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
        <Button x:Name="bApply" Content="Apply" Width="110" Background="#2563EB" FontWeight="SemiBold" HorizontalContentAlignment="Center"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@
  $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dx))
  $d.Owner = $win
  foreach ($k in $win.Resources.Keys) { $d.Resources[$k] = $win.Resources[$k] }
  $build = [Environment]::OSVersion.Version.Build
  $isWin11 = $build -ge 22000
  $winTag = if ($isWin11) { '11' } else { '10' }
  $d.FindName('ver').Text = ('Detected: Windows {0} (build {1}). Only items for your version are shown. A restore point is made before anything changes.' -f $winTag, $build)
  $list = $d.FindName('list')

  $installed = @{}
  $allPkgs = @(Get-AppxPackage | ForEach-Object { $_.Name })
  foreach ($it in ($Catalog | Where-Object { $_.Group -eq 'remove' })) {
    foreach ($pat in $it.Data) { if ($allPkgs -like $pat) { $installed[$it.Id] = $true } }
  }

  $groups = [ordered]@{
    remove = 'REMOVE JUNK APPS   (can be reinstalled from the Microsoft Store)'
    ads    = 'TURN OFF ADS AND SUGGESTIONS'
    bg     = 'TURN OFF BACKGROUND STUFF'
    block  = 'BLOCK APPS   (ticked = blocked. Untick + Apply to allow again)'
  }
  $boxes = @{}
  $state = @{}
  $muted = $bc.ConvertFromString('#7D8594'); $white = $bc.ConvertFromString('#E4E7EC'); $warn = $bc.ConvertFromString('#FACC15')
  foreach ($g in $groups.Keys) {
    $items = @($Catalog | Where-Object { $_.Group -eq $g -and ($_.Win -eq 'all' -or $_.Win -eq $winTag) })
    if ($g -eq 'remove') { $items = @($items | Where-Object { $installed[$_.Id] }) }
    $h = New-Object System.Windows.Controls.TextBlock
    $h.Text = $groups[$g]; $h.Foreground = $bc.ConvertFromString('#38BDF8'); $h.FontWeight = [System.Windows.FontWeights]::SemiBold
    $h.FontSize = 12; $h.Margin = New-Object System.Windows.Thickness 0, 14, 0, 6
    [void]$list.Children.Add($h)
    if (-not $items.Count) {
      $e = New-Object System.Windows.Controls.TextBlock
      $e.Text = '   Nothing to remove - none of these apps are installed.'; $e.Foreground = $muted; $e.FontSize = 12
      [void]$list.Children.Add($e); continue
    }
    foreach ($it in $items) {
      $cb = New-Object System.Windows.Controls.CheckBox
      $cb.Margin = New-Object System.Windows.Thickness 4, 4, 0, 4
      $cb.VerticalContentAlignment = 'Center'
      $sp = New-Object System.Windows.Controls.StackPanel
      $sp.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
      $t1 = New-Object System.Windows.Controls.TextBlock
      $t1.Text = $it.Label; $t1.Foreground = $white; $t1.FontSize = 13
      [void]$sp.Children.Add($t1)
      if ($it.Note) {
        $t2 = New-Object System.Windows.Controls.TextBlock
        $t2.Text = $it.Note; $t2.FontSize = 11
        $t2.Foreground = if ($it.Id -eq 'k_edge' -or $it.Id -eq 'k_wu' -or $it.Id -eq 'b_bgapps') { $warn } else { $muted }
        [void]$sp.Children.Add($t2)
      }
      $cb.Content = $sp
      if ($g -eq 'block') { $on = Is-On $it; $state[$it.Id] = $on; $cb.IsChecked = $on }
      [void]$list.Children.Add($cb)
      $boxes[$it.Id] = $cb
    }
  }

  $d.FindName('bRec').Add_Click({
    foreach ($id in $boxes.Keys) {
      $it = $Catalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1
      if ($it.Group -ne 'block') { $boxes[$id].IsChecked = [bool]$it.Rec }
    }
  })
  $d.FindName('bNone').Add_Click({
    foreach ($id in $boxes.Keys) { $it = $Catalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1; if ($it.Group -ne 'block') { $boxes[$id].IsChecked = $false } }
  })
  $d.FindName('bCancel').Add_Click({ $d.Close() })
  $d.FindName('bUndo').Add_Click({
    $ids = @($Catalog | Where-Object { ($_.Group -eq 'ads' -or $_.Group -eq 'bg') -and ($_.Win -eq 'all' -or $_.Win -eq $winTag) } | ForEach-Object { $_.Id })
    $r = [System.Windows.MessageBox]::Show('Put all ads, suggestions and background settings back to Windows normal?' + [Environment]::NewLine + '(Removed apps and blocked apps are not affected.)', 'Undo all settings', 'YesNo', 'Question')
    if ($r -eq 'Yes') {
      $sync.Args = @{ RestorePoint = $false; Remove = @(); Settings = @(); Undo = $ids; Block = @(); Unblock = @() }
      $d.Close(); Start-Task 'Undo debloat settings' $T.Debloat
    }
  })
  $d.FindName('bApply').Add_Click({
    $rem = @(); $set = @(); $blk = @(); $unb = @()
    foreach ($id in $boxes.Keys) {
      $it = $Catalog | Where-Object { $_.Id -eq $id } | Select-Object -First 1
      $c = [bool]$boxes[$id].IsChecked
      switch ($it.Group) {
        'remove' { if ($c) { $rem += $id } }
        'ads'    { if ($c) { $set += $id } }
        'bg'     { if ($c) { $set += $id } }
        'block'  { if ($c -and -not $state[$id]) { $blk += $id } elseif (-not $c -and $state[$id]) { $unb += $id } }
      }
    }
    if (-not ($rem.Count + $set.Count + $blk.Count + $unb.Count)) { [void][System.Windows.MessageBox]::Show('Nothing to change. Tick some items first (or click Recommended).', 'Debloat'); return }
    $nl = [Environment]::NewLine
    $msg = "This will:$nl$nl  Remove $($rem.Count) app(s)$nl  Turn off $($set.Count) thing(s)$nl  Block $($blk.Count) app(s)$nl  Allow $($unb.Count) app(s) again$nl${nl}A restore point is created first. Continue?"
    $r = [System.Windows.MessageBox]::Show($msg, 'Apply changes', 'YesNo', 'Question')
    if ($r -eq 'Yes') {
      $sync.Args = @{ RestorePoint = $true; Remove = $rem; Settings = $set; Undo = @(); Block = $blk; Unblock = $unb }
      $d.Close(); Start-Task 'Debloat and block apps' $T.Debloat
    }
  })
  [void]$d.ShowDialog()
}

# ===================== DIALOG: AUTO POWER OFF =====================
function Show-AutoOff {
  [xml]$ax = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Auto power off" Width="520" Height="430" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#14161B" FontFamily="Segoe UI">
  <StackPanel Margin="24,20,24,20">
    <TextBlock Text="Auto power off" Foreground="White" FontSize="20" FontWeight="Bold"/>
    <TextBlock Foreground="#9AA2B1" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"
      Text="When nobody uses the mouse or keyboard, Windows turns the screen off. One minute after that, the PC shuts down. If someone moves the mouse during that minute, the shutdown is cancelled."/>
    <Border Background="#1B1F26" CornerRadius="10" Padding="16" Margin="0,16,0,0">
      <StackPanel>
        <CheckBox x:Name="on" Foreground="White" FontSize="14" VerticalContentAlignment="Center">
          <TextBlock Text="Turn on Auto power off" Foreground="White" FontSize="14" Margin="6,0,0,0"/>
        </CheckBox>
        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
          <TextBlock Text="Turn screen off after" Foreground="#E4E7EC" FontSize="13" VerticalAlignment="Center"/>
          <ComboBox x:Name="mins" Width="110" Margin="10,0,0,0" FontSize="13"/>
        </StackPanel>
        <TextBlock x:Name="summary" Foreground="#38BDF8" FontSize="12" Margin="0,12,0,0" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <TextBlock Foreground="#FACC15" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"
      Text="Unsaved work in open apps is lost when it shuts down. Videos, games and presentations keep the screen on, so it will not shut down during them."/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="bCancel" Content="Cancel" Width="90" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
      <Button x:Name="bSave" Content="Save" Width="110" Background="#2563EB" FontWeight="SemiBold" HorizontalContentAlignment="Center"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
  $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $ax))
  $d.Owner = $win
  foreach ($k in $win.Resources.Keys) { $d.Resources[$k] = $win.Resources[$k] }
  $on = $d.FindName('on'); $mins = $d.FindName('mins'); $summary = $d.FindName('summary')
  foreach ($m in 1, 2, 5, 10, 15, 20, 30, 45, 60) { [void]$mins.Items.Add("$m minutes") }

  $cfgFile = Join-Path $env:ProgramData 'TuneBoxPC\autooff.json'
  $cur = @{ Enabled = $false; Minutes = 10 }
  if (Test-Path $cfgFile) { try { $j = Get-Content $cfgFile -Raw | ConvertFrom-Json; $cur.Enabled = [bool]$j.Enabled; $cur.Minutes = [int]$j.Minutes } catch { } }
  if ($cur.Enabled -and -not (Get-ScheduledTask -TaskName 'TuneBox PC Auto Power Off' -ErrorAction SilentlyContinue)) { $cur.Enabled = $false }
  $on.IsChecked = $cur.Enabled
  $mins.SelectedItem = "$($cur.Minutes) minutes"
  if ($mins.SelectedIndex -lt 0) { $mins.SelectedItem = '10 minutes' }

  $upd = {
    $m = [int](("$($mins.SelectedItem)" -split ' ')[0])
    if ($on.IsChecked) { $summary.Text = "No activity for $m min -> screen off -> 1 min later -> PC shuts down (about $($m + 1) min total)." }
    else { $summary.Text = 'Auto power off is OFF.' }
  }
  & $upd
  $on.Add_Click($upd)
  $mins.Add_SelectionChanged($upd)
  $d.FindName('bCancel').Add_Click({ $d.Close() })
  $d.FindName('bSave').Add_Click({
    $m = [int](("$($mins.SelectedItem)" -split ' ')[0])
    $sync.Args = @{ Enabled = [bool]$on.IsChecked; Minutes = $m }
    $d.Close()
    Start-Task 'Auto power off settings' $T.AutoOff
  })
  [void]$d.ShowDialog()
}

$sync.Catalog = $CatalogCode
$sync.WatcherCode = $WatcherCode

# ===================== WINDOW =====================
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TuneBox PC" Width="1180" Height="760" MinWidth="980" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#14161B" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#E4E7EC"/>
      <Setter Property="Background" Value="#1F232B"/>
      <Setter Property="Height" Value="36"/>
      <Setter Property="Margin" Value="0,2"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.8"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#7D8594"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="4,16,0,6"/>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#7D8594"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="CardValue" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontSize" Value="20"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,6,0,2"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
    </Style>
    <Style x:Key="CardSub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#9AA2B1"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="5"/>
      <Setter Property="Margin" Value="0,8,0,0"/>
      <Setter Property="Background" Value="#2A2F39"/>
      <Setter Property="Foreground" Value="#3B82F6"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="270"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- SIDEBAR -->
    <Border Grid.Column="0" Background="#191C22" BorderBrush="#232731" BorderThickness="0,0,1,0">
      <DockPanel Margin="16,18,16,16">
        <StackPanel DockPanel.Dock="Top" Margin="4,0,0,8">
          <TextBlock Text="TuneBox PC" Foreground="White" FontSize="22" FontWeight="Bold"/>
          <TextBlock x:Name="subTitle" Text="Windows 10 / 11" Foreground="#7D8594" FontSize="12" Margin="0,2,0,0"/>
        </StackPanel>
        <Button x:Name="btnQuick" DockPanel.Dock="Top" Content="Quick Optimize" Background="#2563EB" Height="44" FontSize="14" FontWeight="SemiBold" HorizontalContentAlignment="Center" Margin="0,10,0,2"/>
        <Button x:Name="btnRestore" DockPanel.Dock="Top" Content="Create restore point first" Background="#1F232B" HorizontalContentAlignment="Center" Foreground="#9AA2B1"/>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <TextBlock Text="CLEAN UP" Style="{StaticResource Section}"/>
            <Button x:Name="btnTemp" Content="Clean temp files"/>
            <Button x:Name="btnRecycle" Content="Empty Recycle Bin"/>
            <Button x:Name="btnWU" Content="Clean Windows Update leftovers"/>
            <TextBlock Text="SPEED" Style="{StaticResource Section}"/>
            <Button x:Name="btnUltimate" Content="Ultimate Performance power plan"/>
            <Button x:Name="btnBalanced" Content="Balanced power plan"/>
            <Button x:Name="btnStartup" Content="Startup apps"/>
            <Button x:Name="btnVisual" Content="Visual effects settings"/>
            <Button x:Name="btnDrives" Content="Optimize drives"/>
            <Button x:Name="btnRAM" Content="Free up RAM"/>
            <TextBlock Text="CHECK" Style="{StaticResource Section}"/>
            <Button x:Name="btnHealth" Content="PC health check"/>
            <Button x:Name="btnDisk" Content="Drive health check"/>
            <Button x:Name="btnHistory" Content="PC activity history"/>
            <TextBlock Text="TOOLS" Style="{StaticResource Section}"/>
            <Button x:Name="btnDebloat" Content="Debloat and block apps"/>
            <Button x:Name="btnAutoOff" Content="Auto power off"/>
            <TextBlock Text="FIX" Style="{StaticResource Section}"/>
            <Button x:Name="btnDNS" Content="Flush DNS (internet issues)"/>
            <Button x:Name="btnRepair" Content="Repair Windows files (slow)"/>
          </StackPanel>
        </ScrollViewer>
      </DockPanel>
    </Border>

    <!-- MAIN -->
    <Grid Grid.Column="1" Margin="22,18,22,18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- dashboard cards -->
      <UniformGrid Grid.Row="0" Columns="4">
        <Border Background="#1B1F26" CornerRadius="10" Padding="16,14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock Text="CPU" Style="{StaticResource CardTitle}"/>
            <TextBlock x:Name="cpuVal" Text="-" Style="{StaticResource CardValue}"/>
            <TextBlock x:Name="cpuSub" Text="-" Style="{StaticResource CardSub}"/>
            <ProgressBar x:Name="cpuBar" Maximum="100"/>
          </StackPanel>
        </Border>
        <Border Background="#1B1F26" CornerRadius="10" Padding="16,14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock Text="MEMORY" Style="{StaticResource CardTitle}"/>
            <TextBlock x:Name="ramVal" Text="-" Style="{StaticResource CardValue}"/>
            <TextBlock x:Name="ramSub" Text="-" Style="{StaticResource CardSub}"/>
            <ProgressBar x:Name="ramBar" Maximum="100"/>
          </StackPanel>
        </Border>
        <Border Background="#1B1F26" CornerRadius="10" Padding="16,14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock Text="SYSTEM DRIVE" Style="{StaticResource CardTitle}"/>
            <TextBlock x:Name="diskVal" Text="-" Style="{StaticResource CardValue}"/>
            <TextBlock x:Name="diskSub" Text="-" Style="{StaticResource CardSub}"/>
            <ProgressBar x:Name="diskBar" Maximum="100"/>
          </StackPanel>
        </Border>
        <Border Background="#1B1F26" CornerRadius="10" Padding="16,14">
          <StackPanel>
            <TextBlock Text="UPTIME" Style="{StaticResource CardTitle}"/>
            <TextBlock x:Name="upVal" Text="-" Style="{StaticResource CardValue}"/>
            <TextBlock x:Name="upSub" Text="-" Style="{StaticResource CardSub}"/>
          </StackPanel>
        </Border>
      </UniformGrid>

      <!-- status bar -->
      <Grid Grid.Row="1" Margin="0,18,0,8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="statusText" Text="Ready. Pick an option on the left." Foreground="#E4E7EC" FontSize="15" FontWeight="SemiBold"/>
          <ProgressBar x:Name="busyBar" IsIndeterminate="False" Visibility="Hidden" Height="3" Margin="0,8,0,0"/>
        </StackPanel>
        <TextBlock x:Name="timerText" Grid.Column="1" Foreground="#7D8594" FontSize="12" VerticalAlignment="Top" Margin="12,3,0,0"/>
      </Grid>

      <!-- results -->
      <Border Grid.Row="2" Background="#0F1115" CornerRadius="10" BorderBrush="#232731" BorderThickness="1">
        <RichTextBox x:Name="log" Background="Transparent" BorderThickness="0" Foreground="#D8DCE3"
                     FontFamily="Consolas" FontSize="13" IsReadOnly="True" Padding="10"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
      </Border>

      <!-- bottom buttons -->
      <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
        <Button x:Name="btnSave" Content="Save results to Desktop" Width="190" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
        <Button x:Name="btnCopy" Content="Copy" Width="90" HorizontalContentAlignment="Center" Margin="0,0,8,0"/>
        <Button x:Name="btnClear" Content="Clear" Width="90" HorizontalContentAlignment="Center"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
  $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
  if ($n) { $ui[$n] = $win.FindName($n) }
}

# ---------- results panel ----------
$doc = New-Object System.Windows.Documents.FlowDocument
$doc.PageWidth = 2000
$para = New-Object System.Windows.Documents.Paragraph
$para.Margin = New-Object System.Windows.Thickness 0
$doc.Blocks.Add($para)
$ui.log.Document = $doc
$bc = New-Object System.Windows.Media.BrushConverter
$Colors = @{
  Text = $bc.ConvertFromString('#D8DCE3'); Green = $bc.ConvertFromString('#4ADE80'); Yellow = $bc.ConvertFromString('#FACC15')
  Red = $bc.ConvertFromString('#F87171'); Cyan = $bc.ConvertFromString('#38BDF8'); Dim = $bc.ConvertFromString('#6B7280')
  White = $bc.ConvertFromString('#FFFFFF')
}
function Add-Log([string]$t, [string]$c = 'Text') {
  $run = [System.Windows.Documents.Run]::new($t)
  $b = $Colors[$c]; if (-not $b) { $b = $Colors.Text }
  $run.Foreground = $b
  if ($c -eq 'Cyan' -or $c -eq 'White') { $run.FontWeight = [System.Windows.FontWeights]::SemiBold }
  $para.Inlines.Add($run)
  $para.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
}

# ---------- task runner ----------
$ActionButtons = @('btnQuick','btnRestore','btnTemp','btnRecycle','btnWU','btnUltimate','btnBalanced','btnStartup','btnVisual','btnDrives','btnRAM','btnHealth','btnDisk','btnHistory','btnDNS','btnRepair','btnDebloat','btnAutoOff')

function Set-Busy([bool]$busy, [string]$title) {
  foreach ($b in $ActionButtons) { $ui[$b].IsEnabled = -not $busy }
  $ui.busyBar.IsIndeterminate = $busy
  $ui.busyBar.Visibility = if ($busy) { 'Visible' } else { 'Hidden' }
  if ($busy) { $ui.statusText.Text = "Working: $title ..." }
}

function Start-Task([string]$title, [scriptblock]$body) {
  if ($App.Busy) { return }
  $App.Busy = $true
  Set-Busy $true $title
  $rs = [runspacefactory]::CreateRunspace()
  $rs.ApartmentState = 'STA'
  $rs.Open()
  $rs.SessionStateProxy.SetVariable('sync', $sync)
  $ps = [powershell]::Create()
  $ps.Runspace = $rs
  [void]$ps.AddScript($Prelude + "`n" + $body.ToString())
  $App.Job = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Title = $title; Start = (Get-Date) }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
  $item = $null; $n = 0; $added = $false
  while ($n -lt 400 -and $sync.Queue.TryDequeue([ref]$item)) { Add-Log $item[0] $item[1]; $n++; $added = $true }
  if ($added) { $ui.log.ScrollToEnd() }
  $j = $App.Job
  if ($j) {
    $ui.timerText.Text = ('{0:mm\:ss}' -f ((Get-Date) - $j.Start))
    if ($j.Handle.IsCompleted) {
      try { [void]$j.PS.EndInvoke($j.Handle) } catch { Add-Log ('  Error: ' + $_.Exception.Message) 'Red' }
      foreach ($e in ($j.PS.Streams.Error | Select-Object -First 3)) { Add-Log ('  Error: ' + $e.ToString()) 'Red' }
      while ($sync.Queue.TryDequeue([ref]$item)) { Add-Log $item[0] $item[1] }
      $j.PS.Dispose(); $j.RS.Close(); $j.RS.Dispose()
      $App.Job = $null; $App.Busy = $false
      Set-Busy $false ''
      $ui.statusText.Text = "Finished: $($j.Title)"
      $ui.log.ScrollToEnd()
    }
  }
})

# ---------- live dashboard ----------
$cpuName = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim() -replace '\s+', ' '
$ui.cpuSub.Text = $cpuName
$ui.subTitle.Text = (Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ', ''
$cpuCounter = $null
try { $cpuCounter = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total'); [void]$cpuCounter.NextValue() } catch { $cpuCounter = $null }
function Update-Dash {
  try {
    $o = Get-CimInstance Win32_OperatingSystem
    $total = $o.TotalVisibleMemorySize / 1MB; $free = $o.FreePhysicalMemory / 1MB; $used = $total - $free
    $pct = [math]::Round($used / $total * 100)
    $ui.ramVal.Text = "$pct%"
    $ui.ramSub.Text = ('{0:N1} of {1:N1} GB used' -f $used, $total)
    $ui.ramBar.Value = $pct
    $load = $null
    if ($cpuCounter) { try { $load = $cpuCounter.NextValue() } catch { $load = $null } }
    if ($load -eq $null) { $load = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average }
    if ($load -ne $null) { $ui.cpuVal.Text = ('{0}%' -f [math]::Round($load)); $ui.cpuBar.Value = $load }
    $dsk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'")
    if ($dsk -and $dsk.Size) {
      $dp = [math]::Round(($dsk.Size - $dsk.FreeSpace) / $dsk.Size * 100)
      $ui.diskVal.Text = ('{0:N0} GB free' -f ($dsk.FreeSpace / 1GB))
      $ui.diskSub.Text = ('{0} {1}% used of {2:N0} GB' -f $env:SystemDrive, $dp, ($dsk.Size / 1GB))
      $ui.diskBar.Value = $dp
    }
    $up = (Get-Date) - $o.LastBootUpTime
    $ui.upVal.Text = ('{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes)
    $ui.upSub.Text = ('since {0:ddd dd MMM, h:mm tt}' -f $o.LastBootUpTime)
  } catch {}
}
$dash = New-Object System.Windows.Threading.DispatcherTimer
$dash.Interval = [TimeSpan]::FromSeconds(3)
$dash.Add_Tick({ Update-Dash })

# ---------- buttons ----------
$ui.btnQuick.Add_Click({ Start-Task 'Quick Optimize' $T.Quick })
$ui.btnRestore.Add_Click({ Start-Task 'Create restore point' $T.Restore })
$ui.btnTemp.Add_Click({ Start-Task 'Clean temp files' $T.Temp })
$ui.btnRecycle.Add_Click({
  $r = [System.Windows.MessageBox]::Show('This PERMANENTLY deletes everything in the Recycle Bin. Continue?', 'Empty Recycle Bin', 'YesNo', 'Warning')
  if ($r -eq 'Yes') { Start-Task 'Empty Recycle Bin' $T.Recycle }
})
$ui.btnWU.Add_Click({ Start-Task 'Clean Windows Update leftovers' $T.WU })
$ui.btnUltimate.Add_Click({ Start-Task 'Ultimate Performance power plan' $T.Ultimate })
$ui.btnBalanced.Add_Click({ Start-Task 'Balanced power plan' $T.Balanced })
$ui.btnStartup.Add_Click({ Start-Task 'Startup apps' $T.Startup })
$ui.btnVisual.Add_Click({
  Add-Log ''
  Add-Log '  ===== VISUAL EFFECTS =====' 'Cyan'
  Add-Log '  A window is opening. Choose "Adjust for best performance",'
  Add-Log '  then tick "Smooth edges of screen fonts" so text still looks good. Click OK.'
  $ui.log.ScrollToEnd()
  Start-Process SystemPropertiesPerformance.exe
})
$ui.btnDrives.Add_Click({ Start-Task 'Optimize drives' $T.Drives })
$ui.btnRAM.Add_Click({ Start-Task 'Free up RAM' $T.RAM })
$ui.btnHealth.Add_Click({ Start-Task 'PC health check' $T.Health })
$ui.btnDisk.Add_Click({ Start-Task 'Drive health check' $T.Disk })
$ui.btnHistory.Add_Click({ Start-Task 'PC activity history' $T.History })
$ui.btnDNS.Add_Click({ Start-Task 'Flush DNS' $T.DNS })
$ui.btnRepair.Add_Click({
  $r = [System.Windows.MessageBox]::Show('Repairing Windows files can take 10-30 minutes. Start now?', 'Repair Windows files', 'YesNo', 'Question')
  if ($r -eq 'Yes') { Start-Task 'Repair Windows files' $T.Repair }
})

$ui.btnDebloat.Add_Click({ if (-not $App.Busy) { Show-Debloat } })
$ui.btnAutoOff.Add_Click({ if (-not $App.Busy) { Show-AutoOff } })

$ui.btnClear.Add_Click({ $para.Inlines.Clear(); $ui.statusText.Text = 'Ready. Pick an option on the left.'; $ui.timerText.Text = '' })
$ui.btnCopy.Add_Click({
  $txt = (New-Object System.Windows.Documents.TextRange($doc.ContentStart, $doc.ContentEnd)).Text
  if ($txt.Trim()) { [System.Windows.Clipboard]::SetText($txt); $ui.statusText.Text = 'Results copied.' }
})
$ui.btnSave.Add_Click({
  $txt = (New-Object System.Windows.Documents.TextRange($doc.ContentStart, $doc.ContentEnd)).Text
  if (-not $txt.Trim()) { $ui.statusText.Text = 'Nothing to save yet.'; return }
  $desk = [Environment]::GetFolderPath('Desktop')
  if (-not $desk -or -not (Test-Path $desk)) { $desk = $env:USERPROFILE }
  $file = Join-Path $desk ('TuneBoxPC_Results_{0:yyyyMMdd_HHmm}.txt' -f (Get-Date))
  [IO.File]::WriteAllText($file, $txt)
  $ui.statusText.Text = "Saved: $file"
})

$win.Add_Closing({
  param($s, $e)
  if ($App.Busy) {
    $r = [System.Windows.MessageBox]::Show('A task is still running. Close anyway?', 'TuneBox PC', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { $e.Cancel = $true; return }
    try { $App.Job.PS.Stop() } catch {}
  }
  $timer.Stop(); $dash.Stop()
})

# ---------- start ----------
Add-Log '  Welcome to TuneBox PC.' 'Cyan'
Add-Log '  Tip: click "Create restore point first" before changing settings.' 'Dim'
Add-Log '  Then try Quick Optimize, Drive health check, or PC activity history.' 'Dim'
Update-Dash
$timer.Start(); $dash.Start()
[void]$win.ShowDialog()
