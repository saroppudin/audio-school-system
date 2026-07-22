# 📋 Deployment Checklist & Guide

## Pre-Deployment Phase

### 1. Infrastructure Preparation

```bash
# [ ] Hardware ready
  - [ ] Debian 13 minimal install done
  - [ ] Bluetooth adapter tersedia & terdeteksi (kalau pakai mode bluetooth)
  - [ ] Jack audio analog on-board + amplifier kabel siap (kalau pakai mode line_out)
  - [ ] Speaker/mixer Bluetooth siap dipasangkan (kalau pakai mode bluetooth)
  - [ ] Network connectivity (Ethernet lebih stabil untuk API jadwal sholat)
  - [ ] Minimal 2GB free disk space
  - [ ] BIOS/UEFI settings terverifikasi

# [ ] User & SSH setup
  - [ ] Non-root user sudah ada (default: lenovo), masuk grup sudo
  - [ ] SSH key pairs dibuat
  - [ ] SSH dikonfigurasi dengan benar
  - [ ] Firewall dikonfigurasi (UFW disarankan)
```

### 2. Tentukan Output Audio: Bluetooth atau Line Out?

Sistem ini mendukung **dua mode output** — tentukan dulu yang mana yang dipakai
di lokasi ini, karena langkah persiapan hardware-nya berbeda:

**Kalau pakai Bluetooth** — lanjut ke langkah pairing di bawah.

**Kalau pakai Line Out (jack analog ke amplifier kabel)** — tidak perlu pairing
Bluetooth sama sekali. Cukup pastikan kabel jack tersambung ke amplifier, lalu
setelah instalasi jalankan:
```bash
sudo /home/lenovo/atur_output_audio.sh line_out
```
Kartu suara analog akan terdeteksi otomatis (lewat nama kartu, bukan nomor
index, jadi tahan reboot). Kalau ada lebih dari satu kartu non-HDMI di sistem,
sebutkan manual: `atur_output_audio.sh line_out <nama_card>` (lihat nama kartu
lewat `aplay -l`).

### 3. Hardware Pairing Bluetooth (Kalau Dipakai)

```bash
# Pairing Bluetooth speaker SEBELUM instalasi otomasi

# Step 1: Power on speaker, mode discoverable (biasanya tahan tombol 3-5 detik)

# Step 2: Scan devices
bluetoothctl scan on
# Tunggu nama device muncul

# Step 3: Catat MAC address
# Contoh output:
# [CHR] XX:XX:XX:XX:XX:XX  DeviceName

# Step 4: Pair & trust
bluetoothctl pair XX:XX:XX:XX:XX:XX
bluetoothctl trust XX:XX:XX:XX:XX:XX

# Step 5: Verifikasi
bluetoothctl info XX:XX:XX:XX:XX:XX
# Harus tertulis: Connected: yes

# ⚠️ SIMPAN MAC ADDRESS INI! Dipakai untuk MAC_SPEAKER di installer.
```

Kalau proses pairing sulit/gagal, ada skrip interaktif siap pakai setelah
instalasi: `/home/lenovo/pasang_bt.sh`.

### 4. Audio Files Preparation

```bash
# [ ] Kumpulkan semua file MP3 yang diperlukan
  - [ ] Lagu Pagi (4 file)
  - [ ] Indonesia Raya (1 file)
  - [ ] Bel Dzuhur (1 file)
  - [ ] Bel Ujian (6 file)
  - [ ] Tarhim (4 file)

# [ ] Validasi file audio
  - Format: MP3, 128-320 kbps
  - Cek durasi wajar (tidak terlalu pendek/panjang)
  - Test play di komputer sebelum deploy

# [ ] Siapkan metode upload
  - [ ] SSH/SCP siap
  - [ ] Atau USB drive (kalau tidak networked)
  - [ ] Atau rsync (untuk transfer besar)
```

### 5. Configuration Planning

```bash
# [ ] Kumpulkan info sekolah
  NAMA_SEKOLAH="SMK Nurussalaf Kemiri"
  GARIS_LINTANG="-7.7134"          # Cek Google Maps
  GARIS_BUJUR="109.9961"
  MAC_SPEAKER="XX:XX:XX:XX:XX:XX"  # Dari pairing Bluetooth (isi placeholder kalau pakai line_out saja)

# [ ] Rencanakan jadwal
  - [ ] Jam lagu pagi: __ : __
  - [ ] Jam Indonesia Raya: __ : __
  - [ ] Jam bel Dzuhur: __ : __
  - [ ] Jadwal ujian (kalau ada)
```

---

## Installation Phase

### Step 1: Download Repository

```bash
sudo git clone https://github.com/saroppudin/audio-school-system /opt/audio-school
cd /opt/audio-school/scripts
```

### Step 2: Edit Konfigurasi LANGSUNG DI DALAM SKRIP INSTALLER

> ⚠️ **Penting:** konfigurasi sekolah **bukan** file template terpisah.
> Edit langsung bagian "1. KONFIGURASI SEKOLAH" di baris atas
> `Installer-bel-v15.sh`, sebelum menjalankannya.

```bash
sudo nano Installer-bel-v15.sh
```

**Parameter yang harus diisi (bagian atas skrip):**
```bash
USER_SISTEM="lenovo"                    # User non-root Anda
NAMA_SEKOLAH="SMK Nurussalaf Kemiri"
GARIS_LINTANG="-7.7134"
GARIS_BUJUR="109.9961"
MAC_SPEAKER="XX:XX:XX:XX:XX:XX"         # Dari langkah pairing (wajib format valid, atau instalasi ditolak)
```

### Step 3: Jalankan Installer

```bash
sudo bash Installer-bel-v15.sh 2>&1 | tee install.log

# Pantau instalasi (di terminal lain)
tail -f install.log
```

**Output yang diharapkan (9 tahap utama):**
```
[1/9] Menginstal paket pendukung Debian...
[2/9] Mengonfigurasi adapter Bluetooth agar auto-enable saat boot...
[3/9] Mengonfigurasi BlueALSA...
[4/9] (Pengaturan /etc/asound.conf dilakukan otomatis di akhir instalasi)
[5/9] Mencoba memasangkan (pairing) ke speaker...
[6/9] Membuat struktur folder dan file konfigurasi...
[7/9] Membuat berkas skrip operasional audio...
[8/9] Daftarkan skrip ke Systemd Service...
[8b/9] Mengonfigurasi Logrotate global...
[8c/9] Mendaftarkan jadwal harian tetap di Crontab...
[8d/9] Menerapkan routing ALSA awal (/etc/asound.conf)...
[9/9] Verifikasi akhir & ringkasan instalasi...
```

### Step 4: Upload Audio Files

```bash
# Opsi A: SCP
scp *.mp3 lenovo@<server-ip>:/home/lenovo/audio/

# Opsi B: rsync (lebih cepat untuk banyak file)
rsync -avz audio/ lenovo@<server-ip>:/home/lenovo/audio/

# Opsi C: tar via SSH (kalau network tidak stabil)
tar -czf audio.tar.gz *.mp3
scp audio.tar.gz lenovo@<server-ip>:/tmp/
ssh lenovo@<server-ip> 'mkdir -p /home/lenovo/audio && tar -xzf /tmp/audio.tar.gz -C /home/lenovo/audio'

# Verifikasi
ssh lenovo@<server-ip> 'ls -la /home/lenovo/audio/ | head -20'
```

### Step 5: Tentukan & Kunci Output Audio

```bash
# Kalau default (bluetooth) sudah sesuai, tidak perlu apa-apa lagi --
# installer sudah otomatis menjalankan ini di akhir tahap [8d/9].

# Kalau ingin line_out:
sudo /home/lenovo/atur_output_audio.sh line_out

# Verifikasi:
/home/lenovo/atur_output_audio.sh status
```

---

## Verification Phase

### 1. Service Status Check

```bash
sudo systemctl status tahrim-daemon.service
# Harus: active (running)

sudo systemctl status bt-boot-connect.service
# WAJAR "inactive (dead)" -- ini oneshot, sukses jalan sekali saat boot lalu selesai.
# Cek historinya: systemctl status bt-boot-connect.service (lihat baris "Main PID" & waktu selesai)

sudo systemctl status integritas-sistem.timer
# Harus: active (waiting)
```

### 2. Health Check

```bash
/home/lenovo/cek_kesehatan.sh
```
Output mencakup: status `tahrim-daemon.service`, status `bt-boot-connect.service`,
10 log CRITICAL/WARNING terakhir, koneksi Bluetooth, sinkronisasi NTP, sisa
disk, status timer pemulihan integritas, status pause bel Senin, **dan mode
output audio yang sedang aktif**.

### 3. Konektivitas Output Audio

```bash
# Kalau mode bluetooth:
bluetoothctl info <MAC_SPEAKER>
# Harus: Connected: yes

# Tes bunyi cepat lewat output yang sedang aktif (mode apapun):
/home/lenovo/atur_output_audio.sh test
```

### 4. Log Verification

```bash
tail -50 /var/log/otomasi_audio.log
# Harus: service start sukses, tidak ada CRITICAL (WARNING wajar)
```

---

## Testing Phase

### 1. Manual Playback Test

```bash
/home/lenovo/putar_audio.sh test "Test Audio" /home/lenovo/audio/Hymne-guru.mp3

# Cek log:
grep -E "PLAY|SUKSES" /var/log/otomasi_audio.log | tail -5
```

### 2. Schedule Test

```bash
# Tambah jadwal ujian tes untuk 1 menit dari sekarang
TEST_TIME=$(date -d "+1 minute" +%H:%M)
/home/lenovo/kelola_ujian.sh tambah "$TEST_TIME" "*" bel-masuk-ruangan.mp3

# Tunggu waktunya lewat -- audio harus otomatis berbunyi

# Bersihkan
/home/lenovo/kelola_ujian.sh hapus "$TEST_TIME"
```

### 3. Bluetooth Reconnection Test (kalau mode bluetooth)

```bash
# Putuskan speaker manual, lalu jalankan bel apa saja (atau tunggu jadwal) --
# sambung_bt.sh akan otomatis mencoba reconnect sebelum audio diputar.

grep -E "RECOVERY|SUCCESS" /var/log/otomasi_audio.log | tail -5
```

### 4. Switching Output Test (BARU V15)

```bash
sudo /home/lenovo/atur_output_audio.sh line_out
sudo /home/lenovo/atur_output_audio.sh bluetooth
/home/lenovo/atur_output_audio.sh status
# Setiap switch harus tes bunyi otomatis dan mengupdate /etc/asound.conf
```

---

## Production Deployment

### 1. Final Verification

```bash
# [ ] Semua health check lolos
# [ ] File audio lengkap & benar
# [ ] Cron jobs terkonfigurasi (crontab -l -u lenovo)
# [ ] Output audio (bluetooth/line_out) stabil 10+ menit
# [ ] Log bersih (tidak ada CRITICAL)
# [ ] Backup berjalan (cek /home/lenovo/backup/ setelah jam 23:55)
```

### 2. Go-Live Procedure

```bash
# 1. Set mode produksi
/home/lenovo/mode_sekolah.sh hari_biasa

# 2. Verifikasi jadwal
/home/lenovo/kelola_harian.sh daftar
/home/lenovo/kelola_ujian.sh daftar

# 3. Monitor 1 jam pertama
tail -f /var/log/otomasi_audio.log

# 4. Kalau semua OK, informasikan ke pihak sekolah
```

---

## Troubleshooting Selama Deployment

### Issue: Instalasi macet di [2/9] atau [5/9]
**Sebab:** Bluetooth adapter tidak terdeteksi
**Fix:**
```bash
bluetoothctl list
# Kalau tidak ada output: reboot, cek BIOS, coba port USB lain
```

### Issue: Installer gagal di validasi sudoers
**Sebab:** Syntax error di file sudoers
**Fix:**
```bash
sudo visudo -c
sudo rm -f /etc/sudoers.d/otomasi-audio-rfkill
# Jalankan ulang installer
```

### Issue: Audio tidak bunyi setelah instalasi
**Sebab:** File audio belum diupload, atau output audio belum sesuai hardware
**Fix:**
```bash
ls -la /home/lenovo/audio/ | head -20
/home/lenovo/atur_output_audio.sh status
/home/lenovo/atur_output_audio.sh test
```
Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) untuk penanganan lebih lengkap.

---

**Estimasi Total Waktu Deployment:** 30-45 menit (belum termasuk upload audio)
