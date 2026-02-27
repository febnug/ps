# ============================
# Touchpad Driver Checker v2
# Safe for IRM (no Unicode)
# ============================

Write-Host "=== Touchpad Driver Checker ===`n" -ForegroundColor Cyan

# Daftar pola yang dianggap touchpad
$patterns = "Touchpad","I2C HID","Precision","Synaptics","ELAN","ALPS","Dell Touchpad","Lenovo Touchpad"

# Ambil semua device terkait touchpad
$touchpad = Get-PnpDevice | Where-Object {
    foreach ($p in $patterns) {
        if ($_.FriendlyName -match $p) { return $true }
    }
    return $false
}

# Jika tidak ditemukan
if (-not $touchpad -or $touchpad.Count -eq 0) {
    Write-Host "[X] Touchpad tidak ditemukan." -ForegroundColor Red
    Write-Host "Kemungkinan:"
    Write-Host " - Driver hilang atau corrupt"
    Write-Host " - Touchpad dimatikan dari BIOS"
    Write-Host " - Windows belum mengenali device"
    return
}

# Tampilkan device touchpad
Write-Host "Perangkat touchpad terdeteksi:" -ForegroundColor Yellow
$touchpad | Select-Object FriendlyName, Status | Format-Table

# Cek apakah ada yang bermasalah
$bad = $touchpad | Where-Object { $_.Status -ne "OK" }

if ($bad) {
    Write-Host "`n[X] Driver touchpad bermasalah!" -ForegroundColor Red
    $bad | Select-Object FriendlyName, Status | Format-Table

    Write-Host "`nRekomendasi:" -ForegroundColor Cyan
    Write-Host " - Reinstall driver touchpad dari vendor"
    Write-Host " - Pastikan Windows Update selesai"
    Write-Host " - Restart HID Service: sc start hidserv"
    Write-Host " - Jika tetap bermasalah, cek I2C driver"
} else {
    Write-Host "`n[OK] Driver touchpad normal." -ForegroundColor Green
}

Write-Host "`n=== Selesai ==="
