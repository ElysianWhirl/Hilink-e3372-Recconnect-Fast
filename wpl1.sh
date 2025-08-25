#!/bin/sh

HOST="yourhost"
HOST1="yourhost"
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
    # Ping ke HOST
    if ping -I "$INTERFACE" -c 1 -W 1 "$HOST" >/dev/null; then
        HOST_OK=1
        log "Ping OK ke $HOST melalui $INTERFACE"
    else
        HOST_OK=0
        log "Ping GAGAL ke $HOST melalui $INTERFACE"
    fi
    # Ping ke HOST dari modem
    if adb -s $DEVICE_IP:$ADB_PORT shell ping -c 1 -W 1 "$HOST" >/dev/null; then
        HOST_OK=1
        log "Ping OK ke $HOST melalui modem langsung"
    else
        HOST_OK=0
        log "Ping GAGAL ke $HOST melalui modem langsung"
    fi

    # Ping ke HOST1
    if ping -I "$INTERFACE" -c 1 -W 1 "$HOST1" >/dev/null; then
        HOST1_OK=1
        log "Ping OK ke $HOST1 melalui $INTERFACE"
    else
        HOST1_OK=0
        log "Ping GAGAL ke $HOST1 melalui $INTERFACE"
    fi
    # Ping ke HOST1 dari modem
    if adb -s $DEVICE_IP:$ADB_PORT shell ping -c 1 -W 1 "$HOST1" >/dev/null; then
        HOST1_OK=1
        log "Ping OK ke $HOST1 melalui modem langsung"
    else
        HOST1_OK=0
        log "Ping GAGAL ke $HOST1 melalui modem langsung"
    fi

    # Jika kedua host gagal, baru dihitung gagal
    if [ "$HOST_OK" -eq 0 ] && [ "$HOST1_OK" -eq 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        SUCCESS_COUNT=0
        log "Kedua host gagal di-ping ($FAIL_COUNT/$MAX_FAIL)"
    else
        FAIL_COUNT=0
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        log "Minimal salah satu host berhasil di-ping ($SUCCESS_COUNT/$MAX_SUCCESS)"
    fi

    # Jika ping berhasil 3x berturut-turut, kill adb server sekali
    if [ "$SUCCESS_COUNT" -ge "$MAX_SUCCESS" ]; then
        log "Ping ke minimal salah satu host berhasil $MAX_SUCCESS kali berturut-turut, melakukan adb kill-server..."
        #adb kill-server
        log "adb kill-server selesai."
        SUCCESS_COUNT=0
    fi

    # Jika kedua host gagal 3x berturut-turut, reset modem dan kill adb server sekali
    if [ "$FAIL_COUNT" -ge "$MAX_FAIL" ]; then
        log "Kedua host gagal di-ping $MAX_FAIL kali, melakukan adb kill-server sebelum reset modem..."
        #adb kill-server
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
