# 🔒 Security & Hardening Guide

## Overview

Sistem Audio Sekolah ini didesain dengan security-first mindset, mengikuti Debian hardening best practices dan CIS Benchmarks.

---

## Security Features

### 1. **Sudoers Restrictions**

**File:** `/etc/sudoers.d/otomasi-audio`

```bash
# HANYA ini yang diizinkan:
lenovo ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluealsa
lenovo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
```

**Prinsip:** Principle of Least Privilege (PoLP)
- ❌ Tidak ada `NOPASSWD: ALL`
- ✅ Hanya perintah yang diperlukan
- ✅ Semua call di-log di syslog

### 2. **Systemd Service Hardening**

Setiap service punya:

```systemd
[Service]
PrivateTmp=yes                    # /tmp isolated per service
ProtectSystem=partial             # /usr, /etc readonly
NoNewPrivileges=yes               # Tidak bisa gain privileges
ProtectClock=yes                  # Tidak bisa set waktu
ProtectHostname=yes               # Tidak bisa set hostname
ProtectControlGroups=yes          # Protect cgroup
RestartSec=10                     # Delay sebelum restart
```

### 3. **Pre-Installation Validation**

✅ Validasi sebelum install:
- User existence check
- Coordinate format validation
- MAC address format validation
- Tool availability check
- Debian version check

### 4. **API Rate Limiting**

**Aladhan API:**
- Max 1 call per 12 jam (daily schedule)
- Fallback ke local database jika gagal
- Circuit breaker: stop calling jika 3x gagal beruntun
- Exponential backoff retry strategy

```bash
MAX_RETRIES=3
RETRY_DELAY=5  # seconds between retry

if [ "$RETRY_COUNT" -ge 3 ]; then
    # Use offline cache
fi
```

### 5. **Audit Logging**

Semua aksi dicatat di:
```bash
/var/log/otomasi_audio.log
```

Logged events:
- `[PLAY]` - Audio playback
- `[ERROR]` - Error conditions
- `[WARNING]` - Warning conditions
- `[SUCCESS]` - Key operations
- `[RECOVERY]` - Auto-recovery actions
- `[INFO]` - Informational messages

### 6. **File Permissions**

```bash
# Config file (sensitive)
-rw-r--r-- lenovo:lenovo /home/lenovo/sekolah.conf

# Scripts (executable only by lenovo)
-rwxr-x--- lenovo:lenovo /home/lenovo/*.sh

# Audio directory (read for audio group)
drwxr-x--- lenovo:audio /home/lenovo/audio/

# Log file (restricted)
-rw-rw---- lenovo:audio /var/log/otomasi_audio.log
```

### 7. **Error Propagation & Handling**

- ✅ Proper error checking pada setiap tahap
- ✅ Graceful degradation jika ada error
- ✅ Automatic recovery mechanism
- ✅ Circuit breaker pattern untuk API
- ✅ Fallback to cached data

---

## Pre-Deployment Security Checklist

- [ ] Disable root SSH login
  ```bash
  # In /etc/ssh/sshd_config
  PermitRootLogin no
  ```

- [ ] Use SSH keys only (no password auth)
  ```bash
  PasswordAuthentication no
  PubkeyAuthentication yes
  ```

- [ ] Enable UFW firewall
  ```bash
  sudo apt install ufw
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow ssh
  sudo ufw enable
  ```

- [ ] Enable automatic security updates
  ```bash
  sudo apt install unattended-upgrades
  sudo dpkg-reconfigure --priority=low unattended-upgrades
  ```

- [ ] Restrict /tmp, /var/tmp, /dev/shm
  ```bash
  # Add to /etc/fstab
  tmpfs /tmp tmpfs defaults,nosuid,nodev,noexec 0 0
  tmpfs /var/tmp tmpfs defaults,nosuid,nodev,noexec 0 0
  tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0
  ```

- [ ] Disable unnecessary services
  ```bash
  sudo systemctl disable avahi-daemon
  sudo systemctl disable cups
  ```

- [ ] Setup fail2ban
  ```bash
  sudo apt install fail2ban
  sudo systemctl enable --now fail2ban
  ```

---

## Post-Installation Security Verification

```bash
# Verify sudoers config
sudo visudo -c
sudo cat /etc/sudoers.d/otomasi-audio

# Check service isolation
sudo systemctl cat anti-putus.service | grep -E "Protect|Private"

# Monitor audit log
tail -f /var/log/otomasi_audio.log

# Check permissions
ls -la /home/lenovo/sekolah.conf
ls -la /var/log/otomasi_audio.log
```

---

## Known Vulnerabilities & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Bluetooth pairing spoofing | High | Device whitelist (MAC address fixed) |
| Log file tampering | Medium | File permissions (0660), audit trail |
| API downtime | Low | Local cache fallback (24+ hours) |
| Cron job hijacking | Medium | Restricted sudoers, file permissions |
| Network attack | Low | Firewall + fail2ban + rate limiting |

---

## Backup & Recovery Security

```bash
# Backups tersimpan di:
/home/lenovo/backup/config_*.tar.gz

# Retention:
- Keep: Max 10 backups
- Delete: Older than 30 days

# Backup konfigurasi sebelum modifikasi:
sudo cp /home/lenovo/sekolah.conf \
    /home/lenovo/sekolah.conf.backup
```

---

## Security Update Procedure

```bash
# 1. Check available updates
sudo apt update
sudo apt list --upgradable

# 2. Test update (recommended)
sudo apt upgrade -s

# 3. Apply updates
sudo apt upgrade

# 4. Verify no broken dependencies
sudo apt check

# 5. Check if services still running
systemctl status anti-putus.service
systemctl status tahrim-daemon.service
```

---

## References

- [Debian Security Wiki](https://wiki.debian.org/Security)
- [CIS Debian Linux Benchmark](https://www.cisecurity.org/benchmark/debian_linux)
- [Systemd Security](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)

---

**Last Updated:** 2025-07-05  
**Security Level:** Production Grade  
**Audit Status:** Manual review recommended annually
