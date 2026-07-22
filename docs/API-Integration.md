# 🌐 Aladhan API Integration

## Overview

Sistem ini menggunakan **Aladhan Prayer Times API** untuk fetch jadwal sholat otomatis, dijalankan oleh `tahrim_daemon.sh` (service `tahrim-daemon.service`, nonstop).

---

## API Details

### Endpoint
```
GET https://api.aladhan.com/v1/timings/{DATE}?latitude={LAT}&longitude={LNG}&method=2
```

### Parameters
- `DATE`: Format DD-MM-YYYY
- `latitude`: Koordinat lintang (negatif untuk selatan)
- `longitude`: Koordinat bujur (positif untuk timur)
- `method`: `2` = ISNA (Islamic Society of North America) — ini nilai yang dipakai kode, bukan sekadar contoh

### Contoh Panggilan Nyata (dari `tahrim_daemon.sh`)
```bash
curl -4 -s --connect-timeout 10 --max-time 20 --retry 3 --retry-delay 5 \
  "https://api.aladhan.com/v1/timings/05-07-2025?latitude=-7.7134&longitude=109.9961&method=2"
```
Perhatikan: kode sesungguhnya sudah menambahkan `--connect-timeout 10 --max-time 20`
(supaya daemon tidak nyantol lama kalau internet lambat/mati) dan
`--retry 3 --retry-delay 5` (retry otomatis bawaan `curl`, bukan logika retry
manual di level skrip).

### Response Structure
```json
{
  "code": 200,
  "status": "OK",
  "data": {
    "timings": {
      "Fajr": "04:39",
      "Maghrib": "18:22",
      ...
    }
  }
}
```

Kode mengambil `data.timings.Fajr` dan `data.timings.Maghrib` lewat `jq`, lalu
memvalidasi formatnya dengan regex `^[0-2][0-9]:[0-5][0-9]$` sebelum dipakai
menghitung waktu tarhim — respons yang tidak sesuai format ini akan diabaikan
(bukan menyebabkan crash).

---

## Rate Limiting

> ⚠️ **Koreksi (diverifikasi ulang):** dokumentasi versi sebelumnya
> menyebut "~1000 requests/month" — klaim ini **tidak terverifikasi** dan
> kemungkinan sudah usang. Berdasarkan forum komunitas resmi Islamic
> Network (penyedia Aladhan API) per pengecekan terakhir, rate limit yang
> berlaku adalah **~12 request/detik per IP**, dan dokumentasi API mereka
> menyatakan tidak ada limit ketat bulanan — hanya meminta pengguna
> menghindari penggunaan berlebihan dan disarankan melakukan caching.

- **Limit aktual (per detik):** ~12 request/detik/IP (jauh di atas kebutuhan kita)
- **Pemakaian sistem ini:** **1 kali per hari**, sekitar pukul 00:02 waktu
  server (daemon `sleep` sampai tengah malam setelah selesai memproses
  tarhim hari itu, lalu mengambil jadwal untuk hari berikutnya)
- **Status:** jauh di bawah limit ✅ — tapi tetap pakai caching lokal
  (lihat bagian Offline Fallback) sesuai anjuran resmi mereka

---

## Offline Fallback

Kalau API gagal/timeout:
1. `curl` sudah retry otomatis 3x (jeda 5 detik antar percobaan) sebelum menyerah
2. Kalau tetap gagal, daemon jatuh ke cache lokal (`/home/lenovo/jadwal_sholat.json`)
3. Cache dipakai apa adanya (jadwal hari sebelumnya) — cukup akurat karena
   waktu sholat bergeser sangat sedikit dari hari ke hari
4. Kalau cache pun tidak ada (mis. instalasi baru, belum pernah online sama
   sekali), dicatat `[CRITICAL] - Tidak ada data jadwal sholat sama sekali`
   dan tarhim hari itu tidak diputar
5. Tidak perlu intervensi manual selama cache masih ada

---

## Timezone Considerations

Koordinat contoh sudah disesuaikan untuk **Indonesia/Jakarta (WIB)**.

- API mengembalikan waktu dalam **format 24 jam**
- Perhitungan waktu tarhim (`date -d "${JAM} 20 minutes ago"`) memakai
  **timezone sistem lokal** (`timedatectl`) — pastikan `timedatectl
  set-timezone Asia/Jakarta` (atau zona yang sesuai) sudah benar, bukan
  UTC default
- Daemon sengaja **menunggu NTP sinkron** (maks 2 menit) setelah boot
  sebelum menghitung jadwal, supaya jam yang belum sinkron pasca-boot
  tidak membuat perhitungan meleset

---

## Testing API

```bash
# Test API langsung
curl -s "https://api.aladhan.com/v1/timings/$(date +%d-%m-%Y)?latitude=-7.7134&longitude=109.9961&method=2" | jq '.'

# Cek apakah daemon di server bisa menjangkau API
ssh lenovo@server
curl -s "https://api.aladhan.com/v1/timings/$(date +%d-%m-%Y)?latitude=-7.7134&longitude=109.9961&method=2" | jq '.data.timings.Fajr'

# Cek isi cache lokal (fallback) saat ini
cat /home/lenovo/jadwal_sholat.json | jq '.data.timings.{Fajr, Maghrib}' 2>/dev/null \
  || cat /home/lenovo/jadwal_sholat.json | head -c 500

# Paksa daemon fetch ulang sekarang (restart daemon)
sudo systemctl restart tahrim-daemon.service
tail -f /var/log/otomasi_audio.log
```

---

## Referensi

- [AlAdhan API — Islamic Network Community (rate limit)](https://community.islamic.network/d/2-is-there-a-rate-limit-on-the-apis)
- [AlAdhan API Documentation (Gist)](https://gist.github.com/Zxce3/e1cc0363de3694e04bb440a5c8d57726)

---

**API Status:** ✅ Active (per pengecekan terakhir dokumentasi ini)
