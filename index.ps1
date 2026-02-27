# ASUS Touchpad Auto Diagnose & Auto Fix
# IRM-ready. Run as Administrator for full repair.
# Safe: no destructive uninstall; uses disable/enable and service restarts + SFC/DISM as needed.

# ---------- Helpers ----------
function Is-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Is-Admin)) {
    Write-Host "Not running elevated. Trying to restart as Administrator..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell" -ArgumentList ("-ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Path + "`"") -Verb RunAs
    exit
}

$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$report = "$env:USERPROFILE\Desktop\asus_touchpad_report_$timestamp.txt"
function Log {
    param([string]$text)
    $text | Tee-Object -FilePath $report -Append
    Write-Host $text
}

Log "=== ASUS Touchpad Auto Diagnose & Auto-Fix ($timestamp) ==="
Log "User: $env:USERNAME  Computer: $env:COMPUTERNAME"
Log ""

# ---------- Detection Patterns ----------
$patterns = @(
    "ASUS","Asus","Touchpad","Precision","Synaptics","ELAN","I2C HID",
    "Intel Serial IO","Serial IO","I2C","PS/2 Compatible Mouse"
)

# ---------- Step 1: Enumerate relevant devices ----------
Log "[1] Enumerating ASUS / touchpad related PnP devices..."
$pnpAll = Get-PnpDevice -ErrorAction SilentlyContinue
$tpDevices = @()
foreach ($p in $patterns) {
    $found = $pnpAll | Where-Object { $_.FriendlyName -match $p -or $_.InstanceId -match $p } 
    if ($found) { $tpDevices += $found }
}
$tpDevices = $tpDevices | Sort-Object FriendlyName -Unique

if (-not $tpDevices -or $tpDevices.Count -eq 0) {
    Log "  [X] No ASUS/touchpad-related devices found via pattern list."
    Log "  Recommendation: check BIOS settings (touchpad may be disabled) or open laptop for hardware check."
    exit 1
}

Log "  Detected devices:"
$tpDevices | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String | Log

# ---------- Step 2: Driver status check ----------
Log ""
Log "[2] Checking driver statuses..."
$badDrivers = $tpDevices | Where-Object { $_.Status -ne "OK" -and $_.Status -ne $null }
if ($badDrivers) {
    Log "  [!] Some devices report non-OK status:"
    $badDrivers | Select-Object FriendlyName, Status, ProblemCode | Format-Table | Out-String | Log
} else {
    Log "  [OK] All detected devices report OK status."
}

# ---------- Step 3: Check important services (HID + ASUS related) ----------
Log ""
Log "[3] Checking relevant services (HID, PlugPlay, ASUS/ATK)..."
$servicePatterns = "hidserv","PlugPlay","WudfSvc","ATKPackage","Asus","ASUS","AsHid","AsusFan","ASUS ACPI"
$svcFound = @()
foreach ($sp in $servicePatterns) {
    $s = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $sp -or $_.DisplayName -match $sp }
    if ($s) { $svcFound += $s }
}
$svcFound = $svcFound | Sort-Object Name -Unique
if ($svcFound) {
    foreach ($s in $svcFound) {
        Log ("  Service: {0,-25} Status: {1}" -f $s.Name, $s.Status)
    }
} else {
    Log "  No ASUS-specific services discovered by name pattern (this is OK if vendor uses drivers only)."
}

# ---------- Step 4: Ghost cursor hardware vs software test ----------
Log ""
Log "[4] Hardware vs Software test: disabling touchpad devices briefly and observing cursor movement..."
# Save initial position
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MousePos {
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);
    public struct POINT { public int X; public int Y; }
}
"@

function Get-CursorPos {
    $pt = New-Object MousePos+POINT
    [MousePos]::GetCursorPos([ref]$pt) | Out-Null
    return $pt
}

$posBefore = Get-CursorPos

# Identify touchpad devices to disable (narrow selection)
$toToggle = $tpDevices | Where-Object {
    $_.FriendlyName -match "Touchpad|I2C|Precision|Synaptics|ELAN|PS/2|Dell Touchpad|ASUS"
} | Sort-Object FriendlyName -Unique

if (-not $toToggle -or $toToggle.Count -eq 0) {
    Log "  [WARN] No specific touchpad candidates to toggle. Using all detected devices."
    $toToggle = $tpDevices
}

# Attempt disable -> wait -> check -> enable
foreach ($d in $toToggle) {
    try {
        Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
        Log ("  Disabled: {0}" -f $d.FriendlyName)
    } catch {
        Log ("  Cannot disable {0} (may be kernel/driver protected): {1}" -f $d.FriendlyName, $_.Exception.Message)
    }
}

Start-Sleep -Seconds 7
$posAfterDisable = Get-CursorPos
if ($posBefore.X -ne $posAfterDisable.X -or $posBefore.Y -ne $posAfterDisable.Y) {
    Log "  [HARDWARE] Cursor moved while touchpad devices were disabled -> likely hardware or phantom device (100% hardware or other input source)."
    $Global:diagnosis = "hardware"
} else {
    Log "  [SOFTWARE] Cursor did NOT move while touchpad devices were disabled -> likely software/driver issue."
    $Global:diagnosis = "software"
}

# Re-enable devices
foreach ($d in $toToggle) {
    try {
        Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
        Log ("  Re-enabled: {0}" -f $d.FriendlyName)
    } catch {
        Log ("  Cannot re-enable {0}: {1}" -f $d.FriendlyName, $_.Exception.Message)
    }
}

# ---------- Step 5: Auto-fix flows ----------
Log ""
if ($Global:diagnosis -eq "hardware") {
    Log "[5] Diagnosis: HARDWARE suspected."
    Log "  Recommendations:"
    Log "   - Shutdown and reseat touchpad ribbon cable (service center) or check motherboard connector."
    Log "   - Test with external USB mouse removed; check for phantom USB device."
    Log "   - If laptop recently exposed to moisture, dry and test again."
    Log "   - If under warranty, contact ASUS service with report at: $report"
    Log ""
    Log "  Exiting without destructive actions."
    exit 0
}

# Diagnosis == software -> attempt auto-repair
Log "[5] Diagnosis: SOFTWARE suspected. Attempting staged auto-repair..."

# 5.a Restart services: HID + PlugPlay + WUDF
Log "  Restarting core services (hidserv, PlugPlay, WudfSvc) if present..."
foreach ($svcName in "hidserv","PlugPlay","WudfSvc") {
    try {
        $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($s -and $s.Status -ne "Running") {
            Log ("    Starting service {0}..." -f $svcName)
            sc.exe config $svcName start= auto | Out-Null
            sc.exe start $svcName | Out-Null
            Start-Sleep -Milliseconds 600
        } elseif ($s) {
            Log ("    Service {0} already running." -f $svcName)
        }
    } catch {
        Log ("    Service restart {0} failed: {1}" -f $svcName, $_.Exception.Message)
    }
}

# 5.b Restart Plug and Play (may unload/reload devices)
try {
    Log "  Restarting Plug and Play (may disrupt other devices briefly)..."
    Restart-Service -Name "PlugPlay" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
} catch {
    Log ("  Restart PlugPlay failed: {0}" -f $_.Exception.Message)
}

# 5.c Disable/Enable the problematic devices (try to target only those with non-OK)
$target = $tpDevices | Where-Object { $_.Status -ne "OK" } 
if (-not $target -or $target.Count -eq 0) { $target = $tpDevices }

Log "  Performing disable/enable cycle on target devices..."
foreach ($d in $target) {
    try {
        Log ("    Disabling {0} ..." -f $d.FriendlyName)
        Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 800
        Log ("    Enabling {0} ..." -f $d.FriendlyName)
        Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 800
    } catch {
        Log ("    Disable/Enable failed for {0}: {1}" -f $d.FriendlyName, $_.Exception.Message)
    }
}

# 5.d Trigger device re-scan
try {
    Log "  Triggering device re-scan (pnputil /scan-devices)..."
    pnputil /scan-devices | Out-Null
} catch {
    Log "  pnputil scan-devices failed or not present"
}

# 5.e Run SFC/DISM minimal if driver issues were detected earlier
if ($badDrivers) {
    Log "  Running DISM RestoreHealth and SFC to repair possible corrupted components..."
    try { DISM /Online /Cleanup-Image /RestoreHealth | Out-Null } catch { Log "    DISM failed or limited." }
    try { sfc /scannow | Out-Null } catch { Log "    SFC failed or limited." }
    Log "  SFC/DISM completed (or attempted). A reboot is recommended."
}

# 5.f Final quick check: re-evaluate statuses
Start-Sleep -Seconds 2
$pnpAll = Get-PnpDevice -ErrorAction SilentlyContinue
$tpDevicesNew = @()
foreach ($p in $patterns) {
    $found = $pnpAll | Where-Object { $_.FriendlyName -match $p -or $_.InstanceId -match $p } 
    if ($found) { $tpDevicesNew += $found }
}
$tpDevicesNew = $tpDevicesNew | Sort-Object FriendlyName -Unique

Log ""
Log "[6] Final device statuses after repair attempts:"
$tpDevicesNew | Select-Object FriendlyName, Status, ProblemCode | Format-Table | Out-String | Log

# ---------- Step 6: Conclusion & Recommendations ----------
Log ""
Log "=== CONCLUSION ==="
if ($Global:diagnosis -eq "software") {
    $stillBad = $tpDevicesNew | Where-Object { $_.Status -ne "OK" }
    if ($stillBad) {
        Log "  [!] Some devices still report non-OK. Next steps:"
        Log "    - Reboot the laptop and re-check."
        Log "    - Update ASUS chipset / I2C / Precision Touchpad drivers from ASUS support."
        Log "    - If persists, collect report file and contact service center: $report"
    } else {
        Log "  [OK] Devices now report OK. Test cursor behavior; if ghost movement persists, try reboot."
    }
}

Log ""
Log "Report saved to: $report"
Log "End of script."
