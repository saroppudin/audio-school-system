# 🎙️ Bluetooth Setup & Pairing Guide

> **Catatan V15:** panduan ini khusus untuk kalau Anda memakai mode output
> **Bluetooth**. Kalau lokasi Anda memakai jack analog (**Line Out**) ke
> amplifier kabel, panduan ini tidak relevan — langsung ke
> `atur_output_audio.sh line_out` (lihat [README.md](../README.md)).

## Pre-Pairing Checklist

- [ ] Bluetooth adapter terpasang & berfungsi
- [ ] Speaker menyala
- [ ] Speaker dalam mode pairing (biasanya tahan tombol 3-5 detik)
- [ ] Tidak ada masalah pairing sebelumnya (kalau ada riwayat gagal, `bluetoothctl remove <MAC>` dulu)

---

## Cara Tercepat: Pakai Skrip Bawaan (Disarankan)

Setelah sistem terinstal, jangan jalankan langkah manual di bawah satu-satu —
pakai skrip interaktif yang sudah menggabungkan semua langkah dan sudah
menangani lock file (mencegah tabrakan dengan proses reconnect otomatis):

```bash
/home/lenovo/pasang_bt.sh
```

Skrip ini akan menunggu akses adapter Bluetooth (kalau sedang dipakai proses
otomatis lain), lalu `power on` → `scan` 10 detik → `pair` → `trust` →
`connect` → tampilkan status akhir. Ikuti instruksi yang muncul di layar.

Bagian di bawah ini menjelaskan **langkah manual** kalau Anda ingin
memahami/melakukan sendiri tiap tahapnya, atau untuk troubleshooting kalau
`pasang_bt.sh` gagal.

---

## Step-by-Step Manual Pairing

### 1. Verifikasi Adapter Bluetooth

```bash
bluetoothctl list
# Contoh output:
# Controller AA:BB:CC:DD:EE:FF  hostname [default]

# Kalau tidak ada output:
sudo systemctl status bluetooth
sudo rfkill unblock bluetooth
bluetoothctl power on
```

### 2. Scan Perangkat

```bash
bluetoothctl scan on
# Tunggu nama speaker muncul:
# [NEW] Device XX:XX:XX:XX:XX:XX SpeakerName
```

### 3. Pair Perangkat

```bash
bluetoothctl pair XX:XX:XX:XX:XX:XX
# [CHR] Pairing successful
```

### 4. Trust Perangkat

```bash
bluetoothctl trust XX:XX:XX:XX:XX:XX
# [CHR] Device XX:XX:XX:XX:XX:XX trusted
```

### 5. Connect Perangkat

```bash
bluetoothctl connect XX:XX:XX:XX:XX:XX
# Connection successful
```

### 6. Verifikasi Koneksi

```bash
bluetoothctl info XX:XX:XX:XX:XX:XX
# Harus tertulis: Connected: yes
```

---

## Troubleshooting

### Speaker tidak muncul saat scan
- Matikan speaker, tunggu 10 detik, nyalakan lagi
- Dekatkan ke server (kurangi interferensi)
- Pastikan benar-benar dalam mode pairing (biasanya lampu indikator berkedip cepat, beda pola dengan mode "sudah terhubung")

### Pairing gagal
```bash
bluetoothctl remove XX:XX:XX:XX:XX:XX
sudo systemctl restart bluetooth bluealsa
bluetoothctl power on
# Coba pairing lagi (lewat pasang_bt.sh atau manual)
```

### Error `br-connection-busy` saat connect
**Sebab:** dua proses `bluetoothctl` mencoba connect bersamaan — biasanya
`pasang_bt.sh` manual berbarengan dengan `sambung_bt.sh` otomatis yang
dipanggil sebelum bel diputar.
**Catatan:** sudah dicegah lewat lock file bersama `/tmp/bt_op.lock` di kedua
skrip tersebut — kalau tetap terjadi, tunggu beberapa detik dan coba lagi
(lock punya timeout 20-30 detik).

### Error `br-connection-page-timeout` saat connect
**Sebab:** speaker mati, di luar jangkauan, atau sedang terhubung ke device
lain (banyak speaker Bluetooth hanya bisa 1 koneksi aktif).
**Fix:** cek fisik speaker dulu sebelum mencurigai software.

### Sudah Connected tapi tidak ada suara
```bash
# Cek mode output audio yang sedang aktif -- pastikan memang "bluetooth"
/home/lenovo/atur_output_audio.sh status

# Cek isi /etc/asound.conf yang di-generate (harus ada blok
# "pcm.bt_speaker_aktif { type bluealsa; device "<MAC Anda>"; ... }")
cat /etc/asound.conf

# Tes bunyi lewat mekanisme resmi sistem (bukan mpv manual) --
# ini juga otomatis mencoba reconnect kalau perlu:
/home/lenovo/atur_output_audio.sh test

# Kalau masih tidak bunyi, tes langsung ke BlueALSA untuk isolasi masalah:
arecord -D bluealsa --list-devices
amixer scontrols        # lihat nama kontrol yang BENAR-BENAR ada di hardware Anda
```

> **Catatan V15:** jangan lagi menguji dengan
> `mpv --audio-device=alsa/bluealsa file.mp3` secara manual seperti panduan
> versi lama — sejak V15, routing ditentukan sepenuhnya oleh
> `/etc/asound.conf` yang dikelola `atur_output_audio.sh`, jadi cara resmi
> untuk menguji adalah `atur_output_audio.sh test` (otomatis mengikuti mode
> yang sedang aktif, bukan hardcode ke bluealsa).

---

## Menyimpan MAC Address

**Penting:** simpan MAC address speaker Anda!

Diperlukan untuk `MAC_SPEAKER` di bagian atas skrip `Installer-bel-v15.sh`
(kalau instalasi baru), atau langsung di `/home/lenovo/sekolah.conf` (kalau
mengganti speaker di sistem yang sudah berjalan — lihat prosedur "Ganti
Speaker Bluetooth" di [Manual-Book-Sistem-Bel-Sekolah.md](Manual-Book-Sistem-Bel-Sekolah.md)).

---

**Lihat juga:** [Manual-Book-Sistem-Bel-Sekolah.md](Manual-Book-Sistem-Bel-Sekolah.md) untuk panduan operasional lengkap, dan [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) untuk isu di luar Bluetooth.
