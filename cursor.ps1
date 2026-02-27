# =========================================
# Touchpad Ghost-Move Auto Repair
# =========================================

Write-Host "=== Touchpad Repair: Fix Ghost Cursor Movement ===" -ForegroundColor Cyan

# Cari semua device yang berpotensi touchpad
$tp = Get-PnpDevice | Where-Object {
    $_.FriendlyName -match "Touchpad|Synaptics|ELAN|I2C HID|Precision|DELL|ASUS"
}

if (-not $tp) {
    Write-Host "Touchpad tidak ditemukan." -ForegroundColor Red
    return
}

Write-Host "`nPerangkat touchpad:" -ForegroundColor Yellow
$tp | Select-Object Status,Class,FriendlyName | Format-Table -AutoSize

# Step 1: Maximum safe repair (disable → enable)
Write-Host "`n[1] Reset (disable-enable) touchpad..." -ForegroundColor Cyan
foreach ($d in $tp) {
    try {
        Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep 1
        Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
}

# Step 2: Restart HID + PnP service
Write-Host "[2] Restart HID & Plug and Play services..."
Restart-Service -Name "hidserv" -ErrorAction SilentlyContinue
Restart-Service -Name "PlugPlay" -Force

# Step 3: Force re-enumeration
Write-Host "[3] Scan ulang perangkat..."
pnputil /scan-devices | Out-Null

# Step 4: Test ghost movement
Write-Host "`n[4] Menguji apakah touchpad masih mengirim input..." -ForegroundColor Yellow
Write-Host "Matikan touchpad dulu..."

$ghost = $false

foreach ($d in $tp) {
    Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host "Touchpad dimatikan. Gerakkan kursor hanya pakai mouse. Jika kursor MASIH bergerak sendiri → hardware rusak." -ForegroundColor Magenta
Write-Host "Tunggu 10 detik..."
Start-Sleep 10

Write-Host "Mengaktifkan kembali touchpad..."
foreach ($d in $tp) {
    Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host "`n=== Selesai ==="
