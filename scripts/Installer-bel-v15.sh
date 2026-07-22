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
#
# TAMBAHAN VERSION 15 (fitur lapangan + pemulihan bencana, berdasarkan
# insiden nyata /home sempat wipe total karena mati listrik berulang):
#  30. cek_integritas_sistem.sh (BARU) -- pemeriksa berkala (tiap 15
#      menit + saat boot) yang hidup DI LUAR /home (/usr/local/bin),
#      supaya tidak ikut hilang kalau /home wipe total. Kalau >=70%
#      penanda kunci (script/config/folder) hilang, OTOMATIS unduh
#      ulang installer dari GitHub, suntik config lama dari
#      /etc/audio-school-system/recovery.conf, install ulang, lalu
#      pulihkan jadwal_harian.conf/jadwal_ujian.conf terakhir dari
#      /var/backups/audio-school-system/ (dan file audio juga, KALAU
#      memang disimpan di repo GitHub). Ada cooldown 1 jam antar
#      percobaan supaya tidak reinstall berulang kalau gagal terus.
#  29. backup.sh sekarang juga menyalin jadwal_harian.conf,
#      jadwal_ujian.conf, sekolah.conf ke /var/backups/audio-school-system
#      (DI LUAR /home) setiap kali jalan -- supaya ada salinan yang
#      selamat walau /home rusak total.
#  28. Pilihan output audio: AUDIO_OUTPUT="bluetooth" (default) atau
#      "line_out" di sekolah.conf. Ganti lewat atur_output_audio.sh
#      {bluetooth|line_out|status}. Mode line_out melewati semua urusan
#      Bluetooth (sambung_bt.sh, cek koneksi) dan main langsung lewat
#      jack audio analog PC (AUDIO_DEVICE_LINEOUT, default hw:0,0).
#  27. Pause otomatis bel jam pelajaran Senin: begitu bel masuk
#      (kunci jam_ke_0_senin) selesai diputar, semua bel jam_ke_*_senin
#      berikutnya otomatis di-skip sampai admin jalankan
#      lanjutkan_bel_senin.sh (upacara bendera durasinya suka beda-beda,
#      jadi tidak dijadwalkan pakai jam tetap). Ada safety-valve:
#      auto-batal sendiri kalau sudah >90 menit dan admin lupa jalankan
#      lanjutkan_bel_senin.sh, supaya bel tidak diam seharian.
#  26. tahrim_daemon.sh sekarang MENUNGGU NTP sinkron (maks 2 menit)
#      sebelum menghitung jadwal hari itu -- mencegah jadwal Subuh/
#      Maghrib meleset puluhan menit kalau daemon baru boot sebelum jam
#      sistem sempat sinkron (kejadian nyata: Tarhim Maghrib telat 41
#      menit gara-gara ini).
#
# TAMBAHAN VERSION 15b (PERBAIKAN INTI: switching Bluetooth <-> Line Out
# sekarang mulus, bersih, dan instan -- sebelumnya cuma ganti variabel
# AUDIO_OUTPUT di config tanpa mengubah routing ALSA sistem, sehingga
# rawan "device busy", suara nyangkut di output lama, atau harus restart
# proses):
#  24. ROUTING ALSA DINAMIS (/etc/asound.conf): atur_output_audio.sh
#      SEKARANG MENULIS ULANG /etc/asound.conf setiap kali output
#      diganti, mengarahkan pcm.!default langsung ke:
#        - Mode Bluetooth -> pcm virtual "bluealsa" terkunci ke MAC
#          speaker (lewat "plug" supaya konversi format otomatis).
#        - Mode Line Out  -> pcm virtual "dmix" di atas card analog yang
#          TERDETEKSI OTOMATIS PAKAI NAMA KARTU (bukan nomor index),
#          supaya tidak meleset kalau nomor kartu bergeser setelah
#          reboot. dmix juga mencegah error "Device or resource busy"
#          kalau ada beberapa proses audio main beruntun/bersamaan.
#      Karena aplikasi ALSA membaca /etc/asound.conf setiap kali PCM
#      dibuka, perubahan ini langsung berlaku untuk pemutaran BERIKUTNYA
#      tanpa perlu restart service/daemon apapun -- itulah yang membuat
#      transisi terasa instan.
#  25c. UNIFIED PLAYBACK ENGINE (putar_audio.sh): karena routing sudah
#      ditangani di level sistem oleh /etc/asound.conf, mpv SEKARANG
#      SELALU memutar ke "alsa/default" -- tidak perlu lagi cabang
#      device berbeda untuk Bluetooth vs Line Out. Ini menghemat resource
#      dan meniadakan kegagalan playback akibat device string yang salah.
#  26b. AUTO-ELEVATE + SUDOERS: atur_output_audio.sh sekarang otomatis
#      memicu 'sudo' sendiri kalau dijalankan user biasa (perlu root
#      untuk menulis /etc/asound.conf), dan sudah didaftarkan NOPASSWD di
#      sudoers supaya user ${USER_SISTEM} bisa mengeksekusinya instan
#      tanpa diminta password. CATATAN KEAMANAN: karena skrip ini ada di
#      /home (bisa ditulis user tsb), NOPASSWD ini secara teknis berarti
#      user itu punya jalur ke root kalau dia mau mengedit skrip. Ini
#      trade-off yang disengaja demi kenyamanan operasional harian sesuai
#      permintaan; kalau mau lebih aman, pindahkan skrip ini ke
#      /usr/local/bin (root-owned, tidak bisa ditulis user biasa) dan
#      arahkan sudoers ke path baru itu.
#  27b. CLEAN DISCONNECT & UNMUTE HARDWARE: pindah ke Line Out otomatis
#      memutus koneksi Bluetooth yang sedang aktif (speaker jadi bebas
#      dipakai perangkat lain) lalu unmute penuh semua channel analog
#      Lenovo S200z (Master, Headphone, Speaker, Front, PCM). Pindah ke
#      Bluetooth otomatis memicu pencarian & penyambungan ulang instan.
#
# TAMBAHAN VERSION 15 (fitur lapangan + pemulihan bencana, berdasarkan
# insiden nyata /home sempat wipe total karena mati listrik berulang):
#  25b. tahrim_daemon.sh: catch-up -- kalau Subuh/Maghrib baru lewat
#      <30 menit (mis. daemon sempat restart), TETAP diputar telat,
#      bukan di-skip total. Kalau sudah lewat >30 menit, baru di-skip.
#  25c. cek_kesehatan.sh menampilkan status pause Senin, output audio
#      aktif, dan status integritas-sistem.timer.
#
# TAMBAHAN VERSION 14 (hapus penjaga koneksi 24 jam, sesuai kebutuhan lapangan):
#  25. anti-putus.service (loop 24 jam + silent keep-alive audio) DIHAPUS.
#      Speaker BT-MAX terbukti tidak butuh keep-alive untuk tetap
#      terhubung, dan proses silent-audio yang jalan terus-menerus itu
#      justru jadi sumber race condition "Device or resource busy" saat
#      mpv mau main. Diganti bt-boot-connect.service (Type=oneshot) yang
#      cuma jalan SEKALI saat boot untuk reconnect otomatis kalau listrik
#      sempat padam/reboot. Reconnect harian tetap ditangani sambung_bt.sh
#      yang sudah dipanggil putar_audio.sh sebelum tiap bel (tidak berubah).
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
MAC_SPEAKER="16:3E:E3:5F:EF:E5"        # MAC Address Mixer/Speaker Bluetooth

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
    echo "[ERROR] Format MAC_SPEAKER tidak valid. Contoh format yang benar: 16:3E:E3:5F:EF:E5"
    exit 1
fi

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
    cp /etc/bluetooth/main.conf "/etc/bluetooth/main.conf.bak.$(date +%s)"
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

# PERBAIKAN (V15): dulu di sini langsung ditulis /etc/asound.conf format
# lama ("defaults.bluealsa.device ..."). Format itu SEKARANG SUDAH
# DIGANTIKAN oleh routing dinamis pcm.!default yang dikelola
# atur_output_audio.sh (lihat Langkah 8d di bawah, dipanggil otomatis
# sekali di akhir instalasi supaya /etc/asound.conf awal langsung benar
# -- tidak perlu lagi ditulis manual di sini).
echo "[4/9] (Pengaturan detail /etc/asound.conf dilakukan otomatis di akhir instalasi oleh atur_output_audio.sh)"

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
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart tahrim-daemon.service
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bt-boot-connect.service
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluealsa
${USER_SISTEM} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth bluealsa
# PERBAIKAN (V15): atur_output_audio.sh sekarang butuh root untuk menulis
# /etc/asound.conf (routing ALSA dinamis) & memutus koneksi Bluetooth
# saat pindah ke line_out. Auto-elevate di dalam skrip memicu 'sudo $0',
# baris ini membuatnya instan tanpa password. Lihat catatan keamanan V15
# di header skrip ini soal trade-off NOPASSWD pada skrip di /home.
${USER_SISTEM} ALL=(ALL) NOPASSWD: ${DIR_BASE}/atur_output_audio.sh
${USER_SISTEM} ALL=(ALL) NOPASSWD: ${DIR_BASE}/atur_output_audio.sh *
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

# PERBAIKAN: folder config & backup DI LUAR /home, supaya kalau /home
# bersih total (corrupt filesystem, salah hapus, dsb), data untuk
# PEMULIHAN OTOMATIS tetap ada. /etc dan /var/backups ada di partisi
# root, bukan partisi/folder /home.
mkdir -p /etc/audio-school-system
mkdir -p /var/backups/audio-school-system
chown ${USER_SISTEM}:${USER_SISTEM} /var/backups/audio-school-system

cat <<EOF > /etc/audio-school-system/recovery.conf
# Salinan config inti untuk PEMULIHAN OTOMATIS (dipakai
# cek_integritas_sistem.sh kalau /home/${USER_SISTEM} hilang total).
# File ini di /etc, bukan di /home, supaya tidak ikut hilang.
USER_SISTEM="${USER_SISTEM}"
NAMA_SEKOLAH="${NAMA_SEKOLAH}"
GARIS_LINTANG="${GARIS_LINTANG}"
GARIS_BUJUR="${GARIS_BUJUR}"
MAC_SPEAKER="${MAC_SPEAKER}"
EOF

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

# PERBAIKAN (V15): pilihan output audio -- "bluetooth" (default) atau
# "line_out" (jack audio analog PC ke amplifier kabel). Ganti HANYA
# lewat ${DIR_BASE}/atur_output_audio.sh, jangan edit manual -- skrip
# itu juga menulis ulang /etc/asound.conf (routing ALSA sistem) supaya
# switching benar-benar berpindah, bukan cuma variabel di file ini.
AUDIO_OUTPUT="bluetooth"
AUDIO_DEVICE_LINEOUT="hw:0,0"
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

# PERBAIKAN: lock bersama dengan sambung_bt.sh supaya pairing manual ini
# tidak tabrakan dengan proses reconnect otomatis saat jadwal bel tiba.
echo "Menunggu akses adapter Bluetooth (siapa tahu sedang dipakai proses otomatis)..."
exec 202>/tmp/bt_op.lock
flock -w 30 202 || echo "[PERINGATAN] Timeout menunggu lock, lanjut saja."

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

# PERBAIKAN: lock bersama dengan pasang_bt.sh supaya dua proses tidak
# pernah memanggil bluetoothctl connect/pair secara bersamaan (mencegah
# "org.bluez.Error.InProgress: br-connection-busy").
exec 202>/tmp/bt_op.lock
if ! flock -w 20 202; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - Lock Bluetooth timeout (sedang dipakai proses lain), lanjut tanpa lock." >> "$LOG_FILE"
fi

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

# PERBAIKAN (V14): anti_putus.sh (loop 24 jam + silent keep-alive) DIHAPUS.
# BT-MAX terbukti tidak butuh keep-alive untuk tetap terhubung, dan proses
# aplay /dev/zero yang jalan terus-menerus justru jadi sumber race condition
# "Device or resource busy" saat mpv mau main. Reconnect sekarang cukup:
#   1. Sekali saat boot (bt-boot-connect.service, Type=oneshot) -- untuk
#      kasus setelah mati listrik/reboot.
#   2. On-demand oleh sambung_bt.sh, dipanggil putar_audio.sh tiap kali
#      ada bel yang akan diputar (sudah ada sejak V6, tidak berubah).

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

# Skrip lanjutkan_bel_senin.sh
cat <<'EOF' > ${DIR_BASE}/lanjutkan_bel_senin.sh
#!/bin/bash
DIR_SKRIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR_SKRIP}/sekolah.conf"

if [ ! -f "${DIR_FLAG}/pause_senin.flag" ]; then
    echo "Bel Senin memang sedang TIDAK di-pause. Tidak ada yang perlu dilanjutkan."
    exit 0
fi

rm -f "${DIR_FLAG}/pause_senin.flag"
echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - Bel jam pelajaran Senin dilanjutkan kembali (upacara selesai)." >> "$LOG_FILE"
echo "Bel hari Senin sudah dilanjutkan. Bel jam pelajaran berikutnya akan berbunyi normal sesuai jadwal."
EOF
chmod +x ${DIR_BASE}/lanjutkan_bel_senin.sh

# Skrip atur_output_audio.sh (VERSION 15 -- ROUTING ALSA DINAMIS)
# ---------------------------------------------------------------------
# PERBAIKAN UTAMA V15 dibanding versi lama:
#  1. Skrip ini SEKARANG MENULIS ULANG /etc/asound.conf setiap kali
#     output diganti, mengarahkan pcm.!default sistem langsung ke
#     bluealsa (mode bluetooth) atau dmix di atas card analog (mode
#     line_out). Versi lama HANYA mengganti variabel AUDIO_OUTPUT di
#     config tanpa pernah menyentuh routing ALSA -- makanya switching
#     dulu tidak benar-benar berpindah kalau ada proses lama nyantol.
#  2. AUTO-ELEVATE: skrip otomatis 'sudo' dirinya sendiri kalau
#     dijalankan user biasa, karena menulis /etc/asound.conf & memutus
#     Bluetooth butuh root.
#  3. CLEAN DISCONNECT: pindah ke line_out otomatis memutus Bluetooth
#     yang aktif. Pindah ke bluetooth otomatis sambung ulang.
#  4. UNMUTE HARDWARE: pindah ke line_out otomatis unmute penuh semua
#     channel analog (Master, Headphone, Speaker, Front, PCM).
#  5. Deteksi card analog PAKAI NAMA KARTU (bukan nomor index) supaya
#     tidak meleset kalau nomor kartu bergeser setelah reboot.
cat <<'EOF' > ${DIR_BASE}/atur_output_audio.sh
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
chmod +x ${DIR_BASE}/atur_output_audio.sh

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
    # PERBAIKAN: TUNGGU NTP sinkron dulu (maks 2 menit) sebelum
    # menghitung jadwal hari ini. Kalau tidak, jam sistem yang belum
    # sinkron (umum terjadi tepat setelah boot/mati listrik) bikin
    # perhitungan sleep meleset puluhan menit begitu NTP membetulkan
    # jam belakangan (sleep tidak ikut ter-koreksi, jadi target waktu
    # nyata jadi geser sebesar koreksi NTP tsb).
    TUNGGU_NTP=0
    while ! timedatectl show -p NTPSynchronized --value | grep -q "yes" && [ "$TUNGGU_NTP" -lt 120 ]; do
        sleep 5
        TUNGGU_NTP=$((TUNGGU_NTP + 5))
    done
    if ! timedatectl show -p NTPSynchronized --value | grep -q "yes"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - Jam sistem belum tersinkron NTP setelah menunggu ${TUNGGU_NTP} detik. Melanjutkan dengan jam sistem apa adanya (risiko jadwal meleset kalau NTP baru sinkron belakangan)." >> "$LOG_FILE"
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
                elif [ "$tunggu" -gt -1800 ]; then
                    # PERBAIKAN: kalau baru saja lewat (<30 menit, mis.
                    # daemon sempat restart karena mati listrik), tetap
                    # putar telat -- lebih baik telat daripada tidak
                    # bunyi sama sekali. Kalau sudah lewat jauh (>30
                    # menit), baru benar-benar dilewati di bawah.
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CATCHUP] - $nama baru lewat $(( -tunggu )) detik lalu, tetap diputar (telat)." >> "$LOG_FILE"
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

    # PERBAIKAN: lagu_pagi, indonesia_raya, & bel_dzuhur tetap tampil
    # sendiri-sendiri. HANYA bel custom yang ditambahkan lewat
    # kelola_harian.sh (mis. bel_0021_0915, dst) yang digabung jadi
    # satu baris ringkasan "Bel harian" supaya status tidak dipenuhi
    # puluhan baris kunci teknis satu-satu.
    for fitur in lagu_pagi indonesia_raya bel_dzuhur; do
        if [ -f "${DIR_FLAG}/${fitur}.off" ]; then
            printf "  %-15s : [ OFF ] NONAKTIF\n" "$fitur"
        else
            printf "  %-15s : [ ON  ] AKTIF NORMAL\n" "$fitur"
        fi
    done

    local total=0 aktif=0
    for k in $(daftar_kunci_harian); do
        case "$k" in
            lagu_pagi|indonesia_raya|bel_dzuhur) continue ;;
        esac
        [ -z "$k" ] && continue
        total=$((total+1))
        [ -f "${DIR_FLAG}/${k}.off" ] || aktif=$((aktif+1))
    done
    if [ "$total" -gt 0 ]; then
        if [ "$aktif" -eq "$total" ]; then
            printf "  %-15s : [ ON  ] AKTIF NORMAL (%d bel)\n" "Bel harian" "$total"
        elif [ "$aktif" -eq 0 ]; then
            printf "  %-15s : [ OFF ] NONAKTIF (%d bel)\n" "Bel harian" "$total"
        else
            printf "  %-15s : [ SEBAGIAN ] %d dari %d bel aktif\n" "Bel harian" "$aktif" "$total"
        fi
    fi

    for fitur in ujian tarhim_subuh tarhim_maghrib; do
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
systemctl is-active tahrim-daemon.service
echo -n "bt-boot-connect.service (oneshot, wajar kalau 'inactive' setelah sukses jalan sekali saat boot): "
systemctl is-failed bt-boot-connect.service >/dev/null 2>&1 && echo "GAGAL, cek: journalctl -u bt-boot-connect.service" || echo "OK"
echo -e "\n=== 10 LOG CRITICAL/WARNING TERAKHIR ==="
grep -E "CRITICAL|WARNING" "$LOG_FILE" 2>/dev/null | tail -10 || echo "(tidak ada / log belum ada)"
echo -e "\n=== KONEKSI BLUETOOTH ==="
bluetoothctl info "$MAC_SPEAKER" | grep -E "Connected|Paired|Trusted|Name"
echo -e "\n=== SINKRONISASI WAKTU ==="
timedatectl show -p NTPSynchronized --value
echo -e "\n=== SISA RUANG DISK ==="
df -h "${DIR_BASE}" | tail -1
echo -e "\n=== PEMULIHAN OTOMATIS (INTEGRITAS SISTEM) ==="
systemctl is-active integritas-sistem.timer 2>/dev/null || echo "TIDAK AKTIF (perlu dicek manual)"
if [ -f /var/backups/audio-school-system/.terakhir_pemulihan ]; then
    T=$(cat /var/backups/audio-school-system/.terakhir_pemulihan 2>/dev/null)
    if [[ "$T" =~ ^[0-9]+$ ]]; then
        echo "PERNAH memicu pemulihan otomatis pada: $(date -d @${T} '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    fi
fi

echo -e "\n=== STATUS BEL SENIN (UPACARA) ==="
if [ -f "${DIR_FLAG}/pause_senin.flag" ]; then
    PAUSE_SEJAK=$(cat "${DIR_FLAG}/pause_senin.flag" 2>/dev/null)
    if [[ "$PAUSE_SEJAK" =~ ^[0-9]+$ ]]; then
        MENIT_LALU=$(( ($(date +%s) - PAUSE_SEJAK) / 60 ))
        echo "SEDANG DI-PAUSE sejak ${MENIT_LALU} menit lalu (auto-batal di 90 menit). Jalankan lanjutkan_bel_senin.sh kalau upacara sudah selesai."
    else
        echo "SEDANG DI-PAUSE (waktu mulai tidak diketahui)."
    fi
else
    echo "Normal (tidak di-pause)."
fi

echo -e "\n=== OUTPUT AUDIO ==="
echo -n "Mode saat ini: ${AUDIO_OUTPUT}"
if [ "$AUDIO_OUTPUT" = "line_out" ]; then
    echo " (device: ${AUDIO_DEVICE_LINEOUT})"
else
    echo " (speaker: ${MAC_SPEAKER})"
fi

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
for SVC in tahrim-daemon.service; do
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

# PERBAIKAN: salin juga ke /var/backups (DI LUAR /home) supaya kalau
# /home hilang total, cek_integritas_sistem.sh masih punya jadwal
# harian/ujian terakhir untuk dipulihkan (bukan cuma default installer).
BACKUP_LUAR="/var/backups/audio-school-system"
if [ -d "$BACKUP_LUAR" ]; then
    cp -f "${DIR_BASE}/jadwal_harian.conf" "${BACKUP_LUAR}/jadwal_harian.conf.bak" 2>/dev/null
    cp -f "${DIR_BASE}/jadwal_ujian.conf" "${BACKUP_LUAR}/jadwal_ujian.conf.bak" 2>/dev/null
    cp -f "${DIR_BASE}/sekolah.conf" "${BACKUP_LUAR}/sekolah.conf.bak" 2>/dev/null
    ls "${DIR_BASE}/audio/" > "${BACKUP_LUAR}/daftar_file_audio.txt" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - Backup config tersalin ke ${BACKUP_LUAR} (di luar /home)." >> "$LOG_FILE"
fi
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
# PERBAIKAN (V14): anti-putus.service (loop 24 jam) diganti jadi
# bt-boot-connect.service -- Type=oneshot, jalan SEKALI saat boot untuk
# reconnect otomatis setelah mati listrik/reboot, lalu selesai (tidak
# ada proses yang jalan terus-menerus). Reconnect harian tetap ditangani
# sambung_bt.sh yang dipanggil putar_audio.sh sebelum tiap bel.
cat <<EOF > /etc/systemd/system/bt-boot-connect.service
[Unit]
Description=Reconnect Bluetooth Speaker Sekolah Saat Boot (sekali jalan)
After=bluetooth.target bluealsa.service network.target
Wants=bluealsa.service
OnFailure=otomasi-audio-alert@%n.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=${DIR_BASE}/sambung_bt.sh
User=${USER_SISTEM}
RemainAfterExit=no

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

# PERBAIKAN: cek_integritas_sistem.sh -- pemeriksa & pemulihan otomatis.
# SENGAJA disimpan di /usr/local/bin (BUKAN di ${DIR_BASE} / /home),
# supaya kalau /home/${USER_SISTEM} bersih total (crash filesystem,
# corrupt, dsb -- pernah terjadi nyata di lapangan), script penyelamat
# ini TIDAK IKUT HILANG dan tetap bisa jalan mengunduh ulang dari GitHub.
cat <<'INTEOF' > /usr/local/bin/cek_integritas_sistem.sh
#!/bin/bash
# Pemeriksa integritas + pemulihan otomatis sistem otomasi audio sekolah.
# Kalau semua file/folder kunci di /home/<user> masih ada -> tidak
# melakukan apapun (silent, cukup catat log ringan). Kalau MAYORITAS
# hilang (indikasi /home bersih total, bukan cuma 1 file kehapus tidak
# sengaja) -> otomatis unduh ulang dari GitHub & jalankan installer.

LOG_FILE="/var/log/otomasi_audio.log"
RECOVERY_CONF="/etc/audio-school-system/recovery.conf"
BACKUP_LUAR="/var/backups/audio-school-system"
LOCK_COOLDOWN="/var/backups/audio-school-system/.terakhir_pemulihan"
GITHUB_TARBALL="https://github.com/saroppudin/audio-school-system/archive/refs/heads/main.tar.gz"
COOLDOWN_DETIK=3600   # jangan coba pulihkan lagi kalau baru dicoba <1 jam lalu

if [ ! -f "$RECOVERY_CONF" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - cek_integritas_sistem: recovery.conf tidak ditemukan, lewati pemeriksaan." >> "$LOG_FILE"
    exit 0
fi
source "$RECOVERY_CONF"
DIR_BASE="/home/${USER_SISTEM}"

# Daftar penanda kunci -- kalau MAYORITAS ini hilang, anggap /home wipe total.
PENANDA=(
    "${DIR_BASE}/sekolah.conf"
    "${DIR_BASE}/putar_audio.sh"
    "${DIR_BASE}/cek_harian.sh"
    "${DIR_BASE}/cek_ujian.sh"
    "${DIR_BASE}/sambung_bt.sh"
    "${DIR_BASE}/pasang_bt.sh"
    "${DIR_BASE}/tahrim_daemon.sh"
    "${DIR_BASE}/mode_sekolah.sh"
    "${DIR_BASE}/kelola_harian.sh"
    "${DIR_BASE}/kelola_ujian.sh"
    "${DIR_BASE}/jadwal_harian.conf"
    "${DIR_BASE}/jadwal_ujian.conf"
    "${DIR_BASE}/audio"
)
HILANG=0
for p in "${PENANDA[@]}"; do
    [ -e "$p" ] || HILANG=$((HILANG + 1))
done
TOTAL=${#PENANDA[@]}

# Kurang dari 70% hilang -> anggap cuma kejadian kecil (mis. 1-2 file
# kehapus tidak sengaja), BUKAN wipe total. Catat CRITICAL saja, JANGAN
# auto-reinstall (supaya tidak menimpa kustomisasi yang masih ada).
AMBANG=$(( TOTAL * 70 / 100 ))
if [ "$HILANG" -lt "$AMBANG" ]; then
    if [ "$HILANG" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - cek_integritas_sistem: ${HILANG}/${TOTAL} penanda hilang (di bawah ambang wipe-total). Cek manual, TIDAK auto-reinstall." >> "$LOG_FILE"
    fi
    exit 0
fi

# --- Dari titik ini: dianggap /home wipe total ---

# Cooldown supaya tidak reinstall berulang-ulang kalau ada masalah terus.
if [ -f "$LOCK_COOLDOWN" ]; then
    TERAKHIR=$(cat "$LOCK_COOLDOWN" 2>/dev/null)
    SEKARANG=$(date +%s)
    if [[ "$TERAKHIR" =~ ^[0-9]+$ ]] && [ $(( SEKARANG - TERAKHIR )) -lt "$COOLDOWN_DETIK" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - cek_integritas_sistem: wipe total terdeteksi lagi tapi masih cooldown (< 1 jam sejak percobaan terakhir). Menunggu." >> "$LOG_FILE"
        exit 0
    fi
fi
mkdir -p "$BACKUP_LUAR"
date +%s > "$LOCK_COOLDOWN"

echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - cek_integritas_sistem: ${HILANG}/${TOTAL} penanda hilang -- WIPE TOTAL terdeteksi di ${DIR_BASE}. Memulai pemulihan otomatis dari GitHub..." >> "$LOG_FILE"

# Cek internet dulu
if ! curl -fsSL --max-time 10 -o /dev/null https://github.com; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - cek_integritas_sistem: tidak ada koneksi internet, pemulihan otomatis DIBATALKAN. Coba lagi nanti atau pulihkan manual." >> "$LOG_FILE"
    exit 1
fi

TMPDIR=$(mktemp -d)
if ! curl -fsSL "$GITHUB_TARBALL" -o "${TMPDIR}/repo.tar.gz"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - cek_integritas_sistem: gagal unduh dari GitHub. Pemulihan otomatis DIBATALKAN." >> "$LOG_FILE"
    rm -rf "$TMPDIR"
    exit 1
fi
tar -xzf "${TMPDIR}/repo.tar.gz" -C "$TMPDIR"
INSTALLER=$(find "$TMPDIR" -iname "Installer-bel-v*.sh" | head -1)
if [ -z "$INSTALLER" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - cek_integritas_sistem: Installer-bel-v*.sh tidak ditemukan di dalam repo yang diunduh. Pemulihan otomatis DIBATALKAN." >> "$LOG_FILE"
    rm -rf "$TMPDIR"
    exit 1
fi

# Suntikkan kembali config lama (dari /etc, yang tidak ikut hilang) ke
# installer yang baru diunduh, sebelum dijalankan.
sed -i "s/^USER_SISTEM=.*/USER_SISTEM=\"${USER_SISTEM}\"/" "$INSTALLER"
sed -i "s/^NAMA_SEKOLAH=.*/NAMA_SEKOLAH=\"${NAMA_SEKOLAH}\"/" "$INSTALLER"
sed -i "s/^GARIS_LINTANG=.*/GARIS_LINTANG=\"${GARIS_LINTANG}\"/" "$INSTALLER"
sed -i "s/^GARIS_BUJUR=.*/GARIS_BUJUR=\"${GARIS_BUJUR}\"/" "$INSTALLER"
sed -i "s/^MAC_SPEAKER=.*/MAC_SPEAKER=\"${MAC_SPEAKER}\"/" "$INSTALLER"

chmod +x "$INSTALLER"
echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - cek_integritas_sistem: menjalankan installer hasil unduhan (${INSTALLER})..." >> "$LOG_FILE"
bash "$INSTALLER" >> "$LOG_FILE" 2>&1
INSTALL_EXIT=$?

if [ "$INSTALL_EXIT" -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [CRITICAL] - cek_integritas_sistem: installer selesai dengan error (exit ${INSTALL_EXIT}). Perlu dicek manual." >> "$LOG_FILE"
    rm -rf "$TMPDIR"
    exit 1
fi

# Pulihkan jadwal harian/ujian TERAKHIR (bukan default installer) kalau
# ada salinannya di backup luar.
[ -f "${BACKUP_LUAR}/jadwal_harian.conf.bak" ] && cp -f "${BACKUP_LUAR}/jadwal_harian.conf.bak" "${DIR_BASE}/jadwal_harian.conf"
[ -f "${BACKUP_LUAR}/jadwal_ujian.conf.bak" ] && cp -f "${BACKUP_LUAR}/jadwal_ujian.conf.bak" "${DIR_BASE}/jadwal_ujian.conf"
chown "${USER_SISTEM}:${USER_SISTEM}" "${DIR_BASE}/jadwal_harian.conf" "${DIR_BASE}/jadwal_ujian.conf" 2>/dev/null

# PERBAIKAN: pulihkan juga file audio (.mp3) dari repo GitHub hasil
# unduhan, kalau memang disimpan di sana (folder audio/ di dalam repo).
# Cari folder "audio" di dalam hasil ekstrak repo (bukan cuma di root,
# karena struktur tarball GitHub selalu ada folder pembungkus di awal).
AUDIO_REPO=$(find "$TMPDIR" -type d -iname "audio" | head -1)
JUMLAH_AUDIO_DIPULIHKAN=0
if [ -n "$AUDIO_REPO" ]; then
    JUMLAH_AUDIO_DIPULIHKAN=$(find "$AUDIO_REPO" -iname "*.mp3" | wc -l)
    if [ "$JUMLAH_AUDIO_DIPULIHKAN" -gt 0 ]; then
        cp -f "$AUDIO_REPO"/*.mp3 "${DIR_BASE}/audio/" 2>/dev/null
        chown "${USER_SISTEM}:${USER_SISTEM}" "${DIR_BASE}"/audio/*.mp3 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] - cek_integritas_sistem: ${JUMLAH_AUDIO_DIPULIHKAN} file audio (.mp3) berhasil dipulihkan dari GitHub." >> "$LOG_FILE"
    fi
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - [SUKSES] - cek_integritas_sistem: PEMULIHAN OTOMATIS SELESAI. Software, jadwal, dan ${JUMLAH_AUDIO_DIPULIHKAN} file audio sudah dipulihkan." >> "$LOG_FILE"
if [ "$JUMLAH_AUDIO_DIPULIHKAN" -eq 0 ]; then
    if [ -f "${BACKUP_LUAR}/daftar_file_audio.txt" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - cek_integritas_sistem: TIDAK ADA file audio di repo GitHub yang diunduh. Cek daftar terakhir di ${BACKUP_LUAR}/daftar_file_audio.txt dan upload ulang manual ke ${DIR_BASE}/audio/." >> "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] - cek_integritas_sistem: TIDAK ADA file audio di repo GitHub, dan tidak ada daftar cadangan. Upload ulang manual semua file ke ${DIR_BASE}/audio/." >> "$LOG_FILE"
    fi
fi

rm -rf "$TMPDIR"
INTEOF
chmod +x /usr/local/bin/cek_integritas_sistem.sh

cat <<EOF > /etc/systemd/system/integritas-sistem.service
[Unit]
Description=Cek Integritas Sistem Otomasi Audio (auto-pulih dari GitHub kalau /home wipe total)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cek_integritas_sistem.sh
EOF

cat <<EOF > /etc/systemd/system/integritas-sistem.timer
[Unit]
Description=Jadwal cek integritas sistem (tiap 15 menit + saat boot)

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
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
jalankan "Aktifkan bt-boot-connect.service (oneshot, boot saja)" systemctl enable bt-boot-connect.service
jalankan "Jalankan bt-boot-connect.service sekarang (reconnect awal)" systemctl start bt-boot-connect.service
jalankan "Aktifkan tahrim-daemon.service" systemctl enable --now tahrim-daemon.service
jalankan "Aktifkan integritas-sistem.timer (cek tiap 15 menit + saat boot)" systemctl enable --now integritas-sistem.timer

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
# 8. TERAPKAN ROUTING ALSA AWAL (V15)
# --------------------------------------------------------------------
# PERBAIKAN (V15): panggil atur_output_audio.sh SEKALI di sini supaya
# /etc/asound.conf langsung ditulis dengan format routing dinamis yang
# benar sejak awal (mode default: bluetooth), bukan dibiarkan kosong/
# format lama sampai admin sadar harus menjalankannya manual. Kalau
# Bluetooth belum sempat konek (speaker belum di-pairing dsb), skrip ini
# akan gagal dengan pesan jelas -- TIDAK menghentikan instalasi -- dan
# admin tinggal menjalankan ulang manual setelah speaker siap.
echo "[8d/9] Menerapkan routing ALSA awal (/etc/asound.conf) lewat atur_output_audio.sh..."
if "${DIR_BASE}/atur_output_audio.sh" bluetooth; then
    echo "  [OK] /etc/asound.conf awal berhasil ditulis untuk mode Bluetooth."
else
    echo "  [PERINGATAN] Gagal menerapkan routing awal (kemungkinan Bluetooth belum"
    echo "  konek). /etc/asound.conf BELUM ada -- jalankan manual setelah speaker"
    echo "  siap: sudo ${DIR_BASE}/atur_output_audio.sh bluetooth"
fi

# --------------------------------------------------------------------
# 9. VERIFIKASI AKHIR & RINGKASAN INSTALASI
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
echo " Service aktif   : tahrim-daemon.service (nonstop), bt-boot-connect.service (oneshot saat boot)"
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
echo "  6. Ganti output audio : sudo ${DIR_BASE}/atur_output_audio.sh {bluetooth|line_out}"
echo "----------------------------------------------------"
echo " Catatan V14:"
echo "  - TIDAK ADA LAGI penjaga koneksi 24 jam. Reconnect otomatis"
echo "    terjadi: (1) sekali saat boot lewat bt-boot-connect.service,"
echo "    dan (2) on-demand oleh sambung_bt.sh sebelum tiap bel diputar."
echo "  - Watchdog cek_service.sh berjalan tiap 5 menit lewat cron"
echo "    untuk memastikan tahrim-daemon.service tetap hidup."
echo "----------------------------------------------------"
echo " Catatan V15 (switching output audio):"
echo "  - Ganti output cukup: sudo ${DIR_BASE}/atur_output_audio.sh bluetooth"
echo "    atau: sudo ${DIR_BASE}/atur_output_audio.sh line_out"
echo "  - Switching langsung berlaku instan untuk bel berikutnya (routing"
echo "    ALSA sistem ditulis ulang ke /etc/asound.conf, tanpa restart)."
echo "  - Pindah ke line_out otomatis memutus Bluetooth & unmute semua"
echo "    channel analog. Pindah ke bluetooth otomatis sambung ulang."
echo "  - Cek status kapan saja: ${DIR_BASE}/atur_output_audio.sh status"
echo "===================================================="
