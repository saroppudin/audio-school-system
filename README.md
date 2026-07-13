# 🔔 Audio Automation System untuk Sekolah
## Multi-Audio Bell, Exam Scheduler & Prayer Time (Tahrim) Daemon

**Version:** V14 (Production-Ready)
**Target OS:** Debian 13 Headless
**Status:** ✅ Production Ready

---

## 📋 Fitur Utama

✅ **Otomasi Bel Harian**
- Lagu pagi (Senin-Sabtu, 06:30)
- Indonesia Raya (Senin-Jum'at & Sabtu, 09:59)
- Bel Dzuhur (Senin-Jum'at & Sabtu, 11:55)
- Penjadwalan fleksibel via cron, bisa tambah bel custom tanpa batas
  (lihat [Manual Book](docs/Manual-Book-Sistem-Bel-Sekolah.md) bagian 8.1)

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
- Auto-connect ke speaker Bluetooth saat boot (`bt-boot-connect.service`, sekali jalan)
- Reconnect on-demand sebelum tiap bel diputar (`sambung_bt.sh`)
- Lock file bersama mencegah dua proses Bluetooth bentrok
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
# Bluetooth adapter + Speaker Bluetooth (profil A2DP)
# Internet connection
```

### Installation (5 langkah)

```bash
# 1. Download installer
sudo git clone https://github.com/saroppudin/audio-school-system /opt/audio-school
cd /opt/audio-school

# 2. Edit konfigurasi LANGSUNG di installer (bagian "1. KONFIGURASI SEKOLAH")
sudo nano scripts/Installer-bel-v13.sh
# Sesuaikan: USER_SISTEM, NAMA_SEKOLAH, GARIS_LINTANG, GARIS_BUJUR, MAC_SPEAKER
# (config/sekolah.conf.example hanya referensi format, bukan yang dibaca installer)

# 3. Jalankan installer
sudo bash scripts/Installer-bel-v13.sh

# 4. Upload file audio MP3
scp audio/*.mp3 lenovo@server:/home/lenovo/audio/

# 5. Verifikasi
ssh lenovo@server
/home/lenovo/cek_kesehatan.sh
```

Panduan lengkap langkah demi langkah (termasuk troubleshooting nyata yang pernah ditemukan): [Manual Book](docs/Manual-Book-Sistem-Bel-Sekolah.md).

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
│   └── Installer-bel-v13.sh           # Main installer (COMPREHENSIVE, V14)
│
├── config/
│   └── sekolah.conf.example           # Configuration template (referensi format saja)
│
├── audio/
│   └── .placeholder                   # Place .mp3 files here
│
└── docs/
    ├── API-Integration.md             # Aladhan API details
    ├── Bluetooth-Setup.md             # Bluetooth pairing guide
    └── Manual-Book-Sistem-Bel-Sekolah.md   # Panduan instalasi & operasional lengkap
```

---

## ⚙️ Konfigurasi

### Lokasi Config Utama
```bash
/home/lenovo/sekolah.conf
```
(digenerate otomatis oleh installer berdasarkan variabel yang kamu edit di `scripts/Installer-bel-v13.sh`)

### Parameter yang Dapat Diubah

```bash
# Identitas Sekolah
NAMA_SEKOLAH="SMK Negeri Purworejo"

# Koordinat (untuk Aladhan API)
GARIS_LINTANG="-7.7134"
GARIS_BUJUR="109.9961"

# Bluetooth Speaker -- GANTI dengan MAC speaker Anda sendiri, cari lewat:
#   bluetoothctl scan on
MAC_SPEAKER="XX:XX:XX:XX:XX:XX"

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

### Management Jadwal Bel Harian & Ujian
```bash
# Bel harian: tambah/hapus/kosongkan/daftar
/home/lenovo/kelola_harian.sh tambah 15:00 1-5 bel_pulang Bel-Pulang.mp3
/home/lenovo/kelola_harian.sh daftar
/home/lenovo/kelola_harian.sh hapus bel_pulang
/home/lenovo/kelola_harian.sh kosongkan   # kecuali 3 kunci permanen

# Bel ujian: tambah/hapus/kosongkan/daftar
/home/lenovo/kelola_ujian.sh tambah 07:00 1-5 bel-mulai-ujian.mp3
/home/lenovo/kelola_ujian.sh daftar
/home/lenovo/kelola_ujian.sh hapus 07:00
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

# Status (bel custom diringkas jadi 1 baris "Bel harian")
/home/lenovo/mode_sekolah.sh status
```

### Ganti Speaker Bluetooth
```bash
# 1. Edit MAC_SPEAKER di /home/lenovo/sekolah.conf DAN di
#    defaults.bluealsa.device pada /etc/asound.conf (harus sama)
# 2. Pairing ulang:
sudo /home/lenovo/pasang_bt.sh
```

### Monitoring & Debugging
```bash
# Health check lengkap
/home/lenovo/cek_kesehatan.sh

# Monitor log real-time
tail -f /var/log/otomasi_audio.log

# Service status
systemctl status tahrim-daemon.service
systemctl is-failed bt-boot-connect.service   # oneshot, wajar "inactive" setelah sukses

# Restart service
sudo systemctl restart tahrim-daemon.service
sudo systemctl restart bt-boot-connect.service   # reconnect Bluetooth sekali

# View errors
tail -50 /var/log/otomasi_audio.log | grep ERROR
```

---

## 🔒 Security

Sistem ini dilengkapi dengan:
- ✅ Minimal sudo privileges (hanya rfkill & systemctl unit tertentu)
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

# 3. Reconnect via script sistem
sudo /home/lenovo/sambung_bt.sh
# atau pairing ulang dari nol:
sudo /home/lenovo/pasang_bt.sh
```

Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) untuk troubleshooting lengkap.

---

## 📝 Changelog

### V14 (Production Ready, terbaru)
- ✅ **`anti-putus.service` dihapus** (loop 24 jam + silent keep-alive audio,
  penyebab race condition `Device or resource busy`), diganti
  `bt-boot-connect.service` (`Type=oneshot`, reconnect sekali saat boot)
- ✅ `/etc/asound.conf` disederhanakan, hindari bentrok dengan template
  resmi paket `bluez-alsa` (fix error `Unknown field slave`)
- ✅ Flag mpv tidak valid (`--audio-fallback-to-ids`) dihapus
- ✅ Lock file bersama (`flock`) di `sambung_bt.sh` & `pasang_bt.sh`,
  cegah dua proses Bluetooth connect/pair bersamaan
- ✅ `mode_sekolah.sh status`: bel custom diringkas jadi satu baris
  "Bel harian", kunci permanen tetap tampil sendiri-sendiri
- ✅ Dokumentasi lengkap: [Manual Book](docs/Manual-Book-Sistem-Bel-Sekolah.md)

### v4.0
- ✅ Comprehensive security hardening
- ✅ Advanced error handling
- ✅ DST-aware scheduling
- ✅ Exponential backoff untuk reconnection
- ✅ Atomic backup dengan integrity check
- ✅ Pre-installation validation
- ✅ Production-ready systemd configs
- ✅ AppArmor-compatible service design
- ✅ Rate limiting untuk API calls

---

## 📞 Support

Untuk issues atau pertanyaan:
1. Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Cek `/var/log/otomasi_audio.log`
3. Buka issue di GitHub
4. Lihat [DEPLOYMENT.md](DEPLOYMENT.md) untuk deployment guide

## Dokumentasi
Lihat [Manual Book](docs/Manual-Book-Sistem-Bel-Sekolah.md) untuk panduan instalasi, operasional harian, dan pemeliharaan lengkap.

## Versi Terbaru
Installer versi **V14** (`scripts/Installer-bel-v13.sh`) — lihat changelog lengkap di komentar header file tersebut.

---

## 📄 Lisensi

MIT License - Bebas digunakan untuk tujuan komersial & non-komersial

---

## 👨‍💻 Maintainer

Saroppudin (@saroppudin)
GitHub: https://github.com/saroppudin

---

**Last Updated:** 2026-07-10
**Tested On:** Debian 13 Headless, Systemd, BlueALSA
**Production Ready:** ✅ YES
