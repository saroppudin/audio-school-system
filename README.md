# 🔔 Audio Automation System untuk Sekolah
## Multi-Audio Bell, Exam Scheduler & Prayer Time (Tahrim) Daemon

**Version:** 4.0 (Production-Ready)  
**Target OS:** Debian 13 Headless  
**Status:** ✅ Production Ready  

---

## 📋 Fitur Utama

✅ **Otomasi Bel Harian**
- Lagu pagi (Senin-Sabtu, 06:30)
- Indonesia Raya (Senin-Jum'at & Sabtu, 09:59)
- Bel Dzuhur (Senin-Jum'at & Sabtu, 11:55)
- Penjadwalan fleksibel via cron

✅ **Manajemen Ujian**
- Jadwal ujian dinamis
- Multiple bell sounds per sesi
- Mode ujian untuk nonaktifkan bel reguler

✅ **Daemon Tahrim (Jadwal Sholat)**
- Fetch otomatis dari API Aladhan
- Database lokal offline fallback
- Tarhim Subuh & Maghrib (3 variasi)
- DST-aware scheduling

✅ **Bluetooth Audio**
- Auto-connect ke speaker Bluetooth
- Dead air stream untuk maintain koneksi
- Auto-recovery jika disconnect
- Volume management

✅ **Reliability & Monitoring**
- Systemd services dengan auto-restart
- Health check monitoring
- Disk space alerting
- Comprehensive logging dengan rotation
- Backup otomatis konfigurasi

✅ **Security Hardening**
- Minimal sudo privileges
- Service isolation
- Audit logging
- Rate limiting untuk API calls
- Pre-installation validation

---

## 🚀 Quick Start

### Prerequisites
```bash
# Debian 13 headless, fresh install
# User: non-root (default: lenovo)
# Root access (sudo)
# Bluetooth adapter + Speaker Bluetooth
# Internet connection
```

### Installation (5 langkah)

```bash
# 1. Download installer
sudo git clone https://github.com/saroppudin/audio-school-system /opt/audio-school
cd /opt/audio-school

# 2. Edit konfigurasi
sudo nano config/sekolah.conf.example
# Copy ke sekolah.conf dan sesuaikan: NAMA_SEKOLAH, GARIS_LINTANG, GARIS_BUJUR, MAC_SPEAKER

# 3. Jalankan installer
sudo bash scripts/Installer-bel-v4-fixed-improved.sh

# 4. Upload file audio MP3
scp audio/*.mp3 lenovo@server:/home/lenovo/audio/

# 5. Verifikasi
ssh lenovo@server
/home/lenovo/cek_kesehatan.sh
```

---

## 📁 Struktur Direktori

```
audio-school-system/
├── README.md                          # Dokumentasi utama
├── SECURITY.md                        # Security guide
├── DEPLOYMENT.md                      # Deployment checklist
├── TROUBLESHOOTING.md                 # Troubleshooting guide
│
├── scripts/
│   └── Installer-bel-v4-fixed-improved.sh    # Main installer (COMPREHENSIVE)
│
├── config/
│   └── sekolah.conf.example           # Configuration template
│
├── audio/
│   └── .placeholder                   # Place .mp3 files here
│
└── docs/
    ├── API-Integration.md             # Aladhan API details
    └── Bluetooth-Setup.md             # Bluetooth pairing guide
```

---

## ⚙️ Konfigurasi

### Lokasi Config Utama
```bash
/home/lenovo/sekolah.conf
```

### Parameter yang Dapat Diubah

```bash
# Identitas Sekolah
NAMA_SEKOLAH="SMK Negeri Purworejo"

# Koordinat (untuk Aladhan API)
GARIS_LINTANG="-7.7134"
GARIS_BUJUR="109.9961"

# Bluetooth Speaker
MAC_SPEAKER="7d:5b:22:c8:4d:ab"  # bluetoothctl devices untuk cari

# System User (jangan ubah setelah install)
USER_SISTEM="lenovo"
```

---

## 🎵 File Audio yang Diperlukan

Upload ke `/home/lenovo/audio/`:

### Bel Harian (6 files)
- `Hymne-guru.mp3`
- `Tanah-airku.mp3`
- `Rukun-Sama-teman.mp3`
- `Mars.mp3`
- `Pengantar-dan-indonesia-raya.mp3`
- `Bel-Persiapan-Sholat-dzuhur.mp3`

### Bel Ujian (6 files)
- `bel-masuk-ruangan.mp3`
- `bel-mulai-ujian.mp3`
- `istirahat.mp3`
- `bel-sisa-5menit.mp3`
- `istirahat-selesai.mp3`
- `bel-ujian-selesai.mp3`

### Tarhim (4 files)
- `tarhim-subuh.mp3`
- `tarhim-maghrib-1.mp3`
- `tarhim-maghrib-2.mp3`
- `tarhim-maghrib-3.mp3`

**Format:** MP3, 128-320 kbps, Mono/Stereo, 8-48 kHz

---

## 🛠️ Perintah Penting

### Management Jadwal Ujian
```bash
# Tambah jadwal
/home/lenovo/kelola_ujian.sh tambah 07:00 bel-mulai-ujian.mp3

# Lihat jadwal
/home/lenovo/kelola_ujian.sh daftar

# Hapus jadwal
/home/lenovo/kelola_ujian.sh hapus 07:00

# Kosongkan semua
/home/lenovo/kelola_ujian.sh kosongkan
```

### Mode Operasional
```bash
# Hari biasa (bel ON, ujian OFF)
/home/lenovo/mode_sekolah.sh hari_biasa

# Masa ujian (ujian ON, beberapa bel OFF)
/home/lenovo/mode_sekolah.sh masa_ujian

# Liburan (semua bel OFF)
/home/lenovo/mode_sekolah.sh liburan

# Normal semua (all ON)
/home/lenovo/mode_sekolah.sh normal_semua

# Status
/home/lenovo/mode_sekolah.sh status
```

### Monitoring & Debugging
```bash
# Health check lengkap
/home/lenovo/cek_kesehatan.sh

# Monitor log real-time
tail -f /var/log/otomasi_audio.log

# Service status
systemctl status anti-putus.service
systemctl status tahrim-daemon.service

# Restart service
sudo systemctl restart anti-putus.service
sudo systemctl restart tahrim-daemon.service

# View errors
tail -50 /var/log/otomasi_audio.log | grep ERROR
```

---

## 🔒 Security

Sistem ini dilengkapi dengan:
- ✅ Minimal sudo privileges (hanya rfkill & systemctl)
- ✅ Rate limiting untuk API calls (Aladhan)
- ✅ Audit logging untuk semua operasi
- ✅ Encrypted backup storage
- ✅ Restricted file permissions
- ✅ Pre-installation validation
- ✅ Error handling & recovery

Lihat [SECURITY.md](SECURITY.md) untuk detail lengkap.

---

## 📊 Monitoring

Sistem ini mencatat:
- ✅ Status koneksi Bluetooth
- ✅ Audio playback success/failure
- ✅ API call status
- ✅ Service restart count
- ✅ Disk space usage
- ✅ NTP sync status
- ✅ Backup status

Log tersimpan di: `/var/log/otomasi_audio.log`

---

## 🐛 Troubleshooting

### Bel tidak berbunyi
```bash
# 1. Cek file audio ada
ls -la /home/lenovo/audio/

# 2. Cek koneksi Bluetooth
bluetoothctl info <MAC_SPEAKER>

# 3. Cek volume
amixer sget Master

# 4. Test manual playback
mpv --audio-device=alsa/bluealsa /home/lenovo/audio/test.mp3

# 5. Lihat error di log
tail -20 /var/log/otomasi_audio.log | grep ERROR
```

### Bluetooth tidak terhubung
```bash
# 1. Cek adapter
bluetoothctl list

# 2. Power on & pair
bluetoothctl power on
bluetoothctl pair <MAC>
bluetoothctl trust <MAC>
bluetoothctl connect <MAC>

# 3. Restart service
sudo systemctl restart anti-putus.service
```

Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) untuk troubleshooting lengkap.

---

## 📝 Changelog

### v4.0 (Production Ready)
- ✅ Comprehensive security hardening
- ✅ Advanced error handling
- ✅ DST-aware scheduling
- ✅ Exponential backoff untuk reconnection
- ✅ Atomic backup dengan integrity check
- ✅ Pre-installation validation
- ✅ Production-ready systemd configs
- ✅ AppArmor-compatible service design
- ✅ Rate limiting untuk API calls
- ✅ 24/7 auto-recovery mechanism

---

## 📞 Support

Untuk issues atau pertanyaan:
1. Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Cek `/var/log/otomasi_audio.log`
3. Buka issue di GitHub
4. Lihat [DEPLOYMENT.md](DEPLOYMENT.md) untuk deployment guide

## Dokumentasi
Lihat [Manual Book](docs/Manual-Book-Sistem-Bel-Sekolah.md) untuk panduan penggunaan harian dan pemeliharaan.

## Versi Terbaru
Installer versi V13 — lihat changelog lengkap di komentar header `scripts/Installer-bel-v13.sh`.
---

## 📄 Lisensi

MIT License - Bebas digunakan untuk tujuan komersial & non-komersial

---

## 👨‍💻 Maintainer

Saroppudin (@saroppudin)  
GitHub: https://github.com/saroppudin

---

**Last Updated:** 2025-07-05  
**Tested On:** Debian 13 Headless, Systemd, BlueALSA  
**Production Ready:** ✅ YES
