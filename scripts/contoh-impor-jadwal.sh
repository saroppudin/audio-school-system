#!/bin/bash
# Jadwal bel harian - dikelompokkan berdasarkan pola HARI AKTIF, diurutkan
# jam menaik di tiap kelompok, supaya mudah dicek per kelompok hari.
#
# CATATAN: kalau kamu sudah pernah menjalankan versi SEBELUMNYA dari file
# ini (versi urut No.1-40), jalankan dulu:
#   /home/lenovo/kelola_harian.sh kosongkan
# sebelum menjalankan file ini, supaya tidak ada kunci lama yang bentrok.

DIR="/home/lenovo"

# =====================================================================
# KELOMPOK 1: SETIAP HARI SENIN-SABTU (1-6)                — 1 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 06:50 1-6 bel_0078_0650 0078.mp3

# =====================================================================
# KELOMPOK 2: SENIN SAJA (1)                                — 14 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 07:45 1 bel_0017_0745  0017.mp3
$DIR/kelola_harian.sh tambah 08:10 1 bel_0018_0810  0018.mp3
$DIR/kelola_harian.sh tambah 08:35 1 bel_0019_0835  0019.mp3
$DIR/kelola_harian.sh tambah 09:00 1 bel_0020_0900  0020.mp3
$DIR/kelola_harian.sh tambah 09:25 1 bel_0021_0925  0021.mp3
$DIR/kelola_harian.sh tambah 09:50 1 bel_0022_0950  0022.mp3
$DIR/kelola_harian.sh tambah 10:15 1 bel_0008_1015a 0008.mp3
$DIR/kelola_harian.sh tambah 10:30 1 bel_0013_1030a 0013.mp3
$DIR/kelola_harian.sh tambah 11:00 1 bel_0024_1100a 0024.mp3
$DIR/kelola_harian.sh tambah 11:30 1 bel_0025_1130a 0025.mp3
$DIR/kelola_harian.sh tambah 12:00 1 bel_0009_1200a 0009.mp3
$DIR/kelola_harian.sh tambah 12:30 1 bel_0013_1230a 0013.mp3
$DIR/kelola_harian.sh tambah 13:00 1 bel_0027_1300a 0027.mp3
$DIR/kelola_harian.sh tambah 13:30 1 bel_0028_1330a 0028.mp3

# =====================================================================
# KELOMPOK 3: SELASA-KAMIS & SABTU (2-4,6)                  — 13 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 07:15 2-4,6 bel_0017_0715  0017.mp3
$DIR/kelola_harian.sh tambah 07:45 2-4,6 bel_0018_0745  0018.mp3
$DIR/kelola_harian.sh tambah 08:15 2-4,6 bel_0019_0815  0019.mp3
$DIR/kelola_harian.sh tambah 08:45 2-4,6 bel_0020_0845  0020.mp3
$DIR/kelola_harian.sh tambah 09:15 2-4,6 bel_0021_0915  0021.mp3
$DIR/kelola_harian.sh tambah 09:45 2-4,6 bel_0022_0945  0022.mp3
$DIR/kelola_harian.sh tambah 10:15 2-4,6 bel_0008_1015b 0008.mp3
$DIR/kelola_harian.sh tambah 10:30 2-4,6 bel_0013_1030b 0013.mp3
$DIR/kelola_harian.sh tambah 11:00 2-4,6 bel_0024_1100b 0024.mp3
$DIR/kelola_harian.sh tambah 11:30 2-4,6 bel_0025_1130b 0025.mp3
$DIR/kelola_harian.sh tambah 12:00 2-4,6 bel_0009_1200b 0009.mp3
$DIR/kelola_harian.sh tambah 12:30 2-4,6 bel_0013_1230b 0013.mp3
$DIR/kelola_harian.sh tambah 13:00 2-4,6 bel_0027_1300b 0027.mp3

# =====================================================================
# KELOMPOK 4: SELASA-KAMIS, TANPA SABTU (2-4)               — 1 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 13:30 2-4 bel_0028_1330b 0028.mp3

# =====================================================================
# KELOMPOK 5: SENIN-KAMIS, TANPA JUMAT & SABTU (1-4)        — 1 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 14:00 1-4 bel_0062_1400 0062.mp3

# =====================================================================
# KELOMPOK 6: JUMAT SAJA (5)                                — 8 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 07:30 5 bel_0018_0730 0018.mp3
$DIR/kelola_harian.sh tambah 08:05 5 bel_0019_0805 0019.mp3
$DIR/kelola_harian.sh tambah 08:40 5 bel_0020_0840 0020.mp3
$DIR/kelola_harian.sh tambah 09:10 5 bel_0021_0910 0021.mp3
$DIR/kelola_harian.sh tambah 09:45 5 bel_0008_0945 0008.mp3
$DIR/kelola_harian.sh tambah 10:00 5 bel_0013_1000 0013.mp3
$DIR/kelola_harian.sh tambah 10:30 5 bel_0023_1030 0023.mp3
$DIR/kelola_harian.sh tambah 11:00 5 bel_0062_1100 0062.mp3

# =====================================================================
# KELOMPOK 7: SABTU SAJA (6)                                — 1 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 13:30 6 bel_0062_1330 0062.mp3

# =====================================================================
# KELOMPOK 8: SENIN,SELASA,RABU,KAMIS,SABTU (1-4,6)         — 1 entri
# =====================================================================
$DIR/kelola_harian.sh tambah 12:20 1-4,6 bel_0071_1220 0071.mp3
