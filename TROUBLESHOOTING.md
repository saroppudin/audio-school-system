# 🔧 Troubleshooting Guide

## Common Issues & Solutions

### Issue 1: Bell tidak berbunyi

**Symptoms:** Tidak ada suara dari speaker saat jadwal bel

**Troubleshooting steps:**
```bash
# Step 1: Verify audio files exist
ls -la /home/lenovo/audio/ | head -20

# Step 2: Check Bluetooth connection
bluetoothctl info <MAC_SPEAKER>
# Should show: Connected: yes

# Step 3: Check volume
amixer sget Master
# Should be high (80-100%)

# Step 4: Test manual playback
mpv --audio-device=alsa/bluealsa /home/lenovo/audio/Hymne-guru.mp3

# Step 5: Check logs for errors
tail -20 /var/log/otomasi_audio.log | grep ERROR
```

**Common causes & fixes:**
- File missing: Upload audio files to `/home/lenovo/audio/`
- Bluetooth disconnected: Run `sudo /home/lenovo/sambung_bt.sh` (reconnect langsung), atau `sudo systemctl restart bt-boot-connect.service` (reconnect sekali via service)
- Volume low: Adjust with `amixer sset Master 100%`
- Service not running: `sudo systemctl status tahrim-daemon.service`

---

### Issue 2: Bluetooth tidak terhubung

**Symptoms:** "Bluetooth tidak terhubung" pada health check

**Troubleshooting steps:**
```bash
# Step 1: List Bluetooth adapters
bluetoothctl list
# Should show hci0 or similar

# Step 2: Check if adapter is powered on
bluetoothctl show
# Should show: Powered: yes

# Step 3: Power on if needed
bluetoothctl power on

# Step 4: Scan for devices
bluetoothctl scan on
# Wait for your speaker to appear

# Step 5: Pair if not paired yet
bluetoothctl pair <MAC_SPEAKER>

# Step 6: Trust the device
bluetoothctl trust <MAC_SPEAKER>

# Step 7: Try to connect
bluetoothctl connect <MAC_SPEAKER>

# Step 8: Verify connection
bluetoothctl info <MAC_SPEAKER>
# Should show: Connected: yes
```

**If still not connecting:**
```bash
# Option A: Reset Bluetooth adapter
sudo systemctl restart bluetooth bluealsa
sleep 2
bluetoothctl power on

# Option B: Reset speaker
# Power off speaker, wait 10 seconds, power on
# Then try connecting again

# Option C: Remove and re-pair
bluetoothctl remove <MAC_SPEAKER>
# Then repeat pairing steps above, atau jalankan: sudo /home/lenovo/pasang_bt.sh
```

---

### Issue 3: Service tidak jalan

**Symptoms:** Services showing inactive after restart

**Troubleshooting steps:**
```bash
# Check status
sudo systemctl status tahrim-daemon.service
sudo systemctl status bt-boot-connect.service
# Catatan: bt-boot-connect.service itu Type=oneshot, jadi WAJAR statusnya
# "inactive (dead)" setelah sukses jalan sekali saat boot. Yang perlu
# diperhatikan adalah exit code-nya, bukan status "active/inactive"-nya:
sudo systemctl is-failed bt-boot-connect.service   # harus "active" (artinya TIDAK gagal)

# View detailed logs
sudo journalctl -u tahrim-daemon.service -n 50
sudo journalctl -u bt-boot-connect.service -n 50

# Check for errors
sudo journalctl -u tahrim-daemon.service | grep ERROR

# Try to restart
sudo systemctl restart tahrim-daemon.service
sleep 2

# Verify it's running
sudo systemctl is-active tahrim-daemon.service
```

**Common causes:**
- Missing config file: Check `/home/lenovo/sekolah.conf` exists
- Permission issues: `sudo chown lenovo:lenovo /home/lenovo/sekolah.conf`
- Port already in use: `sudo lsof -i :PORT` (if applicable)
- Out of memory: `free -h` to check available memory

---

### Issue 4: Bluetooth keeps disconnecting

**Symptoms:** Bluetooth keeps losing connection, requires manual reconnect

> **Perubahan penting sejak V14:** service `anti-putus.service` (penjaga koneksi 24 jam yang mengirim audio kosong terus-menerus) sudah **dihapus**. Speaker sekarang boleh saja disconnect saat idle lama menunggu jadwal bel berikutnya — itu **normal**, bukan bug, karena `sambung_bt.sh` akan otomatis reconnect sesaat sebelum bel berikutnya diputar (dipanggil dari `putar_audio.sh`). Yang perlu dicurigai sebagai masalah **hanya** kalau reconnect itu **gagal** tepat saat mau bunyi bel.

**Troubleshooting steps:**
```bash
# Step 1: Cek log SAAT JAM BEL berbunyi (bukan saat idle) - apakah ada
# kegagalan reconnect tepat sebelum jadwal main?
grep -B5 "\[PLAY\]" /var/log/otomasi_audio.log | tail -30

# Step 2: Test manual reconnect langsung
sudo /home/lenovo/sambung_bt.sh
bluetoothctl info <MAC_SPEAKER> | grep Connected

# Step 3: Kalau reconnect manual juga lambat/gagal, cek lock file
# (kemungkinan ada proses lain sedang pegang koneksi Bluetooth)
cat /tmp/bt_op.lock 2>/dev/null
ps aux | grep -E "bluetoothctl|sambung_bt|pasang_bt"

# Step 4: Restart layanan terkait Bluetooth
sudo systemctl restart bluetooth bluealsa
sudo systemctl restart bt-boot-connect.service
```

**Possible causes:**
- Bluetooth interference: Move speaker closer to server
- Power management: Check BIOS for Bluetooth power settings
- Driver issue: Update Debian packages: `sudo apt upgrade`
- Overheating: Check server temperature: `sensors`
- Speaker sudah terhubung ke device lain (HP/laptop lain) — pastikan hanya satu device yang connect ke speaker dalam satu waktu

---

### Issue 5: Disk space warning

**Symptoms:** Warning message "Disk Hampir Penuh"

**Troubleshooting steps:**
```bash
# Check disk usage
df -h /home/lenovo

# Find large files
du -sh /home/lenovo/* | sort -h

# Clean up old backups
ls -lh /home/lenovo/backup/
find /home/lenovo/backup -mtime +30 -delete

# Clean old logs (if needed)
sudo truncate -s 0 /var/log/otomasi_audio.log

# Clean apt cache
sudo apt autoclean
sudo apt autoremove
```

---

### Issue 6: API error (no internet)

**Symptoms:** Log shows "CRITICAL - Tidak ada data jadwal sholat"

**Troubleshooting steps:**
```bash
# Check internet connectivity
ping 8.8.8.8

# Check DNS resolution
nslookup api.aladhan.com

# Test API directly
curl -I https://api.aladhan.com/v1/timings/01-01-2025?latitude=-7.7134&longitude=109.9961

# Check if using local cache (offline mode)
cat /home/lenovo/jadwal_sholat.json | head -5

# Restart daemon to force API call
sudo systemctl restart tahrim-daemon.service
```

**Note:** System automatically uses local cache if API is unavailable, so this is not critical.

---

### Issue 7: Cron jobs not running

**Symptoms:** Scheduled bells not playing at expected time

**Troubleshooting steps:**
```bash
# Verify cron jobs installed
crontab -l -u lenovo

# Check if cron service is running
sudo systemctl status cron

# Check cron logs
sudo grep CRON /var/log/syslog | tail -20

# Test cron manually
# Add test job for 1 minute from now
TEST_TIME=$(date -d "+1 minute" +%H:%M)
echo "$TEST_TIME * * * /home/lenovo/putar_audio.sh test \"Test\" /home/lenovo/audio/Hymne-guru.mp3" | crontab -u lenovo -

# Wait and check if runs
# Then remove test job
crontab -u lenovo -e
```

---

### Issue 8: System time not synced

**Symptoms:** NTP shows "no", bells play at wrong times

**Troubleshooting steps:**
```bash
# Check NTP status
timedatectl
timedatectl show -p NTPSynchronized --value

# Enable NTP if disabled
sudo timedatectl set-ntp on

# Check NTP service
sudo systemctl status systemd-timesyncd

# Wait for sync (can take a few minutes)
sleep 30 && timedatectl

# Manually set time if needed
sudo timedatectl set-time "2025-07-05 14:30:00"

# Set timezone if wrong
sudo timedatectl set-timezone Asia/Jakarta
```

---

## Advanced Troubleshooting

### Enable Debug Logging

```bash
# Increase verbosity in scripts
# Edit /home/lenovo/putar_audio.sh (skrip utama pemutaran audio) atau
# /home/lenovo/sambung_bt.sh (skrip reconnect Bluetooth)
# Add: set -x  (setelah baris #!/bin/bash)

# Then monitor with:
tail -f /var/log/otomasi_audio.log
```

### Check Service Resource Usage

```bash
# Memory usage
ps aux | grep -E "tahrim_daemon|mpv|sambung_bt|putar_audio"

# CPU usage (tahrim-daemon.service jalan nonstop, jadi ini yang relevan
# dipantau; bt-boot-connect.service Type=oneshot, cuma jalan sebentar
# saat boot lalu selesai, jadi tidak ada proses jangka panjang untuk itu)
top -p $(pgrep -f tahrim_daemon.sh)

# File descriptor usage
lsof -p $(pgrep -f tahrim_daemon.sh)
```

### Restart All Services

```bash
# Stop
sudo systemctl stop tahrim-daemon.service

# Wait
sleep 5

# Start
sudo systemctl start tahrim-daemon.service

# Reconnect Bluetooth sekali (bt-boot-connect.service Type=oneshot,
# tidak perlu di-stop/start seperti service nonstop)
sudo systemctl restart bt-boot-connect.service

# Verify
sudo systemctl status tahrim-daemon.service
sudo systemctl is-failed bt-boot-connect.service   # harus "active" = tidak gagal
```

### Emergency Rollback

```bash
# Stop services
sudo systemctl stop tahrim-daemon.service
sudo systemctl disable tahrim-daemon.service
sudo systemctl disable bt-boot-connect.service

# Remove sudo entry
sudo rm -f /etc/sudoers.d/otomasi-audio

# Restore from backup (if available)
tar -xzf /home/lenovo/backup/config_YYYYMMDD.tar.gz -C /home/lenovo/
```

---

## Getting Help

If issue persists:

1. **Collect debug info:**
   ```bash
   /home/lenovo/cek_kesehatan.sh > debug.txt
   tail -100 /var/log/otomasi_audio.log >> debug.txt
   sudo systemctl status tahrim-daemon.service >> debug.txt
   sudo systemctl status bt-boot-connect.service >> debug.txt
   ```

2. **Search documentation:**
   - Check [README.md](README.md)
   - Check [DEPLOYMENT.md](DEPLOYMENT.md)
   - Check [SECURITY.md](SECURITY.md)
   - Check [docs/Manual-Book-Sistem-Bel-Sekolah.md](docs/Manual-Book-Sistem-Bel-Sekolah.md)

3. **Open issue on GitHub** with debug info

---

**Last Updated:** 2026-07-10 (V14)
**Maintained By:** Saroppudin (@saroppudin)
