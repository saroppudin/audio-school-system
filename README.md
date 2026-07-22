# 🔔 Audio Automation System untuk Sekolah
## Multi-Audio Bell, Exam Scheduler & Prayer Time (Tahrim) Daemon

**Version:** V15c (Production-Ready)
**Target OS:** Debian 13 Headless
**Hardware referensi:** Lenovo S200z (Intel HDA PCH, codec ALC233)
**Status:** ✅ Production Ready

---

## 📋 Fitur Utama

✅ **Otomasi Bel Harian (dinamis, bukan hardcode)**
- Dikelola lewat `jadwal_harian.conf` + `kelola_harian.sh`
- Default: lagu pagi (Senin-Sabtu 06:30), Indonesia Raya (Senin-Kamis & Sabtu 09:59), bel Dzuhur (Senin-Kamis & Sabtu 11:55)
- Tiga kunci bawaan (`lagu_pagi`, `indonesia_raya`, `bel_dzuhur`) permanen — tidak bisa dihapus, hanya diubah jamnya
- Pause otomatis bel jam pelajaran Senin setelah bel masuk (menunggu upacara selesai, auto-batal setelah 90 menit kalau admin lupa `lanjutkan_bel_senin.sh`)

✅ **Manajemen Ujian**
- Jadwal ujian dinamis via `jadwal_ujian.conf` + `kelola_ujian.sh` (`tambah`/`hapus`/`kosongkan`/`daftar`)
- Multiple bell sounds per sesi
- Mode ujian untuk nonaktifkan bel reguler (`mode_sekolah.sh masa_ujian`)

✅ **Daemon Tahrim (Jadwal Sholat)**
- Fetch otomatis dari API Aladhan (`curl --retry 3 --retry-delay 5`)
- Fallback otomatis ke database lokal (`jadwal_sholat.json`) kalau API gagal/offline
- Tarhim Subuh & Maghrib (3 variasi bergilir per hari) — 20 menit sebelum adzan
- Catch-up: kalau daemon sempat restart dan waktu tarhim baru lewat <30 menit, tetap diputar (telat lebih baik daripada tidak sama sekali)
- Menunggu NTP sinkron (maks 2 menit) sebelum menghitung jadwal, supaya tidak meleset gara-gara jam belum sinkron pasca-boot

✅ **Output Audio Ganda: Bluetooth atau Line Out (BARU di V15)**
- Bisa memutar lewat speaker **Bluetooth** (default) *atau* jack audio analog **Line Out** ke amplifier kabel
- Switching lewat satu perintah: `atur_output_audio.sh bluetooth` / `line_out`
- Routing ditulis ulang secara dinamis ke `/etc/asound.conf` (`pcm.!default`) setiap kali diganti — berlaku instan untuk pemutaran berikutnya, tanpa restart apapun
- Auto-deteksi kartu suara analog lewat **nama kartu** (bukan nomor index) supaya tidak meleset kalau nomor kartu bergeser setelah reboot
- Pindah ke Line Out otomatis memutus Bluetooth & unmute channel playback yang terdeteksi ada; pindah ke Bluetooth otomatis sambung ulang
- Auto-elevate (skrip men-sudo dirinya sendiri) + NOPASSWD sudoers khusus untuk skrip ini

✅ **Bluetooth Reconnect (on-demand, bukan loop 24 jam)**
- `sambung_bt.sh` dipanggil otomatis oleh `putar_audio.sh` sebelum tiap bel — cek koneksi, sambung ulang kalau putus
- `bt-boot-connect.service` (oneshot) reconnect sekali saat boot/reboot setelah mati listrik
- Retry 3x dengan log detail alasan gagal dari `bluetoothctl`; setelah 3x gagal beruntun, otomatis restart service `bluetooth`+`bluealsa`

✅ **Reliability & Disaster Recovery**
- `cek_service.sh` (watchdog, tiap 5 menit): restart otomatis `tahrim-daemon.service` kalau mati
- `integritas-sistem.timer` (tiap 15 menit + saat boot): kalau ≥70% file kunci di `/home` hilang total (indikasi wipe/crash filesystem), otomatis unduh ulang dari GitHub, jalankan installer, dan pulihkan konfigurasi + audio dari backup di `/var/backups/audio-school-system` (di luar `/home`, jadi tidak ikut hilang)
- `backup.sh` (harian 23:55): backup config+script ke `~/backup/` (retensi 14 hari) + salin config ke `/var/backups/audio-school-system`
- `otomasi-audio-alert@.service`: dipicu otomatis lewat `OnFailure=` kalau service benar-benar gagal berulang, mencatat CRITICAL ke log
- Logrotate harian (retensi 7 hari, compress)

✅ **Security Hardening**
- Sudo minimal & spesifik (lihat [SECURITY.md](SECURITY.md))
- Validasi format MAC address & koordinat sebelum instalasi jalan
- `/etc/asound.conf` dmix pakai `ipc_perm 0600` (owner-only, bukan world-writable)
- Validasi input CARD_ID sebelum ditulis ke config ALSA

---

## 🚀 Quick Start

### Prerequisites
```bash
# Debian 13 headless, fresh install
# User non-root (default: lenovo), sudah ada di grup sudo
# Root access (sudo)
# Bluetooth adapter + speaker Bluetooth (untuk mode bluetooth), dan/atau
# jack audio analog on-board + amplifier kabel (untuk mode line_out)
# Internet connection (untuk API jadwal sholat & recovery otomatis)
```

### Installation (Instalasi Baru)

Konfigurasi diisi **langsung di bagian atas skrip installer** (bukan file terpisah):

```bash
# 1. Download installer
sudo git clone https://github.com/saroppudin/audio-school-system /opt/audio-school
cd /opt/audio-school/scripts

# 2. Edit konfigurasi LANGSUNG DI DALAM SKRIP (bagian "1. KONFIGURASI SEKOLAH"
#    di paling atas Installer-bel-v15.sh) -- isi USER_SISTEM, NAMA_SEKOLAH,
#    GARIS_LINTANG, GARIS_BUJUR, MAC_SPEAKER sebelum menjalankan.
sudo nano Installer-bel-v15.sh

# 3. Jalankan installer
sudo bash Installer-bel-v15.sh

# 4. Upload file audio MP3 (lihat daftar lengkap di bawah)
scp audio/*.mp3 lenovo@server:/home/lenovo/audio/

# 5. Verifikasi
ssh lenovo@server
/home/lenovo/cek_kesehatan.sh
```

### Menerapkan Perbaikan V15c ke Server yang SUDAH Berjalan (tanpa install ulang)

Kalau server sudah terpasang versi lama (V13/sebelumnya) dan hanya ingin perbaikan
mekanisme switching output audio + bug fix terkait, tanpa install ulang total:

```bash
cd /opt/audio-school/scripts
sudo bash terapkan_perbaikan_switching_v15.sh

# Kalau ada lebih dari satu instalasi terdeteksi, sebutkan path eksplisit:
sudo bash terapkan_perbaikan_switching_v15.sh /home/lenovo
```

Skrip ini otomatis backup file lama (dengan timestamp), tidak menghapus apa pun,
dan langsung menerapkan mode output yang sedang aktif ke `/etc/asound.conf`.

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
│   ├── Installer-bel-v15.sh                    # Installer utama (instalasi baru)
│   └── terapkan_perbaikan_switching_v15.sh     # Patch V15c untuk server yang sudah berjalan
│
├── audio/
│   └── .placeholder                   # Letakkan file .mp3 di sini sebelum upload
│
└── docs/
    ├── API-Integration.md             # Detail API Aladhan
    └── Bluetooth-Setup.md             # Panduan pairing Bluetooth
```

> Catatan: konfigurasi sekolah **tidak lagi** berupa file template terpisah
> (`config/sekolah.conf.example`) — sejak V9 ke atas, nilai konfigurasi
> (`NAMA_SEKOLAH`, `GARIS_LINTANG`, dst.) diisi langsung di bagian atas skrip
> installer sebelum dijalankan. Hasil akhirnya baru ditulis sebagai
> `/home/lenovo/sekolah.conf` oleh installer.

---

## ⚙️ Konfigurasi

### Lokasi Config Utama (hasil generate installer, JANGAN edit manual)
```bash
/home/lenovo/sekolah.conf
```

### Isi Utama
```bash
NAMA_SEKOLAH="SMK Nurussalaf Kemiri"
GARIS_LINTANG="-7.7134"
GARIS_BUJUR="109.9961"
MAC_SPEAKER="C9:7F:2A:D1:9A:99"          # bluetoothctl devices untuk cari
DIR_BASE="/home/lenovo"

# Output audio (BARU V15) -- ganti HANYA lewat atur_output_audio.sh,
# jangan edit baris ini manual supaya asound.conf tetap konsisten.
AUDIO_OUTPUT="bluetooth"                  # atau "line_out"
AUDIO_DEVICE_LINEOUT="hw:PCH,0"           # diisi otomatis oleh atur_output_audio.sh
```

### Mengganti Output Audio
```bash
# Pindah ke speaker Bluetooth
sudo /home/lenovo/atur_output_audio.sh bluetooth

# Pindah ke jack analog (auto-deteksi kartu, atau sebutkan manual)
sudo /home/lenovo/atur_output_audio.sh line_out
sudo /home/lenovo/atur_output_audio.sh line_out PCH

# Lihat status & isi /etc/asound.conf aktif
/home/lenovo/atur_output_audio.sh status

# Tes bunyi cepat lewat output yang sedang aktif
/home/lenovo/atur_output_audio.sh test
```

---

## 🎵 File Audio yang Diperlukan

Upload ke `/home/lenovo/audio/`:

### Bel Harian
- `Hymne-guru.mp3`, `Tanah-airku.mp3`, `Rukun-Sama-teman.mp3`, `Mars.mp3` (lagu pagi, diputar berurutan)
- `Pengantar-dan-indonesia-raya.mp3` (Indonesia Raya)
- `Bel-Persiapan-Sholat-dzuhur.mp3` (bel Dzuhur)

### Bel Ujian (default `jadwal_ujian.conf`)
- `bel-masuk-ruangan.mp3`
- `bel-mulai-ujian.mp3`
- `istirahat.mp3`
- `bel-sisa-5menit.mp3`
- `istirahat-selesai.mp3`
- `bel-ujian-selesai.mp3`

### Tarhim
- `tarhim-subuh.mp3`
- `tarhim-maghrib-1.mp3`, `tarhim-maghrib-2.mp3`, `tarhim-maghrib-3.mp3` (bergilir per hari)

**Format:** MP3, 128-320 kbps, Mono/Stereo, 8-48 kHz

---

## 🛠️ Perintah Penting

### Output Audio (BARU V15)
```bash
sudo /home/lenovo/atur_output_audio.sh bluetooth
sudo /home/lenovo/atur_output_audio.sh line_out
/home/lenovo/atur_output_audio.sh status
/home/lenovo/atur_output_audio.sh test
```

### Jadwal Harian (bel biasa, bukan ujian)
```bash
/home/lenovo/kelola_harian.sh tambah 07:15 1-5 upacara Mars.mp3
/home/lenovo/kelola_harian.sh daftar
/home/lenovo/kelola_harian.sh hapus 07:15
/home/lenovo/kelola_harian.sh kosongkan
```

### Jadwal Ujian
```bash
/home/lenovo/kelola_ujian.sh tambah 07:00 1-6 bel-mulai-ujian.mp3
/home/lenovo/kelola_ujian.sh daftar
/home/lenovo/kelola_ujian.sh hapus 07:00
/home/lenovo/kelola_ujian.sh kosongkan
```

### Mode Operasional
```bash
/home/lenovo/mode_sekolah.sh hari_biasa      # bel ON, ujian OFF
/home/lenovo/mode_sekolah.sh masa_ujian      # ujian ON, sebagian bel OFF
/home/lenovo/mode_sekolah.sh liburan         # semua bel OFF
/home/lenovo/mode_sekolah.sh normal_semua    # semua ON
/home/lenovo/mode_sekolah.sh status
```

### Bel Senin (Upacara)
```bash
# Setelah upacara selesai, lanjutkan bel jam pelajaran yang di-pause otomatis:
/home/lenovo/lanjutkan_bel_senin.sh
```

### Bluetooth Manual
```bash
/home/lenovo/pasang_bt.sh     # pairing ulang interaktif (speaker harus mode pairing)
/home/lenovo/sambung_bt.sh    # coba sambung ulang sekarang (dipakai juga otomatis)
```

### Monitoring & Debugging
```bash
# Health check lengkap (termasuk status output audio)
/home/lenovo/cek_kesehatan.sh

# Monitor log real-time
tail -f /var/log/otomasi_audio.log

# Service status
systemctl status tahrim-daemon.service
systemctl status bt-boot-connect.service   # oneshot, wajar "inactive" setelah boot
systemctl status integritas-sistem.timer

# Restart service
sudo systemctl restart tahrim-daemon.service

# Lihat CRITICAL/WARNING terbaru
grep -E "CRITICAL|WARNING" /var/log/otomasi_audio.log | tail -20
```

---

## 🔒 Security

Lihat [SECURITY.md](SECURITY.md) untuk detail lengkap: isi sudoers sesungguhnya,
trade-off keamanan auto-elevate `atur_output_audio.sh`, dan pengerasan `/etc/asound.conf`.

---

## 📊 Monitoring

Sistem ini mencatat ke `/var/log/otomasi_audio.log`:
- Status koneksi Bluetooth & percobaan reconnect
- Audio playback sukses/gagal (lengkap dengan kode keluar `mpv` yang diterjemahkan)
- Status API Aladhan & fallback ke cache lokal
- Aktivitas watchdog service & recovery otomatis
- Peringatan disk hampir penuh (>85%)
- Aktivitas pemulihan otomatis integritas sistem

---

## 🐛 Troubleshooting

Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) untuk panduan lengkap, termasuk
isu spesifik switching output audio (mode `line_out` tidak bunyi, kartu tidak
terdeteksi, dsb).

---

## 📝 Changelog

### V15c (Perbaikan mekanisme switching output audio — audit lanjutan)
- 🐛 **Bug fix kritis:** deteksi kartu analog salah mengambil nama panjang kartu
  (`"HDA Intel PCH"`, ada spasi) alih-alih ID pendek (`"PCH"`) — `line_out` tidak
  akan pernah bunyi sebelumnya karena string device ALSA tidak valid
- 🐛 **Bug fix portabilitas:** deteksi kartu sebelumnya memakai fitur `awk`
  khas **gawk** (`match(str,regex,array)`) yang tidak tersedia di `mawk`
  (default `/usr/bin/awk` di banyak instalasi Debian minimal) — diganti kode
  `awk` POSIX yang portable di kedua varian
- 🐛 **Bug fix:** pre-flight check mode `line_out` di `putar_audio.sh`
  sebelumnya selalu bernilai "OK" walau kartu analog benar-benar tidak ada
  (logika `grep -qv` yang salah), sehingga CRITICAL tidak pernah tercatat
- ⚙️ Optimasi: `unmute_semua_channel` sekarang query kontrol mixer yang
  **benar-benar ada** di hardware (`amixer scontrols`) alih-alih menebak 5
  nama kontrol yang sebagian besar tidak ada; volume+unmute digabung jadi
  satu panggilan `amixer` per kontrol
- 🔒 Keamanan: `ipc_perm` dmix diketatkan dari `0666` (world-writable) ke
  `0600`; ditambah validasi format `CARD_ID` sebelum ditulis ke config ALSA
- 🧹 Clean code: dihapus dead code (`MAC_SPEAKER_LOWER` yang tidak terpakai),
  3 blok tes-bunyi identik digabung jadi satu fungsi `tes_bunyi()`, 8+ baris
  logging berulang di `putar_audio.sh` digabung jadi fungsi `catat()`
- ✅ Divalidasi dengan `shellcheck` (bersih, 0 warning) dan simulasi
  end-to-end memakai data hardware & konfigurasi nyata

### V15 (Mekanisme switching output audio)
- ✅ Routing ALSA dinamis: `atur_output_audio.sh` menulis ulang
  `/etc/asound.conf` (`pcm.!default`) setiap kali output diganti — berlaku
  instan tanpa restart apapun
- ✅ Unified playback engine: `putar_audio.sh` selalu memutar ke
  `alsa/default`, tidak lagi dibedakan device per mode
- ✅ Auto-elevate + NOPASSWD sudoers khusus untuk `atur_output_audio.sh`
- ✅ Clean disconnect (Bluetooth diputus otomatis saat pindah ke line_out)
  & unmute hardware otomatis

### V14 dan sebelumnya
- ✅ `anti-putus.service` (loop 24 jam) diganti `bt-boot-connect.service`
  (oneshot, sekali jalan saat boot) — reconnect harian ditangani on-demand
  oleh `sambung_bt.sh` sebelum tiap bel, bukan proses yang jalan terus-menerus
- ✅ Jadwal bel harian dipindah dari hardcode ke `jadwal_harian.conf` +
  `kelola_harian.sh`
- ✅ Pause otomatis bel Senin (menunggu upacara) dengan safety-valve 90 menit
- ✅ Disaster recovery: `cek_integritas_sistem.sh` + `integritas-sistem.timer`
- ✅ DST-aware / NTP-aware scheduling untuk jadwal tarhim

---

## 📞 Support

Untuk issues atau pertanyaan:
1. Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Cek `/var/log/otomasi_audio.log`
3. Jalankan `/home/lenovo/cek_kesehatan.sh` dan lampirkan hasilnya
4. Buka issue di GitHub

---

## 📄 Lisensi

MIT License - Bebas digunakan untuk tujuan komersial & non-komersial

---

## 👨‍💻 Maintainer

Saroppudin (@saroppudin)
GitHub: https://github.com/saroppudin

---

**Tested On:** Debian 13 Headless, Systemd, BlueALSA, Lenovo S200z (Intel HDA PCH / ALC233)
**Production Ready:** ✅ YES
