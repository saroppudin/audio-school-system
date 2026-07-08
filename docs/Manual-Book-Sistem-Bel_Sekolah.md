# MANUAL BOOK
## Sistem Otomasi Audio Bel Sekolah (Bluetooth)
### Versi Installer: V13

---

## DAFTAR ISI

1. Pendahuluan
2. Struktur Folder & File
3. Panduan Penggunaan Harian
   - 3.1 Mengganti Mode Sekolah
   - 3.2 Mengatur Jadwal Bel Harian (Non-Ujian)
   - 3.3 Mengatur Jadwal Bel Ujian
   - 3.4 Melihat Status Sistem
4. Panduan Pemeliharaan
   - 4.1 Mengecek Kesehatan Sistem
   - 4.2 Membaca Log
   - 4.3 Menyambungkan Ulang Bluetooth
   - 4.4 Menambah/Mengganti File Audio
   - 4.5 Backup Otomatis
5. Troubleshooting (Pemecahan Masalah)
6. Referensi Cepat (Cheat Sheet)
7. Lampiran: Kode Hari & Format Konfigurasi

---

## 1. PENDAHULUAN

Sistem ini mengotomasi bunyi bel sekolah lewat speaker/mixer Bluetooth, mencakup:

- **Bel harian** (lagu pagi, Indonesia Raya, bel dzuhur, dan bel custom lain)
- **Bel ujian** (jadwal khusus masa ujian, dengan istirahat)
- **Tarhim otomatis** (menjelang subuh & maghrib, mengikuti jadwal sholat online)
- **Penjaga koneksi Bluetooth** otomatis 24 jam
- **Watchdog** yang memantau dan me-restart layanan jika bermasalah

Semua diatur lewat beberapa skrip di folder utama (`~/`, biasanya `/home/lenovo/`), dijalankan otomatis oleh **cron** (penjadwal) dan **systemd** (penjaga layanan latar belakang).

---

## 2. STRUKTUR FOLDER & FILE

```
~/                              (folder utama, mis. /home/lenovo/)
├── sekolah.conf                 (konfigurasi pusat — JANGAN diedit manual kecuali paham)
├── jadwal_harian.conf           (jadwal bel harian: lagu pagi, indo raya, dzuhur, dst)
├── jadwal_ujian.conf            (jadwal bel ujian)
├── audio/                       (SEMUA file .mp3 disimpan di sini)
├── jadwal_nonaktif/              (flag ON/OFF tiap bel, dikelola otomatis)
├── backup/                      (backup harian konfigurasi, otomatis, 14 hari)
│
├── mode_sekolah.sh              (ganti mode: hari biasa / ujian / libur)
├── kelola_harian.sh             (atur jadwal bel harian)
├── kelola_ujian.sh              (atur jadwal bel ujian)
├── cek_kesehatan.sh             (cek status sistem secara keseluruhan)
├── pasang_bt.sh                 (pairing ulang speaker Bluetooth manual)
│
├── cek_harian.sh / cek_ujian.sh / cek_disk.sh / cek_service.sh   (dijalankan otomatis oleh cron)
├── sambung_bt.sh / anti_putus.sh / putar_audio.sh / tahrim_daemon.sh / backup.sh  (mesin internal, tidak perlu disentuh)

/var/log/otomasi_audio.log       (LOG utama — cek di sini kalau ada masalah)
```

> 📌 **File yang boleh dan perlu Anda sentuh sehari-hari:** `mode_sekolah.sh`, `kelola_harian.sh`, `kelola_ujian.sh`, `cek_kesehatan.sh`, `pasang_bt.sh`, dan folder `audio/`.
> File lainnya adalah "mesin dalam" sistem — tidak perlu diedit manual.

---

## 3. PANDUAN PENGGUNAAN HARIAN

### 3.1 Mengganti Mode Sekolah

Jalankan salah satu perintah ini sesuai kondisi:

| Situasi | Perintah |
|---|---|
| Hari sekolah biasa | `~/mode_sekolah.sh hari_biasa` |
| Masa ujian berlangsung | `~/mode_sekolah.sh masa_ujian` |
| Libur panjang (hanya tarhim aktif) | `~/mode_sekolah.sh liburan` |
| Nyalakan semua tanpa kecuali | `~/mode_sekolah.sh normal_semua` |
| Cek status sekarang | `~/mode_sekolah.sh status` |

**Efek tiap mode:**

- **hari_biasa** → semua bel harian (lagu pagi, Indo Raya, dzuhur, bel custom lain) **ON**, bel ujian **OFF**.
- **masa_ujian** → bel ujian **ON**, semua bel harian **OFF kecuali lagu_pagi** (supaya tetap ada tanda masuk pagi, tapi tidak bentrok jadwal ujian).
- **liburan** → semua bel harian & ujian **OFF**, hanya tarhim subuh/maghrib yang tetap bunyi.

### 3.2 Mengatur Jadwal Bel Harian (Non-Ujian)

Perintah dasar:
```bash
~/kelola_harian.sh tambah <JAM> <HARI> <KUNCI> <file1.mp3> [file2.mp3 ...]
~/kelola_harian.sh hapus <KUNCI>
~/kelola_harian.sh daftar
~/kelola_harian.sh kosongkan
```

**Contoh:**
```bash
# Tambah bel pulang, Senin-Jumat jam 13:00
~/kelola_harian.sh tambah 13:00 1-5 bel_pulang bel-pulang.mp3

# Tambah bel dengan beberapa lagu berurutan
~/kelola_harian.sh tambah 06:30 1-6 lagu_pagi Hymne-guru.mp3 Tanah-airku.mp3 Mars.mp3

# Lihat semua jadwal bel harian yang aktif
~/kelola_harian.sh daftar

# Hapus bel custom (bel permanen tidak bisa dihapus)
~/kelola_harian.sh hapus bel_pulang
```

> ⚠️ **`lagu_pagi`, `indonesia_raya`, `bel_dzuhur` bersifat PERMANEN** — tidak bisa dihapus atau ikut terhapus oleh `kosongkan`. Jam/isinya tetap bisa diubah dengan `tambah` memakai kunci yang sama.
>
> ⚠️ Jadwal baru **tidak boleh bentrok jam** dengan `indonesia_raya` atau `bel_dzuhur` — sistem akan menolak otomatis kalau bentrok.

### 3.3 Mengatur Jadwal Bel Ujian

Sama seperti bel harian, tapi tanpa fitur permanen/anti-bentrok:
```bash
~/kelola_ujian.sh tambah <JAM> <HARI> <file.mp3>
~/kelola_ujian.sh hapus <JAM>
~/kelola_ujian.sh daftar
~/kelola_ujian.sh kosongkan
```

**Contoh:**
```bash
~/kelola_ujian.sh tambah 07:00 1-5 bel-mulai-ujian.mp3
~/kelola_ujian.sh tambah 09:00 '*' istirahat.mp3
~/kelola_ujian.sh daftar
```

### 3.4 Melihat Status Sistem

```bash
~/mode_sekolah.sh status
```
Menampilkan semua bel (harian + ujian + tarhim) beserta status ON/OFF-nya saat ini.

---

## 4. PANDUAN PEMELIHARAAN

### 4.1 Mengecek Kesehatan Sistem

```bash
~/cek_kesehatan.sh
```
Menampilkan dalam satu layar:
- Status layanan (`anti-putus`, `tahrim-daemon`) — harus `active`
- Status koneksi Bluetooth speaker (`Connected: yes/no`)
- Sinkronisasi waktu (NTP)
- Sisa ruang disk
- Status ON/OFF semua bel

**Jalankan ini setiap pagi** sebagai rutinitas cek cepat, atau kapan pun ada laporan bel tidak bunyi.

### 4.2 Membaca Log

```bash
# Lihat 30 baris terakhir log
tail -30 /var/log/otomasi_audio.log

# Pantau log secara langsung (real-time), tekan Ctrl+C untuk berhenti
tail -f /var/log/otomasi_audio.log

# Cari hanya baris CRITICAL/WARNING (paling penting)
grep -E "CRITICAL|WARNING" /var/log/otomasi_audio.log | tail -20
```

Kode log yang perlu diperhatikan:
| Kode | Arti |
|---|---|
| `[PLAY]` | Bel berhasil diputar |
| `[SKIP]` | Bel dilewati karena mode nonaktif |
| `[INFO]` / `[SUCCESS]` | Informasi normal |
| `[WARNING]` | Ada masalah kecil, sistem masih mencoba pulih sendiri |
| `[CRITICAL]` | **Perlu perhatian** — biasanya file hilang atau Bluetooth putus |
| `[RECOVERY]` | Sistem berhasil pulih otomatis dari masalah |

Log dirotasi otomatis tiap hari (disimpan 7 hari, terkompresi) — tidak akan memenuhi disk.

### 4.3 Menyambungkan Ulang Bluetooth

Kalau speaker terputus dan tidak tersambung sendiri:
```bash
sudo ~/pasang_bt.sh
```
- Nyalakan dulu **mode pairing** di speaker (biasanya lampu berkedip) sebelum menjalankan ini.
- Skrip ini akan memindai, pairing ulang, trust, dan connect otomatis, lalu menampilkan hasilnya.

Kalau sudah pernah pairing dan cuma putus sesaat, biasanya sistem **akan sambung sendiri otomatis** lewat `anti-putus.service` — tidak perlu tindakan manual.

### 4.4 Menambah/Mengganti File Audio

1. Salin file `.mp3` baru ke folder:
   ```bash
   cp /path/file-baru.mp3 ~/audio/
   ```
2. Daftarkan ke jadwal (lihat bagian 3.2 / 3.3) dengan nama file **persis sama** (huruf besar/kecil berpengaruh).
3. Tidak perlu restart service apa pun — jadwal langsung terbaca menit berikutnya.

### 4.5 Backup Otomatis

Setiap jam 23:55, seluruh file `.sh` dan `.conf` (termasuk jadwal) di-backup otomatis ke:
```
~/backup/config_YYYYMMDD.tar.gz
```
Disimpan 14 hari, lebih lama otomatis dihapus. Untuk backup manual kapan saja:
```bash
~/backup.sh
```
Untuk memulihkan dari backup:
```bash
cd ~
tar -xzf backup/config_20260101.tar.gz   # sesuaikan nama file
```

---

## 5. TROUBLESHOOTING (PEMECAHAN MASALAH)

| Gejala | Kemungkinan Penyebab | Solusi |
|---|---|---|
| Bel tidak bunyi sama sekali | Bluetooth putus | `~/cek_kesehatan.sh` → cek baris "Connected". Kalau `no`, jalankan `sudo ~/pasang_bt.sh` |
| Bel bunyi tapi file salah/tidak ada | Nama file di jadwal tidak cocok dengan file di `~/audio/` | Cek `grep CRITICAL /var/log/otomasi_audio.log`, cocokkan nama file (case-sensitive) |
| Bel ujian bunyi padahal hari libur/Minggu | Kolom HARI di jadwal salah / pakai `*` | `~/kelola_ujian.sh daftar` atau `~/kelola_harian.sh daftar`, edit ulang dengan `tambah` |
| Bel tetap bunyi walau sudah dimatikan lewat mode | Kunci custom belum dikenal sistem saat mode diganti | Jalankan ulang `~/mode_sekolah.sh <mode>` setelah menambah bel baru |
| Layanan mati / tidak aktif | Crash tak terduga | `sudo systemctl restart anti-putus.service tahrim-daemon.service` — watchdog `cek_service.sh` seharusnya sudah mencoba otomatis tiap 5 menit |
| Tarhim tidak bunyi | Gagal ambil jadwal sholat online (internet mati) | Cek koneksi internet server; sistem otomatis pakai jadwal lokal terakhir kalau offline |
| Disk penuh | Log/file audio menumpuk | `~/cek_kesehatan.sh` → cek "Sisa Ruang Disk"; hapus file lama yang tidak perlu di `~/backup/` |

**Kalau semua di atas tidak menyelesaikan masalah:**
```bash
tail -50 /var/log/otomasi_audio.log
```
Catat pesan errornya dan cek lebih detail berdasarkan pesan tersebut.

---

## 6. REFERENSI CEPAT (CHEAT SHEET)

```bash
# --- MODE SEKOLAH ---
~/mode_sekolah.sh hari_biasa
~/mode_sekolah.sh masa_ujian
~/mode_sekolah.sh liburan
~/mode_sekolah.sh status

# --- BEL HARIAN ---
~/kelola_harian.sh tambah <JAM> <HARI> <kunci> <file1.mp3> [file2.mp3 ...]
~/kelola_harian.sh hapus <kunci>
~/kelola_harian.sh daftar
~/kelola_harian.sh kosongkan

# --- BEL UJIAN ---
~/kelola_ujian.sh tambah <JAM> <HARI> <file.mp3>
~/kelola_ujian.sh hapus <JAM>
~/kelola_ujian.sh daftar
~/kelola_ujian.sh kosongkan

# --- PEMELIHARAAN ---
~/cek_kesehatan.sh
sudo ~/pasang_bt.sh
tail -f /var/log/otomasi_audio.log
grep CRITICAL /var/log/otomasi_audio.log
sudo systemctl restart anti-putus.service tahrim-daemon.service
~/backup.sh
```

---

## 7. LAMPIRAN: KODE HARI & FORMAT KONFIGURASI

**Kode hari (dipakai di semua perintah `tambah`):**

| Kode | Hari |
|---|---|
| 1 | Senin |
| 2 | Selasa |
| 3 | Rabu |
| 4 | Kamis |
| 5 | Jumat |
| 6 | Sabtu |
| 7 | Minggu |
| `*` | Setiap hari |

**Contoh pola gabungan:**
- `1-5` → Senin s/d Jumat
- `1-4,6` → Senin s/d Kamis, dan Sabtu (libur Jumat & Minggu)
- `1,3,5` → Senin, Rabu, Jumat saja
- `5` → Jumat saja
- `6-7` → Sabtu & Minggu (weekend)

**Format file `jadwal_harian.conf`:**
```
JAM HARI KUNCI FILE1.mp3,FILE2.mp3,...
```
Contoh:
```
06:30 1-6 lagu_pagi Hymne-guru.mp3,Tanah-airku.mp3,Mars.mp3
13:00 1-5 bel_pulang bel-pulang.mp3
```

**Format file `jadwal_ujian.conf`:**
```
JAM HARI NAMA_FILE.mp3
```
Contoh:
```
07:00 1-5 bel-mulai-ujian.mp3
09:00 * istirahat.mp3
```

> Kedua file ini **tidak wajib diedit manual** — selalu gunakan `kelola_harian.sh` / `kelola_ujian.sh` supaya format & validasinya terjaga.

---

*Manual ini berlaku untuk Installer versi V13. Simpan dokumen ini di tempat yang mudah diakses operator sekolah (misal dicetak dan ditempel di dekat komputer server).*
