Write-Host "=== Touchpad Auto Diagnose + Auto Fix ===" -ForegroundColor Cyan

function Pause-Input {
    Start-Sleep -Milliseconds 800
}

# -------------------------------
# Step 1: Detect Touchpad Devices
# -------------------------------
Write-Host "`n[1] Mendeteksi perangkat touchpad/HID..." -ForegroundColor Yellow
$tp = Get-PnpDevice | Where-Object {
    $_.FriendlyName -match "Touchpad|Synaptics|I2C HID|ELAN|Precision|HID-compliant mouse|PS/2"
}

if (-not $tp) {
    Write-Host "Tidak ditemukan perangkat touchpad sama sekali! Kemungkinan hardware lepas." -ForegroundColor Red
    $Global:diagnosis = "hardware_missing"
    return
}

Write-Host "Perangkat terdeteksi:"
$tp | Select-Object FriendlyName, Status | Format-Table

Pause-Input

# -------------------------------
# Step 2: Periksa status driver
# -------------------------------
Write-Host "`n[2] Mengecek status driver..." -ForegroundColor Yellow

$bad = $tp | Where-Object { $_.Status -ne "OK" }

if ($bad) {
    Write-Host "Ditemukan driver bermasalah:" -ForegroundColor Red
    $bad | Format-Table
    $Global:driver_issue = $true
} else {
    Write-Host "Semua driver OK." -ForegroundColor Green
    $Global:driver_issue = $false
}

Pause-Input

# -------------------------------
# Step 3: Test: Disable Touchpad
# -------------------------------
Write-Host "`n[3] Menguji apakah kursor masih bergerak saat touchpad dan HID dimatikan..." -ForegroundColor Yellow

# Disable touchpad + HID temporarily
$devs = Get-PnpDevice | Where-Object {
    $_.FriendlyName -match "Touchpad|Synaptics|I2C HID|ELAN|HID-compliant mouse"
}

foreach ($d in $devs) { 
    try { Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop } catch {}
}

Write-Host "Touchpad & HID dimatikan sementara... uji 7 detik."
Start-Sleep -Seconds 7

# Detect whether cursor is still producing events
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MouseCheck {
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);
    public struct POINT { public int X; public int Y; }
}
"@

$pos1 = New-Object MouseCheck+POINT
$pos2 = New-Object MouseCheck+POINT

[MouseCheck]::GetCursorPos([ref]$pos1)
Start-Sleep -Milliseconds 800
[MouseCheck]::GetCursorPos([ref]$pos2)

if ($pos1.X -ne $pos2.X -or $pos1.Y -ne $pos2.Y) {
    $Global:cursor_still_moves = $true
    Write-Host "KURSOR MASIH BERGERAK meski touchpad & HID dinonaktifkan!" -ForegroundColor Red
} else {
    $Global:cursor_still_moves = $false
    Write-Host "Kursor berhenti saat touchpad dimatikan. Ini 99% masalah driver." -ForegroundColor Green
}

# Restore devices
foreach ($d in $devs) { 
    try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop } catch {}
}

Pause-Input

# -------------------------------
# Step 4: HID Service Check + Fix
# -------------------------------
Write-Host "`n[4] Mengecek HID Service..." -ForegroundColor Yellow
$svc = Get-Service -Name hidserv -ErrorAction SilentlyContinue

if ($svc -and $svc.Status -ne "Running") {
    Write-Host "HID Service tidak berjalan. Memperbaiki..." -ForegroundColor Red
    try {
        Set-Service -Name hidserv -StartupType Automatic -ErrorAction Stop
        Start-Service -Name hidserv -ErrorAction Stop
        Write-Host "HID Service berhasil diperbaiki." -ForegroundColor Green
    } catch {
        Write-Host "Gagal memperbaiki HID Service (butuh run as Admin)." -ForegroundColor Red
    }
} else {
    Write-Host "HID Service normal." -ForegroundColor Green
}

Pause-Input

# -------------------------------
# Step 5: Kesimpulan Otomatis
# -------------------------------
Write-Host "`n=== HASIL DIAGNOSA ===" -ForegroundColor Cyan

if ($Global:diagnosis -eq "hardware_missing") {
    Write-Host "Touchpad tidak terdeteksi. Kemungkinan kabel touchpad lepas atau hardware rusak." -ForegroundColor Red
    return
}

if ($Global:cursor_still_moves) {
    Write-Host "`nKursor masih bergerak padahal touchpad & HID OFF → 100% masalah hardware." -ForegroundColor Red
    Write-Host "Kemungkinan besar:" -ForegroundColor Yellow
    Write-Host " - Sensor touchpad short" 
    Write-Host " - Grounding laptop bermasalah"
    Write-Host " - Kabel touchpad rusak/longgar"
    Write-Host " - USB phantom device / port short"
    return
}

if ($Global:driver_issue) {
    Write-Host "`nMasalah driver terdeteksi → memperbaiki otomatis..." -ForegroundColor Yellow

    $bad | ForEach-Object {
        try {
            Write-Host "Uninstall + reinstall $_.FriendlyName ..."
            pnputil /restart-device "$($_.InstanceId)" | Out-Null
        } catch {}
    }

    Write-Host "Driver telah diperbaiki. Restart disarankan." -ForegroundColor Green
    return
}

Write-Host "`nTouchpad fix selesai. Tidak ada masalah hardware, service, atau driver." -ForegroundColor Green

Write-Host "`n=== SELESAI ===" -ForegroundColor Cyan
