# Panduan Instalasi & Operasional Sistem Otomasi Audio Sekolah
### (Installer-bel-v13, revisi V14)

Dokumen ini untuk siapa pun yang akan memasang atau merawat sistem bel otomatis + tarhim + audio Bluetooth di sekolah, menggunakan `Installer-bel-v13.sh`. Ditulis berdasarkan pengalaman instalasi nyata (termasuk troubleshooting yang sudah dilalui), supaya orang lain tidak perlu mengulang proses debugging yang sama.

**Riwayat revisi dokumen ini:**
- V14 — Penghapusan `anti-putus.service` (loop 24 jam) diganti `bt-boot-connect.service` (oneshot saat boot); perbaikan `/etc/asound.conf`; perbaikan race condition `putar_audio.sh`; penghapusan flag mpv tidak valid.
- V14 (lanjutan) — `mode_sekolah.sh status` sekarang meringkas semua bel custom jadi satu baris "Bel harian" (kecuali `lagu_pagi`, `indonesia_raya`, `bel_dzuhur` yang tetap tampil sendiri); ditambahkan panduan impor massal jadwal (bagian 8.4).

---

## 1. Gambaran Umum Sistem

Sistem ini menjalankan otomatis di Debian:
- **Bel harian** (lagu pagi, Indonesia Raya, bel dzuhur, dll — jadwal fleksibel per hari)
- **Bel ujian** (jadwal jam ujian & istirahat, terpisah dari bel harian)
- **Tarhim otomatis** menjelang waktu Subuh & Maghrib (jadwal diambil online dari API jadwal sholat, dengan fallback offline)
- **Output audio HANYA lewat speaker Bluetooth** (mixer sekolah) — tidak ada fallback ke speaker lokal PC
- Watchdog, logging, backup config, dan monitoring kesehatan otomatis

Semua diatur lewat satu file: `sekolah.conf`, dan diinstal oleh satu script: `Installer-bel-v13.sh`.

---

## 2. Prasyarat

### Hardware
- PC/Laptop dengan adapter Bluetooth internal atau USB dongle Bluetooth
- Speaker/mixer Bluetooth berprofil **A2DP** (mendukung streaming audio, bukan cuma headset call)
- Koneksi internet (untuk jadwal sholat online & instalasi paket — sistem tetap bisa jalan offline dengan data jadwal sholat cache terakhir)

### Software
- **Debian 12/13** (sudah diuji, termasuk penamaan paket `polkitd` pengganti `policykit-1` di versi baru)
- Akses **root/sudo**
- User sistem non-root sudah dibuat sebelumnya (default di script: `lenovo` — sesuaikan kalau beda)

### Paket yang otomatis diinstal oleh installer
`bluez`, `bluez-tools`, `bluez-alsa-utils`, `alsa-utils`, `mpv`, `curl`, `jq`, `rfkill`, `nano`, `fail2ban`, `systemd-timesyncd`, `policykit-1`/`polkitd`

> **Penting:** Installer otomatis **menonaktifkan PipeWire/PulseAudio/WirePlumber** kalau ada, karena mereka berebut akses adapter Bluetooth dengan BlueALSA. Sistem ini didesain full pakai **BlueALSA + ALSA murni**, bukan PipeWire.

---

## 3. Persiapan Sebelum Instalasi

### Langkah 1 — Pairing speaker secara manual (WAJIB dilakukan dulu sebelum atau sesaat setelah instalasi)

Cari tahu MAC address speaker Bluetooth yang akan dipakai:

```bash
bluetoothctl scan on
# Tunggu sampai nama speaker/mixer muncul, catat MAC-nya, misal:
# 16:3E:E3:5F:EF:E5  BT-MAX
```

Pastikan speaker dalam **mode pairing** (biasanya lampu indikator berkedip cepat) saat scan.

### Langkah 2 — Edit variabel konfigurasi di awal script installer

Buka `Installer-bel-v13.sh`, cari bagian **"1. KONFIGURASI SEKOLAH"** di awal file, dan sesuaikan:

```bash
USER_SISTEM="lenovo"                   # Nama user non-root di Debian
NAMA_SEKOLAH="SMK Nurussalaf Kemiri"   # Nama Sekolah Anda
GARIS_LINTANG="-7.7134"                # Koordinat Lintang Sekolah
GARIS_BUJUR="109.9961"                 # Koordinat Bujur Sekolah
MAC_SPEAKER="16:3E:E3:5F:EF:E5"        # MAC Address Mixer/Speaker Bluetooth
```

Cara cari koordinat lintang/bujur sekolah: buka Google Maps, klik kanan di lokasi sekolah, koordinat langsung tersalin.

### Langkah 3 — Siapkan file audio

Siapkan file `.mp3` yang dibutuhkan di folder `/home/<user>/audio/` (folder ini dibuat otomatis oleh installer, tapi filenya harus kamu isi sendiri). Nama file default yang dirujuk jadwal bawaan:

- `Hymne-guru.mp3`, `Tanah-airku.mp3`, `Rukun-Sama-teman.mp3`, `Mars.mp3` (lagu pagi)
- `Pengantar-dan-indonesia-raya.mp3`
- `Bel-Persiapan-Sholat-dzuhur.mp3`
- `bel-masuk-ruangan.mp3`, `bel-mulai-ujian.mp3`, `istirahat.mp3`, `bel-sisa-5menit.mp3`, `istirahat-selesai.mp3`, `bel-ujian-selesai.mp3`
- `tarhim-subuh.mp3`, `tarhim-maghrib-1.mp3`, `tarhim-maghrib-2.mp3`, `tarhim-maghrib-3.mp3`

Installer akan **memperingatkan di akhir instalasi** kalau ada file yang belum ada — bel terkait cuma tidak akan bunyi sampai file ditambahkan (tidak menghentikan instalasi).

---

## 4. Proses Instalasi

```bash
sudo chmod +x Installer-bel-v13.sh
sudo ./Installer-bel-v13.sh
```

Installer akan berjalan otomatis lewat 9 tahap (apt update, konfigurasi Bluetooth/BlueALSA, kunci PCM ALSA ke MAC speaker, generate semua script & config, daftarkan systemd service, logrotate, crontab). Total durasi tergantung kecepatan `apt update && apt upgrade` (bisa beberapa menit).

Di akhir instalasi akan muncul ringkasan status:

```
====================================================
 INSTALASI SELESAI - <Nama Sekolah>
====================================================
 Service aktif   : tahrim-daemon.service (nonstop), bt-boot-connect.service (oneshot saat boot)
 ...
 STATUS BLUETOOTH SPEAKER (16:3E:E3:5F:EF:E5)
   Sudah Paired  : YA/TIDAK
   Sudah Connect : YA/TIDAK
```

Kalau status **Paired: TIDAK**, jalankan pairing manual:

```bash
sudo /home/<user>/pasang_bt.sh
```

(Pastikan speaker dalam mode pairing saat menjalankan ini.)

---

## 5. Checklist Verifikasi Paska-Instalasi

Jangan langsung anggap selesai — jalankan checklist ini dulu:

```bash
# 1. Bluetooth benar-benar paired & connected
bluetoothctl info <MAC_SPEAKER> | grep -E "Paired|Trusted|Connected|Name"

# 2. Konfigurasi ALSA benar (harus cuma 2 baris "defaults.bluealsa...")
cat /etc/asound.conf

# 3. Config utama benar
cat /home/<user>/sekolah.conf

# 4. Service aktif & sehat
systemctl status tahrim-daemon.service --no-pager
systemctl status bt-boot-connect.service --no-pager   # wajar kalau "inactive (dead)" setelah sukses jalan sekali
systemctl status bluealsa.service --no-pager
systemctl status bluetooth.service --no-pager

# 5. TEST PALING PENTING: playback manual, dengarkan langsung dari speaker
/home/<user>/putar_audio.sh test "Test Instalasi" /home/<user>/audio/<salah-satu-file>.mp3
tail -20 /var/log/otomasi_audio.log

# 6. Test 2 file berturut-turut (rawan race condition kalau ada)
/home/<user>/putar_audio.sh test1 "Test 1" /home/<user>/audio/<file1>.mp3
sleep 3
/home/<user>/putar_audio.sh test2 "Test 2" /home/<user>/audio/<file2>.mp3

# 7. Cron aktif
crontab -l -u <user>

# 8. TEST REBOOT PENUH — paling penting untuk memastikan
#    bt-boot-connect.service benar-benar reconnect otomatis
sudo reboot
# setelah nyala lagi, tunggu ~1 menit, ulangi langkah 1 & 5 tanpa
# melakukan apapun manual

# 9. Disk & log tidak membengkak
df -h /home
du -sh /var/log/otomasi_audio.log
```

Kalau semua lolos, sistem siap dipakai produksi harian.

---

## 6. Peta Semua Script (letaknya di `/home/<user>/`)

| Script | Dipanggil oleh | Fungsi |
|---|---|---|
| `sekolah.conf` | semua script lain (di-`source`) | Konfigurasi pusat: nama sekolah, koordinat, MAC speaker, path |
| `jadwal_harian.conf` | `cek_harian.sh` | Jadwal bel harian (lagu pagi, Indonesia Raya, bel dzuhur, dst) |
| `jadwal_ujian.conf` | `cek_ujian.sh` | Jadwal bel & istirahat masa ujian |
| `pasang_bt.sh` | **Manual oleh admin** | Pairing ULANG dari nol (scan→pair→trust→connect). Dipakai kalau speaker direset/diganti/ada masalah pairing |
| `sambung_bt.sh` | `putar_audio.sh`, otomatis | Cek cepat status koneksi, reconnect ringan (3x percobaan) kalau putus, sebelum tiap bel diputar |
| `putar_audio.sh` | `cek_harian.sh`, `cek_ujian.sh`, `tahrim_daemon.sh` | Eksekusi aktual pemutaran audio lewat `mpv`, dengan lock file anti-tabrakan |
| `cek_harian.sh` | **cron, tiap menit** | Cek jadwal `jadwal_harian.conf`, panggil `putar_audio.sh` kalau waktunya pas |
| `cek_ujian.sh` | **cron, tiap menit** | Sama seperti di atas tapi untuk `jadwal_ujian.conf` |
| `kelola_harian.sh` | Manual oleh admin | Tambah/ubah/lihat jadwal bel harian (CLI interaktif) |
| `kelola_ujian.sh` | Manual oleh admin | Tambah/ubah/lihat jadwal bel ujian |
| `mode_sekolah.sh` | Manual oleh admin | Aktifkan/nonaktifkan mode: hari biasa / masa ujian / liburan, per fitur bel |
| `tahrim_daemon.sh` | systemd (`tahrim-daemon.service`, nonstop) | Ambil jadwal sholat online (API Aladhan), putar tarhim 20 menit sebelum Subuh/Maghrib |
| `cek_disk.sh` | **cron, tiap 5 menit** | Peringatan kalau disk > 85% penuh |
| `cek_service.sh` | **cron, tiap 5 menit** | Watchdog: restart `tahrim-daemon.service` kalau mati |
| `cek_kesehatan.sh` | Manual oleh admin | Ringkasan status sistem sekali lihat (service, Bluetooth, disk, NTP) |
| `alert_gagal.sh` | systemd `OnFailure=` | Catat log CRITICAL kalau service gagal berulang (bukan reconnect biasa) |
| `backup.sh` | **cron, tiap hari 23:55** | Backup semua `.sh`/`.conf` ke `~/backup/`, simpan 14 hari terakhir |

## 7. Systemd Service & Cron

| Nama | Tipe | Fungsi |
|---|---|---|
| `bt-boot-connect.service` | `oneshot`, jalan sekali saat boot | Reconnect otomatis ke speaker setelah mati listrik/reboot |
| `tahrim-daemon.service` | `simple`, nonstop | Jalankan `tahrim_daemon.sh` terus-menerus |
| `otomasi-audio-alert@.service` | `oneshot`, dipicu `OnFailure=` | Kirim log CRITICAL saat service utama gagal total |

> **Catatan V14:** Versi sebelumnya (V13 ke bawah) punya `anti-putus.service` yang jalan 24 jam nonstop mengirim audio kosong (silent keep-alive) ke speaker supaya koneksi tidak terputus. Ini **dihapus** di V14 karena terbukti tidak diperlukan (speaker BT-MAX tetap reconnect otomatis dengan baik tanpa itu) dan justru jadi sumber bug `Device or resource busy` karena berebut akses PCM dengan `mpv`. Reconnect sekarang cukup ditangani `bt-boot-connect.service` (sekali saat boot) + `sambung_bt.sh` (on-demand sebelum tiap bel).

Cron (`crontab -l -u <user>`):
```
* * * * * /home/<user>/cek_harian.sh
* * * * * /home/<user>/cek_ujian.sh
*/5 * * * * /home/<user>/cek_disk.sh
*/5 * * * * /home/<user>/cek_service.sh
55 23 * * * /home/<user>/backup.sh
```

---

## 8. Panduan Operasional Harian

**Cek status sistem kapan saja:**
```bash
/home/<user>/cek_kesehatan.sh
```

### 8.1 Mengelola Jadwal Bel Harian (`kelola_harian.sh`)

Dipakai untuk bel non-ujian: lagu pagi, Indonesia Raya, bel dzuhur, atau bel custom lain.

**Lihat semua jadwal aktif:**
```bash
/home/<user>/kelola_harian.sh daftar
```
Contoh output:
```
=== DAFTAR JADWAL BEL HARIAN AKTIF ===
JAM      HARI       KUNCI           FILE
06:30    1-6        lagu_pagi       Hymne-guru.mp3,Tanah-airku.mp3,Rukun-Sama-teman.mp3,Mars.mp3 (permanen)
09:59    1-4,6      indonesia_raya  Pengantar-dan-indonesia-raya.mp3 (permanen)
11:55    1-4,6      bel_dzuhur      Bel-Persiapan-Sholat-dzuhur.mp3 (permanen)
```

**Menambah jadwal baru:**
```bash
/home/<user>/kelola_harian.sh tambah <HH:MM> <HARI> <kunci> <file1.mp3> [file2.mp3 ...]
```
Contoh:
```bash
# Bel pulang jam 15:00, Senin-Jumat, 1 file audio
/home/<user>/kelola_harian.sh tambah 15:00 1-5 bel_pulang Bel-Pulang.mp3

# Bel apel pagi, Senin saja, beberapa file diputar berurutan
/home/<user>/kelola_harian.sh tambah 06:45 1 apel_senin Bel-Apel.mp3,Sambutan-Kepsek.mp3
```
Kode `<HARI>`: `1`=Senin `2`=Selasa `3`=Rabu `4`=Kamis `5`=Jumat `6`=Sabtu `7`=Minggu. Bisa rentang (`1-5`), daftar (`1,3,5`), atau `'*'` untuk setiap hari (**pakai tanda kutip** supaya tidak ditafsirkan shell sebagai wildcard file).

`<kunci>` adalah nama unik pengenal jadwal ini (huruf kecil/angka/underscore saja) — dipakai lagi kalau mau menghapus atau mengubahnya, dan juga muncul di `mode_sekolah.sh status`.

> Kalau kamu **tambah lagi dengan kunci yang sama**, jadwal lama otomatis ditimpa (bukan duplikat) — ini cara resmi untuk **mengubah** jadwal yang sudah ada (ubah jam/hari/file-nya).

> Sistem otomatis **menolak** jadwal baru yang jamnya bentrok dengan salah satu dari 3 kunci PERMANEN (`lagu_pagi`, `indonesia_raya`, `bel_dzuhur`) — pilih jam lain kalau muncul pesan `[GAGAL] Jam ... sudah dipakai jadwal PERMANEN`.

**Menghapus satu jadwal:**
```bash
/home/<user>/kelola_harian.sh hapus <kunci>
# contoh:
/home/<user>/kelola_harian.sh hapus bel_pulang
```
> Kunci **permanen** (`lagu_pagi`, `indonesia_raya`, `bel_dzuhur`) **tidak bisa dihapus** — kalau dicoba, akan muncul pesan `[GAGAL] ... bersifat PERMANEN`. Untuk "menghilangkan" bunyinya sementara (bukan menghapus), pakai `mode_sekolah.sh` (lihat 8.3), bukan `hapus`.

**Mengosongkan SEMUA jadwal custom sekaligus:**
```bash
/home/<user>/kelola_harian.sh kosongkan
```
Ini menghapus **semua** jadwal harian **kecuali** 3 kunci permanen — jadwal permanen tetap dipertahankan otomatis, tidak perlu khawatir hilang.

### 8.2 Mengelola Jadwal Bel Ujian (`kelola_ujian.sh`)

Lebih sederhana dari jadwal harian — tidak ada konsep "kunci", dan tidak ada jadwal permanen (semua bisa dihapus/diubah bebas).

**Lihat semua jadwal ujian aktif:**
```bash
/home/<user>/kelola_ujian.sh daftar
```

**Menambah / mengubah jadwal:**
```bash
/home/<user>/kelola_ujian.sh tambah <HH:MM> <HARI> <file.mp3>
# contoh:
/home/<user>/kelola_ujian.sh tambah 07:00 1-5 bel-mulai-ujian.mp3
/home/<user>/kelola_ujian.sh tambah 09:00 '*' istirahat.mp3
```
> Sama seperti jadwal harian: menambah dengan **jam yang sama** akan **menimpa** jadwal lama di jam itu — ini cara mengubah jadwal ujian yang sudah ada.

**Menghapus satu jadwal (berdasarkan jam):**
```bash
/home/<user>/kelola_ujian.sh hapus <HH:MM>
# contoh:
/home/<user>/kelola_ujian.sh hapus 09:00
```

**Mengosongkan SEMUA jadwal ujian:**
```bash
/home/<user>/kelola_ujian.sh kosongkan
```
Beda dengan jadwal harian: **tidak ada yang dipertahankan** — semua baris jadwal ujian akan hilang total. Pastikan memang mau mengosongkan semuanya (misalnya di awal semester baru sebelum menyusun jadwal ujian dari nol).

### 8.3 Menyalakan/Mematikan Bel Tanpa Menghapus Jadwal (`mode_sekolah.sh`)

Ini untuk kebutuhan "matikan sementara" (misalnya pas libur atau masa ujian) **tanpa** menghapus konfigurasi jadwalnya — beda dengan `hapus`/`kosongkan` di atas yang menghapus permanen.

```bash
/home/<user>/mode_sekolah.sh status        # lihat kondisi ON/OFF tiap bel saat ini
/home/<user>/mode_sekolah.sh hari_biasa    # semua bel harian ON, jadwal ujian OFF
/home/<user>/mode_sekolah.sh masa_ujian    # jadwal ujian ON, semua bel harian OFF kecuali lagu_pagi
/home/<user>/mode_sekolah.sh liburan       # SEMUA bel (harian+ujian) OFF, HANYA tarhim tetap ON
/home/<user>/mode_sekolah.sh normal_semua  # aktifkan semua fitur tanpa kecuali (reset total ke ON)
```

Contoh output `status`:
```
====================================================
 STATUS MODE AUDIO OPERASIONAL SEKOLAH
====================================================
  lagu_pagi       : [ ON  ] AKTIF NORMAL
  indonesia_raya  : [ ON  ] AKTIF NORMAL
  bel_dzuhur      : [ ON  ] AKTIF NORMAL
  Bel harian      : [ ON  ] AKTIF NORMAL (40 bel)
  ujian           : [ OFF ] NONAKTIF
  tarhim_subuh    : [ ON  ] AKTIF NORMAL
  tarhim_maghrib  : [ ON  ] AKTIF NORMAL
====================================================
```
> **Catatan tampilan:** `lagu_pagi`, `indonesia_raya`, dan `bel_dzuhur` selalu tampil sendiri-sendiri. Semua bel **custom** lain yang ditambahkan lewat `kelola_harian.sh tambah` (berapa pun jumlahnya) digabung jadi **satu baris ringkasan "Bel harian"**, supaya status tidak dipenuhi puluhan baris kunci teknis. Kalau sebagian bel custom itu dimatikan manual satu-satu (bukan lewat preset di atas), baris ini otomatis berubah jadi `[ SEBAGIAN ] 35 dari 40 bel aktif` sebagai tanda ada yang tidak konsisten.

Contoh alur pemakaian nyata:
- **Awal semester, hari belajar biasa:** `mode_sekolah.sh hari_biasa`
- **Masuk masa Penilaian Akhir Semester:** `mode_sekolah.sh masa_ujian`
- **Libur semester/lebaran:** `mode_sekolah.sh liburan`
- **Habis libur, mulai belajar lagi:** `mode_sekolah.sh hari_biasa`

> Preset ini otomatis ikut mengatur bel **custom** yang kamu tambahkan lewat `kelola_harian.sh tambah` juga — tidak perlu edit script tiap kali menambah bel baru.

### 8.4 Impor Massal Jadwal (Migrasi dari Perangkat/Sistem Lain)

Kalau sekolah sebelumnya pakai perangkat bel otomatis lain dan mau memindahkan seluruh jadwalnya ke sistem ini, cara paling praktis **bukan** mengetik satu-satu lewat `kelola_harian.sh tambah`, tapi membuat **satu file script berisi banyak baris `tambah` sekaligus**, lalu jalankan sekali.

**Langkah-langkahnya:**
1. Kumpulkan data jadwal lama (jam, hari aktif, nama file lagu) — bisa dari screenshot, foto layar perangkat lama, atau tabel manual.
2. Pastikan semua file audio yang dirujuk sudah ada di `/home/<user>/audio/` dengan nama yang sesuai.
3. Buat file `.sh` berisi baris-baris `kelola_harian.sh tambah` — untuk mempermudah verifikasi, kelompokkan berdasarkan **pola hari aktif** (bukan berdasarkan urutan nomor sumber), dan urutkan menaik berdasarkan jam di tiap kelompok. Contoh struktur:

```bash
#!/bin/bash
DIR="/home/lenovo"

# KELOMPOK: SENIN SAJA (1)
$DIR/kelola_harian.sh tambah 07:45 1 bel_contoh_0745 0017.mp3
$DIR/kelola_harian.sh tambah 08:10 1 bel_contoh_0810 0018.mp3

# KELOMPOK: SELASA-KAMIS & SABTU (2-4,6)
$DIR/kelola_harian.sh tambah 07:15 2-4,6 bel_contoh2_0715 0017.mp3
# ...dst
```

4. Beri nama `<kunci>` yang unik dan mudah dilacak balik ke sumbernya, misal `bel_<nomorfile>_<jamHHMM>`. Kalau ada file+jam yang sama muncul lebih dari sekali dengan hari berbeda (dan itu **memang** dua bel terpisah, bukan hasil salah baca), tambahkan akhiran `a`, `b`, dst supaya kunci tidak saling menimpa.
5. Validasi sintaks dulu sebelum dijalankan ke server produksi:
   ```bash
   bash -n nama_file_import.sh && echo "Sintaks OK"
   ```
6. Jalankan sekali:
   ```bash
   chmod +x nama_file_import.sh
   ./nama_file_import.sh
   /home/<user>/kelola_harian.sh daftar   # verifikasi hasilnya
   ```

> **Kalau file impor ini pernah dijalankan sebelumnya** (misalnya sedang menyempurnakan urutan/pengelompokan), jalankan `kelola_harian.sh kosongkan` dulu sebelum menjalankan versi barunya — supaya tidak ada kunci lama dengan penamaan berbeda yang nyangkut dan menyebabkan bel bunyi dobel.

**Waspada saat transkripsi dari foto/screenshot** — kualitas gambar yang buram gampang membuat salah baca 1 digit jam atau hari. Selalu:
- Silang-cek ulang jumlah baris (total entri) antara sumber dan hasil transkripsi.
- Perhatikan baris yang polanya **beda sendiri** dari baris-baris di sekitarnya (kemungkinan besar itu bukan salah baca — potensi pengecualian yang memang disengaja, tapi tetap perlu dikonfirmasi ke yang paling paham jadwal sekolahnya).
- Kalau ragu, lebih baik tanya dulu daripada menjalankan langsung ke server produksi.

**Ganti speaker Bluetooth (kalau beli speaker baru / MAC berubah):**
1. Edit `MAC_SPEAKER` di `/home/<user>/sekolah.conf`
2. Edit juga `defaults.bluealsa.device` di `/etc/asound.conf` — samakan dengan MAC baru
3. Pairing speaker baru: `sudo /home/<user>/pasang_bt.sh`
4. Hapus pairing speaker lama (opsional, kalau tidak dipakai lagi): `bluetoothctl remove <MAC_LAMA>`

---

## 9. Troubleshooting Umum

| Gejala | Penyebab Paling Umum | Solusi |
|---|---|---|
| `mpv` error `Unknown field slave` | `/etc/asound.conf` berisi definisi `pcm.bluealsa` mentah yang bentrok dengan template resmi paket `bluez-alsa` | Pastikan `/etc/asound.conf` **hanya** berisi `defaults.bluealsa.device` & `defaults.bluealsa.profile`, jangan definisikan ulang `pcm.bluealsa`/`ctl.bluealsa` |
| `mpv` error `Device or resource busy` | Ada proses lain (mis. `aplay -D bluealsa`) sedang memegang PCM yang sama | `pkill -f "aplay -q -D bluealsa"` sebelum play (sudah otomatis ditangani `putar_audio.sh`) |
| `mpv` Fatal Error, `option not found` | Opsi command-line mpv yang salah/tidak ada (mis. `--audio-fallback-to-ids` yang memang bukan opsi valid) | Cek `mpv --list-options`, samakan nama opsi yang benar |
| Audio keluar dari speaker PC, bukan Bluetooth | PipeWire/PulseAudio masih aktif dan mengambil alih routing | Pastikan PipeWire/PulseAudio/WirePlumber dinonaktifkan (installer sudah menangani ini otomatis) |
| Bluetooth gagal connect: `br-connection-page-timeout` | Speaker mati / di luar jangkauan / sedang connect ke device lain | Cek fisik speaker dulu (nyala, dekat, tidak dipakai device lain) sebelum curiga ke software |
| Bluetooth gagal connect: `br-connection-busy` | Dua proses `bluetoothctl` mencoba connect bersamaan (mis. `pasang_bt.sh` manual + `sambung_bt.sh` otomatis di waktu bersamaan) | Sudah dicegah lewat lock file bersama `/tmp/bt_op.lock` di `sambung_bt.sh` & `pasang_bt.sh` |
| Log menunjukkan percobaan reconnect ke MAC yang salah/lama | MAC lama masih tersimpan sebagai trusted device di database Bluetooth, atau ada script/proses lama yang belum diperbarui | `bluetoothctl remove <MAC_lama>`; cek juga proses "hantu" yang masih jalan dari script versi lama: `sudo lsof +L1 \| grep sh` |
| `hci0 error` di layar / dmesg | Masalah driver/hardware adapter Bluetooth | `dmesg \| grep -i hci0`, coba `sudo rfkill unblock bluetooth && sudo systemctl restart bluetooth` |

---

## 10. Catatan Keamanan Data

- File `sekolah.conf` menyimpan MAC address speaker dalam bentuk plain text — bukan data sensitif secara keamanan (bukan password), aman disimpan begitu.
- `alert_gagal.sh` dan seluruh log ditulis ke `/var/log/otomasi_audio.log`, dirotasi otomatis tiap hari (disimpan 7 hari, `logrotate`).
- Backup config otomatis harian ke `~/backup/`, disimpan 14 hari terakhir.

---

*Dokumen ini dibuat berdasarkan pengalaman instalasi & debugging nyata sistem Installer-bel-v13 (revisi V14). Kalau menemukan skenario baru yang belum tercakup di sini, sebaiknya ditambahkan supaya panduan ini terus relevan untuk instalasi berikutnya.*
