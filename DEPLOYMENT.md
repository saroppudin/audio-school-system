# 📋 Deployment Checklist & Guide

## Pre-Deployment Phase

### 1. Infrastructure Preparation

```bash
# [ ] Hardware ready
  - [ ] Debian 13 minimal install done
  - [ ] Bluetooth adapter available & working
  - [ ] Speaker/mixer device Bluetooth ready
  - [ ] Network connectivity (Ethernet preferred)
  - [ ] At least 2GB free disk space
  - [ ] BIOS/UEFI settings verified

# [ ] User & SSH setup
  - [ ] Non-root user created (default: lenovo)
  - [ ] SSH key pairs generated
  - [ ] SSH configured properly
  - [ ] Firewall configured (UFW recommended)
```

### 2. Hardware Pairing (CRITICAL)

```bash
# Pairing Bluetooth speaker SEBELUM instalasi otomasi

# Step 1: Power on speaker
# Step 2: Make discoverable (usually hold button 3-5 seconds)

# Step 3: Scan devices
bluetoothctl scan on
# Wait for device name to appear

# Step 4: Note MAC address
# Example output:
# [CHR] XX:XX:XX:XX:XX:XX  DeviceName

# Step 5: Pair device
bluetoothctl pair XX:XX:XX:XX:XX:XX

# Step 6: Trust device
bluetoothctl trust XX:XX:XX:XX:XX:XX

# Step 7: Verify connection
bluetoothctl info XX:XX:XX:XX:XX:XX
# Should show: Connected: yes

# ⚠️ SAVE MAC ADDRESS!
# Will need it for: MAC_SPEAKER in sekolah.conf
```

### 3. Audio Files Preparation

```bash
# [ ] Collect all required MP3 files
  - [ ] Lagu Pagi (4 files)
  - [ ] Indonesia Raya (1 file)
  - [ ] Bel Dzuhur (1 file)
  - [ ] Bel Ujian (6 files)
  - [ ] Tarhim (4 files)

# [ ] Validate audio files
  - Format: MP3, 128-320 kbps
  - Duration: Check reasonable (not too short/long)
  - Test play on computer before deployment

# [ ] Prepare upload method
  - [ ] SSH/SCP ready
  - [ ] Or USB drive (if not networked)
  - [ ] Or rsync (for large transfers)
```

### 4. Configuration Planning

```bash
# [ ] Gather school information
  NAMA_SEKOLAH="SMK Negeri Purworejo"
  GARIS_LINTANG="-7.7134"       # Check Google Maps
  GARIS_BUJUR="109.9961"
  MAC_SPEAKER="XX:XX:XX:XX:XX:XX"  # From Bluetooth pairing

# [ ] Plan schedule
  - [ ] Morning bell time: __ : __
  - [ ] Indonesia Raya time: __ : __
  - [ ] Dzuhur bell time: __ : __
  - [ ] Exam schedule (if applicable)
```

---

## Installation Phase

### Step 1: Download Repository

```bash
sudo git clone https://github.com/saroppudin/audio-school-system /opt/audio-school
cd /opt/audio-school
```

### Step 2: Edit Configuration

Edit variabel konfigurasi **langsung di dalam** `scripts/Installer-bel-v13.sh` (bagian "1. KONFIGURASI SEKOLAH" di awal file) — bukan di `config/sekolah.conf.example` (file itu cuma contoh referensi format):

```bash
sudo nano scripts/Installer-bel-v13.sh
```

**Key parameters to edit:**
```bash
USER_SISTEM="lenovo"                    # Your non-root user
NAMA_SEKOLAH="SMK Negeri Purworejo"
GARIS_LINTANG="-7.7134"
GARIS_BUJUR="109.9961"
MAC_SPEAKER="XX:XX:XX:XX:XX:XX"         # From pairing step
```

### Step 3: Run Installer

```bash
# Run installer dengan verbose output
sudo bash scripts/Installer-bel-v13.sh 2>&1 | tee install.log

# Monitor installation (in another terminal)
tail -f install.log
```

**Expected output (V14):**
```
====================================================
 Memulai Instalasi Otomatisasi Audio V14
====================================================
[INFO] Validasi pre-instalasi...
[1/9] Menginstal paket pendukung Debian...
[2/9] Mengonfigurasi adapter Bluetooth agar auto-enable saat boot...
[3/9] Mengonfigurasi BlueALSA (mode A2DP Source - PC sebagai pengirim audio)...
[4/9] Mengunci PCM ALSA 'bluealsa' ke speaker (XX:XX:XX:XX:XX:XX)...
[5/9] Mencoba memasangkan (pairing) ke speaker XX:XX:XX:XX:XX:XX...
[6/9] Membuat struktur folder dan file konfigurasi...
[7/9] Membuat berkas skrip operasional audio...
[8/9] Daftarkan skrip ke Systemd Service...
[8b/9] Mengonfigurasi Logrotate global...
[8c/9] Mendaftarkan jadwal harian tetap di Crontab...
[9/9] Verifikasi akhir & ringkasan instalasi...

====================================================
  INSTALASI SELESAI - SMK Negeri Purworejo
====================================================
✓ Sistem Operasi    : Debian 13 Headless
✓ User Operasional  : lenovo
✓ Bluetooth Adapter : Terdeteksi
✓ Speaker Target    : XX:XX:XX:XX:XX:XX
 Service aktif      : tahrim-daemon.service (nonstop), bt-boot-connect.service (oneshot saat boot)
```

> **Catatan V14:** tidak ada lagi `anti-putus.service` di daftar service. Reconnect Bluetooth sekarang ditangani `bt-boot-connect.service` (jalan sekali saat boot) + `sambung_bt.sh` (on-demand sebelum tiap bel).

### Step 4: Upload Audio Files

```bash
# Option A: Using SCP (from your computer)
cd /path/to/audio/files
scp *.mp3 lenovo@<server-ip>:/home/lenovo/audio/

# Option B: Using rsync (faster for large transfers)
rsync -avz audio/ lenovo@<server-ip>:/home/lenovo/audio/

# Option C: Using SSH + tar (if network unreliable)
tar -czf audio.tar.gz *.mp3
ssh lenovo@<server-ip> 'mkdir -p /home/lenovo/audio'
scp audio.tar.gz lenovo@<server-ip>:/tmp/
ssh lenovo@<server-ip> 'tar -xzf /tmp/audio.tar.gz -C /home/lenovo/audio'

# Verify upload
ssh lenovo@<server-ip> 'ls -la /home/lenovo/audio/ | head -20'
```

---

## Verification Phase

### 1. Service Status Check

```bash
sudo systemctl status tahrim-daemon.service
# Should show: active (running)

sudo systemctl status bt-boot-connect.service
# WAJAR kalau statusnya "inactive (dead)" -- ini Type=oneshot, jalan
# sekali saat boot lalu selesai. Yang penting cek TIDAK gagal:
sudo systemctl is-failed bt-boot-connect.service
# Harus keluar: active (artinya tidak failed)
```

### 2. Health Check

```bash
/home/lenovo/cek_kesehatan.sh

# Should show:
# - Services: active
# - Bluetooth: TERHUBUNG
# - NTP: yes
# - Disk: sufficient space
# - Recent logs: successful
```

### 3. Bluetooth Connectivity

```bash
bluetoothctl info <MAC_SPEAKER>
# Should show: Connected: yes

# Test audio playback
mpv --audio-device=alsa/bluealsa /home/lenovo/audio/test.mp3
```

### 4. Log Verification

```bash
tail -50 /var/log/otomasi_audio.log

# Should show:
# - Successful service starts
# - API calls to Aladhan (if prayer time configured)
# - No ERROR messages (warnings OK)
```

---

## Testing Phase

### 1. Manual Playback Test

```bash
/home/lenovo/putar_audio.sh test "Test Audio" \
    /home/lenovo/audio/Hymne-guru.mp3

# Audio should play on speaker
# Check log: grep "PLAY\|SUCCESS" /var/log/otomasi_audio.log
```

### 2. Schedule Test

```bash
# Add test schedule for 1 minute from now
TEST_TIME=$(date -d "+1 minute" +%H:%M)
/home/lenovo/kelola_ujian.sh tambah $TEST_TIME bel-masuk-ruangan.mp3

# Wait for time to pass
# Audio should play automatically

# Cleanup
/home/lenovo/kelola_ujian.sh hapus $TEST_TIME
```

### 3. Bluetooth Reconnection Test

```bash
# Disconnect Bluetooth speaker manually
# Wait, lalu trigger satu playback manual (V14 reconnect terjadi
# on-demand sebelum play, BUKAN otomatis tiap saat seperti versi lama)
/home/lenovo/putar_audio.sh test "Test Reconnect" /home/lenovo/audio/test.mp3

# Verify di log:
grep "PLAY\|SUCCESS" /var/log/otomasi_audio.log | tail -5
```

### 4. Reboot Test (khusus V14 — PENTING)

```bash
# Test paling penting untuk memastikan bt-boot-connect.service bekerja
sudo reboot

# Setelah nyala lagi, tunggu ~1 menit, TANPA melakukan apapun manual:
bluetoothctl info <MAC_SPEAKER> | grep Connected
# Harus: Connected: yes (reconnect otomatis dari bt-boot-connect.service)
```

---

## Production Deployment

### 1. Final Verification

```bash
# [ ] All health checks passing
# [ ] Audio files complete & correct
# [ ] Cron jobs configured
# [ ] Bluetooth reconnect setelah reboot berhasil (lihat Testing Phase #4)
# [ ] Logs clean (no errors)
```

### 2. Go-Live Procedure

```bash
# 1. Set mode to production
/home/lenovo/mode_sekolah.sh hari_biasa

# 2. Verify schedule
/home/lenovo/kelola_ujian.sh daftar

# 3. Monitor for 1 hour
tail -f /var/log/otomasi_audio.log

# 4. If all OK, mark in calendar
# 5. Communicate to school staff
```

---

## Troubleshooting During Deployment

### Issue: Installation hangs at [2/9]
**Cause:** Bluetooth adapter not detected
**Fix:**
```bash
bluetoothctl list
# If no output: Reboot, check BIOS, try different USB port
```

### Issue: Installer fails at sudoers validation
**Cause:** Syntax error in sudoers file
**Fix:**
```bash
sudo visudo -c
sudo rm -f /etc/sudoers.d/otomasi-audio
# Re-run installer
```

### Issue: Audio not playing after installation
**Cause:** Audio files missing or wrong path
**Fix:**
```bash
ls -la /home/lenovo/audio/ | head -20
stat /home/lenovo/audio/test.mp3
mpv /home/lenovo/audio/test.mp3
```

---

**Estimated Total Deployment Time:** 30-45 minutes
**Last Updated:** 2026-07-10 (V14)
