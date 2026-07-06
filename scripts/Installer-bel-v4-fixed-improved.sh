#!/bin/bash
# ====================================================================
# MASTER INSTALLER AUTOMATION AUDIO SEKOLAH (VERSION 4 - PERBAIKAN)
# SYSTEM: MULTI-AUDIO BEL UJIAN, BEL HARIAN & DAEMON TAHRIM
# ----------------------------------------------------------------
# CATATAN PERBAIKAN DARI VERSION 3:
#   1. Skrip sebelumnya TERPOTONG di baris terakhir (tahap 8/8 hilang)
#      -> sudah dilengkapi dengan ringkasan & verifikasi akhir.
#   2. Setiap skrip anak sebelumnya hardcode "source /home/lenovo/..."
#      lalu ditambal pakai sed -> sekarang tiap skrip menemukan lokasi
#      sekolah.conf sendiri secara dinamis (lebih aman & tidak rapuh).
#   3. Cron pengecek disk sebelumnya memakai strftime() yang HANYA ada
#      di gawk (Debian default-nya mawk, tidak mendukung strftime) DAN
#      menaruh tanda persen (%) mentah di baris crontab, padahal cron
#      memperlakukan % sebagai baris baru -> sekarang dipisah jadi
#      skrip cek_disk.sh tersendiri, aman dari kedua masalah itu.
#   4. Baris sudoers sebelumnya ditambahkan langsung ke /etc/sudoers
#      (berisiko jika ada kesalahan sintaks) -> sekarang ditulis ke
#      /etc/sudoers.d/ terpisah dan divalidasi dengan visudo -c.
#   5. Ditambahkan validasi konfigurasi (USER_SISTEM, koordinat, MAC)
#      di awal supaya kesalahan ketik ketahuan sebelum instalasi jalan.
#   6. Ditambahkan pengecekan hasil setiap tahap penting (apt, dsb)
#      supaya tidak diam-diam gagal di tengah jalan.
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
# 0. VALIDASI AWAL (BARU) - mencegah instalasi jalan dengan konfigurasi
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

echo "===================================================="
echo " Memulai Instalasi Otomatisasi Audio V4 untuk:"
echo " ${NAMA_SEKOLAH}"
echo "===================================================="

# --------------------------------------------------------------------
# 2. INSTALASI PAKET DEPENDENSI SISTEM
# --------------------------------------------------------------------
echo "[1/8] Menginstal paket pendukung Debian..."
apt update && apt upgrade -y
if ! apt install bluez bluez-tools bluez-alsa-utils alsa-utils mpv curl jq rfkill nano fail2ban systemd-timesyncd -y; then
    echo "[ERROR] Gagal menginstal paket dependensi. Periksa koneksi internet / repository apt Anda."
    exit 1
fi

# Atur zona waktu dan aktifkan NTP
timedatectl set-timezone Asia/Jakarta
systemctl enable --now systemd-timesyncd
systemctl enable --now fail2ban

# Matikan PipeWire jika ada (agar tidak berebut bluetooth adapter)
systemctl disable --now pipewire pipewire-pulse wireplumber 2>/dev/null

# Mencegah PC masuk ke mode tidur/suspend
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Masukkan user ke grup audio dan bluetooth
usermod -aG audio,bluetooth "${USER_SISTEM}"

# Konfigurasi BlueALSA ke mode A2DP sink saja
echo "[2/8] Mengonfigurasi BlueALSA..."
mkdir -p /etc/systemd/system/bluealsa.service.d
cat <<EOF > /etc/systemd/system/bluealsa.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/bluealsa -p a2dp-sink
EOF
systemctl daemon-reload
systemctl restart bluetooth bluealsa
rfkill unblock bluetooth
bluetoothctl power on

# PERBAIKAN: sudoers ditulis ke file terpisah di /etc/sudoers.d/ dan
# divalidasi dengan visudo -c, jauh lebih aman daripada menambahkan
# baris langsung ke /etc/sudoers utama.
SUDOERS_FILE="/etc/sudoers.d/otomasi-audio-rfkill"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/sbin/rfkill" > "$SUDOERS_FILE"
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
echo "[3/8] Membuat struktur folder dan file konfigurasi..."
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
echo "[4/8] Membuat berkas skrip operasional audio..."

# PERBAIKAN: setiap skrip di bawah ini memakai baris berikut untuk
# menemukan sekolah.conf secara dinamis, mengikuti lokasi skrip itu
# sendiri. Ini menggantikan cara lama (hardcode path + sed di akhir)
# yang rapuh dan berisiko salah tambal.
#   DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${DIR_SKRIP}/sekolah.conf"

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
echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - Memulai jaring pengaman koneksi Bluetooth di ${NAMA_SEKOLAH}..." >> "$LOG_FILE"

for i in {1..3}; do
    bluetoothctl connect "$MAC_SPEAKER"
    sleep 3
    if bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [SUCCESS] - Bluetooth tersambung pada percobaan ke-$i." >> "$LOG_FILE"
        echo 0 > "$GAGAL_FILE"
        exit 0
    fi
done

GAGAL_KE=$(( $(cat "$GAGAL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$GAGAL_KE" > "$GAGAL_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - Gagal koneksi (beruntun ke-$GAGAL_KE)." >> "$LOG_FILE"

if [ "$GAGAL_KE" -ge 3 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [RECOVERY] - Reset adapter Bluetooth karena gagal beruntun." >> "$LOG_FILE"
    sudo rfkill block bluetooth
    sleep 2
    sudo rfkill unblock bluetooth
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

# Skrip cek_disk.sh (BARU - menggantikan baris cron lama yang bermasalah)
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
echo -e "\n=== KONEKSI BLUETOOTH ==="
bluetoothctl info "$MAC_SPEAKER" | grep -E "Connected|Name"
echo -e "\n=== SINKRONISASI WAKTU ==="
timedatectl show -p NTPSynchronized --value
echo -e "\n=== SISA RUANG DISK ==="
df -h "${DIR_BASE}" | tail -1
echo -e "\n=== STATUS AKTIVASI FITUR AUDIO ==="
"${DIR_SKRIP}/mode_sekolah.sh" status
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
echo "[5/8] Daftarkan skrip ke Systemd Service..."

cat <<EOF > /etc/systemd/system/anti-putus.service
[Unit]
Description=Penjaga Koneksi Bluetooth Mixer Audio Sekolah
After=bluetooth.target network.target

[Service]
Type=simple
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
After=network-online.target bluetooth.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${DIR_BASE}/tahrim_daemon.sh
Restart=always
RestartSec=10
User=${USER_SISTEM}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now anti-putus.service
systemctl enable --now tahrim-daemon.service

# --------------------------------------------------------------------
# 6. INSTALASI MANAJEMEN LOG (LOGROTATE GLOBAL)
# --------------------------------------------------------------------
echo "[6/8] Mengonfigurasi Logrotate global..."
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
echo "[7/8] Mendaftarkan jadwal harian tetap di Crontab..."
crontab -l -u ${USER_SISTEM} 2>/dev/null | grep -v "putar_audio.sh\|cek_ujian.sh\|cek_disk.sh\|backup.sh\|df /home" > /tmp/cron_bak

cat <<EOF >> /tmp/cron_bak
# --- JADWAL TETAP HARIAN GENERATED BY AUTOMATION ---
30 6 * * 1-6 ${DIR_BASE}/putar_audio.sh lagu_pagi "Lagu Pagi" ${DIR_AUDIO}/Hymne-guru.mp3 ${DIR_AUDIO}/Tanah-airku.mp3 ${DIR_AUDIO}/Rukun-Sama-teman.mp3 ${DIR_AUDIO}/Mars.mp3
59 9 * * 1-4,6 ${DIR_BASE}/putar_audio.sh indonesia_raya "Indonesia Raya" ${DIR_AUDIO}/Pengantar-dan-indonesia-raya.mp3
55 11 * * 1-4,6 ${DIR_BASE}/putar_audio.sh bel_dzuhur "Bel Dzuhur" ${DIR_AUDIO}/Bel-Persiapan-Sholat-dzuhur.mp3
* * * * * ${DIR_BASE}/cek_ujian.sh
0 7 * * * ${DIR_BASE}/cek_disk.sh
55 23 * * * ${DIR_BASE}/backup.sh
EOF

crontab -u ${USER_SISTEM} /tmp/cron_bak
rm -f /tmp/cron_bak

# --------------------------------------------------------------------
# 8. VERIFIKASI AKHIR & RINGKASAN INSTALASI (BARU - sebelumnya hilang)
# --------------------------------------------------------------------
echo "[8/8] Verifikasi akhir & ringkasan instalasi..."

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

echo "===================================================="
echo " INSTALASI SELESAI - ${NAMA_SEKOLAH}"
echo "===================================================="
echo " Service aktif : anti-putus.service, tahrim-daemon.service"
echo " Folder utama  : ${DIR_BASE}"
echo " Folder audio  : ${DIR_AUDIO}"
echo " Log sistem    : ${LOG_FILE}"
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
echo "  2. Cek status sistem  : ${DIR_BASE}/cek_kesehatan.sh"
echo "  3. Atur jadwal ujian  : ${DIR_BASE}/kelola_ujian.sh"
echo "  4. Atur mode sekolah  : ${DIR_BASE}/mode_sekolah.sh"
echo "===================================================="
