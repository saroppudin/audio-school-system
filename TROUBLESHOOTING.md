# 🔧 Troubleshooting Guide

## Common Issues & Solutions

### Issue 1: Bel tidak berbunyi

**Symptoms:** Tidak ada suara dari speaker/amplifier saat jadwal bel

**Langkah troubleshooting:**
```bash
# Step 1: Cek file audio ada
ls -la /home/lenovo/audio/ | head -20

# Step 2: Cek mode output audio yang sedang aktif
/home/lenovo/atur_output_audio.sh status

# Step 3: Kalau mode bluetooth, cek koneksi
bluetoothctl info <MAC_SPEAKER>
# Harus: Connected: yes

# Step 4: Cek volume (kontrol mixer bisa beda tiap hardware --
# lihat dulu apa yang tersedia)
amixer scontrols
amixer sget Master

# Step 5: Tes manual lewat output yang sedang aktif
/home/lenovo/atur_output_audio.sh test

# Step 6: Lihat error di log
tail -20 /var/log/otomasi_audio.log | grep -E "CRITICAL|GAGAL"
```

**Sebab umum & solusi:**
- File hilang: upload ulang ke `/home/lenovo/audio/`
- Bluetooth putus: `sudo /home/lenovo/atur_output_audio.sh bluetooth` (otomatis sambung ulang)
- Volume kecil: `amixer sset Master 100%` (nama kontrol lihat `amixer scontrols` — di Lenovo S200z biasanya hanya `Master` & `Capture`, jangan asumsikan ada `Speaker`/`Headphone`/`Front`)
- Salah mode: kalau amplifier tersambung ke jack analog tapi sistem masih di mode `bluetooth` (atau sebaliknya), bel tidak akan pernah bunyi — cek `atur_output_audio.sh status`

---

### Issue 2: Mode `line_out` tidak bunyi / kartu tidak terdeteksi (BARU V15)

**Symptoms:** `atur_output_audio.sh line_out` sukses tanpa error, tapi tetap tidak ada suara; atau muncul `[GAGAL] Tidak ada kartu suara analog terdeteksi`

**Langkah troubleshooting:**
```bash
# Step 1: Lihat daftar kartu ALSA yang terdeteksi sistem
aplay -l

# Step 2: Cari baris "card N: <ID> [...]" yang BUKAN HDMI -- itu <ID>
# (contoh: "PCH") yang seharusnya otomatis terdeteksi.

# Step 3: Kalau auto-deteksi salah/ada lebih dari satu kartu non-HDMI,
# sebutkan manual:
sudo /home/lenovo/atur_output_audio.sh line_out PCH

# Step 4: Cek isi /etc/asound.conf yang di-generate -- "pcm hw:XXX,0"
# harus id kartu pendek TANPA SPASI (mis. "hw:PCH,0"). Kalau ada spasi
# di dalamnya, deteksi salah -- laporkan sebagai bug.
cat /etc/asound.conf

# Step 5: Cek kabel jack fisik & volume amplifier eksternal (di luar
# kendali software).

# Step 6: Tes langsung ke device tanpa lewat dmix, untuk isolasi masalah:
aplay -D "hw:PCH,0" /usr/share/sounds/alsa/Front_Center.wav
```

**Sebab umum & solusi:**
- Kartu memang tidak terdeteksi Debian sama sekali → cek driver/`lspci -v | grep -A5 audio`
- Auto-deteksi ambil kartu yang salah (ada >1 kartu non-HDMI) → sebutkan manual seperti Step 3
- Kabel jack lepas/amplifier mati → cek fisik

---

### Issue 3: Bluetooth tidak terhubung

**Symptoms:** "Bluetooth tidak terhubung" di health check, atau mode `bluetooth` gagal saat switch

**Langkah troubleshooting:**
```bash
# Step 1: List adapter Bluetooth
bluetoothctl list
# Harus tampil hci0 atau serupa

# Step 2: Cek adapter menyala
bluetoothctl show
# Harus: Powered: yes

# Step 3: Nyalakan kalau perlu
bluetoothctl power on

# Step 4: Kalau BELUM pernah di-pair, jalankan skrip pairing interaktif
/home/lenovo/pasang_bt.sh

# Step 5: Coba sambung manual
/home/lenovo/sambung_bt.sh

# Step 6: Verifikasi
bluetoothctl info <MAC_SPEAKER>
```

**Kalau masih gagal:**
```bash
# Opsi A: Restart service Bluetooth (butuh sudo, sudah diizinkan lewat sudoers)
sudo systemctl restart bluetooth bluealsa
sleep 2
bluetoothctl power on

# Opsi B: Restart speaker fisik (matikan 10 detik, nyalakan lagi)

# Opsi C: Unpair & pair ulang total
bluetoothctl remove <MAC_SPEAKER>
/home/lenovo/pasang_bt.sh
```

**Catatan:** `sambung_bt.sh` sudah otomatis dipanggil sebelum setiap bel
diputar, dan mencoba 3x sebelum menyerah. Kalau speaker memang **belum
pernah di-pair**, log akan mencatat CRITICAL yang jelas mengarahkan ke
`pasang_bt.sh` — restart service tidak akan menolong kasus ini.

---

### Issue 4: Service tidak jalan

**Symptoms:** `tahrim-daemon.service` menunjukkan inactive/failed

```bash
# Cek status
sudo systemctl status tahrim-daemon.service

# NOTE: bt-boot-connect.service WAJAR "inactive (dead)" -- ini oneshot,
# sukses jalan sekali saat boot lalu selesai, BUKAN tanda error.

# Lihat log detail
sudo journalctl -u tahrim-daemon.service -n 50

# Coba restart
sudo systemctl restart tahrim-daemon.service
sleep 2
sudo systemctl is-active tahrim-daemon.service
```

**Catatan:** `cek_service.sh` (cron tiap 5 menit) sudah otomatis mendeteksi
& restart `tahrim-daemon.service` kalau mati — kalau tetap mati setelah
restart otomatis, itu tanda ada error yang berulang (cek log CRITICAL).

**Sebab umum:**
- Config hilang: cek `/home/lenovo/sekolah.conf` ada
- Permission salah: `sudo chown lenovo:lenovo /home/lenovo/sekolah.conf`
- Dependency hilang (`jq`, `curl`, `mpv`, `bluez-alsa-utils`): `sudo apt install --reinstall jq curl mpv bluez-alsa-utils`

---

### Issue 5: Disk space warning

```bash
df -h /home/lenovo
du -sh /home/lenovo/* | sort -h

# Backup lama dibersihkan otomatis (retensi 14 hari), tapi kalau perlu manual:
find /home/lenovo/backup -mtime +14 -delete

sudo apt autoclean
sudo apt autoremove
```

---

### Issue 6: API jadwal sholat error (tidak ada internet)

**Symptoms:** Log menunjukkan `[CRITICAL] - Tidak ada data jadwal sholat sama sekali`

```bash
ping 8.8.8.8
nslookup api.aladhan.com
curl -I "https://api.aladhan.com/v1/timings/$(date +%d-%m-%Y)?latitude=-7.7134&longitude=109.9961&method=2"

# Cek cache lokal (fallback otomatis)
cat /home/lenovo/jadwal_sholat.json | head -5

sudo systemctl restart tahrim-daemon.service
```

**Catatan:** `tahrim_daemon.sh` retry otomatis (`curl --retry 3 --retry-delay 5`)
lalu jatuh ke `jadwal_sholat.json` lokal kalau API tetap gagal — ini **tidak
kritis** selama cache lokal masih ada. Baru jadi CRITICAL kalau cache pun
tidak ada (mis. instalasi baru, belum pernah online sama sekali).

---

### Issue 7: Cron jobs tidak jalan

```bash
crontab -l -u lenovo
# Harus ada: cek_harian.sh, cek_ujian.sh (tiap menit), cek_disk.sh (07:00),
# cek_service.sh (tiap 5 menit), backup.sh (23:55)

sudo systemctl status cron
sudo grep CRON /var/log/syslog | tail -20

# Tes manual
TEST_TIME=$(date -d "+1 minute" +%H:%M)
echo "$TEST_TIME * * * /home/lenovo/putar_audio.sh test \"Test\" /home/lenovo/audio/Hymne-guru.mp3" | crontab -u lenovo -
# Tunggu, cek log, lalu hapus baris tes ini lagi via: crontab -u lenovo -e
```

---

### Issue 8: Waktu sistem tidak sinkron

**Symptoms:** NTP `no`, bel main di jam yang salah

```bash
timedatectl
timedatectl show -p NTPSynchronized --value

sudo timedatectl set-ntp on
sudo systemctl status systemd-timesyncd
sleep 30 && timedatectl

sudo timedatectl set-timezone Asia/Jakarta
```

**Catatan:** `tahrim_daemon.sh` sudah menunggu NTP sinkron (maks 2 menit)
sebelum menghitung jadwal tarhim setelah boot — kalau NTP tetap belum
sinkron setelah 2 menit, daemon tetap lanjut jalan dengan jam apa adanya
dan mencatat WARNING (bukan berhenti total).

---

### Issue 9: Bel jam pelajaran Senin tidak bunyi (macet di "pause")

**Symptoms:** Bel selain bel masuk Senin tidak berbunyi sepanjang hari

```bash
/home/lenovo/cek_kesehatan.sh   # lihat bagian "STATUS BEL SENIN (UPACARA)"

# Kalau sedang di-pause dan upacara sudah selesai:
/home/lenovo/lanjutkan_bel_senin.sh
```

**Catatan:** ini **bukan bug** — bel jam pelajaran Senin memang otomatis
di-pause setelah bel masuk (menunggu upacara selesai, durasinya beda-beda
tiap minggu). Ada safety-valve: kalau admin lupa jalankan
`lanjutkan_bel_senin.sh`, pause **otomatis batal sendiri setelah 90 menit**.

---

### Issue 10: `/home` bersih total / sistem "hilang" setelah mati listrik

**Symptoms:** Semua skrip di `/home/lenovo` hilang

```bash
# Cek apakah pemulihan otomatis sudah/akan berjalan:
sudo systemctl status integritas-sistem.timer
sudo journalctl -u integritas-sistem.service -n 50

# Pemulihan otomatis (>=70% file kunci hilang) berjalan otomatis tiap 15
# menit -- tunggu satu siklus, atau pantau langsung:
sudo /usr/local/bin/cek_integritas_sistem.sh

# Cek hasil setelah pemulihan:
tail -30 /var/log/otomasi_audio.log
```

**Catatan:** kalau **kurang dari 70%** file kunci yang hilang, sistem
**TIDAK** akan auto-reinstall (supaya tidak menimpa kustomisasi) — hanya
mencatat CRITICAL. Anda perlu memulihkan file yang hilang secara manual
dari `/home/lenovo/backup/` atau `/var/backups/audio-school-system/`.

---

## Advanced Troubleshooting

### Enable Debug Logging
```bash
# Tambahkan "set -x" setelah "#!/bin/bash" di skrip yang ingin di-debug,
# misalnya /home/lenovo/tahrim_daemon.sh, lalu:
sudo systemctl restart tahrim-daemon.service
sudo journalctl -u tahrim-daemon.service -f
```

### Cek Resource Usage
```bash
ps aux | grep -E "tahrim_daemon|mpv|putar_audio"
top -p "$(pgrep -f tahrim_daemon.sh)"
```

### Restart Semua Service
```bash
sudo systemctl restart tahrim-daemon.service
sudo systemctl start bt-boot-connect.service   # oneshot, aman dijalankan ulang
sudo systemctl status tahrim-daemon.service bt-boot-connect.service
```

### Emergency Rollback
```bash
sudo systemctl stop tahrim-daemon.service
sudo systemctl disable tahrim-daemon.service bt-boot-connect.service integritas-sistem.timer
sudo rm -f /etc/sudoers.d/otomasi-audio-rfkill

# Restore dari backup (kalau ada)
tar -xzf /home/lenovo/backup/config_YYYYMMDD.tar.gz -C /home/lenovo/
```

---

## Getting Help

Kalau isu masih berlanjut:

1. **Kumpulkan info debug:**
   ```bash
   /home/lenovo/cek_kesehatan.sh > debug.txt
   tail -100 /var/log/otomasi_audio.log >> debug.txt
   sudo systemctl status tahrim-daemon.service >> debug.txt
   aplay -l >> debug.txt
   amixer scontrols >> debug.txt
   /home/lenovo/atur_output_audio.sh status >> debug.txt
   ```

2. **Cek dokumentasi lain:**
   - [README.md](README.md)
   - [DEPLOYMENT.md](DEPLOYMENT.md)
   - [SECURITY.md](SECURITY.md)

3. **Buka issue di GitHub** dengan `debug.txt` di atas dilampirkan

---

**Maintained By:** Saroppudin (@saroppudin)
