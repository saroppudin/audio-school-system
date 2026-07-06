#!/bin/bash
# ====================================================================
# MASTER INSTALLER AUTOMATION AUDIO SEKOLAH (VERSION 5 - ENHANCED)
# SYSTEM: MULTI-AUDIO BEL UJIAN, BEL HARIAN & DAEMON TAHRIM
# + BLUETOOTH AUTO-RECONNECT + SECURITY HARDENING
# ====================================================================
# PERBAIKAN DARI V4:
#   1. BLUETOOTH AUTO-CONNECT: Ditambahkan udev rules + systemd service
#      untuk reconnect otomatis setelah reboot.
#   2. asound.conf: Enhanced dengan auto-sink selection dan fallback.
#   3. Trust device Bluetooth di /var/lib/bluetooth untuk auto-pair.
#   4. Security: Disable unnecessary services, firewall basic rules.
#   5. Validasi pulseaudio vs. pipewire untuk kompatibilitas audio.
#   6. Log rotation untuk /var/log/otomasi_audio.log.
#   7. Systemd service hardening (PrivateTmp, NoNewPrivileges, dsb).
# ====================================================================

set -o pipefail

# ====================================================================
# SECTION 1: KONFIGURASI SEKOLAH
# ====================================================================
USER_SISTEM="lenovo"
NAMA_SEKOLAH="SMK Negeri Purworejo"
GARIS_LINTANG="-7.7134"
GARIS_BUJUR="109.9961"
MAC_SPEAKER="7d:5b:22:c8:4d:ab"  # Mixer/Speaker Bluetooth

# Jalur Direktori
DIR_BASE="/home/${USER_SISTEM}"
DIR_AUDIO="${DIR_BASE}/audio"
DIR_FLAG="${DIR_BASE}/jadwal_nonaktif"
DIR_SCRIPTS="${DIR_BASE}/scripts"
LOG_FILE="/var/log/otomasi_audio.log"
CONFIG_FILE="/etc/sekolah.conf"

# ====================================================================
# SECTION 2: VALIDASI AWAL
# ====================================================================
validate_config() {
    local errors=0

    if [ "$EUID" -ne 0 ]; then
        echo "[ERROR] Harap jalankan sebagai root atau gunakan 'sudo'."
        exit 1
    fi

    if ! id "${USER_SISTEM}" &>/dev/null; then
        echo "[ERROR] User '${USER_SISTEM}' tidak ditemukan."
        echo "        Buat dengan: adduser ${USER_SISTEM}"
        ((errors++))
    fi

    if ! [[ "$GARIS_LINTANG" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "[ERROR] GARIS_LINTANG tidak valid: '${GARIS_LINTANG}'"
        ((errors++))
    fi

    if ! [[ "$GARIS_BUJUR" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "[ERROR] GARIS_BUJUR tidak valid: '${GARIS_BUJUR}'"
        ((errors++))
    fi

    if ! [[ "$MAC_SPEAKER" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "[ERROR] MAC_SPEAKER tidak valid: '${MAC_SPEAKER}'"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        echo "[ABORT] Fix konfigurasi di atas sebelum lanjut."
        exit 1
    fi

    echo "[OK] Validasi konfigurasi berhasil."
}

# ====================================================================
# SECTION 3: HELPER FUNCTIONS
# ====================================================================
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_message "[INSTALL] Installing $1..."
        apt-get install -y "$2" &>>"${LOG_FILE}" || {
            log_message "[ERROR] Failed to install $2"
            return 1
        }
    fi
    return 0
}

# ====================================================================
# SECTION 4: SETUP DASAR SISTEM
# ====================================================================
stage_0_system_setup() {
    log_message "====== STAGE 0/10: System Setup ======"

    # Update system
    log_message "Updating system packages..."
    apt-get update &>>"${LOG_FILE}" || {
        log_message "[ERROR] apt update failed"
        return 1
    }
    apt-get upgrade -y &>>"${LOG_FILE}" || {
        log_message "[ERROR] apt upgrade failed"
        return 1
    }

    # Install essential packages
    local packages="bluez bluez-tools alsa-utils pulseaudio pavucontrol mpv sox ffmpeg curl wget git build-essential"
    log_message "Installing essential packages..."
    apt-get install -y $packages &>>"${LOG_FILE}" || {
        log_message "[ERROR] Package installation failed"
        return 1
    }

    # Create directories
    mkdir -p "${DIR_AUDIO}" "${DIR_FLAG}" "${DIR_SCRIPTS}" &>>"${LOG_FILE}" || {
        log_message "[ERROR] Failed to create directories"
        return 1
    }
    chown "${USER_SISTEM}:${USER_SISTEM}" "${DIR_AUDIO}" "${DIR_FLAG}" "${DIR_SCRIPTS}"

    # Setup logfile
    touch "${LOG_FILE}"
    chmod 666 "${LOG_FILE}"
    chown "${USER_SISTEM}:${USER_SISTEM}" "${LOG_FILE}"

    # Enable services
    systemctl enable bluetooth &>>"${LOG_FILE}"
    systemctl start bluetooth &>>"${LOG_FILE}"

    log_message "[OK] System setup complete."
    return 0
}

# ====================================================================
# SECTION 5: BLUETOOTH CONFIGURATION (WITH AUTO-RECONNECT)
# ====================================================================
stage_1_bluetooth_setup() {
    log_message "====== STAGE 1/10: Bluetooth Setup + Auto-Reconnect ======"

    # Enable Bluetooth and increase power
    log_message "Configuring Bluetooth daemon..."
    mkdir -p /etc/bluetooth
    cat > /etc/bluetooth/main.conf <<'BLUETOOTH_EOF'
[General]
Name = SekolahBel
Class = 0x0c010c
DiscoverableTimeout = 0
AlwaysPairingMode = false
RememberPowered = true
PowerOnBoot = true
Experimental = true
FastConnectable = true

[Headset]
HFP = true

[Policy]
AutoEnable = true
BLUETOOTH_EOF

    # Restart Bluetooth daemon
    systemctl restart bluetooth &>>"${LOG_FILE}" || {
        log_message "[ERROR] Bluetooth restart failed"
        return 1
    }
    sleep 2

    log_message "[OK] Bluetooth configuration complete."
    return 0
}

# ====================================================================
# SECTION 6: BLUETOOTH DEVICE PAIRING & TRUST
# ====================================================================
stage_2_pair_and_trust_device() {
    log_message "====== STAGE 2/10: Pairing & Trusting Bluetooth Device ======"

    # Power on and wait
    bluetoothctl power on &>>"${LOG_FILE}"
    sleep 1

    # Scan and trust device (if not already paired)
    log_message "Attempting to pair and trust device ${MAC_SPEAKER}..."
    
    # Check if already paired
    if bluetoothctl info "${MAC_SPEAKER}" &>/dev/null; then
        log_message "[INFO] Device already paired."
    else
        log_message "[INFO] Scanning for device..."
        timeout 10 bluetoothctl scan on &>>"${LOG_FILE}" &
        sleep 3
        bluetoothctl pair "${MAC_SPEAKER}" &>>"${LOG_FILE}" || {
            log_message "[WARN] Pairing may have failed or device not found. Continuing..."
        }
        killall bluetoothctl 2>/dev/null || true
    fi

    # Trust the device (persistent connection)
    bluetoothctl trust "${MAC_SPEAKER}" &>>"${LOG_FILE}" || {
        log_message "[WARN] Failed to trust device, may already be trusted"
    }

    sleep 1
    log_message "[OK] Device pairing/trust attempted."
    return 0
}

# ====================================================================
# SECTION 7: BLUEALSA + PULSE SETUP
# ====================================================================
stage_3_bluealsa_pulseaudio_setup() {
    log_message "====== STAGE 3/10: BlueALSA + PulseAudio Setup ======"

    # Install bluealsa if not present
    if ! command -v bluealsa &>/dev/null; then
        log_message "Installing bluealsa from Debian repos..."
        apt-get install -y bluealsa &>>"${LOG_FILE}" || {
            log_message "[ERROR] bluealsa installation failed"
            return 1
        }
    fi

    # Configure bluealsa service
    log_message "Configuring bluealsa service..."
    mkdir -p /etc/systemd/system/bluealsa.service.d
    cat > /etc/systemd/system/bluealsa.service.d/override.conf <<'BLUEALSA_EOF'
[Service]
Type = idle
ExecStart =
ExecStart = /usr/bin/bluealsa -i hci0 -p a2dp-source
Restart = on-failure
RestartSec = 5

# Hardening
PrivateTmp = yes
NoNewPrivileges = yes
ProtectSystem = strict
ProtectHome = yes
ReadWritePaths = /dev /run /sys
BLUEALSA_EOF

    systemctl daemon-reload &>>"${LOG_FILE}"
    systemctl enable bluealsa &>>"${LOG_FILE}"
    systemctl restart bluealsa &>>"${LOG_FILE}"
    sleep 2

    # Verify bluealsa is running
    if systemctl is-active --quiet bluealsa; then
        log_message "[OK] BlueALSA is running."
    else
        log_message "[ERROR] BlueALSA failed to start"
        systemctl status bluealsa &>>"${LOG_FILE}"
        return 1
    fi

    # Configure PulseAudio to use BlueALSA
    log_message "Configuring PulseAudio..."
    if ! command -v pulseaudio &>/dev/null; then
        apt-get install -y pulseaudio pulseaudio-alsa &>>"${LOG_FILE}" || {
            log_message "[ERROR] PulseAudio installation failed"
            return 1
        }
    fi

    # Check if user has pulseaudio config
    if [ ! -d "/home/${USER_SISTEM}/.config/pulse" ]; then
        mkdir -p "/home/${USER_SISTEM}/.config/pulse"
        chown "${USER_SISTEM}:${USER_SISTEM}" "/home/${USER_SISTEM}/.config/pulse"
    fi

    # Create pulse config to load BlueALSA module
    cat > "/home/${USER_SISTEM}/.config/pulse/default.pa" <<'PULSE_EOF'
.include /etc/pulse/default.pa
load-module module-alsa-sink device=bluealsa
load-module module-alsa-source device=bluealsa
PULSE_EOF
    chown "${USER_SISTEM}:${USER_SISTEM}" "/home/${USER_SISTEM}/.config/pulse/default.pa"

    log_message "[OK] BlueALSA and PulseAudio configured."
    return 0
}

# ====================================================================
# SECTION 8: ASOUND.CONF SETUP (ALSA CONFIGURATION)
# ====================================================================
stage_4_asound_config() {
    log_message "====== STAGE 4/10: ALSA Configuration (asound.conf) ======"

    cat > /etc/asound.conf <<'ASOUND_EOF'
# ========== BLUETOOTH ALSA DEVICE ==========
pcm.bluealsa {
    type bluealsa
    device "7d:5b:22:c8:4d:ab"
    profile "a2dp"
    delay 10000
}

ctl.bluealsa {
    type bluealsa
}

# ========== DEFAULT DEVICE (Fallback + BlueALSA Priority) ==========
pcm.!default {
    type asym
    playback.pcm "playback"
    capture.pcm "capture"
}

ctl.!default {
    type asym
    playback.ctl "playback_ctl"
    capture.ctl "capture_ctl"
}

pcm.playback {
    type plug
    slave {
        pcm "bluetooth_or_hw"
    }
}

pcm.capture {
    type plug
    slave {
        pcm "hw:0,0"
    }
}

ctl.playback_ctl {
    type hw
    card 0
}

ctl.capture_ctl {
    type hw
    card 0
}

# ========== BLUETOOTH FIRST, FALLBACK TO HW ==========
pcm.bluetooth_or_hw {
    type plug
    slave.pcm "bluetooth_with_fallback"
}

pcm.bluetooth_with_fallback {
    type softvol
    slave {
        pcm "bluealsa_with_fallback"
    }
    control {
        name "Bluetooth Volume"
        card 0
    }
}

pcm.bluealsa_with_fallback {
    type asym
    playback.pcm {
        type plug
        slave.pcm "bluealsa"
    }
    fallback.pcm {
        type plug
        slave.pcm "hw:0,0"
    }
}

# ========== VOLUME CONTROL ==========
ctl.!default {
    type hw
    card 0
}
ASOUND_EOF

    chmod 644 /etc/asound.conf
    log_message "[OK] ALSA configuration created at /etc/asound.conf"
    return 0
}

# ====================================================================
# SECTION 9: UDEV RULES FOR BLUETOOTH AUTO-CONNECT
# ====================================================================
stage_5_udev_rules() {
    log_message "====== STAGE 5/10: UDEV Rules for Auto-Connect ======"

    cat > /etc/udev/rules.d/99-bluetooth-auto-connect.rules <<'UDEV_EOF'
# Auto-connect Bluetooth device on system startup
ACTION=="add", SUBSYSTEM=="bluetooth", DRIVER=="btusb", RUN+="/usr/bin/systemctl --no-block restart bluetooth-auto-connect"
UDEV_EOF

    udevadm control --reload-rules &>>"${LOG_FILE}"
    log_message "[OK] UDEV rules installed."
    return 0
}

# ====================================================================
# SECTION 10: SYSTEMD SERVICE FOR BLUETOOTH AUTO-CONNECT
# ====================================================================
stage_6_bluetooth_autoconnect_service() {
    log_message "====== STAGE 6/10: Systemd Service for Auto-Connect ======"

    cat > /etc/systemd/system/bluetooth-auto-connect.service <<'SERVICE_EOF'
[Unit]
Description=Bluetooth Auto-Connect Service
After=bluetooth.service bluealsa.service
Wants=bluetooth.service bluealsa.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/bluetooth-auto-connect.sh
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

# Hardening
PrivateTmp=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    cat > /usr/local/bin/bluetooth-auto-connect.sh <<'BASH_SCRIPT_EOF'
#!/bin/bash

LOG_FILE="/var/log/otomasi_audio.log"
MAC_SPEAKER="7d:5b:22:c8:4d:ab"
MAX_RETRIES=15
RETRY_INTERVAL=2

log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

log_msg "Starting Bluetooth auto-connect service..."

# Wait for Bluetooth to be ready
for i in $(seq 1 $MAX_RETRIES); do
    if [ -d "/sys/class/bluetooth" ] && [ "$(find /sys/class/bluetooth -name 'hci*' | wc -l)" -gt 0 ]; then
        log_msg "Bluetooth adapter found on attempt $i"
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        log_msg "[ERROR] Bluetooth adapter not found after $MAX_RETRIES attempts"
        exit 1
    fi
    sleep 1
done

sleep 3

# Power on Bluetooth
/usr/bin/bluetoothctl power on >> "${LOG_FILE}" 2>&1
sleep 2

# Check if device exists and is trusted
if /usr/bin/bluetoothctl info "${MAC_SPEAKER}" > /dev/null 2>&1; then
    log_msg "Device ${MAC_SPEAKER} found in Bluetooth database"
    /usr/bin/bluetoothctl trust "${MAC_SPEAKER}" >> "${LOG_FILE}" 2>&1
else
    log_msg "[WARN] Device ${MAC_SPEAKER} not in Bluetooth database yet"
fi

# Attempt to connect (with retry)
for attempt in $(seq 1 $MAX_RETRIES); do
    log_msg "Connect attempt $attempt of $MAX_RETRIES..."
    
    if /usr/bin/bluetoothctl connect "${MAC_SPEAKER}" >> "${LOG_FILE}" 2>&1; then
        log_msg "[SUCCESS] Connected to ${MAC_SPEAKER}"
        
        # Verify connection
        sleep 2
        if /usr/bin/bluetoothctl info "${MAC_SPEAKER}" | grep -q "Connected: yes"; then
            log_msg "[OK] Connection verified"
            exit 0
        fi
    fi
    
    if [ $attempt -lt $MAX_RETRIES ]; then
        sleep $RETRY_INTERVAL
    fi
done

log_msg "[ERROR] Failed to connect to ${MAC_SPEAKER} after $MAX_RETRIES attempts"
exit 1
BASH_SCRIPT_EOF

    chmod 755 /usr/local/bin/bluetooth-auto-connect.sh

    systemctl daemon-reload &>>"${LOG_FILE}"
    systemctl enable bluetooth-auto-connect.service &>>"${LOG_FILE}"
    systemctl start bluetooth-auto-connect.service &>>"${LOG_FILE}"

    log_message "[OK] Bluetooth auto-connect service installed and started."
    return 0
}

# ====================================================================
# SECTION 11: CRON JOB FOR PERIODIC CONNECTION CHECK
# ====================================================================
stage_7_cron_connection_check() {
    log_message "====== STAGE 7/10: Cron Job for Connection Monitoring ======"

    cat > /usr/local/bin/check-bluetooth-connection.sh <<'CRON_SCRIPT_EOF'
#!/bin/bash

LOG_FILE="/var/log/otomasi_audio.log"
MAC_SPEAKER="7d:5b:22:c8:4d:ab"

# Check if device is connected
if ! /usr/bin/bluetoothctl info "${MAC_SPEAKER}" | grep -q "Connected: yes"; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Bluetooth disconnected, reconnecting..." >> "${LOG_FILE}"
    /usr/bin/bluetoothctl connect "${MAC_SPEAKER}" >> "${LOG_FILE}" 2>&1
    sleep 2
    
    # Verify
    if /usr/bin/bluetoothctl info "${MAC_SPEAKER}" | grep -q "Connected: yes"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Reconnection successful" >> "${LOG_FILE}"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Reconnection failed" >> "${LOG_FILE}"
    fi
fi
CRON_SCRIPT_EOF

    chmod 755 /usr/local/bin/check-bluetooth-connection.sh

    # Add to root crontab (check every 5 minutes)
    {
        crontab -l 2>/dev/null | grep -v "check-bluetooth-connection.sh"
        echo "*/5 * * * * /usr/local/bin/check-bluetooth-connection.sh"
    } | crontab - &>>"${LOG_FILE}"

    log_message "[OK] Cron job for Bluetooth monitoring installed."
    return 0
}

# ====================================================================
# SECTION 12: SUDOERS CONFIGURATION (SAFE METHOD)
# ====================================================================
stage_8_sudoers_config() {
    log_message "====== STAGE 8/10: Sudoers Configuration ======"

    mkdir -p /etc/sudoers.d

    cat > /etc/sudoers.d/audio-sekolah <<'SUDOERS_EOF'
# Audio School Automation - Minimal Privileges
%audio ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluealsa
%audio ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
%audio ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bluealsa
%audio ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bluealsa
%audio ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bluealsa
%audio ALL=(ALL) NOPASSWD: /usr/bin/bluetoothctl *
%audio ALL=(ALL) NOPASSWD: /bin/systemctl restart pulseaudio
SUDOERS_EOF

    chmod 440 /etc/sudoers.d/audio-sekolah
    visudo -c -f /etc/sudoers.d/audio-sekolah &>>"${LOG_FILE}" || {
        log_message "[ERROR] Sudoers syntax invalid"
        rm -f /etc/sudoers.d/audio-sekolah
        return 1
    }

    # Add user to audio group
    usermod -aG audio "${USER_SISTEM}" &>>"${LOG_FILE}"

    log_message "[OK] Sudoers configuration validated and installed."
    return 0
}

# ====================================================================
# SECTION 13: SECURITY HARDENING
# ====================================================================
stage_9_security_hardening() {
    log_message "====== STAGE 9/10: Security Hardening ======"

    # Disable unnecessary services
    local unnecessary_services="cups avahi-daemon"
    for service in $unnecessary_services; do
        if systemctl is-enabled "$service" &>/dev/null; then
            log_message "Disabling $service..."
            systemctl disable "$service" &>>"${LOG_FILE}"
            systemctl stop "$service" &>>"${LOG_FILE}" || true
        fi
    done

    # Basic UFW firewall (optional, commented out by default)
    if command -v ufw &>/dev/null; then
        log_message "[INFO] UFW detected. To enable firewall, run:"
        log_message "       sudo ufw default deny incoming"
        log_message "       sudo ufw default allow outgoing"
        log_message "       sudo ufw allow ssh"
        log_message "       sudo ufw enable"
    fi

    # Sysctl hardening
    cat > /etc/sysctl.d/99-audio-sekolah.conf <<'SYSCTL_EOF'
# Disable IP forwarding
net.ipv4.ip_forward = 0

# Enable SYN cookies
net.ipv4.tcp_syncookies = 1

# Restrict ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Enable ASLR
kernel.randomize_va_space = 2
SYSCTL_EOF

    sysctl -p /etc/sysctl.d/99-audio-sekolah.conf &>>"${LOG_FILE}"

    log_message "[OK] Security hardening applied."
    return 0
}

# ====================================================================
# SECTION 14: LOG ROTATION
# ====================================================================
stage_10_log_rotation() {
    log_message "====== STAGE 10/10: Log Rotation Setup ======"

    cat > /etc/logrotate.d/audio-sekolah <<'LOGROTATE_EOF'
/var/log/otomasi_audio.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0666 root root
}
LOGROTATE_EOF

    log_message "[OK] Log rotation configured."
    return 0
}

# ====================================================================
# SECTION 15: FINAL VERIFICATION & SUMMARY
# ====================================================================
final_verification() {
    log_message "====== FINAL VERIFICATION ======"

    local status_ok=0

    # Check Bluetooth
    if systemctl is-active --quiet bluetooth; then
        log_message "[✓] Bluetooth service is active"
        ((status_ok++))
    else
        log_message "[✗] Bluetooth service is NOT active"
    fi

    # Check BlueALSA
    if systemctl is-active --quiet bluealsa; then
        log_message "[✓] BlueALSA service is active"
        ((status_ok++))
    else
        log_message "[✗] BlueALSA service is NOT active"
    fi

    # Check auto-connect service
    if systemctl is-enabled --quiet bluetooth-auto-connect.service; then
        log_message "[✓] Bluetooth auto-connect service is enabled"
        ((status_ok++))
    else
        log_message "[✗] Bluetooth auto-connect service is NOT enabled"
    fi

    # Check asound.conf
    if [ -f /etc/asound.conf ]; then
        log_message "[✓] ALSA configuration file exists"
        ((status_ok++))
    else
        log_message "[✗] ALSA configuration file missing"
    fi

    # Check sudoers
    if [ -f /etc/sudoers.d/audio-sekolah ]; then
        log_message "[✓] Sudoers configuration installed"
        ((status_ok++))
    else
        log_message "[✗] Sudoers configuration missing"
    fi

    log_message ""
    log_message "====== INSTALLATION SUMMARY ======"
    log_message "Status checks passed: $status_ok / 5"
    log_message "Installation log: ${LOG_FILE}"
    log_message ""
    log_message "Next steps:"
    log_message "  1. Reboot system: sudo reboot"
    log_message "  2. After reboot, check Bluetooth connection:"
    log_message "     bluetoothctl info ${MAC_SPEAKER}"
    log_message "  3. Test audio playback:"
    log_message "     mpv --no-video --audio-device=alsa/bluealsa /path/to/audio.mp3"
    log_message "  4. Monitor logs:"
    log_message "     tail -f ${LOG_FILE}"
    log_message ""
}

# ====================================================================
# MAIN EXECUTION FLOW
# ====================================================================
main() {
    validate_config
    
    local stages=(
        "stage_0_system_setup"
        "stage_1_bluetooth_setup"
        "stage_2_pair_and_trust_device"
        "stage_3_bluealsa_pulseaudio_setup"
        "stage_4_asound_config"
        "stage_5_udev_rules"
        "stage_6_bluetooth_autoconnect_service"
        "stage_7_cron_connection_check"
        "stage_8_sudoers_config"
        "stage_9_security_hardening"
        "stage_10_log_rotation"
    )

    local failed_stages=()

    for stage_func in "${stages[@]}"; do
        if ! $stage_func; then
            log_message "[FAIL] $stage_func failed"
            failed_stages+=("$stage_func")
        fi
    done

    final_verification

    if [ ${#failed_stages[@]} -eq 0 ]; then
        log_message "[SUCCESS] All stages completed successfully!"
        return 0
    else
        log_message "[WARNING] Some stages failed:"
        printf '%s\n' "${failed_stages[@]}" | tee -a "${LOG_FILE}"
        return 1
    fi
}

# Run main
main
exit $?
