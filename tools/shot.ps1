# Captures home-screen states from the TV box for side-by-side review against docs/tvos-ref/.
# Usage: pwsh tools/shot.ps1 -Phase 0 [-Device 192.168.1.24:5555] [-Package com.bennyftw32.arctv.debug]
param(
    [Parameter(Mandatory)] [string] $Phase,
    [string] $Device = "192.168.1.24:5555",
    [string] $Package = "com.bennyftw32.arctv.debug"
)

$ErrorActionPreference = "Stop"
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
$out = Join-Path $PSScriptRoot "..\docs\shots\phase-$Phase"
New-Item -ItemType Directory -Force $out | Out-Null

& $adb connect $Device | Out-Null

function Key([string] $code, [int] $times = 1) {
    for ($i = 0; $i -lt $times; $i++) { & $adb -s $Device shell input keyevent $code | Out-Null; Start-Sleep -Milliseconds 350 }
}

function Shot([string] $name) {
    Start-Sleep -Milliseconds 800
    & $adb -s $Device shell screencap -p /sdcard/arc-shot.png | Out-Null
    & $adb -s $Device pull /sdcard/arc-shot.png (Join-Path $out "$name.png") | Out-Null
    & $adb -s $Device shell rm /sdcard/arc-shot.png | Out-Null
    Write-Host "saved $name.png"
}

# Fresh start on the dock.
& $adb -s $Device shell am force-stop $Package | Out-Null
& $adb -s $Device shell monkey -p $Package -c android.intent.category.HOME 1 | Out-Null
Start-Sleep -Seconds 4
Shot "01-home-dock"

Key KEYCODE_DPAD_RIGHT 2
Shot "02-dock-third-app"

Key KEYCODE_DPAD_DOWN
Shot "03-grid-focused"

Key KEYCODE_DPAD_DOWN 2
Shot "04-grid-scrolled"

Key KEYCODE_DPAD_UP 5
Shot "05-top"

Write-Host "Screenshots in $out"
