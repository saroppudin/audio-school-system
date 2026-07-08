#!/bin/bash
# ====================================================================
# MASTER INSTALLER AUTOMATION AUDIO SEKOLAH (VERSION 5 - PERBAIKAN BLUETOOTH)
# SYSTEM: MULTI-AUDIO BEL UJIAN, BEL HARIAN & DAEMON TAHRIM
# ----------------------------------------------------------------
# CATATAN PERBAIKAN DARI VERSION 4:
#   1. [PENYEBAB UTAMA "BLUETOOTH TIDAK BISA KONEK"]
#      V4 tidak pernah melakukan PAIRING ke speaker, hanya "connect".
#      Kalau speaker belum pernah dipasangkan, connect akan SELALU
#      gagal. -> Sekarang ada proses pairing+trust otomatis saat
#      instalasi, plus skrip pasang_bt.sh untuk pairing ulang manual.
#   2. [PENYEBAB "SUDAH CONNECTED TAPI TETAP TIDAK BERBUNYI"]
#      PCM ALSA default "bluealsa" (dari paket bluez-alsa-utils) punya
#      DEV default 00:00:00:00:00:00 (placeholder), BUKAN MAC speaker
#      Anda. Artinya aplay/mpv -D bluealsa tidak pernah menunjuk ke
#      speaker yang benar. -> Sekarang dibuatkan /etc/asound.conf yang
#      mengunci PCM "bluealsa" ke MAC_SPEAKER secara eksplisit.
#   3. Adapter Bluetooth sekarang dipaksa AutoEnable=true di
#      /etc/bluetooth/main.conf supaya otomatis nyala tiap boot,
#      tidak bergantung hanya pada 'bluetoothctl power on' saat
#      instalasi.
#   4. Servis systemd (anti-putus, tahrim-daemon) sekarang punya
#      After=/Wants= ke bluealsa.service supaya tidak race condition
#      saat baru boot.
#   5. Ditambahkan aturan Polkit + D-Bus supaya user non-root yang
#      menjalankan bluetoothctl lewat systemd/cron (tanpa sesi login
#      konsol) tidak ditolak diam-diam oleh Polkit.
#   6. sambung_bt.sh sekarang trust dulu sebelum connect, dan
#      mencatat OUTPUT asli dari bluetoothctl ke log supaya kalau
#      gagal lagi, penyebabnya kelihatan (bukan cuma "gagal").
#   7. putar_audio.sh sekarang benar-benar mengecek status koneksi
#      sebelum main dan mencatat CRITICAL yang jelas kalau tetap putus.
#   8. Verifikasi akhir sekarang juga mengecek apakah MAC_SPEAKER
#      sudah ada di daftar paired-devices.
#
# TAMBAHAN VERSION 6:
#   9. Error handling diperluas: perintah-perintah sistem penting
#      (systemctl, crontab, dbus) sekarang dibungkus fungsi jalankan()
#      yang mencatat sukses/gagal dengan jelas, bukan diam-diam lanjut.
#  10. FALLBACK AUDIO LOKAL: kalau speaker Bluetooth gagal konek saat
#      jadwal bel tiba, bel tetap dibunyikan lewat output audio lokal
#      (jack/HDMI PC) supaya sekolah tidak "bisu total" saat Bluetooth
#      bermasalah.
#  11. MONITORING KEGAGALAN SERVICE: anti-putus.service & tahrim-
#      daemon.service sekarang punya OnFailure= yang mencatat ke log
#      kalau service benar-benar gagal (bukan cuma reconnect biasa),
#      plus watchdog cron cek_service.sh setiap 5 menit sebagai
#      jaring pengaman kedua kalau systemd sendiri tidak mendeteksinya.
#
# TAMBAHAN VERSION 7 (sesuai permintaan):
#  12. FALLBACK AUDIO LOKAL DIHAPUS. Output audio HANYA lewat
#      Bluetooth speaker -- itu memang satu-satunya output utama.
#  13. PEMAKAIAN RFKILL DIMINIMALKAN. rfkill sekarang HANYA dipakai
#      sekali saat instalasi awal dan lewat pasang_bt.sh (manual, atas
#      permintaan admin). Loop recovery otomatis di sambung_bt.sh
#      TIDAK lagi mem-block/unblock rfkill berulang -- karena dengan
#      AutoEnable=true (adapter auto-nyala tiap boot) dan
#      anti-putus.service (menjaga koneksi tetap hidup nonstop),
#      adapter seharusnya tidak pernah dalam kondisi ter-blok saat
#      runtime. Kalau tetap gagal 3x beruntun, recovery sekarang cukup
#      restart service bluetooth & bluealsa saja.
#
# TAMBAHAN VERSION 8 (perbaikan bug instalasi):
#  14. Paket 'policykit-1' TIDAK ADA lagi di Debian 12/13 (namanya
#      berubah jadi 'polkitd'), sehingga baris 'apt install ... -y'
#      yang menggabung semua paket jadi GAGAL TOTAL dan skrip exit 1.
#      -> Sekarang instalasi Polkit dipisah dari paket inti, mencoba
#      'policykit-1' lalu 'polkitd' sebagai fallback, dan kalau
#      keduanya tetap tidak ada, hanya PERINGATAN (tidak fatal) --
#      karena polkit di skrip ini cuma hardening tambahan, bukan
#      syarat mutlak Bluetooth & bel bisa berfungsi.
#
# TAMBAHAN VERSION 9 (idempotensi untuk upgrade komputer lama):
#  15. File sudoers otomasi-audio SEKARANG SELALU ditulis ulang &
#      divalidasi tiap kali installer dijalankan (sebelumnya hanya
#      dibuat kalau belum ada -- artinya komputer yang sudah pernah
#      diinstal versi lama TIDAK mendapat izin sudo terbaru walau
#      installer-nya di-update). Ini membuat skrip aman untuk
#      di-RE-RUN di atas instalasi lama untuk keperluan upgrade/
#      perbaikan, tanpa menghapus jadwal_ujian.conf atau file audio.
#
# TAMBAHAN VERSION 10 (bug fundamental Bluetooth):
#  16. BlueALSA sebelumnya didaftarkan sebagai '-p a2dp-sink' (PC =
#      penerima audio), padahal speaker fisik juga selalu berperan
#      sebagai Sink -- dua-duanya sink membuat profil AVDTP gagal
#      disepakati ("br-connection-profile-unavailable"). Diperbaiki
#      jadi '-p a2dp-source' (PC = pengirim audio ke speaker).
#
# TAMBAHAN VERSION 11 (filter hari untuk bel ujian):
#  17. jadwal_ujian.conf sekarang punya kolom HARI (format cron-style:
#      '*', '1-5', '1,3,5', dst -- 1=Senin...7=Minggu). Sebelumnya bel
#      ujian bunyi setiap hari tanpa pandang bulu termasuk Minggu/libur.
#      kelola_ujian.sh & cek_ujian.sh diperbarui mendukung ini, dengan
#      kompatibilitas mundur untuk baris format lama (2 kolom = jam+file,
#      otomatis dianggap berlaku setiap hari).
#
# TAMBAHAN VERSION 12 (migrasi bel harian ke sistem konfigurasi):
#  18. Bel HARI BIASA (lagu pagi, Indonesia Raya, bel dzuhur) sekarang
#      dikelola lewat file jadwal_harian.conf + kelola_harian.sh &
#      cek_harian.sh -- bukan lagi hardcode langsung di crontab. Bisa
#      tambah bel baru dengan banyak file sekaligus & filter hari,
#      persis seperti kelola_ujian.sh.
#  19. 'lagu_pagi', 'indonesia_raya', 'bel_dzuhur' dijadikan KUNCI
#      PERMANEN: tidak bisa dihapus lewat 'hapus' maupun 'kosongkan'
#      (isi jam/hari/file-nya tetap bisa diubah lewat 'tambah' dengan
#      kunci yang sama). 'kosongkan' hanya menghapus jadwal custom,
#      tiga kunci permanen ini selalu dipertahankan.
#  20. Jadwal baru yang jamnya BENTROK dengan salah satu kunci permanen
#      (lagu_pagi/indonesia_raya/bel_dzuhur) otomatis DITOLAK oleh
#      kelola_harian.sh, supaya tidak saling menimpa.
#  21. mode_sekolah.sh sekarang membaca daftar kunci bel secara dinamis
#      dari jadwal_harian.conf, jadi bel baru yang ditambahkan otomatis
#      ikut muncul di status ON/OFF tanpa perlu edit skrip.
#
# TAMBAHAN VERSION 13 (masa_ujian mematikan semua bel harian kecuali lagu_pagi):
#  22. Sebelumnya mode 'masa_ujian' HANYA mematikan indonesia_raya &
#      bel_dzuhur -- bel custom lain (atau bel baru yang ditambahkan
#      nanti lewat kelola_harian.sh) tetap ON tanpa disadari. Sekarang
#      'masa_ujian' otomatis mematikan SEMUA kunci di jadwal_harian.conf
#      KECUALI 'lagu_pagi' (supaya tidak bentrok dengan jadwal ujian),
#      dan ini berlaku dinamis untuk bel baru juga -- tidak perlu edit
#      skrip tiap kali menambah bel harian baru.
#  23. 'hari_biasa' juga diperluas: sekarang menghidupkan SEMUA kunci
#      bel harian (bukan cuma 3 yang lama) secara dinamis.
#  24. 'liburan' juga diperluas: mematikan SEMUA kunci bel harian
#      (termasuk bel custom baru) secara dinamis, hanya Tarhim yang aktif.
# ====================================================================

set -o pipefail

# --------------------------------------------------------------------
# 1. KONFIGURASI SEKOLAH (SESUAIKAN DI SINI SEBELUM MENJALANKAN)
# --------------------------------------------------------------------
USER_SISTEM="lenovo"                   # Nama user non-root di Debian
NAMA_SEKOLAH="SMK Nurussalaf Kemiri"   # Nama Sekolah Anda
GARIS_LINTANG="-7.7134"                # Koordinat Lintang Sekolah
GARIS_BUJUR="109.9961"                 # Koordinat Bujur Sekolah
MAC_SPEAKER="7d:5b:22:c8:4d:ab"        # MAC Address Mixer/Speaker Bluetooth

# Jalur Direktori (Otomatis menyesuaikan dengan USER_SISTEM)
DIR_BASE="/home/${USER_SISTEM}"
DIR_AUDIO="${DIR_BASE}/audio"
DIR_FLAG="${DIR_BASE}/jadwal_nonaktif"
LOG_FILE="/var/log/otomasi_audio.log"

# --------------------------------------------------------------------
# 0. VALIDASI AWAL - mencegah instalasi jalan dengan konfigurasi
#    yang salah ketik / tidak masuk akal
# --------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Harap jalankan skrip ini sebagai root atau gunakan 'sudo ./Installer-bel.sh'"
  exit 1
fi

if ! id "${USER_SISTEM}" &>/dev/null; then
    echo "[ERROR] User sistem '${USER_SISTEM}' tidak ditemukan di server ini."
    echo "        Buat usernya dulu, contoh: adduser ${USER_SISTEM}"
    echo "        atau sesuaikan variabel USER_SISTEM di bagian atas skrip ini."
    exit 1
fi

if ! [[ "$GARIS_LINTANG" =~ ^-?[0-9]+\.?[0-9]*$ ]] || ! [[ "$GARIS_BUJUR" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    echo "[ERROR] Format GARIS_LINTANG / GARIS_BUJUR tidak valid. Harus berupa angka desimal, contoh: -7.7134"
    exit 1
fi

if ! [[ "$MAC_SPEAKER" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
    echo "[ERROR] Format MAC_SPEAKER tidak valid. Contoh format yang benar: 7d:5b:22:c8:4d:ab"
    exit 1
fi
MAC_SPEAKER_LOWER=$(echo "$MAC_SPEAKER" | tr 'A-F' 'a-f')

# PERBAIKAN (BARU V6): pembungkus perintah-perintah penting supaya
# kegagalan tidak diam-diam terlewat. Perintah non-fatal (systemctl,
# crontab, dbus, dll) tetap lanjut instalasi tapi dicatat jelas kalau
# gagal, sehingga admin bisa langsung tahu apa yang perlu dicek ulang.
jalankan() {
    local deskripsi="$1"; shift
    if "$@" >/tmp/jalankan_output.$$ 2>&1; then
        echo "  [OK] ${deskripsi}"
        rm -f /tmp/jalankan_output.$$
        return 0
    else
        local kode=$?
        echo "  [PERINGATAN] ${deskripsi} - GAGAL (exit code ${kode})"
        sed 's/^/      > /' /tmp/jalankan_output.$$
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [INSTALL-WARNING] - ${deskripsi} gagal (exit ${kode})." >> "$LOG_FILE" 2>/dev/null
        rm -f /tmp/jalankan_output.$$
        return "$kode"
    fi
}

echo "===================================================="
echo " Memulai Instalasi Otomatisasi Audio V13 untuk:"
echo " ${NAMA_SEKOLAH}"
echo "===================================================="

# --------------------------------------------------------------------
# 2. INSTALASI PAKET DEPENDENSI SISTEM
# --------------------------------------------------------------------
echo "[1/9] Menginstal paket pendukung Debian..."
apt update && apt upgrade -y
if ! apt install bluez bluez-tools bluez-alsa-utils alsa-utils mpv curl jq rfkill nano fail2ban systemd-timesyncd -y; then
    echo "[ERROR] Gagal menginstal paket dependensi. Periksa koneksi internet / repository apt Anda."
    exit 1
fi

# PERBAIKAN (V8): 'policykit-1' sudah TIDAK ADA lagi namanya di Debian
# 12/13 -- diganti jadi 'polkitd'. Sebelumnya paket ini digabung dalam
# satu baris 'apt install ... -y', jadi satu nama paket yang tidak
# ditemukan bikin SELURUH instalasi dianggap gagal & skrip exit 1.
# Sekarang dipisah dan dicoba kedua nama; kalau tetap tidak ada,
# hanya PERINGATAN (bukan fatal) karena polkit di sini cuma hardening
# tambahan untuk izin D-Bus, bukan syarat mutlak Bluetooth bisa jalan.
echo "Menginstal Polkit (policykit-1 / polkitd)..."
if apt install policykit-1 -y 2>/dev/null; then
    echo "  [OK] policykit-1 terpasang."
elif apt install polkitd pkexec -y 2>/dev/null; then
    echo "  [OK] polkitd terpasang (nama pengganti policykit-1 di Debian baru)."
else
    echo "  [PERINGATAN] Tidak bisa memasang policykit-1 maupun polkitd."
    echo "               Aturan Polkit tambahan akan dilewati -- fitur inti"
    echo "               Bluetooth & bel tetap berjalan normal."
fi

# Atur zona waktu dan aktifkan NTP
timedatectl set-timezone Asia/Jakarta
systemctl enable --now systemd-timesyncd
systemctl enable --now fail2ban

# Matikan PipeWire jika ada (agar tidak berebut bluetooth adapter)
systemctl disable --now pipewire pipewire-pulse wireplumber 2>/dev/null
# Kalau ada sesi user aktif dengan pipewire versi --user, matikan juga
loginctl list-users --no-legend 2>/dev/null | awk '{print $1}' | while read -r uid; do
    runuser -l "$(id -nu "$uid" 2>/dev/null)" -c 'systemctl --user disable --now pipewire pipewire-pulse wireplumber' 2>/dev/null
done

# Mencegah PC masuk ke mode tidur/suspend
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Masukkan user ke grup audio dan bluetooth
usermod -aG audio,bluetooth "${USER_SISTEM}"

# PERBAIKAN (BARU): pastikan adapter otomatis nyala tiap kali boot,
# tidak bergantung pada 'power on' manual saat instalasi saja.
echo "[2/9] Mengonfigurasi adapter Bluetooth agar auto-enable saat boot..."
if [ -f /etc/bluetooth/main.conf ]; then
    cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak.$(date +%s)
    if grep -q "^AutoEnable" /etc/bluetooth/main.conf; then
        sed -i 's/^AutoEnable.*/AutoEnable=true/' /etc/bluetooth/main.conf
    elif grep -q "^\[Policy\]" /etc/bluetooth/main.conf; then
        sed -i '/^\[Policy\]/a AutoEnable=true' /etc/bluetooth/main.conf
    else
        printf "\n[Policy]\nAutoEnable=true\n" >> /etc/bluetooth/main.conf
    fi
fi

# PERBAIKAN (BARU): aturan Polkit supaya user non-root yang menjalankan
# bluetoothctl lewat systemd/cron (tanpa sesi login konsol interaktif)
# tidak ditolak diam-diam saat power on / connect / trust dsb.
mkdir -p /etc/polkit-1/rules.d
cat <<'EOF' > /etc/polkit-1/rules.d/50-otomasi-audio-bluetooth.rules
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.bluez") == 0 && subject.isInGroup("bluetooth")) {
        return polkit.Result.YES;
    }
});
EOF
jalankan "Restart polkit" systemctl restart polkit

# PERBAIKAN (BARU): aturan D-Bus tambahan sebagai jaring pengaman kedua,
# untuk distro/versi bluez yang policy default-nya lebih ketat.
cat <<EOF > /etc/dbus-1/system.d/60-otomasi-audio-bluetooth.conf
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy group="bluetooth">
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.Agent1"/>
    <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
  </policy>
</busconfig>
EOF
jalankan "Reload dbus" systemctl reload dbus.service

# PERBAIKAN (V10 - BUG FUNDAMENTAL): sebelumnya bluealsa dikonfigurasi
# dengan '-p a2dp-sink', yang artinya PC ini didaftarkan sebagai
# PENERIMA audio (seperti PC berlagak jadi speaker untuk HP orang lain).
# Padahal yang kita mau justru sebaliknya: PC ini harus jadi PENGIRIM
# audio ke speaker/mixer fisik. Speaker fisik selalu berperan sebagai
# "Sink" (penerima) -- kalau PC JUGA didaftarkan sebagai sink, dua-duanya
# sink dan tidak ada yang mau jadi source, sehingga profil AVDTP gagal
# disepakati saat connect (persis error "br-connection-profile-unavailable").
# -> Sekarang bluealsa didaftarkan sebagai '-p a2dp-source' (PC = pengirim
# audio), sesuai kebutuhan sebenarnya.
echo "[3/9] Mengonfigurasi BlueALSA (mode A2DP Source - PC sebagai pengirim audio)..."
mkdir -p /etc/systemd/system/bluealsa.service.d
cat <<EOF > /etc/systemd/system/bluealsa.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa -p a2dp-source
EOF
jalankan "Reload daemon systemd" systemctl daemon-reload
jalankan "Restart service bluetooth" systemctl restart bluetooth
sleep 2
jalankan "Unblock rfkill bluetooth" rfkill unblock bluetooth
jalankan "Power on adapter bluetooth" bluetoothctl power on
sleep 1
jalankan "Restart service bluealsa" systemctl restart bluealsa
sleep 2

# PERBAIKAN (BARU): kunci PCM ALSA "bluealsa" ke MAC speaker yang benar.
# Tanpa ini, DEV memakai placeholder 00:00:00:00:00:00 dan audio TIDAK
# akan pernah keluar ke speaker walau Bluetooth berhasil connect.
echo "[4/9] Mengunci PCM ALSA 'bluealsa' ke speaker (${MAC_SPEAKER})..."
[ -f /etc/asound.conf ] && cp /etc/asound.conf /etc/asound.conf.bak.$(date +%s)
cat <<EOF > /etc/asound.conf
pcm.bluealsa {
    type bluealsa
    device "${MAC_SPEAKER}"
    profile "a2dp"
}
ctl.bluealsa {
    type bluealsa
}
EOF

# PERBAIKAN (BARU): PAIRING otomatis ke speaker. Ini yang HILANG di V4
# dan menjadi penyebab utama "bluetooth tidak bisa konek" -- V4 langsung
# mencoba 'connect' tanpa pernah 'pair'/'trust' dulu.
echo "[5/9] Mencoba memasangkan (pairing) ke speaker ${MAC_SPEAKER}..."
echo "      >>> PASTIKAN SPEAKER SEDANG DALAM MODE PAIRING SEKARANG <<<"
bluetoothctl agent NoInputNoOutput >/dev/null 2>&1
bluetoothctl default-agent >/dev/null 2>&1
timeout 10 bluetoothctl scan on >/dev/null 2>&1
sleep 8
bluetoothctl scan off >/dev/null 2>&1

if bluetoothctl pair "$MAC_SPEAKER" 2>&1 | tee -a "$LOG_FILE" | grep -qi "Pairing successful\|already paired\|AlreadyExists"; then
    echo "  [OK] Pairing berhasil (atau sudah pernah dipasangkan sebelumnya)."
else
    echo "  [PERINGATAN] Pairing otomatis tidak berhasil dipastikan."
    echo "  Kemungkinan speaker belum dalam mode pairing / di luar jangkauan."
    echo "  Setelah instalasi selesai, jalankan manual: ${DIR_BASE}/pasang_bt.sh"
fi
bluetoothctl trust "$MAC_SPEAKER" >/dev/null 2>&1
bluetoothctl connect "$MAC_SPEAKER" 2>&1 | tee -a "$LOG_FILE"

# PERBAIKAN: sudoers ditulis ke file terpisah di /etc/sudoers.d/ dan
# divalidasi dengan visudo -c, jauh lebih aman daripada menambahkan
# baris langsung ke /etc/sudoers utama.
# PERBAIKAN: sudoers ditulis ke file terpisah di /etc/sudoers.d/ dan
# divalidasi dengan visudo -c, jauh lebih aman daripada menambahkan
# baris langsung ke /etc/sudoers utama.
# PERBAIKAN (V9): file ini SEKARANG SELALU ditulis ulang (bukan hanya
# kalau belum ada). Sebelumnya kalau file sudah ada dari instalasi versi
# lama, isinya tidak pernah diperbarui -- artinya re-run installer versi
# baru di komputer yang sudah pernah diinstal versi lama TIDAK akan
# mendapat izin sudo terbaru (systemctl restart bluetooth/bluealsa, dll)
# yang dibutuhkan fitur watchdog & recovery. Ditulis ke file sementara
# dulu lalu divalidasi visudo -c SEBELUM menimpa file asli, supaya kalau
# sintaksnya rusak, sudoers lama yang masih valid tidak ikut hilang.
SUDOERS_FILE="/etc/sudoers.d/otomasi-audio-rfkill"
SUDOERS_TMP="$(mktemp)"
cat <<EOF > "$SUDOERS_TMP"
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart anti-putus.service
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart tahrim-daemon.service
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluealsa
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth bluealsa
EOF
if visudo -c -f "$SUDOERS_TMP" &>/dev/null; then
    mv "$SUDOERS_TMP" "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    echo "  [OK] Sudoers otomasi-audio diperbarui."
else
    echo "[ERROR] Sintaks sudoers baru tidak valid, sudoers LAMA (kalau ada) dibiarkan apa adanya demi keamanan."
    rm -f "$SUDOERS_TMP"
    exit 1
fi

# --------------------------------------------------------------------
# 3. MEMBUAT STRUKTUR DIREKTORI & FILE KONFIGURASI SENTRAL
# --------------------------------------------------------------------
echo "[6/9] Membuat struktur folder dan file konfigurasi..."
mkdir -p "${DIR_AUDIO}"
mkdir -p "${DIR_FLAG}"

cat <<EOF > ${DIR_BASE}/sekolah.conf
# FILE KONFIGURASI GENERATED AUTOMATICALLY
NAMA_SEKOLAH="${NAMA_SEKOLAH}"
GARIS_LINTANG="${GARIS_LINTANG}"
GARIS_BUJUR="${GARIS_BUJUR}"
MAC_SPEAKER="${MAC_SPEAKER}"
DIR_BASE="${DIR_BASE}"
DIR_AUDIO="${DIR_AUDIO}"
DIR_FLAG="${DIR_FLAG}"
LOG_FILE="${LOG_FILE}"
DB_LOKAL="${DIR_BASE}/jadwal_sholat.json"
CONF_UJIAN="${DIR_BASE}/jadwal_ujian.conf"
CONF_HARIAN="${DIR_BASE}/jadwal_harian.conf"
EOF

# MEMBUAT DEFAULT JADWAL BEL UJIAN (Berdasarkan Istirahat Baru V2)
if [ ! -f "${DIR_BASE}/jadwal_ujian.conf" ]; then
cat <<EOF > ${DIR_BASE}/jadwal_ujian.conf
# ====================================================================
# JADWAL BEL UJIAN & ISTIRAHAT
# FORMAT: JAM[SPASI]HARI[SPASI]NAMA_FILE.mp3
#   HARI: '*' = setiap hari, atau kode cron-style:
#         1=Senin 2=Selasa 3=Rabu 4=Kamis 5=Jumat 6=Sabtu 7=Minggu
#         Contoh: 1-5 (Senin-Jumat), 1,3,5 (Senin/Rabu/Jumat), 6-7 (weekend)
# Sesuai Lampiran Jadwal Harian Sekolah / Masa Ujian Semester/Kelas 3
# Default di bawah ini diset hari "1-6" (Senin-Sabtu, libur Minggu).
# ====================================================================

# --- SHIFT PAGI ---
06:50 1-6 bel-masuk-ruangan.mp3
07:00 1-6 bel-mulai-ujian.mp3

# --- ISTIRAHAT PERTAMA (09.00 - 09.15) ---
09:00 1-6 istirahat.mp3
09:12 1-6 bel-sisa-5menit.mp3
09:15 1-6 istirahat-selesai.mp3

# --- PERSIAPAN SHIFT SIANG ---
10:10 1-6 bel-masuk-ruangan.mp3
10:30 1-6 bel-mulai-ujian.mp3

# --- ISTIRAHAT KEDUA (12.15 - 12.45) ---
12:15 1-6 istirahat.mp3
12:42 1-6 bel-sisa-5menit.mp3
12:45 1-6 istirahat-selesai.mp3

# --- AKHIR SELURUH UJIAN HARI INI ---
13:45 1-6 bel-ujian-selesai.mp3
EOF
fi

# PERBAIKAN (V12): jadwal bel HARI BIASA (lagu pagi, Indonesia Raya, bel
# dzuhur) sekarang dikelola lewat file konfigurasi + kelola_harian.sh,
# sama seperti jadwal ujian -- bukan lagi hardcode langsung di crontab.
# Tiga KUNCI di bawah ini bersifat PERMANEN: tidak bisa dihapus lewat
# 'hapus' atau 'kosongkan' (hanya bisa diubah jam/hari/isinya lewat
# 'tambah' dengan kunci yang sama).
if [ ! -f "${DIR_BASE}/jadwal_harian.conf" ]; then
cat <<EOF > ${DIR_BASE}/jadwal_harian.conf
# ====================================================================
# JADWAL BEL HARIAN (BUKAN UJIAN)
# FORMAT: JAM[SPASI]HARI[SPASI]KUNCI[SPASI]FILE1.mp3,FILE2.mp3,...
#   HARI: '*' = setiap hari, atau kode cron-style 1=Senin...7=Minggu
#   KUNCI: pengenal unik bel ini (huruf kecil/angka/underscore),
#          dipakai juga sebagai nama flag ON/OFF di mode_sekolah.sh
#
# TIGA KUNCI DI BAWAH INI PERMANEN (tidak bisa dihapus):
#   lagu_pagi, indonesia_raya, bel_dzuhur
# Jadwal baru yang bentrok jam dengan salah satu di atas akan ditolak
# otomatis oleh kelola_harian.sh.
# ====================================================================
06:30 1-6 lagu_pagi Hymne-guru.mp3,Tanah-airku.mp3,Rukun-Sama-teman.mp3,Mars.mp3
09:59 1-4,6 indonesia_raya Pengantar-dan-indonesia-raya.mp3
11:55 1-4,6 bel_dzuhur Bel-Persiapan-Sholat-dzuhur.mp3
EOF
fi

# --------------------------------------------------------------------
# 4. MEMBUAT SEMUA SKRIP INTI SISTEM
# --------------------------------------------------------------------
echo "[7/9] Membuat berkas skrip operasional audio..."

# Setiap skrip di bawah ini memakai baris berikut untuk menemukan
# sekolah.conf secara dinamis, mengikuti lokasi skrip itu sendiri.
#   DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${DIR_SKRIP}/sekolah.conf"

# Skrip pasang_bt.sh (BARU) - untuk pairing ulang manual kapan saja,
# misalnya kalau speaker direset/diganti/pindah lokasi.
cat <<'EOF' > ${DIR_BASE}/pasang_bt.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"

echo "===================================================="
echo " PAIRING ULANG SPEAKER BLUETOOTH: ${MAC_SPEAKER}"
echo "===================================================="
echo "Pastikan speaker/mixer SEDANG dalam mode pairing (lampu berkedip),"
echo "lalu tekan Enter untuk melanjutkan..."
read -r _

sudo rfkill unblock bluetooth
bluetoothctl power on
bluetoothctl agent NoInputNoOutput
bluetoothctl default-agent
echo "Memindai perangkat selama 10 detik..."
bluetoothctl --timeout 10 scan on
bluetoothctl devices | grep -i "$MAC_SPEAKER" && echo "[INFO] Speaker terdeteksi." || echo "[PERINGATAN] Speaker belum terdeteksi, cek jarak/mode pairing."

echo "Mencoba pair..."
bluetoothctl pair "$MAC_SPEAKER"
bluetoothctl trust "$MAC_SPEAKER"
bluetoothctl connect "$MAC_SPEAKER"

echo "----------------------------------------------------"
bluetoothctl info "$MAC_SPEAKER" | grep -E "Connected|Paired|Trusted|Name"
echo "----------------------------------------------------"
echo "Kalau 'Connected: yes' di atas, speaker sudah siap dipakai."
echo "Kalau masih gagal, cek log: ${LOG_FILE}"
EOF

# Skrip sambung_bt.sh
cat <<'EOF' > ${DIR_BASE}/sambung_bt.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
GAGAL_FILE="${DIR_BASE}/.gagal_beruntun"

if bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
    echo 0 > "$GAGAL_FILE"
    exit 0
fi

bluetoothctl power on
sleep 1
# PERBAIKAN: trust dulu sebelum connect (jaga-jaga kalau trust flag
# tercabut, misalnya setelah unpair/pair ulang otomatis oleh speaker).
bluetoothctl trust "$MAC_SPEAKER" >/dev/null 2>&1
echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - Memulai jaring pengaman koneksi Bluetooth di ${NAMA_SEKOLAH}..." >> "$LOG_FILE"

for i in {1..3}; do
    HASIL=$(bluetoothctl connect "$MAC_SPEAKER" 2>&1)
    sleep 3
    if bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [SUCCESS] - Bluetooth tersambung pada percobaan ke-$i." >> "$LOG_FILE"
        echo 0 > "$GAGAL_FILE"
        exit 0
    else
        # PERBAIKAN: catat alasan gagal yang sebenarnya dari bluetoothctl,
        # supaya kalau tetap gagal, penyebabnya kelihatan di log (misalnya
        # "Device not available" = belum pernah di-pair, dsb).
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [DEBUG] - Percobaan ke-$i: ${HASIL}" >> "$LOG_FILE"
    fi
done

GAGAL_KE=$(( $(cat "$GAGAL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$GAGAL_KE" > "$GAGAL_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - Gagal koneksi (beruntun ke-$GAGAL_KE)." >> "$LOG_FILE"

# Kalau perangkat memang belum pernah dipasangkan, restart adapter tidak
# akan menolong -- beri tahu dengan jelas di log.
if ! bluetoothctl devices Paired | grep -qi "$MAC_SPEAKER"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Speaker $MAC_SPEAKER BELUM PERNAH DI-PAIR. Jalankan ${DIR_SKRIP}/pasang_bt.sh secara manual." >> "$LOG_FILE"
fi

if [ "$GAGAL_KE" -ge 3 ]; then
    # PERBAIKAN (V7): rfkill TIDAK dipakai lagi di sini. Dengan
    # AutoEnable=true (adapter otomatis nyala tiap boot) dan
    # anti-putus.service (menjaga koneksi tetap hidup terus-menerus),
    # seharusnya adapter memang tidak pernah dalam kondisi ter-blok
    # oleh rfkill saat runtime -- rfkill hanya dipakai sekali saat
    # instalasi awal / lewat pasang_bt.sh secara manual kalau memang
    # diperlukan. Recovery otomatis di sini cukup restart service
    # bluetooth & bluealsa saja, tanpa menyentuh rfkill.
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [RECOVERY] - Gagal beruntun ke-$GAGAL_KE, restart service bluetooth & bluealsa." >> "$LOG_FILE"
    sudo systemctl restart bluetooth bluealsa 2>>"$LOG_FILE"
    sleep 3
    bluetoothctl power on
    bluetoothctl connect "$MAC_SPEAKER"
    echo 0 > "$GAGAL_FILE"
fi
EOF

# Skrip anti_putus.sh
cat <<'EOF' > ${DIR_BASE}/anti_putus.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
HENING_PID=""
while true; do
    # PERBAIKAN: hanya jaga koneksi kalau memang sedang terhubung,
    # supaya tidak spam proses aplay yang gagal terus-menerus saat
    # speaker sedang putus (menunggu bel berikutnya reconnect).
    if bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
        if pgrep -x "mpv" > /dev/null; then
            if [ -n "$HENING_PID" ] && kill -0 "$HENING_PID" 2>/dev/null; then
                kill "$HENING_PID" 2>/dev/null
                HENING_PID=""
            fi
        else
            if [ -z "$HENING_PID" ] || ! kill -0 "$HENING_PID" 2>/dev/null; then
                aplay -q -D bluealsa -f cd -t raw /dev/zero > /dev/null 2>&1 &
                HENING_PID=$!
            fi
        fi
    else
        if [ -n "$HENING_PID" ] && kill -0 "$HENING_PID" 2>/dev/null; then
            kill "$HENING_PID" 2>/dev/null
            HENING_PID=""
        fi
    fi
    sleep 2
done
EOF

# Skrip putar_audio.sh
cat <<'EOF' > ${DIR_BASE}/putar_audio.sh
#!/bin/bash
exec 201>/tmp/putar_audio.lock
flock -n 201 || exit 0

DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
mkdir -p "$DIR_FLAG"

KUNCI="$1"; NAMA="$2"; shift 2
FILES=("$@")

if [ -f "${DIR_FLAG}/semua.off" ] || [ -f "${DIR_FLAG}/${KUNCI}.off" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [SKIP] - $NAMA dilewati (mode nonaktif sedang aktif)." >> "$LOG_FILE"
    exit 0
fi

for f in "${FILES[@]}"; do
    [ -f "$f" ] || echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - File hilang: $f" >> "$LOG_FILE"
done

"${DIR_SKRIP}/sambung_bt.sh"

# Cek betul-betul status koneksi sebelum main, dan catat CRITICAL yang
# jelas kalau tetap tidak konek (bukan diam-diam gagal). Output audio
# HANYA lewat Bluetooth (tidak ada fallback ke audio lokal PC).
if ! bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - $NAMA GAGAL DIPUTAR: Bluetooth speaker tidak terhubung. Cek ${DIR_SKRIP}/pasang_bt.sh" >> "$LOG_FILE"
fi

amixer -q sset Master 100% 2>/dev/null

DAFTAR=$(printf '%s, ' "${FILES[@]##*/}")
echo "$(date '+%Y-%m-%d %H:%M:%S') - [PLAY] - Memutar $NAMA: ${DAFTAR%, } (Volume 80%)" >> "$LOG_FILE"
mpv --no-video --audio-device=alsa/bluealsa --volume=80 --audio-fallback-to-ids=no --audio-delay=1.5 "${FILES[@]}" >> "$LOG_FILE" 2>&1
EOF

# Skrip cek_ujian.sh
cat <<'EOF' > ${DIR_BASE}/cek_ujian.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
JAM_SEKARANG=$(date +%H:%M)
HARI_INI=$(date +%u)   # 1=Senin ... 7=Minggu

[ -f "$CONF_UJIAN" ] || exit 0

# PERBAIKAN (V11): cocokkan pola hari cron-style ('*', '1-5', '1,3,5', dst)
# terhadap hari ini, supaya bel ujian tidak lagi bunyi setiap hari tanpa
# pandang bulu (termasuk Minggu/libur).
cocok_hari() {
    local pola="$1"
    [ "$pola" = "*" ] && return 0
    local bagian
    IFS=',' read -ra bagian <<< "$pola"
    for b in "${bagian[@]}"; do
        if [[ "$b" == *-* ]]; then
            local awal="${b%-*}" akhir="${b#*-}"
            if [[ "$awal" =~ ^[0-9]+$ ]] && [[ "$akhir" =~ ^[0-9]+$ ]] && \
               [ "$HARI_INI" -ge "$awal" ] && [ "$HARI_INI" -le "$akhir" ]; then
                return 0
            fi
        elif [[ "$b" =~ ^[0-9]+$ ]] && [ "$HARI_INI" -eq "$b" ]; then
            return 0
        fi
    done
    return 1
}

BARIS_JADWAL=$(grep -v '^#' "$CONF_UJIAN" | grep -v '^[[:space:]]*$' | awk -v jam="$JAM_SEKARANG" '$1==jam')

if [ -n "$BARIS_JADWAL" ]; then
    JUMLAH_KOLOM=$(echo "$BARIS_JADWAL" | awk '{print NF}')
    if [ "$JUMLAH_KOLOM" -ge 3 ]; then
        HARI_POLA=$(echo "$BARIS_JADWAL" | awk '{print $2}')
        NAMA_AUDIO=$(echo "$BARIS_JADWAL" | awk '{print $3}')
    else
        # Kompatibel dengan jadwal_ujian.conf format lama (tanpa kolom hari)
        HARI_POLA="*"
        NAMA_AUDIO=$(echo "$BARIS_JADWAL" | awk '{print $2}')
    fi

    if ! cocok_hari "$HARI_POLA"; then
        exit 0
    fi

    JALUR_AUDIO="${DIR_AUDIO}/${NAMA_AUDIO}"

    if [ -f "$JALUR_AUDIO" ]; then
        "${DIR_SKRIP}/putar_audio.sh" ujian "Bel Ujian (${JAM_SEKARANG})" "$JALUR_AUDIO"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Gagal Bunyi! File $NAMA_AUDIO tidak ada di folder audio." >> "$LOG_FILE"
    fi
fi
EOF

# Skrip cek_disk.sh
cat <<'EOF' > ${DIR_BASE}/cek_disk.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
PERSEN=$(df "${DIR_BASE}" | awk 'NR==2{print $5}' | tr -d '%')
if [ -n "$PERSEN" ] && [ "$PERSEN" -gt 85 ] 2>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - Disk Hampir Penuh ${PERSEN}%" >> "$LOG_FILE"
fi
EOF

# Skrip tahrim_daemon.sh
cat <<'EOF' > ${DIR_BASE}/tahrim_daemon.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"

ambil_jadwal() {
    local tanggal="$1"
    local api="https://api.aladhan.com/v1/timings/${tanggal}?latitude=${GARIS_LINTANG}&longitude=${GARIS_BUJUR}&method=2"
    local data
    data=$(curl -4 -s --connect-timeout 10 --max-time 20 --retry 3 --retry-delay 5 "$api")
    if echo "$data" | jq -e '.code==200' > /dev/null 2>&1; then
        echo "$data" > "$DB_LOKAL"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - Jadwal online sukses diambil untuk lokasi ${NAMA_SEKOLAH}." >> "$LOG_FILE"
        echo "$data"
    elif [ -f "$DB_LOKAL" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [RECOVERY] - Offline, menggunakan database lokal terakhir." >> "$LOG_FILE"
        cat "$DB_LOKAL"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Tidak ada data jadwal sholat sama sekali." >> "$LOG_FILE"
        echo ""
    fi
}

while true; do
    if ! timedatectl show -p NTPSynchronized --value | grep -q "yes"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - Jam sistem belum tersinkron NTP." >> "$LOG_FILE"
    fi

    TANGGAL_HARI_INI=$(date +%d-%m-%Y)
    JADWAL=$(ambil_jadwal "$TANGGAL_HARI_INI")

    if [ -n "$JADWAL" ]; then
        JAM_SUBUH=$(echo "$JADWAL" | jq -r '.data.timings.Fajr // empty')
        JAM_MAGHRIB=$(echo "$JADWAL" | jq -r '.data.timings.Maghrib // empty')

        if [ -n "$JAM_SUBUH" ] && [ -n "$JAM_MAGHRIB" ] && [[ "$JAM_SUBUH" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
            TAHRIM_SUBUH=$(date -d "${JAM_SUBUH} 20 minutes ago" +%s 2>/dev/null)
            TAHRIM_MAGHRIB=$(date -d "${JAM_MAGHRIB} 20 minutes ago" +%s 2>/dev/null)
            ANGKA_HARI=$(date +%u)
            NOMOR_LAGU=$(( (ANGKA_HARI - 1) % 3 + 1 ))
            FILE_MAGHRIB="${DIR_AUDIO}/tarhim-maghrib-${NOMOR_LAGU}.mp3"

            for pasangan in "${TAHRIM_SUBUH}|tarhim_subuh|${DIR_AUDIO}/tarhim-subuh.mp3|Tarhim Subuh" \
                            "${TAHRIM_MAGHRIB}|tarhim_maghrib|${FILE_MAGHRIB}|Tarhim Maghrib"; do
                target_epoch="${pasangan%%|*}"
                if [ -z "$target_epoch" ] || ! [[ "$target_epoch" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                sisa="${pasangan#*|}"
                kunci="${sisa%%|*}"
                sisa2="${sisa#*|}"
                file_audio="${sisa2%%|*}"
                nama="${sisa2##*|}"

                sekarang=$(date +%s)
                tunggu=$(( target_epoch - sekarang ))
                if [ "$tunggu" -gt 0 ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - [STANDBY] - $nama menunggu ${tunggu} detik." >> "$LOG_FILE"
                    sleep "$tunggu"
                    "${DIR_SKRIP}/putar_audio.sh" "$kunci" "$nama" "$file_audio"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - [SKIP] - $nama sudah lewat, dilewati." >> "$LOG_FILE"
                fi
            done
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Format jam sholat tidak valid." >> "$LOG_FILE"
        fi
    fi
    detik_ke_tengah_malam=$(( $(date -d "tomorrow 00:02" +%s) - $(date +%s) ))
    sleep "$detik_ke_tengah_malam"
done
EOF

# Skrip kelola_ujian.sh
cat <<'EOF' > ${DIR_BASE}/kelola_ujian.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
touch "$CONF_UJIAN"
AKSI="$1"; JAM="$2"; HARI="$3"; FILE_MP3="$4"

validasi_hari() {
    local pola="$1"
    [ "$pola" = "*" ] && return 0
    [[ "$pola" =~ ^[1-7](-[1-7])?(,[1-7](-[1-7])?)*$ ]]
}

case "$AKSI" in
    tambah)
        if [[ ! "$JAM" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then echo "Format jam salah (HH:MM)."; exit 1; fi
        if [ -z "$HARI" ] || [ -z "$FILE_MP3" ]; then
            echo "Harap masukkan hari dan nama file mp3. Contoh:"
            echo "  ./kelola_ujian.sh tambah 07:00 1-5 bel-mulai-ujian.mp3   (Senin-Jumat)"
            echo "  ./kelola_ujian.sh tambah 07:00 '*' bel-mulai-ujian.mp3  (setiap hari)"
            echo "  Kode hari: 1=Senin 2=Selasa 3=Rabu 4=Kamis 5=Jumat 6=Sabtu 7=Minggu"
            exit 1
        fi
        if ! validasi_hari "$HARI"; then
            echo "Format HARI tidak valid. Contoh benar: '*' , '1-5' , '1,3,5' , '6-7'"
            exit 1
        fi
        if grep -q "^${JAM} " "$CONF_UJIAN"; then
            sed -i "/^${JAM} /d" "$CONF_UJIAN"
        fi
        echo "$JAM $HARI $FILE_MP3" >> "$CONF_UJIAN"
        sort -o "$CONF_UJIAN" "$CONF_UJIAN"
        echo "Jadwal Ujian $JAM (hari: $HARI) dengan suara $FILE_MP3 berhasil disimpan." ;;
    hapus)
        if grep -q "^${JAM} " "$CONF_UJIAN"; then
            sed -i "/^${JAM} /d" "$CONF_UJIAN"
            echo "Jadwal ujian jam $JAM berhasil dihapus."
        else
            echo "Jadwal ujian jam $JAM tidak ditemukan."
        fi ;;
    kosongkan) > "$CONF_UJIAN"; echo "Semua antrean jadwal bel ujian telah dikosongkan." ;;
    daftar)
        echo "=== DAFTAR JADWAL BEL UJIAN AKTIF ==="
        printf "%-8s %-10s %s\n" "JAM" "HARI" "FILE"
        if [ -s "$CONF_UJIAN" ] && grep -qv '^#' "$CONF_UJIAN"; then
            grep -v '^#' "$CONF_UJIAN" | grep -v '^[[:space:]]*$' | while read -r j h f; do
                if [ -z "$f" ]; then f="$h"; h="*"; fi
                printf "%-8s %-10s %s\n" "$j" "$h" "$f"
            done
        else
            echo "(kosong)"
        fi ;;
    *)
        echo "Pakai: ./kelola_ujian.sh [tambah|hapus|daftar|kosongkan] [HH:MM] [HARI] [nama_file.mp3]"
        echo "  Kode hari: 1=Senin 2=Selasa 3=Rabu 4=Kamis 5=Jumat 6=Sabtu 7=Minggu, atau '*' = semua hari"
        echo "  Contoh: ./kelola_ujian.sh tambah 07:00 1-5 bel-mulai-ujian.mp3" ;;
esac
EOF

# Skrip cek_harian.sh (BARU V12) - jalan tiap menit via cron, membaca
# jadwal_harian.conf, mendukung banyak file per bel & filter hari sama
# seperti cek_ujian.sh.
cat <<'EOF' > ${DIR_BASE}/cek_harian.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
JAM_SEKARANG=$(date +%H:%M)
HARI_INI=$(date +%u)   # 1=Senin ... 7=Minggu

[ -f "$CONF_HARIAN" ] || exit 0

cocok_hari() {
    local pola="$1"
    [ "$pola" = "*" ] && return 0
    local bagian
    IFS=',' read -ra bagian <<< "$pola"
    for b in "${bagian[@]}"; do
        if [[ "$b" == *-* ]]; then
            local awal="${b%-*}" akhir="${b#*-}"
            if [[ "$awal" =~ ^[0-9]+$ ]] && [[ "$akhir" =~ ^[0-9]+$ ]] && \
               [ "$HARI_INI" -ge "$awal" ] && [ "$HARI_INI" -le "$akhir" ]; then
                return 0
            fi
        elif [[ "$b" =~ ^[0-9]+$ ]] && [ "$HARI_INI" -eq "$b" ]; then
            return 0
        fi
    done
    return 1
}

nama_dari_kunci() {
    echo "$1" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}'
}

BARIS_JADWAL=$(grep -v '^#' "$CONF_HARIAN" | grep -v '^[[:space:]]*$' | awk -v jam="$JAM_SEKARANG" '$1==jam')
[ -z "$BARIS_JADWAL" ] && exit 0

# Loop: bisa saja lebih dari satu KUNCI kebetulan dijadwalkan jam yang sama
while IFS= read -r baris; do
    [ -z "$baris" ] && continue
    HARI_POLA=$(echo "$baris" | awk '{print $2}')
    KUNCI=$(echo "$baris" | awk '{print $3}')
    DAFTAR_FILE=$(echo "$baris" | awk '{print $4}')

    cocok_hari "$HARI_POLA" || continue

    NAMA=$(nama_dari_kunci "$KUNCI")
    IFS=',' read -ra NAMA_FILE_ARR <<< "$DAFTAR_FILE"
    JALUR_ARR=()
    for f in "${NAMA_FILE_ARR[@]}"; do
        JALUR_ARR+=("${DIR_AUDIO}/${f}")
    done

    "${DIR_SKRIP}/putar_audio.sh" "$KUNCI" "$NAMA" "${JALUR_ARR[@]}"
done <<< "$BARIS_JADWAL"
EOF

# Skrip kelola_harian.sh (BARU V12) - kelola jadwal bel harian seperti
# kelola_ujian.sh, dengan tambahan: KUNCI permanen (lagu_pagi,
# indonesia_raya, bel_dzuhur) tidak bisa dihapus, dan jadwal baru tidak
# boleh bentrok jam dengan salah satu kunci permanen tersebut.
cat <<'EOF' > ${DIR_BASE}/kelola_harian.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
touch "$CONF_HARIAN"

# PERMANEN: kunci-kunci ini tidak bisa dihapus lewat hapus/kosongkan,
# dan jadwal LAIN tidak boleh bentrok jam dengan kunci-kunci ini.
KUNCI_PERMANEN=("lagu_pagi" "indonesia_raya" "bel_dzuhur")

is_permanen() {
    local k="$1"
    for p in "${KUNCI_PERMANEN[@]}"; do
        [ "$k" = "$p" ] && return 0
    done
    return 1
}

validasi_hari() {
    local pola="$1"
    [ "$pola" = "*" ] && return 0
    [[ "$pola" =~ ^[1-7](-[1-7])?(,[1-7](-[1-7])?)*$ ]]
}

validasi_kunci() {
    [[ "$1" =~ ^[a-z0-9_]+$ ]]
}

# Cek apakah JAM yang mau dipakai sudah dipakai kunci PERMANEN lain
# (selain kunci yang sedang diedit sendiri).
cek_bentrok_permanen() {
    local jam_baru="$1" kunci_baru="$2"
    [ -f "$CONF_HARIAN" ] || return 0
    while IFS= read -r baris; do
        [[ "$baris" =~ ^# ]] && continue
        [ -z "${baris// }" ] && continue
        local j k
        j=$(echo "$baris" | awk '{print $1}')
        k=$(echo "$baris" | awk '{print $3}')
        if [ "$j" = "$jam_baru" ] && [ "$k" != "$kunci_baru" ] && is_permanen "$k"; then
            echo "$k"
            return 1
        fi
    done < "$CONF_HARIAN"
    return 0
}

AKSI="$1"
case "$AKSI" in
    tambah)
        JAM="$2"; HARI="$3"; KUNCI="$4"; shift 4 2>/dev/null
        FILES=("$@")
        if [[ ! "$JAM" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then echo "Format jam salah (HH:MM)."; exit 1; fi
        if [ -z "$HARI" ] || [ -z "$KUNCI" ] || [ "${#FILES[@]}" -eq 0 ]; then
            echo "Pakai: ./kelola_harian.sh tambah <HH:MM> <HARI> <kunci> <file1.mp3> [file2.mp3 ...]"
            echo "Contoh: ./kelola_harian.sh tambah 06:30 1-6 lagu_pagi Hymne-guru.mp3 Tanah-airku.mp3"
            echo "Kode hari: 1=Senin 2=Selasa 3=Rabu 4=Kamis 5=Jumat 6=Sabtu 7=Minggu, atau '*' = semua hari"
            exit 1
        fi
        if ! validasi_hari "$HARI"; then
            echo "Format HARI tidak valid. Contoh benar: '*' , '1-5' , '1,3,5' , '6-7'"
            exit 1
        fi
        if ! validasi_kunci "$KUNCI"; then
            echo "KUNCI hanya boleh huruf kecil, angka, underscore. Contoh: lagu_pagi, bel_masuk_siang"
            exit 1
        fi
        BENTROK=$(cek_bentrok_permanen "$JAM" "$KUNCI")
        if [ $? -eq 1 ]; then
            echo "[GAGAL] Jam $JAM sudah dipakai jadwal PERMANEN '$BENTROK'. Pilih jam lain supaya tidak bentrok."
            exit 1
        fi
        DAFTAR_FILE=$(IFS=,; echo "${FILES[*]}")
        if grep -q " ${KUNCI} " "$CONF_HARIAN" 2>/dev/null; then
            sed -i "/ ${KUNCI} /d" "$CONF_HARIAN"
        fi
        echo "$JAM $HARI $KUNCI $DAFTAR_FILE" >> "$CONF_HARIAN"
        sort -o "$CONF_HARIAN" "$CONF_HARIAN"
        echo "Jadwal harian '$KUNCI' jam $JAM (hari: $HARI) berhasil disimpan: $DAFTAR_FILE" ;;
    hapus)
        KUNCI_HAPUS="$2"
        if [ -z "$KUNCI_HAPUS" ]; then echo "Pakai: ./kelola_harian.sh hapus <kunci>"; exit 1; fi
        if is_permanen "$KUNCI_HAPUS"; then
            echo "[GAGAL] Kunci '$KUNCI_HAPUS' bersifat PERMANEN dan tidak bisa dihapus."
            echo "        Kalau mau ubah jadwalnya, pakai 'tambah' dengan kunci yang sama."
            exit 1
        fi
        if grep -q " ${KUNCI_HAPUS} " "$CONF_HARIAN" 2>/dev/null; then
            sed -i "/ ${KUNCI_HAPUS} /d" "$CONF_HARIAN"
            echo "Jadwal harian '$KUNCI_HAPUS' berhasil dihapus."
        else
            echo "Jadwal harian '$KUNCI_HAPUS' tidak ditemukan."
        fi ;;
    kosongkan)
        if [ -f "$CONF_HARIAN" ]; then
            TEMP=$(mktemp)
            while IFS= read -r baris; do
                if [[ "$baris" =~ ^# ]] || [ -z "${baris// }" ]; then
                    echo "$baris" >> "$TEMP"
                    continue
                fi
                k=$(echo "$baris" | awk '{print $3}')
                if is_permanen "$k"; then
                    echo "$baris" >> "$TEMP"
                fi
            done < "$CONF_HARIAN"
            mv "$TEMP" "$CONF_HARIAN"
        fi
        echo "Jadwal harian custom telah dikosongkan."
        echo "Jadwal PERMANEN (${KUNCI_PERMANEN[*]}) tetap dipertahankan." ;;
    daftar)
        echo "=== DAFTAR JADWAL BEL HARIAN AKTIF ==="
        printf "%-8s %-10s %-15s %s\n" "JAM" "HARI" "KUNCI" "FILE"
        if [ -s "$CONF_HARIAN" ] && grep -qv '^#' "$CONF_HARIAN"; then
            grep -v '^#' "$CONF_HARIAN" | grep -v '^[[:space:]]*$' | while read -r j h k f; do
                tanda=""
                is_permanen "$k" && tanda=" (permanen)"
                printf "%-8s %-10s %-15s %s%s\n" "$j" "$h" "$k" "$f" "$tanda"
            done
        else
            echo "(kosong)"
        fi ;;
    *)
        echo "Pakai: ./kelola_harian.sh [tambah|hapus|daftar|kosongkan] ..."
        echo "  tambah <HH:MM> <HARI> <kunci> <file1.mp3> [file2.mp3 ...]"
        echo "  hapus <kunci>"
        echo "  Kode hari: 1=Senin 2=Selasa 3=Rabu 4=Kamis 5=Jumat 6=Sabtu 7=Minggu, atau '*' = semua hari"
        echo "  Kunci permanen (tidak bisa dihapus): ${KUNCI_PERMANEN[*]}"
        ;;
esac
EOF

# Skrip mode_sekolah.sh
cat <<'EOF' > ${DIR_BASE}/mode_sekolah.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
mkdir -p "$DIR_FLAG"
AKSI="$1"

# PERBAIKAN (V13): daftar kunci bel harian dibaca dinamis dari
# jadwal_harian.conf, supaya preset hari_biasa/masa_ujian/liburan
# otomatis ikut mengatur bel BARU yang ditambahkan lewat
# kelola_harian.sh -- tidak perlu edit skrip ini lagi tiap nambah bel.
daftar_kunci_harian() {
    [ -f "$CONF_HARIAN" ] && grep -v '^#' "$CONF_HARIAN" | grep -v '^[[:space:]]*$' | awk '{print $3}' | awk '!seen[$0]++'
}

status_sistem() {
    echo "===================================================="
    echo " STATUS MODE AUDIO OPERASIONAL SEKOLAH"
    echo "===================================================="
    local daftar_kunci
    daftar_kunci=$( { daftar_kunci_harian; printf "ujian\ntarhim_subuh\ntarhim_maghrib\n"; } | awk '!seen[$0]++')
    for fitur in $daftar_kunci; do
        [ -z "$fitur" ] && continue
        if [ -f "${DIR_FLAG}/${fitur}.off" ]; then
            printf "  %-15s : [ OFF ] NONAKTIF\n" "$fitur"
        else
            printf "  %-15s : [ ON  ] AKTIF NORMAL\n" "$fitur"
        fi
    done
    echo "===================================================="
}

case "$AKSI" in
    hari_biasa)
        # Semua bel harian (termasuk bel custom yang ditambahkan nanti) ON
        for k in $(daftar_kunci_harian); do
            rm -f "${DIR_FLAG}/${k}.off"
        done
        touch ${DIR_FLAG}/ujian.off
        echo "[SUKSES] Mode Hari Pembelajaran Biasa diaktifkan (semua bel harian ON, Jadwal Ujian dinonaktifkan)."
        status_sistem ;;
    masa_ujian)
        rm -f ${DIR_FLAG}/ujian.off
        # PERBAIKAN (V13): SEMUA bel harian dimatikan otomatis KECUALI
        # lagu_pagi (supaya tidak bentrok dengan jadwal ujian), termasuk
        # bel custom yang ditambahkan lewat kelola_harian.sh nanti.
        for k in $(daftar_kunci_harian); do
            if [ "$k" = "lagu_pagi" ]; then
                rm -f "${DIR_FLAG}/${k}.off"
            else
                touch "${DIR_FLAG}/${k}.off"
            fi
        done
        echo "[SUKSES] Mode Masa Ujian Aktif (semua bel harian dimatikan KECUALI lagu_pagi, supaya tidak bentrok dengan jadwal ujian)."
        status_sistem ;;
    liburan)
        # Semua bel harian (termasuk lagu_pagi & bel custom) OFF saat libur
        for k in $(daftar_kunci_harian); do
            touch "${DIR_FLAG}/${k}.off"
        done
        touch ${DIR_FLAG}/ujian.off
        rm -f ${DIR_FLAG}/tarhim_subuh.off ${DIR_FLAG}/tarhim_maghrib.off
        echo "[SUKSES] Mode Liburan Panjang Aktif (Semua Bel sekolah libur, HANYA TARHIM YANG AKTIF)."
        status_sistem ;;
    normal_semua)
        rm -f ${DIR_FLAG}/*.off
        echo "[SUKSES] Semua fitur audio diaktifkan tanpa pengecualian."
        status_sistem ;;
    status)
        status_sistem ;;
    *)
        echo "Format Salah! Gunakan perintah berikut:"
        echo "  ./mode_sekolah.sh hari_biasa   -> (Semua bel harian ON, Ujian OFF)"
        echo "  ./mode_sekolah.sh masa_ujian   -> (Ujian ON, semua bel harian OFF kecuali lagu_pagi)"
        echo "  ./mode_sekolah.sh liburan      -> (Semua Bel OFF, Hanya Tarhim ON)"
        echo "  ./mode_sekolah.sh status       -> (Melihat kondisi aktif/nonaktif saat ini)"
        ;;
esac
EOF

# Skrip cek_kesehatan.sh
cat <<'EOF' > ${DIR_BASE}/cek_kesehatan.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
echo "=== STATUS SERVER: ${NAMA_SEKOLAH} ==="
systemctl is-active anti-putus.service tahrim-daemon.service
echo -e "\n=== 10 LOG CRITICAL/WARNING TERAKHIR ==="
grep -E "CRITICAL|WARNING" "$LOG_FILE" 2>/dev/null | tail -10 || echo "(tidak ada / log belum ada)"
echo -e "\n=== KONEKSI BLUETOOTH ==="
bluetoothctl info "$MAC_SPEAKER" | grep -E "Connected|Paired|Trusted|Name"
echo -e "\n=== SINKRONISASI WAKTU ==="
timedatectl show -p NTPSynchronized --value
echo -e "\n=== SISA RUANG DISK ==="
df -h "${DIR_BASE}" | tail -1
echo -e "\n=== STATUS AKTIVASI FITUR AUDIO ==="
"${DIR_SKRIP}/mode_sekolah.sh" status
EOF

# Skrip alert_gagal.sh (BARU V6) - dipanggil systemd lewat OnFailure=
# saat anti-putus.service atau tahrim-daemon.service benar-benar gagal
# (bukan sekadar reconnect biasa, tapi service-nya sendiri berhenti).
cat <<'EOF' > ${DIR_BASE}/alert_gagal.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
NAMA_SERVICE="${1:-tidak_diketahui}"
echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Service ${NAMA_SERVICE} BERHENTI/GAGAL tak terduga (systemd OnFailure). Cek: systemctl status ${NAMA_SERVICE}" >> "$LOG_FILE"
EOF

# Skrip cek_service.sh (BARU V6) - watchdog cron sebagai jaring pengaman
# KEDUA di luar systemd, jaga-jaga kalau OnFailure tidak sempat terpicu
# (misal proses mati tanpa systemd sadar service gagal).
cat <<'EOF' > ${DIR_BASE}/cek_service.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
for SVC in anti-putus.service tahrim-daemon.service; do
    if ! systemctl is-active --quiet "$SVC"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Watchdog: $SVC TIDAK AKTIF. Mencoba restart..." >> "$LOG_FILE"
        sudo systemctl restart "$SVC" 2>>"$LOG_FILE"
        sleep 3
        if systemctl is-active --quiet "$SVC"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [RECOVERY] - Watchdog: $SVC berhasil di-restart." >> "$LOG_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - Watchdog: $SVC GAGAL di-restart, perlu pengecekan manual." >> "$LOG_FILE"
        fi
    fi
done
EOF

# Skrip backup.sh
cat <<'EOF' > ${DIR_BASE}/backup.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
mkdir -p "${DIR_BASE}/backup"
TANGGAL=$(date +%Y%m%d)
tar -czf ${DIR_BASE}/backup/config_${TANGGAL}.tar.gz ${DIR_BASE}/*.sh ${DIR_BASE}/*.conf 2>/dev/null
find ${DIR_BASE}/backup -name "*.tar.gz" -mtime +14 -delete
EOF

# Berikan hak akses eksekusi ke semua berkas skrip baru
chmod +x ${DIR_BASE}/*.sh
chown -R ${USER_SISTEM}:${USER_SISTEM} ${DIR_BASE}/

# --------------------------------------------------------------------
# 5. REGISTER DAN AKTIFKAN SYSTEMD SERVICE (24 JAM NONSTOP)
# --------------------------------------------------------------------
echo "[8/9] Daftarkan skrip ke Systemd Service..."

# PERBAIKAN: tambah After=/Wants= ke bluealsa.service supaya tidak
# race condition saat baru boot (daemon coba pakai bluealsa sebelum siap).
# PERBAIKAN (V6): tambah OnFailure= + StartLimit supaya kalau service
# benar-benar gagal berulang kali (bukan sekadar Restart=always biasa),
# systemd akan memicu otomasi-audio-alert@.service yang mencatatnya
# sebagai CRITICAL ke log -- bukan cuma diam-diam mencoba restart terus.
cat <<EOF > /etc/systemd/system/anti-putus.service
[Unit]
Description=Penjaga Koneksi Bluetooth Mixer Audio Sekolah
After=bluetooth.target bluealsa.service network.target
Wants=bluealsa.service
OnFailure=otomasi-audio-alert@%n.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=${DIR_BASE}/anti_putus.sh
Restart=always
RestartSec=5
User=${USER_SISTEM}

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/tahrim-daemon.service
[Unit]
Description=Daemon Jadwal Tarhim Otomatis
After=network-online.target bluetooth.target bluealsa.service
Wants=network-online.target bluealsa.service
OnFailure=otomasi-audio-alert@%n.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=${DIR_BASE}/tahrim_daemon.sh
Restart=always
RestartSec=10
User=${USER_SISTEM}

[Install]
WantedBy=multi-user.target
EOF

# Template service alert (BARU V6) - dipanggil otomatis lewat OnFailure=
# di atas kalau salah satu service benar-benar gagal berulang kali.
cat <<EOF > /etc/systemd/system/otomasi-audio-alert@.service
[Unit]
Description=Notifikasi kegagalan service otomasi audio (%i)

[Service]
Type=oneshot
ExecStart=${DIR_BASE}/alert_gagal.sh %i
User=${USER_SISTEM}
EOF

jalankan "Reload daemon systemd (service utama)" systemctl daemon-reload
jalankan "Aktifkan anti-putus.service" systemctl enable --now anti-putus.service
jalankan "Aktifkan tahrim-daemon.service" systemctl enable --now tahrim-daemon.service

# --------------------------------------------------------------------
# 6. INSTALASI MANAJEMEN LOG (LOGROTATE GLOBAL)
# --------------------------------------------------------------------
echo "[8b/9] Mengonfigurasi Logrotate global..."
touch "${LOG_FILE}"
chown ${USER_SISTEM}:audio "${LOG_FILE}"
chmod 664 "${LOG_FILE}"

cat <<EOF > /etc/logrotate.d/otomasi-audio
${LOG_FILE} {
    daily
    rotate 7
    copytruncate
    missingok
    notifempty
    compress
    delaycompress
    create 0664 ${USER_SISTEM} audio
}
EOF
chown root:root /etc/logrotate.d/otomasi-audio
chmod 644 /etc/logrotate.d/otomasi-audio

# --------------------------------------------------------------------
# 7. MENYUSUN JADWAL HARIAN TETAP (CRONTAB)
# --------------------------------------------------------------------
echo "[8c/9] Mendaftarkan jadwal harian tetap di Crontab..."
crontab -l -u ${USER_SISTEM} 2>/dev/null | grep -v "putar_audio.sh\|cek_ujian.sh\|cek_harian.sh\|cek_disk.sh\|cek_service.sh\|backup.sh\|df /home" > /tmp/cron_bak

cat <<EOF >> /tmp/cron_bak
# --- JADWAL TETAP HARIAN GENERATED BY AUTOMATION ---
* * * * * ${DIR_BASE}/cek_harian.sh
* * * * * ${DIR_BASE}/cek_ujian.sh
0 7 * * * ${DIR_BASE}/cek_disk.sh
*/5 * * * * ${DIR_BASE}/cek_service.sh
55 23 * * * ${DIR_BASE}/backup.sh
EOF

jalankan "Memasang jadwal crontab" crontab -u ${USER_SISTEM} /tmp/cron_bak
rm -f /tmp/cron_bak

# --------------------------------------------------------------------
# 8. VERIFIKASI AKHIR & RINGKASAN INSTALASI
# --------------------------------------------------------------------
echo "[9/9] Verifikasi akhir & ringkasan instalasi..."

DAFTAR_AUDIO_WAJIB=(
    "bel-masuk-ruangan.mp3" "bel-mulai-ujian.mp3" "istirahat.mp3"
    "bel-sisa-5menit.mp3" "istirahat-selesai.mp3" "bel-ujian-selesai.mp3"
    "Hymne-guru.mp3" "Tanah-airku.mp3" "Rukun-Sama-teman.mp3" "Mars.mp3"
    "Pengantar-dan-indonesia-raya.mp3" "Bel-Persiapan-Sholat-dzuhur.mp3"
    "tarhim-subuh.mp3" "tarhim-maghrib-1.mp3" "tarhim-maghrib-2.mp3" "tarhim-maghrib-3.mp3"
)
AUDIO_HILANG=()
for f in "${DAFTAR_AUDIO_WAJIB[@]}"; do
    [ -f "${DIR_AUDIO}/${f}" ] || AUDIO_HILANG+=("$f")
done

# PERBAIKAN (BARU): cek status pairing & koneksi secara eksplisit di
# ringkasan akhir, supaya masalah bluetooth langsung kelihatan di sini
# dan tidak perlu menunggu bel pertama berbunyi untuk tahu ada masalah.
STATUS_PAIRED="TIDAK"
STATUS_CONNECTED="TIDAK"
bluetoothctl devices Paired | grep -qi "$MAC_SPEAKER" && STATUS_PAIRED="YA"
bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes" && STATUS_CONNECTED="YA"

echo "===================================================="
echo " INSTALASI SELESAI - ${NAMA_SEKOLAH}"
echo "===================================================="
echo " Service aktif   : anti-putus.service, tahrim-daemon.service"
echo " Folder utama    : ${DIR_BASE}"
echo " Folder audio    : ${DIR_AUDIO}"
echo " Log sistem      : ${LOG_FILE}"
echo "----------------------------------------------------"
echo " STATUS BLUETOOTH SPEAKER (${MAC_SPEAKER})"
echo "   Sudah Paired  : ${STATUS_PAIRED}"
echo "   Sudah Connect : ${STATUS_CONNECTED}"
if [ "$STATUS_PAIRED" = "TIDAK" ] || [ "$STATUS_CONNECTED" = "TIDAK" ]; then
    echo "   [PERHATIAN] Bluetooth BELUM siap. Jalankan perintah berikut:"
    echo "     sudo ${DIR_BASE}/pasang_bt.sh"
    echo "   (Pastikan speaker dalam mode pairing saat menjalankannya.)"
fi
echo "----------------------------------------------------"
if [ "${#AUDIO_HILANG[@]}" -eq 0 ]; then
    echo " Semua file audio bawaan sudah lengkap. Mantap!"
else
    echo " [PERHATIAN] File audio berikut BELUM ada di ${DIR_AUDIO}/ :"
    for f in "${AUDIO_HILANG[@]}"; do
        echo "   - $f"
    done
    echo " Bel terkait tidak akan berbunyi sampai file-file ini ditambahkan."
fi
echo "----------------------------------------------------"
echo " Langkah selanjutnya:"
echo "  1. Salin file-file .mp3 ke folder ${DIR_AUDIO}/"
echo "  2. Kalau Bluetooth belum siap: sudo ${DIR_BASE}/pasang_bt.sh"
echo "  3. Cek status sistem  : ${DIR_BASE}/cek_kesehatan.sh"
echo "  4. Atur jadwal ujian  : ${DIR_BASE}/kelola_ujian.sh"
echo "  5. Atur mode sekolah  : ${DIR_BASE}/mode_sekolah.sh"
echo "----------------------------------------------------"
echo " Catatan V7:"
echo "  - Output audio HANYA lewat Bluetooth speaker (tidak ada"
echo "    fallback ke audio lokal). anti-putus.service menjaga koneksi"
echo "    tetap hidup nonstop supaya bel tidak pernah bisu."
echo "  - Watchdog cek_service.sh berjalan tiap 5 menit lewat cron"
echo "    untuk memastikan kedua service utama tetap hidup."
echo "===================================================="
