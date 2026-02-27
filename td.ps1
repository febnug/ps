Write-Host "=== TOUCHPAD DIAGNOSE TOOL v3 ===`n" -ForegroundColor Cyan

# --------------------------
# 1. DETEKSI HID / TOUCHPAD
# --------------------------
Write-Host "[1] Mendeteksi perangkat touchpad..." -ForegroundColor Yellow

$tp = Get-PnpDevice | Where-Object {
    $_.Class -match "HID|Mouse|Sensor" -or $_.FriendlyName -match "Touch|Synaptics|ELAN|I2C"
}

if ($tp) {
    Write-Host "Perangkat HID / Touchpad ditemukan:" -ForegroundColor Green
    $tp.FriendlyName | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "Tidak ditemukan perangkat touchpad!" -ForegroundColor Red
}

# --------------------------
# 2. CEK DRIVER STATUS
# --------------------------
Write-Host "`n[2] Mengecek status driver..." -ForegroundColor Yellow

$prob = Get-PnpDevice | Where-Object { $_.Status -ne "OK" }

if ($prob) {
    Write-Host "Ditemukan driver bermasalah:" -ForegroundColor Red
    $prob | Select-Object Class, FriendlyName, Status | Format-Table
} else {
    Write-Host "Semua driver OK." -ForegroundColor Green
}

# --------------------------
# 3. CEK I2C CONTROLLER
# --------------------------
Write-Host "`n[3] Mengecek I2C Controller..." -ForegroundColor Yellow

$i2c = Get-PnpDevice | Where-Object { $_.FriendlyName -match "I2C|SMBus|Precision" }

if ($i2c) {
    Write-Host "Controller I2C terdeteksi:" -ForegroundColor Green
    $i2c | Select-Object FriendlyName, Status | Format-Table
} else {
    Write-Host "I2C controller tidak ditemukan (bisa jadi masalah hardware)." -ForegroundColor Red
}

# --------------------------
# 4. CEK SERVICE HID
# --------------------------
Write-Host "`n[4] Mengecek service input..." -ForegroundColor Yellow

$services = "hidserv","TabletInputService","Wudfsvc"

foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Write-Host "$svc : $($s.Status)"
    } else {
        Write-Host "$svc : tidak ditemukan"
    }
}

# --------------------------
# 5. AUTO-FIX HID SERVICE
# --------------------------
Write-Host "`n[5] Memperbaiki HID Service jika mati..." -ForegroundColor Yellow

$hid = Get-Service hidserv -ErrorAction SilentlyContinue

if ($hid.Status -ne "Running") {
    Write-Host "HID Service tidak berjalan → memperbaiki..." -ForegroundColor Red
    Set-Service -Name hidserv -StartupType Automatic
    Start-Service -Name hidserv
    Write-Host "HID Service sudah diperbaiki dan berjalan." -ForegroundColor Green
} else {
    Write-Host "HID Service sudah berjalan normal." -ForegroundColor Green
}

# --------------------------
# 6. CEK IRQ CONFLICT
# --------------------------
Write-Host "`n[6] Mengecek kemungkinan IRQ conflict..." -ForegroundColor Yellow

$irq = Get-CimInstance Win32_IRQResource
$conflict = $irq | Group-Object IRQNumber | Where-Object { $_.Count -gt 1 -and $_.Name -ne "0" }

if ($conflict) {
    Write-Host "Ada kemungkinan IRQ conflict:" -ForegroundColor Red
    $conflict | ForEach-Object {
        Write-Host "IRQ $_.Name dipakai oleh:"
        $_.Group.Component | ForEach-Object { Write-Host " - $_" }
    }
} else {
    Write-Host "Tidak ada tanda IRQ conflict." -ForegroundColor Green
}

# --------------------------
# 7. CEK EVENT LOG ERROR TOUCHPAD
# --------------------------
Write-Host "`n[7] Mengecek Event Log terkait input..." -ForegroundColor Yellow

$log = Get-WinEvent -LogName System -ErrorAction SilentlyContinue |
       Where-Object { $_.Message -match "HID|I2C|Touch|Synaptics|ELAN|Precision" } |
       Select-Object TimeCreated, Id, LevelDisplayName, Message -First 20

if ($log) {
    Write-Host "Event log terkait input ditemukan (tidak semuanya error):" -ForegroundColor Cyan
    $log | Format-List
} else {
    Write-Host "Tidak ada error terkait input." -ForegroundColor Green
}

Write-Host "`n=== SELESAI. Diagnosa lengkap ditampilkan. ===`n" -ForegroundColor Cyan
