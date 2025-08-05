#!/bin/sh

HOST="your_host"
DEVICE_IP="192.168.8.1"
ADB_PORT="5555"
FAIL_COUNT=0
MAX_FAIL=3
SLEEP_CHECK=2
SLEEP_RESET=2
INTERFACE="eth1"
SUCCESS_COUNT=0
MAX_SUCCESS=3

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /tmp/modem_monitor.log
}

while true; do
    if ping -I "$INTERFACE" -c 1 -W 1 "$HOST" >/dev/null; then
        FAIL_COUNT=0
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        log "Ping OK ke $HOST melalui $INTERFACE ($SUCCESS_COUNT/$MAX_SUCCESS)"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        SUCCESS_COUNT=0
        log "Ping GAGAL melalui $INTERFACE ($FAIL_COUNT/$MAX_FAIL)"
    fi

    # Jika ping berhasil 3x berturut-turut, kill adb server sekali
    if [ "$SUCCESS_COUNT" -ge "$MAX_SUCCESS" ]; then
        log "Ping berhasil $MAX_SUCCESS kali berturut-turut, melakukan adb kill-server..."
        adb kill-server
        log "adb kill-server selesai."
        SUCCESS_COUNT=0
    fi

    # Jika ping gagal 3x, reset modem dan kill adb server sekali
    if [ "$FAIL_COUNT" -ge "$MAX_FAIL" ]; then
        log "Ping gagal $MAX_FAIL kali, melakukan adb kill-server sebelum reset modem..."
        adb kill-server
        log "adb kill-server selesai."

        log "Mencoba adb connect ke $DEVICE_IP:$ADB_PORT..."
        if adb connect $DEVICE_IP | grep -q 'connected'; then
            log "ADB berhasil terkoneksi."

            log "Mengirim AT+CFUN=0..."
            adb -s $DEVICE_IP:$ADB_PORT shell atc AT+CFUN=0

            log "Tunggu $SLEEP_RESET detik..."
            sleep "$SLEEP_RESET"

            log "Mengirim AT+CFUN=1..."
            adb -s $DEVICE_IP:$ADB_PORT shell atc AT+CFUN=1

            log "Tes ping via modem..."
            #timeout 5 adb shell ping -c 1 -W 2 ava.game.naver.com
        else
            log "Gagal connect ADB ke $DEVICE_IP"
        fi
        FAIL_COUNT=0
    fi

    sleep "$SLEEP_CHECK"
done
