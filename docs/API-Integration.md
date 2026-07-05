# 🌐 Aladhan API Integration

## Overview

Sistem ini menggunakan **Aladhan Prayer Times API** untuk fetch jadwal sholat otomatis.

---

## API Details

### Endpoint
```
GET https://api.aladhan.com/v1/timings/{DATE}?latitude={LAT}&longitude={LNG}&method=2
```

### Parameters
- `DATE`: Format DD-MM-YYYY
- `latitude`: Koordinat lintang (negative untuk selatan)
- `longitude`: Koordinat bujur (positive untuk timur)
- `method`: 2 = ISNA (North America)

### Example Request
```bash
curl -s "https://api.aladhan.com/v1/timings/05-07-2025?latitude=-7.7134&longitude=109.9961&method=2" | jq '.data.timings | {Fajr, Maghrib}'
```

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

---

## Rate Limiting

- **Limit:** ~1000 requests/month per IP
- **Our usage:** 1 request/12 hours (daily)
- **Status:** Well within limits ✅

---

## Offline Fallback

Jika API error:
1. System mencoba retry (max 3x)
2. Gunakan local cache (`/home/lenovo/jadwal_sholat.json`)
3. Cache berlaku hingga 24+ jam
4. No manual intervention needed

---

## Timezone Considerations

Coordinates already tuned untuk **Indonesia/Jakarta (WIB)**

API returns times in:**
- Local timezone (WIB)
- 24-hour format

---

## Testing API

```bash
# Test API directly
curl -s "https://api.aladhan.com/v1/timings/05-07-2025?latitude=-7.7134&longitude=109.9961&method=2" | jq '.'

# Check if daemon can reach API
ssh lenovo@server
curl -s https://api.aladhan.com/v1/timings/05-07-2025?latitude=-7.7134&longitude=109.9961&method=2 | jq '.data.timings.Fajr'
```

---

**Last Updated:** 2025-07-05  
**API Status:** ✅ Active
