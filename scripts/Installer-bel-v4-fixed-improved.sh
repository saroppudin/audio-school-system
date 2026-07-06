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
# TAMBAHAN VERSION 9 (perbaikan "br-connection-profile-unavailable"):
#  15. Root cause error 'org.bluez.Error.Failed:
#      br-connection-profile-unavailable' adalah BlueZ mencoba
#      menyambungkan profil A2DP Sink padahal daemon bluealsa (yang
#      mendaftarkan profil itu ke BlueZ lewat D-Bus) belum aktif /
#      belum selesai registrasi saat 'bluetoothctl connect' dipanggil.
#      -> Sekarang SETIAP tempat yang memanggil 'bluetoothctl connect'
#      (installer, pasang_bt.sh, sambung_bt.sh) memverifikasi dulu
#      bahwa service bluealsa benar-benar 'active', me-restart-nya
#      kalau belum, lalu mencoba connect dengan retry loop. Kalau
#      error yang sama tetap muncul di tengah retry, bluealsa
#      di-restart ulang sebelum percobaan berikutnya (bukan menunggu
#      3 kegagalan beruntun seperti sebelumnya).
# ====================================================================

set -o pipefail

# --------------------------------------------------------------------
# 1. KONFIGURASI SEKOLAH (SESUAIKAN DI SINI SEBELUM MENJALANKAN)
# --------------------------------------------------------------------
USER_SISTEM="lenovo"                   # Nama user non-root di Debian
NAMA_SEKOLAH="SMK Negeri Purworejo"     # Nama Sekolah Anda
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
echo " Memulai Instalasi Otomatisasi Audio V9 untuk:"
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

# Konfigurasi BlueALSA ke mode A2DP sink saja
echo "[3/9] Mengonfigurasi BlueALSA..."
mkdir -p /etc/systemd/system/bluealsa.service.d
cat <<EOF > /etc/systemd/system/bluealsa.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa -p a2dp-sink
EOF
jalankan "Reload daemon systemd" systemctl daemon-reload
jalankan "Restart service bluetooth" systemctl restart bluetooth
sleep 2
jalankan "Unblock rfkill bluetooth" rfkill unblock bluetooth
jalankan "Power on adapter bluetooth" bluetoothctl power on
sleep 1
jalankan "Restart service bluealsa" systemctl restart bluealsa
sleep 2

# PERBAIKAN (BARU V9): verifikasi bluealsa BENAR-BENAR aktif (bukan
# cuma percaya exit code 'systemctl restart' saja). Ini persis daemon
# yang mendaftarkan profil A2DP Sink ke BlueZ lewat D-Bus -- kalau dia
# belum 'active' saat 'bluetoothctl connect' dipanggil, BlueZ akan
# menolak dengan error "br-connection-profile-unavailable".
echo "  Memverifikasi service bluealsa benar-benar aktif..."
for _percobaan in 1 2 3; do
    if systemctl is-active --quiet bluealsa; then
        echo "  [OK] bluealsa aktif."
        break
    fi
    echo "  [PERINGATAN] bluealsa belum aktif, mencoba restart (percobaan ${_percobaan}/3)..."
    systemctl restart bluealsa
    sleep 3
done
if ! systemctl is-active --quiet bluealsa; then
    echo "  [ERROR] bluealsa TETAP gagal aktif. Cek manual: journalctl -u bluealsa -n 50 --no-pager"
    echo "          Selama bluealsa tidak aktif, koneksi Bluetooth speaker akan"
    echo "          SELALU gagal dengan error 'br-connection-profile-unavailable'."
fi

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

# PERBAIKAN (BARU V9): connect dengan retry loop. Kalau BlueZ membalas
# dengan "br-connection-profile-unavailable" di tengah percobaan
# (artinya bluealsa sempat belum siap / profil belum ter-registrasi),
# restart bluealsa dulu sebelum mencoba lagi, alih-alih menyerah di
# percobaan pertama.
echo "  Mencoba connect ke speaker (dengan retry otomatis)..."
KONEK_OK=0
for _percobaan_connect in 1 2 3 4 5; do
    HASIL_CONNECT=$(bluetoothctl connect "$MAC_SPEAKER" 2>&1)
    echo "$HASIL_CONNECT" | tee -a "$LOG_FILE"
    if echo "$HASIL_CONNECT" | grep -qi "Connection successful"; then
        KONEK_OK=1
        break
    fi
    if echo "$HASIL_CONNECT" | grep -qi "br-connection-profile-unavailable"; then
        echo "  [INFO] Profil A2DP belum siap di BlueZ, restart bluealsa lalu coba lagi (percobaan ${_percobaan_connect}/5)..."
        systemctl restart bluealsa
        sleep 4
    else
        sleep 2
    fi
done
if [ "$KONEK_OK" -eq 1 ]; then
    echo "  [OK] Speaker berhasil terhubung."
else
    echo "  [PERINGATAN] Speaker belum berhasil terhubung otomatis."
    echo "  Setelah instalasi selesai, jalankan manual: ${DIR_BASE}/pasang_bt.sh"
fi

# PERBAIKAN: sudoers ditulis ke file terpisah di /etc/sudoers.d/ dan
# divalidasi dengan visudo -c, jauh lebih aman daripada menambahkan
# baris langsung ke /etc/sudoers utama.
SUDOERS_FILE="/etc/sudoers.d/otomasi-audio-rfkill"
if [ ! -f "$SUDOERS_FILE" ]; then
    cat <<EOF > "$SUDOERS_FILE"
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart anti-putus.service
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart tahrim-daemon.service
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluealsa
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth bluealsa
EOF
    chmod 440 "$SUDOERS_FILE"
    if ! visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        echo "[ERROR] Sintaks sudoers tidak valid, file dihapus demi keamanan."
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
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
EOF

# MEMBUAT DEFAULT JADWAL BEL UJIAN (Berdasarkan Istirahat Baru V2)
if [ ! -f "${DIR_BASE}/jadwal_ujian.conf" ]; then
cat <<EOF > ${DIR_BASE}/jadwal_ujian.conf
# ====================================================================
# JADWAL BEL UJIAN & ISTIRAHAT (FORMAT: JAM[SPASI]NAMA_FILE.mp3)
# Sesuai Lampiran Jadwal Harian Sekolah / Masa Ujian Semester/Kelas 3
# ====================================================================

# --- SHIFT PAGI ---
06:50 bel-masuk-ruangan.mp3
07:00 bel-mulai-ujian.mp3

# --- ISTIRAHAT PERTAMA (09.00 - 09.15) ---
09:00 istirahat.mp3
09:12 bel-sisa-5menit.mp3
09:15 istirahat-selesai.mp3

# --- PERSIAPAN SHIFT SIANG ---
10:10 bel-masuk-ruangan.mp3
10:30 bel-mulai-ujian.mp3

# --- ISTIRAHAT KEDUA (12.15 - 12.45) ---
12:15 istirahat.mp3
12:42 bel-sisa-5menit.mp3
12:45 istirahat-selesai.mp3

# --- AKHIR SELURUH UJIAN HARI INI ---
13:45 bel-ujian-selesai.mp3
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

# PERBAIKAN (BARU V9): pastikan bluealsa (pendaftar profil A2DP Sink
# ke BlueZ) benar-benar aktif SEBELUM mencoba connect. Kalau tidak,
# BlueZ akan menolak dengan "br-connection-profile-unavailable" walau
# pairing/trust sukses.
echo "Memastikan layanan bluealsa aktif..."
for i in 1 2 3; do
    if systemctl is-active --quiet bluealsa; then
        echo "  [OK] bluealsa aktif."
        break
    fi
    echo "  bluealsa belum aktif, restart (percobaan $i/3)..."
    sudo systemctl restart bluealsa
    sleep 3
done
if ! systemctl is-active --quiet bluealsa; then
    echo "  [ERROR] bluealsa tetap gagal aktif. Cek: journalctl -u bluealsa -n 50 --no-pager"
fi

echo "Mencoba pair..."
bluetoothctl pair "$MAC_SPEAKER"
bluetoothctl trust "$MAC_SPEAKER"

# PERBAIKAN (BARU V9): connect dengan retry, dan kalau errornya
# spesifik "br-connection-profile-unavailable", restart bluealsa dulu
# di tengah percobaan (bukan cuma sekali coba lalu menyerah).
KONEK_OK=0
for i in 1 2 3 4 5; do
    HASIL=$(bluetoothctl connect "$MAC_SPEAKER" 2>&1)
    echo "$HASIL"
    if echo "$HASIL" | grep -qi "Connection successful"; then
        KONEK_OK=1
        break
    fi
    if echo "$HASIL" | grep -qi "br-connection-profile-unavailable"; then
        echo "  [INFO] Profil A2DP belum siap di BlueZ, restart bluealsa lalu coba lagi (percobaan $i/5)..."
        sudo systemctl restart bluealsa
        sleep 4
    else
        sleep 2
    fi
done

echo "----------------------------------------------------"
bluetoothctl info "$MAC_SPEAKER" | grep -E "Connected|Paired|Trusted|Name"
echo "----------------------------------------------------"
if [ "$KONEK_OK" -eq 1 ]; then
    echo "Speaker sudah siap dipakai."
else
    echo "Kalau masih gagal, cek log: ${LOG_FILE}"
    echo "dan cek layanan bluealsa: journalctl -u bluealsa -n 50 --no-pager"
fi
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

# PERBAIKAN (BARU V9): pastikan bluealsa aktif SEBELUM mencoba connect
# sama sekali. Ini penyebab paling umum dari error
# "br-connection-profile-unavailable" -- BlueZ tidak menemukan profil
# A2DP Sink karena bluealsa belum/tidak aktif saat connect dipanggil.
if ! systemctl is-active --quiet bluealsa; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - bluealsa tidak aktif, restart sebelum connect." >> "$LOG_FILE"
    sudo systemctl restart bluealsa
    sleep 4
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
        # PERBAIKAN (BARU V9): kalau errornya spesifik profil A2DP belum
        # tersedia, restart bluealsa SEGERA di tengah retry loop ini,
        # jangan tunggu sampai 3 kegagalan beruntun lintas-eksekusi cron.
        if echo "$HASIL" | grep -qi "br-connection-profile-unavailable"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [RECOVERY] - Profil A2DP belum siap, restart bluealsa segera (percobaan ke-$i)." >> "$LOG_FILE"
            sudo systemctl restart bluealsa
            sleep 4
        fi
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

[ -f "$CONF_UJIAN" ] || exit 0

BARIS_JADWAL=$(grep -v '^#' "$CONF_UJIAN" | grep "^${JAM_SEKARANG}")

if [ -n "$BARIS_JADWAL" ]; then
    NAMA_AUDIO=$(echo "$BARIS_JADWAL" | awk '{print $2}')
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
AKSI="$1"; JAM="$2"; FILE_MP3="$3"
case "$AKSI" in
    tambah)
        if [[ ! "$JAM" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then echo "Format jam salah (HH:MM)."; exit 1; fi
        if [ -z "$FILE_MP3" ]; then echo "Harap masukkan nama file mp3 target. Contoh: ./kelola_ujian.sh tambah 07:00 bel-mulai-ujian.mp3"; exit 1; fi
        if grep -q "^${JAM} " "$CONF_UJIAN"; then
            sed -i "/^${JAM} /d" "$CONF_UJIAN"
        fi
        echo "$JAM $FILE_MP3" >> "$CONF_UJIAN"
        sort -o "$CONF_UJIAN" "$CONF_UJIAN"
        echo "Jadwal Ujian $JAM dengan suara $FILE_MP3 berhasil disimpan." ;;
    hapus)
        if grep -q "^${JAM} " "$CONF_UJIAN"; then
            sed -i "/^${JAM} /d" "$CONF_UJIAN"
            echo "Jadwal ujian jam $JAM berhasil dihapus."
        else
            echo "Jadwal ujian jam $JAM tidak ditemukan."
        fi ;;
    kosongkan) > "$CONF_UJIAN"; echo "Semua antrean jadwal bel ujian telah dikosongkan." ;;
    daftar) echo "=== DAFTAR JADWAL BEL UJIAN AKTIF ==="; [ -s "$CONF_UJIAN" ] && cat "$CONF_UJIAN" || echo "(kosong)" ;;
    *) echo "Pakai: ./kelola_ujian.sh [tambah|hapus|daftar|kosongkan] [HH:MM] [nama_file.mp3]" ;;
esac
EOF

# Skrip mode_sekolah.sh
cat <<'EOF' > ${DIR_BASE}/mode_sekolah.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
mkdir -p "$DIR_FLAG"
AKSI="$1"

status_sistem() {
    echo "===================================================="
    echo " STATUS MODE AUDIO OPERASIONAL SEKOLAH"
    echo "===================================================="
    for fitur in lagu_pagi indonesia_raya bel_dzuhur ujian tarhim_subuh tarhim_maghrib; do
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
        rm -f ${DIR_FLAG}/lagu_pagi.off ${DIR_FLAG}/indonesia_raya.off ${DIR_FLAG}/bel_dzuhur.off
        touch ${DIR_FLAG}/ujian.off
        echo "[SUKSES] Mode Hari Pembelajaran Biasa diaktifkan (Jadwal Ujian dinonaktifkan)."
        status_sistem ;;
    masa_ujian)
        rm -f ${DIR_FLAG}/ujian.off
        touch ${DIR_FLAG}/indonesia_raya.off ${DIR_FLAG}/bel_dzuhur.off
        echo "[SUKSES] Mode Masa Ujian Aktif (Lagu Indonesia Raya & Bel Dzuhur dinonaktifkan)."
        status_sistem ;;
    liburan)
        touch ${DIR_FLAG}/lagu_pagi.off ${DIR_FLAG}/indonesia_raya.off ${DIR_FLAG}/bel_dzuhur.off ${DIR_FLAG}/ujian.off
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
        echo "  ./mode_sekolah.sh hari_biasa   -> (Bel harian ON, Ujian OFF)"
        echo "  ./mode_sekolah.sh masa_ujian   -> (Ujian ON, Indonesia Raya & Dzuhur OFF)"
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
echo -e "\n=== STATUS BLUEALSA (profil A2DP Sink) ==="
systemctl is-active bluealsa
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
for SVC in anti-putus.service tahrim-daemon.service bluealsa; do
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
crontab -l -u ${USER_SISTEM} 2>/dev/null | grep -v "putar_audio.sh\|cek_ujian.sh\|cek_disk.sh\|cek_service.sh\|backup.sh\|df /home" > /tmp/cron_bak

cat <<EOF >> /tmp/cron_bak
# --- JADWAL TETAP HARIAN GENERATED BY AUTOMATION ---
30 6 * * 1-6 ${DIR_BASE}/putar_audio.sh lagu_pagi "Lagu Pagi" ${DIR_AUDIO}/Hymne-guru.mp3 ${DIR_AUDIO}/Tanah-airku.mp3 ${DIR_AUDIO}/Rukun-Sama-teman.mp3 ${DIR_AUDIO}/Mars.mp3
59 9 * * 1-4,6 ${DIR_BASE}/putar_audio.sh indonesia_raya "Indonesia Raya" ${DIR_AUDIO}/Pengantar-dan-indonesia-raya.mp3
55 11 * * 1-4,6 ${DIR_BASE}/putar_audio.sh bel_dzuhur "Bel Dzuhur" ${DIR_AUDIO}/Bel-Persiapan-Sholat-dzuhur.mp3
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
STATUS_BLUEALSA="TIDAK AKTIF"
systemctl is-active --quiet bluealsa && STATUS_BLUEALSA="AKTIF"

echo "===================================================="
echo " INSTALASI SELESAI - ${NAMA_SEKOLAH}"
echo "===================================================="
echo " Service aktif   : anti-putus.service, tahrim-daemon.service"
echo " Folder utama    : ${DIR_BASE}"
echo " Folder audio    : ${DIR_AUDIO}"
echo " Log sistem      : ${LOG_FILE}"
echo "----------------------------------------------------"
echo " STATUS BLUETOOTH SPEAKER (${MAC_SPEAKER})"
echo "   Layanan bluealsa (profil A2DP Sink) : ${STATUS_BLUEALSA}"
echo "   Sudah Paired  : ${STATUS_PAIRED}"
echo "   Sudah Connect : ${STATUS_CONNECTED}"
if [ "$STATUS_BLUEALSA" = "TIDAK AKTIF" ]; then
    echo "   [PERHATIAN] bluealsa TIDAK AKTIF. Ini penyebab paling umum dari"
    echo "   error 'br-connection-profile-unavailable'. Cek dengan:"
    echo "     journalctl -u bluealsa -n 50 --no-pager"
fi
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
echo " Catatan V9:"
echo "  - Output audio HANYA lewat Bluetooth speaker (tidak ada"
echo "    fallback ke audio lokal). anti-putus.service menjaga koneksi"
echo "    tetap hidup nonstop supaya bel tidak pernah bisu."
echo "  - Watchdog cek_service.sh berjalan tiap 5 menit lewat cron"
echo "    untuk memastikan kedua service utama tetap hidup, TERMASUK"
echo "    bluealsa (penyebab error br-connection-profile-unavailable"
echo "    kalau service ini tidak aktif)."
echo "===================================================="
