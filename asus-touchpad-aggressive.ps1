# ============================
# ASUS Touchpad Aggressive Checker v4 (Ultra Safe Version)
# ============================

# --- Auto Elevate ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] 'Administrator'
)

if (-not $IsAdmin) {
    Write-Host '[!] Not elevated — Restarting as Administrator...' -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-ExecutionPolicy Bypass -File "' + $PSCommandPath + '"')
    exit
}

Write-Host ''
Write-Host '=== ASUS Touchpad Aggressive Diagnostic v4 ===' -ForegroundColor Cyan
Write-Host ''

# --- Touchpad patterns ---
$patterns = @(
    'Touchpad','I2C HID','Precision','Synaptics','ELAN','ALPS','ASUS','ASUSTeK','HID Touchpad'
)

Write-Host '[*] Scanning Touchpad Devices...' -ForegroundColor Green

$devices = Get-PnpDevice | Where-Object {
    $name = $_.FriendlyName
    foreach ($p in $patterns) {
        if ($name -like ('*' + $p + '*')) { return $true }
    }
    return $false
}

if (-not $devices) {
    Write-Host '[X] No touchpad-related devices found!' -ForegroundColor Red
    exit
}

foreach ($dev in $devices) {

    Write-Host '---------------------------------' -ForegroundColor DarkGray
    Write-Host ('Device       : ' + $dev.FriendlyName)
    Write-Host ('Status       : ' + $dev.Status)
    Write-Host ('Class        : ' + $dev.Class)
    Write-Host ('Instance ID  : ' + $dev.InstanceId)
    Write-Host ('Error Code   : ' + $dev.ProblemCode)

    switch ($dev.ProblemCode) {
        0   { $msg = 'OK (No issues detected)' }
        10  { $msg = 'Code 10: Device failed to start (driver corrupt / service error).' }
        28  { $msg = 'Code 28: Driver not installed.' }
        31  { $msg = 'Code 31: Windows cannot load driver.' }
        43  { $msg = 'Code 43: Device returned a failure signal.' }
        56  { $msg = 'Code 56: Driver conflict or invalid data.' }
        default { $msg = 'Unknown error or no issue.' }
    }

    Write-Host ('Explanation  : ' + $msg) -ForegroundColor Yellow

    Write-Host ''
    Write-Host '[*] Checking registry...' -ForegroundColor Cyan

    $regPaths = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\i8042prt',
        'HKLM:\SYSTEM\CurrentControlSet\Services\SynTP',
        'HKLM:\SYSTEM\CurrentControlSet\Services\ETD'
    )

    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            Write-Host (' - Exists : ' + $rp) -ForegroundColor Green
        } else {
            Write-Host (' - Missing: ' + $rp) -ForegroundColor DarkYellow
        }
    }

    Write-Host ''
    Write-Host '[*] Checking HID IRQ conflicts...' -ForegroundColor Cyan

    $hid = Get-WmiObject Win32_IRQResource | Where-Object { $_.Name -like '*HID*' }

    if ($hid) {
        foreach ($h in $hid) {
            Write-Host ('IRQ: ' + $h.IRQNumber + ' - ' + $h.Name)
        }
    } else {
        Write-Host 'No IRQ conflict.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '[*] Checking Power Management...' -ForegroundColor Cyan

    $pm = Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -eq $dev.FriendlyName }

    if ($pm) {
        if ($pm.PowerManagementSupported) {
            Write-Host 'Power Management Supported: YES' -ForegroundColor Green
        } else {
            Write-Host 'Power Management Supported: NO' -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host '=== Scan Complete ===' -ForegroundColor Cyan
Write-Host ''
