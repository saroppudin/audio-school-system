#!/bin/bash
# =====================================================================
# terapkan_perbaikan_switching_v15.sh
# ---------------------------------------------------------------------
# Menerapkan PERBAIKAN V15 (switching Bluetooth <-> Line Out yang mulus,
# bersih, dan instan lewat routing ALSA dinamis) pada sistem otomasi bel
# yang SUDAH TERPASANG dan berjalan -- TANPA install ulang total.
#
# Yang dilakukan skrip ini:
#   1. Mencari folder instalasi (DIR_BASE) yang sudah ada, lewat
#      sekolah.conf.
#   2. Backup atur_output_audio.sh & putar_audio.sh lama (dengan
#      timestamp), TIDAK menghapus apapun.
#   3. Menulis ulang atur_output_audio.sh & putar_audio.sh dengan versi
#      V15 (identik dengan yang dihasilkan installer V15).
#   4. Menambahkan/menyegarkan aturan NOPASSWD sudoers untuk
#      atur_output_audio.sh (auto-elevate).
#   5. Menerapkan mode output audio yang SEDANG AKTIF di sekolah.conf
#      sekarang juga, supaya /etc/asound.conf langsung terisi dan
#      konsisten (tidak menunggu switch manual pertama).
#
# TIDAK MENYENTUH: jadwal_ujian.conf, jadwal_harian.conf, file audio,
# MAC_SPEAKER, atau service/cron yang sudah berjalan.
#
# PEMAKAIAN:
#   sudo ./terapkan_perbaikan_switching_v15.sh
#   sudo ./terapkan_perbaikan_switching_v15.sh /path/ke/folder/instalasi
# =====================================================================
set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "[INFO] Skrip ini butuh root, otomatis re-exec pakai sudo..."
    exec sudo bash "$0" "$@"
fi

echo "===================================================================="
echo " TERAPKAN PERBAIKAN V15 - SWITCHING OUTPUT AUDIO (BLUETOOTH <-> LINE OUT)"
echo "===================================================================="

# ---------------------------------------------------------------------
# 1. TEMUKAN FOLDER INSTALASI (DIR_BASE)
# ---------------------------------------------------------------------
DIR_BASE="${1:-}"

if [ -n "$DIR_BASE" ]; then
    if [ ! -f "${DIR_BASE}/sekolah.conf" ]; then
        echo "[ERROR] Tidak ditemukan sekolah.conf di: ${DIR_BASE}"
        exit 1
    fi
else
    echo "[1/6] Mencari folder instalasi (sekolah.conf) secara otomatis..."
    KANDIDAT=$(find /home /opt /root -maxdepth 4 -name "sekolah.conf" 2>/dev/null | head -n 5)
    JUMLAH=$(echo "$KANDIDAT" | grep -c . || true)

    if [ "$JUMLAH" -eq 0 ]; then
        echo "[ERROR] sekolah.conf tidak ditemukan di /home, /opt, atau /root."
        echo "        Jalankan ulang dengan path eksplisit, contoh:"
        echo "        sudo $0 /home/lenovo/otomasi-bel"
        exit 1
    elif [ "$JUMLAH" -gt 1 ]; then
        echo "[ERROR] Ditemukan lebih dari satu sekolah.conf, sebutkan path yang benar:"
        echo "$KANDIDAT" | sed 's/^/   - /; s|/sekolah.conf$||'
        exit 1
    fi
    DIR_BASE="$(dirname "$KANDIDAT")"
fi

echo "      -> Folder instalasi ditemukan: ${DIR_BASE}"
CONF="${DIR_BASE}/sekolah.conf"
# shellcheck disable=SC1090
source "$CONF"

if [ -z "${MAC_SPEAKER:-}" ] || [ -z "${LOG_FILE:-}" ]; then
    echo "[ERROR] sekolah.conf tidak lengkap (MAC_SPEAKER/LOG_FILE kosong). Batal."
    exit 1
fi

# Kompatibilitas mundur: kalau AUDIO_OUTPUT belum ada di sekolah.conf
# lama (instalasi sebelum V15/bluetooth-only), default ke bluetooth.
AUDIO_OUTPUT="${AUDIO_OUTPUT:-bluetooth}"
AUDIO_DEVICE_LINEOUT="${AUDIO_DEVICE_LINEOUT:-hw:0,0}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ---------------------------------------------------------------------
# 2. BACKUP SKRIP LAMA (TIDAK MENGHAPUS APAPUN)
# ---------------------------------------------------------------------
echo "[2/6] Membuat backup skrip lama (kalau ada)..."
for f in atur_output_audio.sh putar_audio.sh; do
    if [ -f "${DIR_BASE}/${f}" ]; then
        cp -f "${DIR_BASE}/${f}" "${DIR_BASE}/${f}.bak_pre_v15_${TIMESTAMP}"
        echo "      -> Backup dibuat: ${DIR_BASE}/${f}.bak_pre_v15_${TIMESTAMP}"
    fi
done
[ -f /etc/asound.conf ] && cp -f /etc/asound.conf "/etc/asound.conf.bak_pre_v15_${TIMESTAMP}" \
    && echo "      -> Backup /etc/asound.conf lama: /etc/asound.conf.bak_pre_v15_${TIMESTAMP}"

# ---------------------------------------------------------------------
# 3. TULIS ULANG atur_output_audio.sh (VERSION 15)
# ---------------------------------------------------------------------
echo "[3/6] Menulis atur_output_audio.sh versi V15 (routing ALSA dinamis)..."
cat <<'EOF' > "${DIR_BASE}/atur_output_audio.sh"
#!/bin/bash
# =====================================================================
# atur_output_audio.sh (VERSION 15)
# Switching Bluetooth <-> Line Out yang mulus, bersih, dan instan lewat
# routing ALSA dinamis (pcm.!default di /etc/asound.conf). Setiap kali
# skrip ini dijalankan, /etc/asound.conf ditulis ulang -- dan karena
# aplikasi ALSA membaca file itu setiap kali membuka PCM, pemutaran
# BERIKUTNYA otomatis lewat output baru TANPA perlu restart apapun.
# =====================================================================

# --- AUTO-ELEVATE ---------------------------------------------------
# Menulis /etc/asound.conf & memutus Bluetooth butuh root. Kalau
# dijalankan user biasa, otomatis re-exec pakai sudo. Sudah didaftarkan
# NOPASSWD di /etc/sudoers.d/otomasi-audio-rfkill supaya instan.
# PERBAIKAN (V15b): pakai PATH ABSOLUT (bukan $0 mentah) saat re-exec --
# kalau dipanggil sebagai path relatif (mis. "./atur_output_audio.sh"),
# sudoers yang mendaftarkan path absolut bisa tidak cocok dan malah
# minta password / ditolak.
if [ "$(id -u)" -ne 0 ]; then
    SKRIP_ABSOLUT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    exec sudo "$SKRIP_ABSOLUT" "$@"
fi

DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${DIR_SKRIP}/sekolah.conf"
source "$CONF"

WAV_TES="/usr/share/sounds/alsa/Front_Center.wav"
ASOUND_CONF="/etc/asound.conf"

catat_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------
# PERBAIKAN (V15b): GUARD ANTI-TABRAKAN DENGAN BEL YANG SEDANG DIPUTAR.
# putar_audio.sh memegang lock /tmp/putar_audio.lock selama mpv main.
# Kalau kita menulis ulang /etc/asound.conf & memutus Bluetooth SAAT bel
# sedang berbunyi, bel itu bisa terputus mendadak di tengah jalan. Jadi
# sebelum benar-benar switching, coba tunggu (maks 12 detik, cukup untuk
# bel pendek) sampai lock itu bebas. Kalau tetap terkunci (bel panjang
# seperti lagu/mars), TETAP lanjut switching (jangan sampai admin
# menekan tombol dan tidak terjadi apa-apa), tapi beri peringatan jelas.
tunggu_giliran_aman() {
    exec 202>/tmp/putar_audio.lock
    if flock -w 12 202; then
        return 0
    else
        echo "[PERINGATAN] Ada bel yang sedang diputar & masih berlangsung setelah 12"
        echo "             detik menunggu. Tetap melanjutkan switching -- bel yang"
        echo "             sedang main mungkin terpotong."
        catat_log "[PERINGATAN] - Switching output dipaksa lanjut walau ada bel yang masih diputar (lock tidak bebas dalam 12 detik)."
        return 1
    fi
}

# ---------------------------------------------------------------------
# Deteksi ID/nama kartu suara analog Lenovo S200z secara otomatis, PAKAI
# NAMA KARTU (mis. "PCH"), BUKAN nomor index -- supaya tetap benar walau
# nomor kartu bergeser setelah reboot/kernel update. Kartu virtual HDMI
# disingkirkan dari kandidat.
#
# PERBAIKAN (V15c - BUG KRITIS): versi sebelumnya salah mengambil NAMA
# PANJANG kartu di dalam kurung siku (mis. "HDA Intel PCH", ada spasi)
# alih-alih ID PENDEK-nya (mis. "PCH"). Kalau dipakai sebagai
# "hw:HDA Intel PCH,0", ALSA GAGAL membuka device (string tidak valid
# berisi spasi) -- line_out tidak akan pernah bunyi walau kartu
# terdeteksi. Selain itu, versi sebelumnya memakai match(str, re, arr)
# 3-argumen yang HANYA didukung gawk, padahal /usr/bin/awk default di
# instalasi Debian minimal biasanya symlink ke mawk (TIDAK mendukung
# fitur itu) -- fungsi bisa gagal total tanpa pesan error yang jelas di
# sebagian sistem. Sekarang ditulis ulang pakai sub()/print POSIX biasa
# yang portable di awk manapun (mawk maupun gawk), dan mengambil ID
# pendek yang benar dari sebelum tanda "[".
# ---------------------------------------------------------------------
deteksi_card_analog() {
    aplay -l 2>/dev/null | awk '
        /^card/ && !/HDMI/ {
            sub(/^card [0-9]+: /, "")
            sub(/ \[.*/, "")
            print
            exit
        }'
}

# PERBAIKAN (V15c - OPTIMASI + BUG): versi sebelumnya menebak 5 nama
# kontrol mixer (Master, Headphone, Speaker, Front, PCM) tanpa mengecek
# yang mana yang BENAR-BENAR ADA di hardware. Di Lenovo S200z asli
# (dikonfirmasi lewat `amixer scontrols`), HANYA ADA 'Master' dan
# 'Capture' -- 4 dari 5 percobaan sebelumnya selalu gagal diam-diam
# (disuppress 2>/dev/null), membuang proses amixer tanpa hasil. Sekarang
# kontrol yang ada dideteksi SEKALI lewat `amixer scontrols`, lalu hanya
# kontrol PLAYBACK yang relevan (bukan 'Capture'/mic) yang disentuh --
# dan volume+unmute digabung jadi SATU panggilan amixer per kontrol
# (bukan dua) untuk mengurangi overhead proses.
unmute_semua_channel() {
    local card_arg=()
    [ -n "$1" ] && card_arg=(-c "$1")

    local daftar_kontrol
    daftar_kontrol=$(amixer "${card_arg[@]}" scontrols 2>/dev/null | sed -n "s/.*'\([^']*\)'.*/\1/p")

    local kontrol
    while IFS= read -r kontrol; do
        [ -z "$kontrol" ] && continue
        # 'Capture' adalah jalur mikrofon/input, bukan playback -- jangan
        # disentuh di sini (di luar tanggung jawab fungsi unmute output).
        [ "$kontrol" = "Capture" ] && continue
        amixer -q "${card_arg[@]}" sset "$kontrol" 100% unmute 2>/dev/null
    done <<< "$daftar_kontrol"
}

# Clean disconnect: putuskan Bluetooth kalau sedang aktif, supaya
# speaker bebas dipakai perangkat lain saat kita pindah ke line_out.
putus_bluetooth_jika_aktif() {
    if bluetoothctl info "$MAC_SPEAKER" 2>/dev/null | grep -q "Connected: yes"; then
        echo "Memutus koneksi Bluetooth speaker (${MAC_SPEAKER})..."
        bluetoothctl disconnect "$MAC_SPEAKER" >/dev/null 2>&1
        sleep 1
    fi
}

# PERBAIKAN (V15c - KEAMANAN): validasi CARD_ID sebelum dipakai menulis
# /etc/asound.conf & sed sekolah.conf. ID kartu ALSA yang sah hanya
# terdiri dari huruf/angka/underscore/titik (mis. "PCH", "sofhdadsp").
# Tanpa validasi ini, argumen ganjil/salah ketik (atau -- kalau suatu
# saat skrip dipanggil dari konteks lain dengan input tak terduga --
# argumen yang disusupi karakter aneh) bisa merusak isi asound.conf atau
# menyisipkan baris konfigurasi ALSA yang tidak diinginkan.
validasi_card_id() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

# PERBAIKAN (V15c - DRY): satu fungsi tes bunyi dipakai ulang oleh mode
# bluetooth, line_out, dan test -- sebelumnya 3 blok kode nyaris identik
# ditulis berulang (melanggar DRY, dan kalau ada bug di satu blok, mudah
# lupa memperbaiki blok lainnya).
tes_bunyi() {
    local label="$1" file_log="$2" batas_waktu="${3:-5}"
    if [ ! -f "$WAV_TES" ]; then
        echo "[PERINGATAN] File tes ${WAV_TES} tidak ada, lewati tes bunyi otomatis."
        return 0
    fi
    echo "Menguji output ${label} (harus terdengar bunyi singkat)..."
    if timeout "$batas_waktu" aplay -D default "$WAV_TES" >"$file_log" 2>&1; then
        echo "[OK] ${label} berhasil mengeluarkan suara."
        return 0
    else
        echo "[PERINGATAN] Tes bunyi gagal/tidak bisa dipastikan, cek ${file_log}"
        return 1
    fi
}

tulis_asound_bluetooth() {
    [ -f "$ASOUND_CONF" ] && cp -f "$ASOUND_CONF" "${ASOUND_CONF}.bak.$(date +%s)" 2>/dev/null
    cat <<CONFEOF > "$ASOUND_CONF"
# ======================================================================
# GENERATED OTOMATIS oleh atur_output_audio.sh -- JANGAN EDIT MANUAL.
# Mode aktif saat ini: BLUETOOTH (${MAC_SPEAKER})
# ======================================================================
pcm.!default {
    type plug
    slave.pcm "bt_speaker_aktif"
}
pcm.bt_speaker_aktif {
    type bluealsa
    device "${MAC_SPEAKER}"
    profile "a2dp"
}
ctl.!default {
    type bluealsa
}
CONFEOF
}

tulis_asound_lineout() {
    local card_id="$1"
    [ -f "$ASOUND_CONF" ] && cp -f "$ASOUND_CONF" "${ASOUND_CONF}.bak.$(date +%s)" 2>/dev/null
    cat <<CONFEOF > "$ASOUND_CONF"
# ======================================================================
# GENERATED OTOMATIS oleh atur_output_audio.sh -- JANGAN EDIT MANUAL.
# Mode aktif saat ini: LINE OUT / ANALOG JACK (card: ${card_id})
# dmix dipakai supaya beberapa proses audio beruntun tidak saling
# rebutan device ("Device or resource busy").
# ======================================================================
pcm.!default {
    type plug
    slave.pcm "line_out_aktif"
}
pcm.line_out_aktif {
    type dmix
    ipc_key 1024
    # PERBAIKAN (V15c - KEAMANAN): 0666 (world-writable) sebelumnya
    # mengizinkan SEMBARANG user/proses lokal di sistem ini menulis ke
    # shared-memory ring buffer dmix -- celah kecil tapi nyata untuk
    # tamper/DoS terhadap audio yang sedang diputar. Diketatkan ke 0600
    # (owner-only) karena semua proses pemutaran (cron, systemd daemon,
    # manual) SELALU berjalan sebagai user OS yang sama.
    ipc_perm 0600
    slave {
        pcm "hw:${card_id},0"
        rate 48000
        period_time 0
        period_size 1024
        buffer_size 4096
    }
}
ctl.!default {
    type hw
    card ${card_id}
}
CONFEOF
}

case "$1" in
    bluetooth)
        echo "Menyambungkan ulang ke speaker Bluetooth (${MAC_SPEAKER})..."
        "${DIR_SKRIP}/sambung_bt.sh"
        if ! bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
            echo "[GAGAL] Speaker Bluetooth tidak terhubung. Output TIDAK diubah -- cek dulu"
            echo "        koneksi (${DIR_SKRIP}/pasang_bt.sh) sebelum pindah ke Bluetooth."
            catat_log "[CRITICAL] - Gagal pindah ke Bluetooth: speaker tidak terhubung."
            exit 1
        fi
        tunggu_giliran_aman
        tulis_asound_bluetooth
        sed -i 's/^AUDIO_OUTPUT=.*/AUDIO_OUTPUT="bluetooth"/' "$CONF"
        catat_log "[SUKSES] - Output audio diubah ke BLUETOOTH (${MAC_SPEAKER}); pcm.!default direute ke bluealsa."
        echo "[OK] Output audio diubah ke: BLUETOOTH (${MAC_SPEAKER})"
        echo "     (berlaku instan untuk pemutaran audio berikutnya)"
        tes_bunyi "Bluetooth (${MAC_SPEAKER})" /tmp/tes_bt.log 8
        ;;
    line_out|lineout)
        CARD_ID="${2:-$(deteksi_card_analog)}"
        if [ -z "$CARD_ID" ]; then
            echo "[GAGAL] Tidak ada kartu suara analog terdeteksi. Cek manual: aplay -l"
            catat_log "[CRITICAL] - Gagal pindah ke line_out: tidak ada card analog terdeteksi."
            exit 1
        fi
        if ! validasi_card_id "$CARD_ID"; then
            echo "[GAGAL] ID kartu '${CARD_ID}' tidak valid (hanya huruf/angka/underscore/titik/dash)."
            catat_log "[CRITICAL] - Gagal pindah ke line_out: CARD_ID '${CARD_ID}' tidak lolos validasi."
            exit 1
        fi
        tunggu_giliran_aman
        putus_bluetooth_jika_aktif
        tulis_asound_lineout "$CARD_ID"
        unmute_semua_channel "$CARD_ID"
        tes_bunyi "line out (card ${CARD_ID})" /tmp/tes_lineout.log 5
        sed -i "s/^AUDIO_OUTPUT=.*/AUDIO_OUTPUT=\"line_out\"/" "$CONF"
        sed -i "s|^AUDIO_DEVICE_LINEOUT=.*|AUDIO_DEVICE_LINEOUT=\"hw:${CARD_ID},0\"|" "$CONF"
        catat_log "[SUKSES] - Output audio diubah ke LINE OUT (card ${CARD_ID}); Bluetooth diputus, pcm.!default direute ke dmix, semua channel playback di-unmute."
        echo "[OK] Output audio diubah ke: LINE OUT (hw:${CARD_ID},0)"
        echo "     (berlaku instan untuk pemutaran audio berikutnya)"
        ;;
    test)
        tes_bunyi "default ALSA saat ini (mode: ${AUDIO_OUTPUT})" /tmp/tes_default.log 5
        ;;
    status)
        echo "Output audio saat ini : ${AUDIO_OUTPUT}"
        echo "--- Isi /etc/asound.conf aktif ---"
        if [ -f "$ASOUND_CONF" ]; then
            cat "$ASOUND_CONF"
        else
            echo "(belum ada -- jalankan 'bluetooth' atau 'line_out' dulu)"
        fi
        echo "-----------------------------------"
        if [ "$AUDIO_OUTPUT" = "bluetooth" ]; then
            echo "MAC Speaker Bluetooth : ${MAC_SPEAKER}"
            bluetoothctl info "$MAC_SPEAKER" 2>/dev/null | grep -E "Connected|Paired"
        else
            echo "Device ALSA           : ${AUDIO_DEVICE_LINEOUT}"
        fi
        ;;
    *)
        echo "Pemakaian: sudo $0 {bluetooth|line_out [card_id]|status|test}"
        echo "  bluetooth        - pindah ke speaker Bluetooth (sambung ulang otomatis)"
        echo "  line_out [card]  - pindah ke jack analog (auto-deteksi card kalau tidak disebut)"
        echo "  status           - lihat output, isi asound.conf & status koneksi saat ini"
        echo "  test             - tes bunyi singkat lewat output default yang sedang aktif"
        exit 1
        ;;
esac
EOF
chmod +x "${DIR_BASE}/atur_output_audio.sh"

# ---------------------------------------------------------------------
# 4. TULIS ULANG putar_audio.sh (UNIFIED PLAYBACK ENGINE)
# ---------------------------------------------------------------------
echo "[4/6] Menulis putar_audio.sh versi V15 (unified playback engine)..."
cat <<'EOF' > "${DIR_BASE}/putar_audio.sh"
#!/bin/bash
exec 201>/tmp/putar_audio.lock
flock -n 201 || exit 0

DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"
mkdir -p "$DIR_FLAG"

KUNCI="$1"; NAMA="$2"; shift 2
FILES=("$@")

# PERBAIKAN (V15c - DRY): satu fungsi logging dipakai ulang alih-alih
# menulis "$(date ...) - [X] - ..." >> "$LOG_FILE" berulang di 8+ tempat.
catat() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ -f "${DIR_FLAG}/semua.off" ] || [ -f "${DIR_FLAG}/${KUNCI}.off" ]; then
    catat "[SKIP] - $NAMA dilewati (mode nonaktif sedang aktif)."
    exit 0
fi

# PERBAIKAN: pause otomatis bel jam pelajaran hari Senin setelah bel
# masuk (jam_ke_0_senin), sampai upacara selesai dan admin menjalankan
# lanjutkan_bel_senin.sh secara manual (durasi upacara suka beda-beda,
# jadi tidak dijadwalkan otomatis pakai jam tetap).
case "$KUNCI" in
    jam_ke_*_senin)
        if [ -f "${DIR_FLAG}/pause_senin.flag" ]; then
            # PERBAIKAN: safety-valve -- auto-batalkan pause kalau sudah
            # lebih dari 90 menit sejak bel masuk (jaga-jaga admin lupa
            # jalankan lanjutkan_bel_senin.sh setelah upacara selesai;
            # tanpa ini, bel Senin bisa diam SEHARIAN tanpa peringatan).
            PAUSE_SEJAK=$(cat "${DIR_FLAG}/pause_senin.flag" 2>/dev/null)
            SEKARANG_EPOCH=$(date +%s)
            if [[ "$PAUSE_SEJAK" =~ ^[0-9]+$ ]] && [ $(( SEKARANG_EPOCH - PAUSE_SEJAK )) -gt 5400 ]; then
                rm -f "${DIR_FLAG}/pause_senin.flag"
                catat "[INFO] - Pause bel Senin otomatis dibatalkan (sudah >90 menit -- kemungkinan admin lupa jalankan lanjutkan_bel_senin.sh)."
            else
                catat "[SKIP] - $NAMA di-pause (menunggu upacara Senin selesai, jalankan lanjutkan_bel_senin.sh)."
                exit 0
            fi
        fi
        ;;
esac

for f in "${FILES[@]}"; do
    [ -f "$f" ] || catat "[CRITICAL] - File hilang: $f"
done

# PERBAIKAN (V15 - UNIFIED PLAYBACK ENGINE): routing sistem SUDAH
# ditangani secara dinamis di level ALSA oleh atur_output_audio.sh, yang
# menulis /etc/asound.conf setiap kali output diganti (pcm.!default ->
# bluealsa terkunci MAC speaker untuk mode bluetooth, atau dmix di atas
# card analog untuk mode line_out). Karena itu mpv TIDAK PERLU LAGI
# dibedakan device-nya per mode -- selalu cukup "alsa/default". Cek
# koneksi di bawah ini HANYA untuk logging/diagnostik.
if [ "$AUDIO_OUTPUT" = "line_out" ]; then
    # PERBAIKAN (V15c - BUG): versi sebelumnya "grep -qv 'bluealsa\|HDMI'"
    # SELALU bernilai benar (exit 0) karena aplay -l selalu punya baris
    # lain (header, "Subdevices: ...", dst) yang tidak memuat kata
    # "bluealsa"/"HDMI" -- jadi CRITICAL di bawah ini TIDAK PERNAH
    # terpicu walau kartu analognya benar-benar tidak ada. Sekarang
    # dicek TEPAT pola "^card" yang bukan HDMI (sama seperti di
    # atur_output_audio.sh), bukan sembarang baris.
    if ! aplay -l 2>/dev/null | awk '"'"'/^card/ && !/HDMI/ {f=1} END{exit !f}'"'"'; then
        catat "[CRITICAL] - $NAMA GAGAL DIPUTAR: tidak ada kartu suara analog terdeteksi ALSA untuk mode line_out. Cek kabel/sound card, atau jalankan atur_output_audio.sh line_out untuk auto-deteksi ulang."
    fi
else
    "${DIR_SKRIP}/sambung_bt.sh"

    # Cek betul-betul status koneksi sebelum main, dan catat CRITICAL yang
    # jelas kalau tetap tidak konek (bukan diam-diam gagal). Output audio
    # HANYA lewat Bluetooth (tidak ada fallback ke audio lokal PC).
    if ! bluetoothctl info "$MAC_SPEAKER" | grep -q "Connected: yes"; then
        catat "[CRITICAL] - $NAMA GAGAL DIPUTAR: Bluetooth speaker tidak terhubung. Cek ${DIR_SKRIP}/pasang_bt.sh"
    fi

    # PERBAIKAN (jaga-jaga): lepas paksa sisa proses aplay yang masih
    # menahan PCM bluealsa, kalau ada, sebelum mpv coba membuka PCM yang sama.
    pkill -f "aplay -q -D bluealsa" 2>/dev/null
    sleep 0.3
fi

# PERBAIKAN (V15): satu device untuk semua mode -- rute sesungguhnya
# ditentukan oleh /etc/asound.conf (dikelola atur_output_audio.sh).
MPV_AUDIO_DEVICE="alsa/default"

# PERBAIKAN (V15c): kontrol mixer 'Master' dikonfirmasi ADA di hardware
# asli (lihat `amixer scontrols`), jadi satu panggilan gabungan ini
# cukup, tidak perlu mencoba nama kontrol lain yang tidak ada.
amixer -q sset Master 100% unmute 2>/dev/null

DAFTAR=$(printf '%s, ' "${FILES[@]##*/}")
catat "[PLAY] - Memutar $NAMA: ${DAFTAR%, } (Volume 80%, output: ${AUDIO_OUTPUT})"

# PERBAIKAN (V14): --audio-fallback-to-ids BUKAN opsi valid di mpv (lihat
# `mpv --list-options`), menyebabkan mpv Fatal Error dan TIDAK PERNAH
# main audio apapun. Opsi ini dihapus total.
mpv --no-video --audio-device="${MPV_AUDIO_DEVICE}" --volume=80 --audio-delay=1.5 "${FILES[@]}" >> "$LOG_FILE" 2>&1
MPV_EXIT=$?

# PERBAIKAN: kalau bel yang baru selesai diputar adalah bel masuk
# Senin, otomatis pause bel jam pelajaran Senin berikutnya (menunggu
# upacara selesai).
if [ "$KUNCI" = "jam_ke_0_senin" ] && [ "$MPV_EXIT" -eq 0 ]; then
    date +%s > "${DIR_FLAG}/pause_senin.flag"
    catat "[INFO] - Bel jam pelajaran Senin di-pause otomatis setelah bel masuk (menunggu upacara selesai, maks 90 menit). Jalankan lanjutkan_bel_senin.sh setelah upacara usai."
fi

# PERBAIKAN: catat baris log jelas SUKSES/GAGAL setelah playback selesai,
# lengkap dengan jam selesai dan nama bel -- supaya mudah dicari lewat
# grep tanpa perlu menebak dari banyak baris debug bluealsa-pcm.
if [ "$MPV_EXIT" -eq 0 ]; then
    catat "[SUKSES] - $NAMA berhasil diputar (selesai jam $(date '+%H:%M'))."
else
    # PERBAIKAN: terjemahkan exit code mpv secara akurat (sesuai
    # dokumentasi resmi mpv), bukan tebakan generik. Exit 4 itu KELUAR
    # KARENA SINYAL (mis. Ctrl+C) -- BUKAN error device/koneksi, jadi
    # jangan diarahkan ke "cek Bluetooth" yang menyesatkan.
    case "$MPV_EXIT" in
        1) KETERANGAN_EXIT="mpv gagal inisialisasi (opsi tidak dikenal, atau device audio \"${MPV_AUDIO_DEVICE}\" tidak valid/tidak ditemukan)" ;;
        2) KETERANGAN_EXIT="file audio tidak bisa diputar (format tidak didukung, file rusak, atau file tidak ditemukan)" ;;
        3) KETERANGAN_EXIT="sebagian file berhasil diputar, sebagian gagal" ;;
        4) KETERANGAN_EXIT="mpv dihentikan paksa oleh sinyal (mis. Ctrl+C) -- BUKAN error device, kemungkinan proses ter-interrupt" ;;
        *) KETERANGAN_EXIT="kode keluar tidak dikenal" ;;
    esac
    catat "[GAGAL] - $NAMA GAGAL diputar (mpv exit code ${MPV_EXIT}: ${KETERANGAN_EXIT})."
fi
EOF
chmod +x "${DIR_BASE}/putar_audio.sh"
chown "$(stat -c '%U:%G' "${DIR_BASE}")" "${DIR_BASE}/atur_output_audio.sh" "${DIR_BASE}/putar_audio.sh" 2>/dev/null

# ---------------------------------------------------------------------
# 5. SUDOERS: NOPASSWD UNTUK atur_output_audio.sh (AUTO-ELEVATE)
# ---------------------------------------------------------------------
echo "[5/6] Memperbarui aturan sudoers untuk auto-elevate..."
USER_SISTEM="$(stat -c '%U' "${DIR_BASE}")"
SUDOERS_FILE="/etc/sudoers.d/otomasi-audio-rfkill"
SUDOERS_TMP="$(mktemp)"

if [ -f "$SUDOERS_FILE" ]; then
    grep -v "atur_output_audio.sh" "$SUDOERS_FILE" > "$SUDOERS_TMP"
else
    : > "$SUDOERS_TMP"
fi

cat <<EOF >> "$SUDOERS_TMP"
# PERBAIKAN (V15) - ditulis oleh terapkan_perbaikan_switching_v15.sh
# CATATAN KEAMANAN: skrip ini ada di ${DIR_BASE} (writable oleh
# ${USER_SISTEM}), jadi NOPASSWD ini secara teknis berarti user tsb
# punya jalur ke root kalau dia mau mengedit skrip. Trade-off yang
# disengaja demi kenyamanan operasional. Kalau mau lebih aman, pindahkan
# atur_output_audio.sh ke /usr/local/bin (root-owned) dan ubah baris ini.
${USER_SISTEM} ALL=(ALL) NOPASSWD: ${DIR_BASE}/atur_output_audio.sh
${USER_SISTEM} ALL=(ALL) NOPASSWD: ${DIR_BASE}/atur_output_audio.sh *
EOF

if visudo -c -f "$SUDOERS_TMP" &>/dev/null; then
    mv "$SUDOERS_TMP" "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    echo "      -> [OK] Sudoers diperbarui: ${SUDOERS_FILE}"
else
    echo "      -> [ERROR] Sintaks sudoers baru tidak valid, sudoers LAMA dibiarkan apa adanya."
    rm -f "$SUDOERS_TMP"
fi

# ---------------------------------------------------------------------
# 6. TERAPKAN MODE OUTPUT YANG SEDANG AKTIF SEKARANG JUGA
# ---------------------------------------------------------------------
echo "[6/6] Menerapkan /etc/asound.conf sesuai mode aktif saat ini (${AUDIO_OUTPUT})..."
if [ "$AUDIO_OUTPUT" = "line_out" ]; then
    "${DIR_BASE}/atur_output_audio.sh" line_out
else
    "${DIR_BASE}/atur_output_audio.sh" bluetooth
fi

echo "===================================================================="
echo " SELESAI. Perbaikan V15 sudah diterapkan pada sistem yang berjalan."
echo "===================================================================="
echo " Folder instalasi   : ${DIR_BASE}"
echo " Backup skrip lama   : ${DIR_BASE}/*.bak_pre_v15_${TIMESTAMP}"
echo " Mode aktif sekarang : ${AUDIO_OUTPUT}"
echo "--------------------------------------------------------------------"
echo " Cara ganti output mulai sekarang:"
echo "   sudo ${DIR_BASE}/atur_output_audio.sh bluetooth"
echo "   sudo ${DIR_BASE}/atur_output_audio.sh line_out"
echo "   ${DIR_BASE}/atur_output_audio.sh status"
echo "===================================================================="
