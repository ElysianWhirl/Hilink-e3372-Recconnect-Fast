#!/bin/sh

HOST="104.18.213.235"              # IP tujuan ping
DEVICE_IP="192.168.8.1"     # IP modem HiLink / ADB
ADB_PORT="5555"             # Port default ADB
FAIL_COUNT=0
MAX_FAIL=3
SLEEP_CHECK=3               # Detik antar ping
SLEEP_RESET=3               # Detik antara CFUN=0 dan CFUN=1
INTERFACE="eth1"            # Interface untuk ping / interface yang di pakai modem hilink

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

while true; do
    if ping -I "$INTERFACE" -c 1 -W 1 "$HOST" >/dev/null; then
        FAIL_COUNT=0
        log "Ping OK ke $HOST melalui $INTERFACE"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "Ping GAGAL melalui $INTERFACE ($FAIL_COUNT/$MAX_FAIL)"
    fi

    if [ "$FAIL_COUNT" -ge "$MAX_FAIL" ]; then
        log "Ping gagal $MAX_FAIL kali berturut-turut, reconnect modem LTE..."

        # Connect ke modem lewat ADB
        log "Mencoba adb connect ke $DEVICE_IP:$ADB_PORT..."
        adb connect $DEVICE_IP

        # Kirim perintah AT untuk reset modem
        log "Mengirim AT+CFUN=0..."
        adb shell atc AT+CFUN=0
        log "Modem dimatikan sementara..."

        log "Mengirim AT+CFUN=1..."
        adb shell atc AT+CFUN=1
        log "Modem diaktifkan kembali."
        sleep $SLEEP_RESET
        FAIL_COUNT=0
    fi

    sleep "$SLEEP_CHECK"
done
