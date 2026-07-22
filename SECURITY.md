# 🔒 Security & Hardening Guide

## Overview

Dokumen ini menjelaskan **apa yang sesungguhnya diterapkan di kode** (bukan daftar
aspirasional) — termasuk trade-off keamanan yang disengaja demi kenyamanan
operasional, supaya admin tahu persis apa yang perlu diawasi.

---

## 1. Sudoers — Isi Sesungguhnya

**File:** `/etc/sudoers.d/otomasi-audio-rfkill`

Ditulis ulang **setiap kali installer dijalankan** (bukan hanya kalau belum ada),
lalu divalidasi `visudo -c` ke file sementara SEBELUM menimpa file asli — supaya
kalau sintaksnya rusak, sudoers lama yang masih valid tidak ikut hilang.

```bash
lenovo ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart tahrim-daemon.service
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bt-boot-connect.service
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluealsa
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth bluealsa

# BARU V15 — lihat catatan trade-off di bawah:
lenovo ALL=(ALL) NOPASSWD: /home/lenovo/atur_output_audio.sh
lenovo ALL=(ALL) NOPASSWD: /home/lenovo/atur_output_audio.sh *
```

**Prinsip:** Principle of Least Privilege (PoLP) — tidak ada `NOPASSWD: ALL`,
hanya perintah spesifik yang benar-benar dipanggil oleh skrip watchdog/recovery.

### ⚠️ Trade-off Keamanan yang Disengaja: `atur_output_audio.sh`

Dua baris terakhir di atas berarti user `lenovo` bisa menjalankan
`atur_output_audio.sh` sebagai root **tanpa password**. Skrip itu sendiri
melakukan **auto-elevate** (`exec sudo "$SKRIP_ABSOLUT" "$@"`) supaya bisa
menulis `/etc/asound.conf` dan memutus Bluetooth tanpa admin harus ketik
`sudo` manual tiap kali ganti output.

**Konsekuensi nyata:** karena skrip ini berada di `/home/lenovo` (bisa ditulis
oleh user `lenovo` sendiri), NOPASSWD ini **secara teknis berarti user itu
punya jalur ke root** kalau dia (atau siapa pun yang berhasil login sebagai
`lenovo`) mengedit isi skrip tersebut lalu menjalankannya.

Ini adalah **trade-off yang disengaja** demi kenyamanan operasional harian
(admin sekolah tidak perlu ingat password sudo tiap ganti output audio).
Kalau lingkungan Anda butuh isolasi lebih ketat:

```bash
# Opsi pengerasan: pindahkan skrip ke lokasi root-owned, lalu ubah baris
# sudoers agar menunjuk ke path baru itu (bukan lagi /home/lenovo/...).
sudo cp /home/lenovo/atur_output_audio.sh /usr/local/bin/atur_output_audio.sh
sudo chown root:root /usr/local/bin/atur_output_audio.sh
sudo chmod 755 /usr/local/bin/atur_output_audio.sh
# lalu edit /etc/sudoers.d/otomasi-audio-rfkill menyesuaikan path
```

---

## 2. Routing Audio Dinamis (`/etc/asound.conf`) — Pengerasan V15c

`atur_output_audio.sh` menulis ulang `/etc/asound.conf` setiap kali output
diganti. Mode `line_out` memakai plugin ALSA `dmix` (shared-memory ring buffer
antar proses pemutaran):

```
pcm.line_out_aktif {
    type dmix
    ipc_key 1024
    ipc_perm 0600   # <- V15c: owner-only, BUKAN 0666 (world-writable)
    ...
}
```

**Riwayat:** versi V15 awal memakai `ipc_perm 0666`, yang berarti **siapa pun**
proses/user lokal di sistem bisa menulis ke shared-memory audio yang sedang
aktif diputar — celah kecil untuk tamper/DoS. Diketatkan ke `0600` di V15c
karena semua proses pemutaran (cron, systemd daemon, manual) selalu berjalan
sebagai user OS yang sama.

Validasi tambahan: `CARD_ID` (hasil auto-deteksi atau input manual admin)
divalidasi lewat regex `^[A-Za-z0-9_.-]+$` sebelum dipakai menulis config ALSA
maupun `sed` ke `sekolah.conf`, untuk mencegah config rusak akibat input ganjil.

---

## 3. Systemd Service — Konfigurasi Sesungguhnya

**Tidak ada** `PrivateTmp`, `ProtectSystem`, `NoNewPrivileges`, dsb. di unit
file saat ini — kalau Anda ingin menambahkannya, ini adalah area pengerasan
lanjutan yang **belum** diterapkan, bukan sesuatu yang sudah aktif. Konfigurasi
sesungguhnya:

```systemd
# bt-boot-connect.service — oneshot, jalan SEKALI saat boot
[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/home/lenovo/sambung_bt.sh
User=lenovo
RemainAfterExit=no

# tahrim-daemon.service — daemon persisten
[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=/home/lenovo/tahrim_daemon.sh
Restart=always
RestartSec=10
User=lenovo
StartLimitIntervalSec=300
StartLimitBurst=10

# integritas-sistem.service + .timer — cek tiap 15 menit + saat boot
[Service]
Type=oneshot
ExecStart=/usr/local/bin/cek_integritas_sistem.sh
# (berjalan sebagai root — lihat bagian Disaster Recovery di bawah)

# otomasi-audio-alert@.service — dipicu OnFailure= service lain
[Service]
Type=oneshot
ExecStart=/home/lenovo/alert_gagal.sh %i
User=lenovo
```

Kedua service utama (`bt-boot-connect`, `tahrim-daemon`) punya `OnFailure=`
mengarah ke `otomasi-audio-alert@%n.service`, yang mencatat CRITICAL ke log
kalau service gagal berulang — bukan diam-diam retry selamanya tanpa jejak.

---

## 4. Disaster Recovery — `cek_integritas_sistem.sh`

**Lokasi:** `/usr/local/bin/cek_integritas_sistem.sh` (**bukan** di `/home`)
**Alasan:** kalau `/home/lenovo` bersih total (pernah terjadi nyata di
lapangan akibat mati listrik berulang/crash filesystem), skrip penyelamat ini
harus tetap ada supaya bisa mengunduh ulang dari GitHub.

**Cara kerja:**
1. Timer `integritas-sistem.timer` menjalankannya tiap 15 menit + saat boot
2. Mengecek daftar file/folder kunci (skrip inti, config, folder audio)
3. Kalau **<70%** hilang → anggap kejadian kecil, catat CRITICAL saja, **TIDAK** auto-reinstall (supaya tidak menimpa kustomisasi admin)
4. Kalau **≥70%** hilang → anggap `/home` wipe total, otomatis:
   - Unduh tarball repo dari `https://github.com/saroppudin/audio-school-system`
   - Jalankan ulang installer
   - Pulihkan config (`sekolah.conf`, `jadwal_harian.conf`, `jadwal_ujian.conf`) dari `/var/backups/audio-school-system` (backup harian di luar `/home`)
   - Pulihkan file audio `.mp3` dari repo GitHub kalau ada
5. Cooldown 1 jam (`.terakhir_pemulihan`) — tidak akan mencoba pulihkan berulang-ulang kalau masalah terus terjadi

**Implikasi keamanan:** skrip ini punya kemampuan `git clone`/`curl` dari
internet lalu **mengeksekusi installer sebagai root secara otomatis** tanpa
campur tangan manusia. Ini sengaja demi ketahanan operasional (sekolah di
lokasi terpencil tanpa admin IT standby), tapi berarti integritas
`https://github.com/saroppudin/audio-school-system` (siapa yang punya akses
push ke branch `main`) menjadi bagian penting dari rantai kepercayaan sistem
ini. Kalau repo tersebut dikompromikan, mekanisme pemulihan ini bisa jadi
jalur eksekusi kode arbitrer sebagai root.

---

## 5. Audit Logging

Semua aksi dicatat di `/var/log/otomasi_audio.log` (permission `0664`,
owner `lenovo:audio`, logrotate harian retensi 7 hari, compress).

Prefix log yang dipakai secara konsisten:
`[PLAY]` `[SUKSES]` `[GAGAL]` `[CRITICAL]` `[WARNING]` `[INFO]` `[RECOVERY]`
`[SKIP]` `[STANDBY]` `[CATCHUP]` `[DEBUG]`

---

## 6. Validasi Pre-Instalasi

Installer menolak jalan kalau:
- `MAC_SPEAKER` tidak sesuai format `XX:XX:XX:XX:XX:XX` (regex hex 2 digit × 6, dipisah `:`)
- (Tambahkan validasi lain di sini sesuai isi bagian "0. VALIDASI AWAL" di installer Anda)

---

## Pre-Deployment Security Checklist (Rekomendasi Umum Debian, di Luar Skrip)

Item di bawah ini adalah rekomendasi hardening OS umum — **bukan** sesuatu
yang dijalankan otomatis oleh installer, jadi terapkan manual sesuai kebutuhan:

- [ ] Disable root SSH login (`PermitRootLogin no` di `/etc/ssh/sshd_config`)
- [ ] SSH key-only auth (`PasswordAuthentication no`)
- [ ] Firewall UFW (`ufw default deny incoming`, allow ssh saja)
- [ ] `unattended-upgrades` untuk security patch otomatis
- [ ] `fail2ban` untuk percobaan brute-force SSH

---

## Post-Installation Security Verification

```bash
# Verifikasi sudoers
sudo visudo -c
sudo cat /etc/sudoers.d/otomasi-audio-rfkill

# Cek isi /etc/asound.conf aktif (harus ipc_perm 0600 kalau mode line_out)
cat /etc/asound.conf

# Monitor audit log
tail -f /var/log/otomasi_audio.log

# Cek permission file kunci
ls -la /home/lenovo/sekolah.conf
ls -la /var/log/otomasi_audio.log
ls -la /etc/sudoers.d/otomasi-audio-rfkill   # harus 440
```

---

## Known Risks & Mitigasi

| Risiko | Dampak | Mitigasi Saat Ini |
|---|---|---|
| NOPASSWD sudo untuk `atur_output_audio.sh` di `/home` (writable user) | Sedang–Tinggi | Trade-off disengaja demi kenyamanan; bisa diperketat (lihat bagian 1) |
| `cek_integritas_sistem.sh` auto-eksekusi installer dari GitHub sebagai root | Tinggi (kalau repo dikompromikan) | Cooldown 1 jam; ambang 70% mencegah trigger dari kejadian kecil |
| Bluetooth pairing spoofing | Sedang | MAC address tetap (whitelist implisit lewat `MAC_SPEAKER`) |
| API Aladhan downtime | Rendah | Fallback otomatis ke `jadwal_sholat.json` lokal |
| `/etc/asound.conf` dmix shared-memory | Rendah (setelah V15c) | `ipc_perm 0600`, sebelumnya `0666` |
| Log file tampering | Rendah | Permission `0664`, owner grup `audio` |

---

## Backup & Recovery

```bash
# Backup harian otomatis (cron 23:55):
/home/lenovo/backup/config_YYYYMMDD.tar.gz     # retensi 14 hari
/var/backups/audio-school-system/*.bak         # di luar /home, untuk disaster recovery

# Restore manual kalau perlu:
tar -xzf /home/lenovo/backup/config_YYYYMMDD.tar.gz -C /home/lenovo/
```

---

## References

- [Debian Security Wiki](https://wiki.debian.org/Security)
- [Systemd Security](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)
- [ALSA dmix/bluealsa Plugin Docs](https://www.alsa-project.org/wiki/Asoundrc)

---

**Security Level:** Production, dengan trade-off yang didokumentasikan secara eksplisit di atas (bukan diklaim "aman total")
**Audit Status:** Manual review disarankan setiap kali `atur_output_audio.sh` atau sudoers diubah
