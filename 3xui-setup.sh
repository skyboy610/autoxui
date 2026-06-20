#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  GoldIP 3X-UI Manager  v8.0  |  xray-core  |  Multi-Preset  ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Colors ───────────────────────────────────────────────────────
BG_NAVY='\033[48;5;17;97m';    BG_DPURPLE='\033[48;5;54;97m'
BG_DTEAL='\033[48;5;23;97m';   BG_DMAROON='\033[48;5;52;97m'
BG_DOLIVE='\033[48;5;58;97m';  BG_DMAGENTA='\033[48;5;90;97m'
BG_DSLATE='\033[48;5;237;97m'; BG_DINDIGO='\033[48;5;18;97m'
BG_DFOREST='\033[48;5;22;97m'; BG_DCRIMSON='\033[48;5;88;97m'
BG_GREEN='\033[42;30m'   # dark text on green (better readability)
BG_RED='\033[41;97m'     # white on red
BG_YELLOW='\033[43;30m'  # dark text on yellow
C1='\033[38;5;39m';  C2='\033[38;5;135m'; C3='\033[38;5;214m'
C4='\033[38;5;51m';  C5='\033[38;5;200m'; C6='\033[38;5;118m'
C7='\033[38;5;45m';  C8='\033[38;5;220m'; C9='\033[38;5;165m'
C10='\033[38;5;87m'; NC='\033[0m'

print_success() { echo -e "${BG_GREEN}  [OK]  $1  ${NC}"; }
print_error()   { echo -e "${BG_RED}  [ERR] $1  ${NC}"; }
print_warn()    { echo -e "${BG_YELLOW}  [>>>] $1  ${NC}"; }
_LI=0; print_line() {
    local a=("$C1" "$C2" "$C3" "$C4" "$C5" "$C6" "$C7" "$C8" "$C9" "$C10")
    echo -e "${a[$((_LI%10))]}$1${NC}"; ((_LI++)); }

[ "$EUID" -ne 0 ] && { echo -e "${BG_RED}  Run as root!  ${NC}"; exit 1; }

# ── Constants ────────────────────────────────────────────────────
DB_FILE="/etc/x-ui/x-ui.db"
GOLDIP_CONF="/etc/x-ui/.goldip"
PANEL_DOMAIN="" PANEL_PORT="" PANEL_PATH="" PANEL_USER="" PANEL_PASS=""
CERT_FILE="" KEY_FILE="" SSL_OK=false CERT_ENTRY=""
PRIVATE_KEY="" PUBLIC_KEY="" REALITY_OK=false
CREATED=0 SKIPPED=0 PATH_IDX=0
NEXT_RPATH="" NEXT_XHTTP_HDR="" NEXT_WS_HDR="" NEXT_HU_HDR=""
NEXT_FP="" NEXT_PORT=0 RT_TARGET="" RT_SNS=""

# ── Config Persistence ───────────────────────────────────────────
save_conf() {
    mkdir -p "$(dirname "$GOLDIP_CONF")"
    printf 'PANEL_DOMAIN=%q\nPANEL_PORT=%q\nPANEL_PATH=%q\nSSL_OK=%s\nCERT_FILE=%q\nKEY_FILE=%q\n' \
        "$PANEL_DOMAIN" "$PANEL_PORT" "$PANEL_PATH" "$SSL_OK" "$CERT_FILE" "$KEY_FILE" > "$GOLDIP_CONF"
}
load_conf() {
    [ -f "$GOLDIP_CONF" ] && source "$GOLDIP_CONF"
    if [ "$SSL_OK" = true ] && [ -n "$CERT_FILE" ] && [ -n "$KEY_FILE" ]; then
        CERT_ENTRY="\"certificates\":[{\"certificateFile\":\"${CERT_FILE}\",\"keyFile\":\"${KEY_FILE}\"}],"
    fi
}
get_db_val() { sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='$1';" 2>/dev/null; }

# ── Pools ────────────────────────────────────────────────────────
ALL_PATHS=(
    "/assets/js/chunk-vendors.min.js"      "/static/css/app.chunk.min.css"
    "/api/v2/telemetry/events"             "/v3/auth/token/refresh"
    "/scripts/analytics/gtm.loader.js"    "/cdn-cgi/challenge-platform/h/g/scripts/alpha"
    "/wp-includes/js/jquery/jquery.min.js" "/assets/fonts/inter-v12-latin-regular.woff2"
    "/api/beacon/collect"                  "/static/media/logo.a3b2c1d4.svg"
    "/pkg/api/v1/health"                   "/resources/css/bootstrap.bundle.min.css"
    "/hub/api/token"                       "/assets/vendor/react.production.min.js"
    "/api/graphql/batch"                   "/s/cdn-load/v3/launcher.js"
    "/public/locales/en/translation.json"  "/micro/static/js/runtime-main.min.js"
    "/assets/js/polyfills.min.js"          "/static/chunks/pages/_app.js"
    "/api/v1/log/event"                    "/cdn/shop/t/5/assets/theme.min.js"
    "/sockjs-node/info"                    "/api/client/v2/sessions"
    "/dist/js/app.bundle.min.js"           "/api/v3/config/flags"
)
REALITY_TARGETS=("www.nvidia.com:443" "www.cloudflare.com:443" "www.microsoft.com:443" "www.apple.com:443")
REALITY_SNS=('["www.nvidia.com","nvidia.com"]' '["www.cloudflare.com","cloudflare.com","one.one.one.one"]' '["www.microsoft.com","microsoft.com"]' '["www.apple.com","apple.com","icloud.com"]')
GRPC_SVCS=("GrpcService" "api.service.v1" "bing.api.v2" "cdn.asset.v3" "grpc.health.v1")
GRPC_UA_POOL=("grpc-go/1.63.2" "grpc-java/1.62.2" "grpc-node/1.46.6" "grpc-python/1.62.1" "grpc-dotnet/2.62.0")
FP_POOL=("chrome" "chrome" "firefox" "edge" "android")
SS_CIPHERS=("aes-256-gcm" "chacha20-poly1305" "aes-128-gcm")

# sockopt — exact field names from xray-core/infra/conf/transport.go
# tcpFastOpen:true → reduces connection latency
# tcpCongestion:bbr → better throughput (requires kernel ≥4.9)
# tcpKeepAliveInterval/Idle → connection persistence
# NOTE: xtls-rprx-vision is TCP-only; NOT compatible with gRPC/WS/HU/XHTTP
SO_STD='"mark":0,"tcpFastOpen":true,"tproxy":"off","domainStrategy":"UseIP","tcpKeepAliveInterval":30,"tcpKeepAliveIdle":100,"tcpCongestion":"bbr","tcpWindowClamp":0,"v6only":false,"tcpMptcp":false'
SO_GRPC='"mark":0,"tcpFastOpen":true,"tproxy":"off","domainStrategy":"UseIP","tcpKeepAliveInterval":15,"tcpKeepAliveIdle":60,"tcpCongestion":"bbr","tcpWindowClamp":0,"v6only":false,"tcpMptcp":false'

SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

# Browser-family header pools — 5 profiles, ALL values are strings (xray map[string]string)
# Profile: 0=Chrome/Win  1=Chrome/Mac  2=Firefox/Win  3=Edge/Win  4=Chrome/Android
XHTTP_HDR_POOL=(
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"macOS\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Ch-Ua":"\"Microsoft Edge\";v=\"124\", \"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?1","Sec-Ch-Ua-Platform":"\"Android\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.82 Mobile Safari/537.36"}'
)
WS_HDR_POOL=(
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"macOS\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Ch-Ua":"\"Microsoft Edge\";v=\"124\", \"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"}'
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?1","Sec-Ch-Ua-Platform":"\"Android\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.82 Mobile Safari/537.36"}'
)
HU_HDR_POOL=(
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"macOS\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"max-age=0","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Microsoft Edge\";v=\"124\", \"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?1","Sec-Ch-Ua-Platform":"\"Android\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.82 Mobile Safari/537.36"}'
)

# ── Core Engine ──────────────────────────────────────────────────
advance() {
    local BIDX=$((PATH_IDX % ${#FP_POOL[@]}))
    NEXT_RPATH="${ALL_PATHS[$((PATH_IDX % ${#ALL_PATHS[@]}))]}"
    NEXT_XHTTP_HDR="${XHTTP_HDR_POOL[$BIDX]}"
    NEXT_WS_HDR="${WS_HDR_POOL[$BIDX]}"
    NEXT_HU_HDR="${HU_HDR_POOL[$BIDX]}"
    NEXT_FP="${FP_POOL[$BIDX]}"
    local RI=$((RANDOM % ${#REALITY_TARGETS[@]}))
    RT_TARGET="${REALITY_TARGETS[$RI]}"; RT_SNS="${REALITY_SNS[$RI]}"
    NEXT_PORT=$((RANDOM % 45000 + 10000))
    ((PATH_IDX++))
}

do_insert() {
    local REMARK="$1" PROTO="$2" PORT="$3" SETTINGS="$4" STREAM="$5"
    SETTINGS=$(echo "$SETTINGS" | tr -d '\n'); STREAM=$(echo "$STREAM" | tr -d '\n')
    local S_ESC="${SETTINGS//\'/\'\'}"; local ST_ESC="${STREAM//\'/\'\'}"
    local SN_ESC="${SNIFFING//\'/\'\'}"
    sqlite3 "$DB_FILE" \
"INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,listen,port,protocol,settings,stream_settings,tag,sniffing) \
VALUES (1,0,0,0,'${REMARK}',1,0,'',${PORT},'${PROTO}','${S_ESC}','${ST_ESC}','inbound-${PORT}','${SN_ESC}');"
    if [ $? -eq 0 ]; then
        local IID; IID=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")
        sqlite3 "$DB_FILE" "INSERT INTO client_traffics (inbound_id,enable,email,up,down,expiry_time,total) VALUES (${IID},1,'${PROTO}_${PORT}',0,0,0,0);"
        print_success "Created [${REMARK}]  port=${PORT}  fp=${NEXT_FP}"
        ((CREATED++))
    else
        print_error "Failed: ${REMARK}"; ((SKIPPED++))
    fi
}

mkuuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16; }
reset_counters() { CREATED=0; SKIPPED=0; }

mk_vless() {
    local U="$1" F="$2" E="$3"
    cat <<J
{"clients":[{"id":"${U}","flow":"${F}","email":"${E}","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":"","subId":"","comment":"","reset":0}],"decryption":"none","fallbacks":[]}
J
}
mk_trojan() {
    local P="$1" E="$2"
    cat <<J
{"clients":[{"password":"${P}","email":"${E}","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":"","subId":"","comment":"","reset":0}],"fallbacks":[]}
J
}
mk_ss() {
    local M="$1" P="$2" E="$3"
    cat <<J
{"method":"${M}","password":"${P}","network":"tcp,udp","clients":[{"email":"${E}","password":"${P}","method":"${M}","enable":true}]}
J
}

# ── Inbound Creators ─────────────────────────────────────────────
# VLESS Reality TCP — flow:xtls-rprx-vision (TCP-only, no host needed)
create_vless_reality_tcp() {
    [ "$REALITY_OK" = false ] && { print_warn "SKIP: VLESS-Reality-TCP (no keys)"; ((SKIPPED++)); return; }
    advance
    local UUID SID1 SID2 SID3 S ST
    UUID=$(mkuuid); SID1=$(openssl rand -hex 4); SID2=$(openssl rand -hex 4); SID3=$(openssl rand -hex 8)
    S=$(mk_vless "$UUID" "xtls-rprx-vision" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"tcp","security":"reality","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"none"}},"realitySettings":{"show":false,"xver":0,"target":"${RT_TARGET}","serverNames":${RT_SNS},"privateKey":"${PRIVATE_KEY}","minClientVer":"","maxClientVer":"","maxTimediff":60,"shortIds":["${SID1}","${SID2}","${SID3}"],"settings":{"publicKey":"${PUBLIC_KEY}","fingerprint":"${NEXT_FP}","serverName":"","spiderX":"/"}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_Reality_TCP" "vless" "$NEXT_PORT" "$S" "$ST"
}

# VLESS Reality XHTTP — host="" (Reality handles SNI)
create_vless_reality_xhttp() {
    [ "$REALITY_OK" = false ] && { print_warn "SKIP: VLESS-Reality-XHTTP (no keys)"; ((SKIPPED++)); return; }
    advance
    local UUID SID1 SID2 SID3 S ST
    UUID=$(mkuuid); SID1=$(openssl rand -hex 4); SID2=$(openssl rand -hex 4); SID3=$(openssl rand -hex 8)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"reality","xhttpSettings":{"path":"${NEXT_RPATH}","host":"","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"realitySettings":{"show":false,"xver":0,"target":"${RT_TARGET}","serverNames":${RT_SNS},"privateKey":"${PRIVATE_KEY}","minClientVer":"","maxClientVer":"","maxTimediff":60,"shortIds":["${SID1}","${SID2}","${SID3}"],"settings":{"publicKey":"${PUBLIC_KEY}","fingerprint":"${NEXT_FP}","serverName":"","spiderX":"/"}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_Reality_XHTTP" "vless" "$NEXT_PORT" "$S" "$ST"
}

# VLESS XHTTP plain — host=PANEL_DOMAIN, xPaddingObfsMode:true
create_vless_xhttp() {
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"none","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_XHTTP" "vless" "$NEXT_PORT" "$S" "$ST"
}

# VLESS WS TLS — host, heartbeatPeriod, ALPN:http/1.1
create_vless_ws_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: VLESS-WS-TLS (no SSL)"; ((SKIPPED++)); return; }
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"ws","security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["http/1.1"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_WS_TLS" "vless" "$NEXT_PORT" "$S" "$ST"
}

# VLESS gRPC TLS — authority, permit_without_stream (heartbeat), ALPN:h2
# NOTE: xtls-rprx-vision NOT applicable to gRPC (TCP-only feature per xray spec)
create_vless_grpc_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: VLESS-gRPC-TLS (no SSL)"; ((SKIPPED++)); return; }
    advance
    local UUID SVC GRPC_UA S ST
    UUID=$(mkuuid)
    SVC="${GRPC_SVCS[$((RANDOM % ${#GRPC_SVCS[@]}))]}"
    GRPC_UA="${GRPC_UA_POOL[$((RANDOM % ${#GRPC_UA_POOL[@]}))]}"
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"grpc","security":"tls","grpcSettings":{"authority":"${PANEL_DOMAIN}","serviceName":"${SVC}","multiMode":false,"idle_timeout":60,"health_check_timeout":20,"permit_without_stream":true,"initial_windows_size":65536,"user_agent":"${GRPC_UA}"},"tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["h2"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"sockopt":{${SO_GRPC}}}
ENDJSON
)
    do_insert "VLESS_gRPC_TLS" "vless" "$NEXT_PORT" "$S" "$ST"
}

# VLESS HttpUpgrade TLS — host, ALPN:http/1.1
create_vless_hu_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: VLESS-HU-TLS (no SSL)"; ((SKIPPED++)); return; }
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"httpupgrade","security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["http/1.1"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"httpupgradeSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_HU_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_HU_TLS" "vless" "$NEXT_PORT" "$S" "$ST"
}

# Trojan WS TLS — host, heartbeat, ALPN:http/1.1
create_trojan_ws_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: Trojan-WS-TLS (no SSL)"; ((SKIPPED++)); return; }
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"ws","security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["http/1.1"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "Trojan_WS_TLS" "trojan" "$NEXT_PORT" "$S" "$ST"
}

# Trojan XHTTP — host, xPaddingObfsMode
create_trojan_xhttp() {
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"none","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "Trojan_XHTTP" "trojan" "$NEXT_PORT" "$S" "$ST"
}

# Shadowsocks TCP — host N/A (raw TCP), sockopt
create_ss_tcp() {
    local METHOD="${1:-aes-256-gcm}"
    advance
    local PASS S ST MU
    PASS=$(openssl rand -base64 24 | tr -d '=+/\n' | head -c 24)
    S=$(mk_ss "$METHOD" "$PASS" "ss_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"tcp","security":"none","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"none"}},"sockopt":{${SO_STD}}}
ENDJSON
)
    MU=$(echo "$METHOD" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    do_insert "SS_${MU}" "shadowsocks" "$NEXT_PORT" "$S" "$ST"
}

# Shadowsocks XHTTP — host=PANEL_DOMAIN, path obfuscation
create_ss_xhttp() {
    advance
    local PASS S ST
    PASS=$(openssl rand -base64 24 | tr -d '=+/\n' | head -c 24)
    S=$(mk_ss "aes-256-gcm" "$PASS" "ss_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"none","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "SS_XHTTP" "shadowsocks" "$NEXT_PORT" "$S" "$ST"
}

# ── Presets ──────────────────────────────────────────────────────
# 3-config: CDN Primary + Secondary + Direct fallback
run_preset_3() {
    reset_counters; PATH_IDX=0
    print_line "  ▶ 3-Config: WS-TLS + gRPC-TLS + Reality-TCP"
    create_vless_ws_tls
    create_vless_grpc_tls
    create_vless_reality_tcp
}
# 5-config: Full stack (WS+gRPC+XHTTP+Trojan+SS)
run_preset_5() {
    reset_counters; PATH_IDX=0
    print_line "  ▶ 5-Config: WS-TLS + gRPC-TLS + XHTTP + Trojan-WS + SS-TCP"
    create_vless_ws_tls
    create_vless_grpc_tls
    create_vless_xhttp
    create_trojan_ws_tls
    create_ss_tcp "aes-256-gcm"
}
# 6-config: Load balance — 3×XHTTP + WS + gRPC + Trojan
run_preset_6_lb() {
    reset_counters; PATH_IDX=0
    print_line "  ▶ 6-Config LB: XHTTP×3 (Chrome/Firefox/Edge) + WS + gRPC + Trojan"
    create_vless_xhttp   # Chrome/Win profile (idx 0)
    create_vless_xhttp   # Chrome/Mac profile (idx 1)
    create_vless_xhttp   # Firefox/Win profile (idx 2)
    create_vless_ws_tls
    create_vless_grpc_tls
    create_trojan_ws_tls
}
# 7-config: Anti-DPI + CDN coverage
run_preset_7() {
    reset_counters; PATH_IDX=0
    print_line "  ▶ 7-Config: Reality-TCP + XHTTP×3 + gRPC + Trojan-WS + SS"
    create_vless_reality_tcp
    create_vless_xhttp   # Chrome/Win
    create_vless_xhttp   # Chrome/Mac
    create_vless_xhttp   # Firefox/Win
    create_vless_grpc_tls
    create_trojan_ws_tls
    create_ss_tcp "chacha20-poly1305"
}
# 10-config: Full coverage (all transport types)
run_preset_10() {
    reset_counters; PATH_IDX=0
    print_line "  ▶ 10-Config: Full Coverage (Reality+XHTTP×3+WS+gRPC+HU+Trojan+SS)"
    create_vless_reality_tcp
    create_vless_reality_xhttp
    create_vless_xhttp        # Chrome/Win
    create_vless_xhttp        # Chrome/Mac
    create_vless_xhttp        # Firefox/Win
    create_vless_ws_tls
    create_vless_grpc_tls
    create_vless_hu_tls
    create_trojan_ws_tls
    create_ss_tcp "chacha20-poly1305"
}

# ── Reality Key Discovery ─────────────────────────────────────────
find_and_gen_keys() {
    XRAY_BIN=""
    for p in "/usr/local/x-ui/bin/xray-linux-amd64" "/usr/local/x-ui/bin/xray-linux-arm64" \
             "/usr/local/x-ui/bin/xray" "/usr/local/bin/xray" "/usr/bin/xray"; do
        [ -f "$p" ] && [ -x "$p" ] && { XRAY_BIN="$p"; break; }
    done
    [ -z "$XRAY_BIN" ] && XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f 2>/dev/null | head -n 1)
    [ -n "$XRAY_BIN" ] && chmod +x "$XRAY_BIN"
    PRIVATE_KEY="" PUBLIC_KEY="" REALITY_OK=false
    if [ -n "$XRAY_BIN" ]; then
        local KEY_OUT; KEY_OUT=$("$XRAY_BIN" x25519 2>/dev/null)
        PRIVATE_KEY=$(echo "$KEY_OUT" | grep -i "private" | awk '{print $NF}' | tr -d '[:space:]')
        PUBLIC_KEY=$(echo  "$KEY_OUT" | grep -i "public"  | awk '{print $NF}' | tr -d '[:space:]')
        if [[ ${#PRIVATE_KEY} -ge 40 && ${#PUBLIC_KEY} -ge 40 ]]; then
            REALITY_OK=true; print_success "Reality keys generated."
        else
            print_error "Reality key gen failed."
        fi
    else
        print_error "xray binary not found — Reality disabled."
    fi
}

# ── Get SSL ───────────────────────────────────────────────────────
get_ssl() {
    [ -z "$PANEL_DOMAIN" ] && { print_error "No domain set."; return 1; }
    print_warn "Getting SSL for ${PANEL_DOMAIN}..."
    systemctl stop nginx 2>/dev/null; systemctl stop apache2 2>/dev/null
    certbot certonly --standalone --non-interactive --agree-tos \
        --register-unsafely-without-email -d "${PANEL_DOMAIN}" 2>&1 \
        | while IFS= read -r l; do echo -e "${C4}  [certbot] ${l}${NC}"; done
    CERT_FILE="/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
    KEY_FILE="/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem"
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webCertFile','${CERT_FILE}');" 2>/dev/null
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webKeyFile','${KEY_FILE}');"  2>/dev/null
        SSL_OK=true
        CERT_ENTRY="\"certificates\":[{\"certificateFile\":\"${CERT_FILE}\",\"keyFile\":\"${KEY_FILE}\"}],"
        save_conf; print_success "SSL obtained."
    else
        SSL_OK=false; CERT_ENTRY=""
        print_error "SSL FAILED — DNS must point here, port 80 open."
    fi
}

# ── Management Functions ──────────────────────────────────────────
restart_xui() {
    x-ui restart 2>/dev/null || systemctl restart x-ui
    sleep 3
    if systemctl is-active --quiet x-ui; then
        print_success "x-ui restarted."
    else
        print_error "x-ui failed. Run: journalctl -u x-ui -n 50"
    fi
}

change_credential() {
    local FIELD="$1"
    echo -e "${BG_DINDIGO}  New ${FIELD}:  ${NC}"
    echo -n -e "${C4}  > ${NC}"; read -r NEW_VAL
    [ -z "$NEW_VAL" ] && { print_warn "Cancelled."; return; }
    /usr/local/x-ui/x-ui setting "-${FIELD}" "$NEW_VAL"
    restart_xui; sleep 1
}

change_port() {
    echo -e "${BG_DINDIGO}  New Panel Port [current: ${PANEL_PORT}]:  ${NC}"
    echo -n -e "${C4}  > ${NC}"; read -r NEW_PORT
    [ -z "$NEW_PORT" ] && return
    /usr/local/x-ui/x-ui setting -port "$NEW_PORT"
    PANEL_PORT="$NEW_PORT"; save_conf; restart_xui
}

change_path() {
    echo -e "${BG_DINDIGO}  New Web Path [current: ${PANEL_PATH}]:  ${NC}"
    echo -n -e "${C4}  > ${NC}"; read -r NEW_PATH
    [ -z "$NEW_PATH" ] && return
    [[ ! "$NEW_PATH" =~ ^/ ]] && NEW_PATH="/$NEW_PATH"
    [[ ! "$NEW_PATH" =~ /$ ]] && NEW_PATH="$NEW_PATH/"
    /usr/local/x-ui/x-ui setting -webBasePath "$NEW_PATH"
    PANEL_PATH="$NEW_PATH"; save_conf; restart_xui
}

change_domain_ssl() {
    echo -e "${BG_DINDIGO}  New Domain (SSL will renew):  ${NC}"
    echo -n -e "${C4}  > ${NC}"; read -r NEW_DOM
    [ -z "$NEW_DOM" ] && return
    PANEL_DOMAIN="$NEW_DOM"; get_ssl; save_conf
    restart_xui
}

clean_inbounds() {
    echo -e "${BG_DCRIMSON}  Delete ALL inbounds? (yes/no):  ${NC}"
    echo -n -e "${C5}  > ${NC}"; read -r CONF
    [ "$CONF" != "yes" ] && { print_warn "Cancelled."; return; }
    sqlite3 "$DB_FILE" "DELETE FROM client_traffics;" 2>/dev/null
    sqlite3 "$DB_FILE" "DELETE FROM inbounds WHERE user_id=1;" 2>/dev/null
    print_success "All inbounds deleted."; restart_xui
}

list_inbounds() {
    echo -e "${C4}"
    printf "  %-5s %-30s %-8s %-12s %-10s\n" "ID" "Remark" "Port" "Protocol" "Tag"
    echo "  ──────────────────────────────────────────────────────────"
    sqlite3 "$DB_FILE" "SELECT id,remark,port,protocol,tag FROM inbounds WHERE user_id=1;" 2>/dev/null \
        | while IFS='|' read -r id remark port proto tag; do
            printf "  %-5s %-30s %-8s %-12s %-10s\n" "$id" "$remark" "$port" "$proto" "$tag"
        done
    echo -e "${NC}"
}

# ── Header ───────────────────────────────────────────────────────
show_header() {
    echo -e "${C1}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║  GoldIP  3X-UI Manager  v8.0  |  xray-core              ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    local ST_COLOR; local ST_TEXT
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        ST_COLOR="${BG_GREEN}"; ST_TEXT=" RUNNING "
    else
        ST_COLOR="${BG_RED}"; ST_TEXT=" STOPPED "
    fi
    echo -e "  ${C6}● xray:${NC} ${ST_COLOR}${ST_TEXT}${NC}  ${C4}${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    [ "$SSL_OK" = true ] && echo -e "  ${C6}● SSL:${NC}  ${BG_GREEN}  VALID  ${NC}" \
                         || echo -e "  ${C6}● SSL:${NC}  ${BG_RED}  NONE  ${NC}"
    [ "$REALITY_OK" = true ] && echo -e "  ${C6}● Reality PubKey:${NC} ${C4}${PUBLIC_KEY:0:20}...${NC}"
    echo ""
}

after_inbounds() {
    echo ""
    restart_xui
    echo -e "${C1}  Inbounds created: ${CREATED}${NC}  ${C3}Skipped: ${SKIPPED}${NC}"
    [ "$SKIPPED" -gt 0 ] && [ "$SSL_OK" = false ] && \
        print_warn "TLS inbounds skipped — run 'Get SSL' from Settings menu."
    echo ""; echo -e "${C7}  Press Enter...${NC}"; read -r
}

# ── Menu: Inbounds ───────────────────────────────────────────────
menu_inbounds() {
    while true; do
        clear; show_header
        print_line "  ══ CREATE INBOUNDS ══"
        [ "$SSL_OK" != true ] && echo -e "  ${BG_YELLOW}  ⚠  No SSL — TLS inbounds will be skipped  ${NC}"
        [ "$REALITY_OK" != true ] && echo -e "  ${BG_YELLOW}  ⚠  No Reality keys — Reality inbounds skipped  ${NC}"
        echo ""
        echo -e "${C1}  1)${NC} 3-Config   │ WS-TLS + gRPC-TLS + Reality-TCP"
        echo -e "${C2}  2)${NC} 5-Config   │ WS-TLS + gRPC-TLS + XHTTP + Trojan-WS + SS-TCP"
        echo -e "${C3}  3)${NC} 6-Config   │ Load Balance: XHTTP×3 + WS + gRPC + Trojan [for relay]"
        echo -e "${C4}  4)${NC} 7-Config   │ Reality-TCP + XHTTP×3 + gRPC + Trojan-WS + SS"
        echo -e "${C5}  5)${NC} 10-Config  │ Full Coverage: all transport types"
        echo -e "${C6}  L)${NC} List current inbounds"
        echo -e "${C8}  D)${NC} Delete ALL inbounds"
        echo -e "${C9}  0)${NC} Back"
        echo ""
        echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case "${CH^^}" in
            1) clear; show_header; run_preset_3;    after_inbounds ;;
            2) clear; show_header; run_preset_5;    after_inbounds ;;
            3) clear; show_header; run_preset_6_lb; after_inbounds ;;
            4) clear; show_header; run_preset_7;    after_inbounds ;;
            5) clear; show_header; run_preset_10;   after_inbounds ;;
            L) clear; list_inbounds; echo -e "${C7}  Press Enter...${NC}"; read -r ;;
            D) clean_inbounds; echo -e "${C7}  Press Enter...${NC}"; read -r ;;
            0) return ;;
        esac
    done
}

# ── Menu: Settings ───────────────────────────────────────────────
menu_settings() {
    while true; do
        clear; show_header
        print_line "  ══ PANEL SETTINGS ══"
        local CUR_PORT; CUR_PORT=$(get_db_val "webPort" || echo "$PANEL_PORT")
        local CUR_PATH; CUR_PATH=$(get_db_val "webBasePath" || echo "$PANEL_PATH")
        echo ""
        echo -e "${C1}  1)${NC} Change Username"
        echo -e "${C2}  2)${NC} Change Password"
        echo -e "${C3}  3)${NC} Change Port      [${CUR_PORT}]"
        echo -e "${C4}  4)${NC} Change Path      [${CUR_PATH}]"
        echo -e "${C5}  5)${NC} Change Domain + Renew SSL  [${PANEL_DOMAIN}]"
        echo -e "${C6}  6)${NC} Get / Renew SSL (same domain)"
        echo -e "${C9}  0)${NC} Back"
        echo ""
        echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1) change_credential "username"; sleep 2 ;;
            2) change_credential "password"; sleep 2 ;;
            3) change_port; sleep 2 ;;
            4) change_path; sleep 2 ;;
            5) change_domain_ssl; sleep 2 ;;
            6) get_ssl; sleep 2 ;;
            0) return ;;
        esac
    done
}

# ── Menu: Service ────────────────────────────────────────────────
menu_service() {
    while true; do
        clear; show_header
        print_line "  ══ SERVICE CONTROL ══"; echo ""
        echo -e "${C1}  1)${NC} Start x-ui"
        echo -e "${C2}  2)${NC} Stop x-ui"
        echo -e "${C3}  3)${NC} Restart x-ui"
        echo -e "${C4}  4)${NC} Status (live)"
        echo -e "${C5}  5)${NC} xray Logs (last 80 lines)"
        echo -e "${C9}  0)${NC} Back"
        echo ""
        echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1) systemctl start x-ui;   print_success "Started";  sleep 2 ;;
            2) systemctl stop x-ui;    print_success "Stopped";  sleep 2 ;;
            3) restart_xui; sleep 2 ;;
            4) clear; systemctl status x-ui --no-pager -l
               echo ""; echo -e "${C4}  Press Enter...${NC}"; read -r ;;
            5) clear; journalctl -u x-ui -n 80 --no-pager
               echo ""; echo -e "${C4}  Press Enter...${NC}"; read -r ;;
            0) return ;;
        esac
    done
}

# ── Install ───────────────────────────────────────────────────────
do_install() {
    clear
    echo -e "${C1}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║  GoldIP 3X-UI Auto Install  v8.0                        ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    PANEL_DOMAIN=""
    while [ -z "$PANEL_DOMAIN" ]; do
        echo -e "${BG_NAVY}  [1/5]  Panel Domain (e.g. panel.example.com):  ${NC}"
        echo -n -e "${C4}  domain > ${NC}"; read -r PANEL_DOMAIN
    done
    PANEL_PATH=""
    while [ -z "$PANEL_PATH" ]; do
        echo -e "${BG_DPURPLE}  [2/5]  Web Path (e.g. /secret/):  ${NC}"
        echo -n -e "${C2}  path > ${NC}"; read -r PANEL_PATH
    done
    [[ ! "$PANEL_PATH" =~ ^/ ]] && PANEL_PATH="/$PANEL_PATH"
    [[ ! "$PANEL_PATH" =~ /$ ]] && PANEL_PATH="$PANEL_PATH/"
    PANEL_USER=""
    while [ -z "$PANEL_USER" ]; do
        echo -e "${BG_DTEAL}  [3/5]  Admin Username:  ${NC}"
        echo -n -e "${C7}  username > ${NC}"; read -r PANEL_USER
    done
    PANEL_PASS=""
    while [ -z "$PANEL_PASS" ]; do
        echo -e "${BG_DMAROON}  [4/5]  Admin Password:  ${NC}"
        echo -n -e "${C5}  password > ${NC}"; read -r PANEL_PASS
    done
    PANEL_PORT=""
    while [ -z "$PANEL_PORT" ]; do
        echo -e "${BG_DOLIVE}  [5/5]  Panel Port (e.g. 2053):  ${NC}"
        echo -n -e "${C8}  port > ${NC}"; read -r PANEL_PORT
    done

    echo ""; print_line "  ══ DEPENDENCIES ══"
    apt-get update -y -q 2>/dev/null
    apt-get install -y -q curl sqlite3 openssl certbot 2>/dev/null
    print_success "Dependencies installed."

    # Firewall OFF per user config
    systemctl disable ufw 2>/dev/null; systemctl stop ufw 2>/dev/null
    print_warn "Firewall disabled."

    if command -v x-ui >/dev/null 2>&1 && [ -f /usr/local/x-ui/x-ui ]; then
        print_success "3x-ui already installed."
    else
        print_warn "Installing 3x-ui..."
        export XUI_NONINTERACTIVE=1
        echo "" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) 2>&1 \
            | grep -E -i "(install|success|error|fail|done)" \
            | while IFS= read -r l; do echo -e "${C4}  [3x-ui] ${l}${NC}"; done
        print_success "3x-ui installed."
    fi

    systemctl stop x-ui 2>/dev/null; sleep 2
    print_warn "Applying credentials..."
    /usr/local/x-ui/x-ui setting -username "${PANEL_USER}" -password "${PANEL_PASS}"
    sleep 1
    /usr/local/x-ui/x-ui setting -port "${PANEL_PORT}"
    /usr/local/x-ui/x-ui setting -webBasePath "${PANEL_PATH}"
    sleep 1; print_success "Credentials applied."

    get_ssl

    print_warn "Cleaning existing inbounds..."
    sqlite3 "$DB_FILE" "DELETE FROM client_traffics;" 2>/dev/null
    sqlite3 "$DB_FILE" "DELETE FROM inbounds WHERE user_id=1;" 2>/dev/null
    print_success "DB cleaned."

    save_conf
    find_and_gen_keys

    echo ""; print_line "  ══ SELECT INBOUND PRESET ══"; echo ""
    echo -e "${C1}  1)${NC} 3-Config   │ WS-TLS + gRPC-TLS + Reality-TCP"
    echo -e "${C2}  2)${NC} 5-Config   │ Full Stack (WS+gRPC+XHTTP+Trojan+SS)"
    echo -e "${C3}  3)${NC} 6-Config   │ Load Balance: XHTTP×3 + WS + gRPC + Trojan"
    echo -e "${C4}  4)${NC} 7-Config   │ Reality-TCP + XHTTP×3 + gRPC + Trojan-WS + SS"
    echo -e "${C5}  5)${NC} 10-Config  │ Full Coverage (all types)"
    echo -e "${C9}  0)${NC} Skip (add inbounds later from menu)"
    echo ""
    PRESET=""
    while [[ ! "$PRESET" =~ ^[0-5]$ ]]; do
        echo -e "${BG_DMAGENTA}  Select preset (0-5):  ${NC}"
        echo -n -e "${C3}  preset > ${NC}"; read -r PRESET
    done

    case $PRESET in
        1) run_preset_3 ;;
        2) run_preset_5 ;;
        3) run_preset_6_lb ;;
        4) run_preset_7 ;;
        5) run_preset_10 ;;
        0) print_warn "Skipped. Create inbounds from main menu." ;;
    esac

    restart_xui

    echo ""
    print_line "  ══ INSTALL COMPLETE ══"; echo ""
    if [ "$SSL_OK" = true ]; then
        echo -e "${C4}  Panel: ${C1}https://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    else
        echo -e "${C3}  Panel: ${C8}http://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    fi
    echo -e "${C2}  User: ${C7}${PANEL_USER}${NC}  ${C5}Pass: ${C9}${PANEL_PASS}${NC}"
    echo -e "${C1}  Inbounds: ${CREATED}  Skipped: ${SKIPPED}${NC}"
    [ "$REALITY_OK" = true ] && echo -e "${C4}  Reality PubKey: ${NC}${PUBLIC_KEY}"
    echo ""; print_success "Done. Loading management menu..."
    sleep 3
}

# ── Main Menu ────────────────────────────────────────────────────
main_menu() {
    while true; do
        clear; show_header
        print_line "  ══ MAIN MENU ══"; echo ""
        echo -e "${C1}  1)${NC} Create / Manage Inbounds"
        echo -e "${C2}  2)${NC} Panel Settings  (user/pass/port/path/domain/SSL)"
        echo -e "${C3}  3)${NC} Service Control  (start/stop/restart/logs)"
        echo -e "${C4}  4)${NC} Reinstall / Re-setup"
        echo -e "${C9}  0)${NC} Exit"
        echo ""
        echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1) menu_inbounds ;;
            2) menu_settings ;;
            3) menu_service ;;
            4) do_install ;;
            0) exit 0 ;;
        esac
    done
}

# ── Entry Point ───────────────────────────────────────────────────
load_conf
find_and_gen_keys

if command -v x-ui >/dev/null 2>&1 && [ -f /usr/local/x-ui/x-ui ]; then
    main_menu
else
    do_install
    main_menu
fi
