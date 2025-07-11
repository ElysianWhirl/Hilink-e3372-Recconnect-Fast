#!/bin/sh

# === Konfigurasi ===
ipmodem="192.168.8.1"
BOT_TOKEN="tokenbot"     # Ganti dengan token bot kamu
CHAT_ID="chatid"                                           # Ganti dengan chat ID kamu
SLEEP_INTERVAL=60                                              # Interval pengecekan (detik)

# === Lokasi file sementara ===
SESSION_FILE="/tmp/hilink.session"
TOKEN_FILE="/tmp/hilink.token"
OLD_IP_FILE="/tmp/last_modem_ip"
OLD_TIME_FILE="/tmp/last_modem_time"

login() {
    echo "🔐 Login ke modem..."
    pass=$(uci get hilink.settings.password)
    data=$(curl -s "http://$ipmodem/api/webserver/SesTokInfo")
    sesi=$(echo "$data" | grep "SessionID=" | cut -b 10-147)
    token=$(echo "$data" | grep "TokInfo" | cut -b 10-41)

    check=$(curl -s "http://$ipmodem/api/user/state-login" -H "Cookie: $sesi")
    state=$(echo $check | awk -F "<State>" '{print $2}' | awk -F "</State>" '{print $1}')
    type=$(echo $check | awk -F "<password_type>" '{print $2}' | awk -F "</password_type>" '{print $1}')

    if [ "$state" = "0" ]; then
        echo "$sesi" > "$SESSION_FILE"
        echo "$token" > "$TOKEN_FILE"
        echo "✅ Sesi aktif, login tidak perlu"
        return
    fi

    if [ "$type" = "4" ]; then
        pass1=$(echo -n "$pass" | sha256sum | head -c 64 | base64 -w 0)
        pass1=$(echo -n "admin$pass1$token" | sha256sum | head -c 64 | base64 -w 0)
        pass1="<Password>$pass1</Password><password_type>4</password_type>"
    else
        pass1="<Password>$(echo -n "$pass" | base64 -w 0)</Password>"
    fi

    login=$(curl -s -D- -o /dev/null -X POST "http://$ipmodem/api/user/login" \
        -H "__RequestVerificationToken: $token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Cookie: $sesi" \
        -d "<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><Username>admin</Username>$pass1</request>")

    scoki=$(echo "$login" | grep -i set-cookie | cut -d':' -f2 | cut -b 1-138)

    if [ -n "$scoki" ]; then
        echo "$scoki" > "$SESSION_FILE"
        echo "$token" > "$TOKEN_FILE"
        echo "✅ Login berhasil"
    else
        echo "❌ Login gagal"
        rm -f "$SESSION_FILE" "$TOKEN_FILE"
        exit 1
    fi
}

get_ip() {
    sesi=$(cat "$SESSION_FILE" 2>/dev/null)
    token=$(cat "$TOKEN_FILE" 2>/dev/null)

    if [ -z "$sesi" ] || [ -z "$token" ]; then
        login
        sesi=$(cat "$SESSION_FILE")
        token=$(cat "$TOKEN_FILE")
    fi

    curl -s "http://$ipmodem/api/device/information" \
        -H "__RequestVerificationToken: $token" \
        -H "Cookie: $sesi" > /tmp/modeminfo.xml

    # Cek apakah response berisi error (token/sesi kadaluarsa)
    if grep -q "<code>125002</code>" /tmp/modeminfo.xml || grep -q "<error>" /tmp/modeminfo.xml; then
        echo "⚠️  Respon error (token/sesi mungkin kadaluarsa), mencoba login ulang..."
        rm -f "$SESSION_FILE" "$TOKEN_FILE"
        login
        sesi=$(cat "$SESSION_FILE")
        token=$(cat "$TOKEN_FILE")
        curl -s "http://$ipmodem/api/device/information" \
            -H "__RequestVerificationToken: $token" \
            -H "Cookie: $sesi" > /tmp/modeminfo.xml
    fi

    # Cek ulang apakah masih error
    if grep -q "<error>" /tmp/modeminfo.xml; then
        echo "❌ Gagal mendapatkan IP: respon berisi error"
        cat /tmp/modeminfo.xml
        echo ""
        return 1
    fi

    new_ip=$(sed -n 's:.*<WanIPAddress>\(.*\)</WanIPAddress>.*:\1:p' /tmp/modeminfo.xml)
    echo "$new_ip"
}

monitor_ip() {
    new_ip=$(get_ip)

    if [ $? -ne 0 ]; then
        echo "⚠️ Gagal mendapatkan IP WAN, akan mencoba lagi nanti."
        return
    fi

    if echo "$new_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        [ -f "$OLD_IP_FILE" ] && old_ip=$(cat "$OLD_IP_FILE") || old_ip="0.0.0.0"
        [ -f "$OLD_TIME_FILE" ] && old_time=$(cat "$OLD_TIME_FILE") || old_time=$(date +%s)

        if [ "$new_ip" != "$old_ip" ]; then
            current_time=$(date +%s)
            selisih=$((current_time - old_time))
            selisih_fmt=$(printf '%02d:%02d:%02d' $((selisih/3600)) $(( (selisih%3600)/60 )) $((selisih%60)))
            waktu_now=$(date '+%Y-%m-%d %H:%M:%S')

            message="🔰 IP Modem:%0A🔰 Current IP WAN: $old_ip%0A🔰 New IP WAN: $new_ip%0A%0A✅ IP change successfully.%0A⏱️ Duration since last change: $selisih_fmt%0A🕓 Time: $waktu_now"

            curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
                -d chat_id="$CHAT_ID" \
                -d text="$message"

            echo "$new_ip" > "$OLD_IP_FILE"
            echo "$current_time" > "$OLD_TIME_FILE"
            echo "📨 IP berubah: $old_ip → $new_ip"
        else
            echo "ℹ️ IP belum berubah: $new_ip"
        fi
    else
        echo "❌ Tidak bisa parsing IP dari response"
        cat /tmp/modeminfo.xml
    fi
}

# === Loop utama ===
while true; do
    monitor_ip
    sleep "$SLEEP_INTERVAL"
done
