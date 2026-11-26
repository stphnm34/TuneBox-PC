# Reverses the system-level changes TuneBox PC can make, so the PC is
# left clean after uninstall. Safe to run on its own too.
# - Unblocks any apps that were blocked (removes the IFEO "Debugger" entries).
# - Removes the Auto power off scheduled task and stops its watcher.
# - Cancels any pending auto shutdown.
# - Puts screen/sleep timers back to Windows defaults.
# It does NOT touch the ads/background preference tweaks - those are harmless
# and are left as you set them.
$ErrorActionPreference = 'SilentlyContinue'

# 1. Unblock apps (IFEO entries that point to our blocker)
$IFEO = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
Get-ChildItem $IFEO | ForEach-Object {
  $dbg = (Get-ItemProperty -Path $_.PSPath -Name Debugger -ErrorAction SilentlyContinue).Debugger
  if ("$dbg" -like '*TuneBoxPC*') { Remove-ItemProperty -Path $_.PSPath -Name Debugger -ErrorAction SilentlyContinue }
}

# 2. Auto power off: scheduled task + running watcher + pending shutdown
Unregister-ScheduledTask -TaskName 'TuneBox PC Auto Power Off' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*TuneBoxPC\AutoOff.ps1*' } |
  ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
shutdown /a 2>$null | Out-Null

# 3. Power timers back to Windows defaults
powercfg /change monitor-timeout-ac 10 | Out-Null
powercfg /change monitor-timeout-dc 5  | Out-Null
powercfg /change standby-timeout-ac 30 | Out-Null
powercfg /change standby-timeout-dc 15 | Out-Null

# 4. Remove the app's data folder
Remove-Item -LiteralPath (Join-Path $env:ProgramData 'TuneBoxPC') -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'System changes reversed: apps unblocked, auto power off removed, timers reset.'
