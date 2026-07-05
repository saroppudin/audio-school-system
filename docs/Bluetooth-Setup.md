# 🎙️ Bluetooth Setup & Pairing Guide

## Pre-Pairing Checklist

- [ ] Bluetooth adapter installed & working
- [ ] Speaker powered on
- [ ] Speaker in pairing mode (usually hold button 3-5 seconds)
- [ ] No previous pairing issues

---

## Step-by-Step Pairing

### 1. Verify Bluetooth Adapter

```bash
# List adapters
bluetoothctl list

# Expected output:
# Controller AA:BB:CC:DD:EE:FF	hostname [default]

# If no output, check:
sudo systemctl status bluetooth
```

### 2. Scan for Devices

```bash
bluetoothctl scan on

# Wait for speaker name to appear:
# [NEW] Device XX:XX:XX:XX:XX:XX SpeakerName
```

### 3. Pair Device

```bash
bluetoothctl pair XX:XX:XX:XX:XX:XX

# Expected output:
# [CHR] Pairing successful
```

### 4. Trust Device

```bash
bluetoothctl trust XX:XX:XX:XX:XX:XX

# Expected output:
# [CHR] Device XX:XX:XX:XX:XX:XX trusted
```

### 5. Connect Device

```bash
bluetoothctl connect XX:XX:XX:XX:XX:XX

# Expected output:
# Connection successful
```

### 6. Verify Connection

```bash
bluetoothctl info XX:XX:XX:XX:XX:XX

# Should show:
# Connected: yes
```

---

## Troubleshooting

### Speaker not appearing in scan
- Power off speaker, wait 10 seconds, power on
- Move closer to server (reduce interference)
- Put speaker in pairing mode again

### Pairing fails
- Try removing: `bluetoothctl remove XX:XX:XX:XX:XX:XX`
- Restart Bluetooth: `sudo systemctl restart bluetooth`
- Try pairing again

### Connected but no audio
- Check BlueALSA: `arecord -D bluealsa --list-devices`
- Check volume: `amixer -D bluealsa sget Master`
- Test: `mpv --audio-device=alsa/bluealsa test.mp3`

---

## Saving MAC Address

**Important:** Save your speaker's MAC address!

You'll need it for: `MAC_SPEAKER` in `sekolah.conf`

---

**Last Updated:** 2025-07-05
