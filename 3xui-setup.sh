#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  GoldIP 3X-UI Manager  v9.8  |  xray-core  |  Fixed Build   ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Colors ────────────────────────────────────────────────────────
BG_NAVY='\033[48;5;17;97m';    BG_DPURPLE='\033[48;5;54;97m'
BG_DTEAL='\033[48;5;23;97m';   BG_DMAROON='\033[48;5;52;97m'
BG_DOLIVE='\033[48;5;58;97m';  BG_DMAGENTA='\033[48;5;90;97m'
BG_DSLATE='\033[48;5;237;97m'; BG_DINDIGO='\033[48;5;18;97m'
BG_DFOREST='\033[48;5;22;97m'; BG_DCRIMSON='\033[48;5;88;97m'
BG_GREEN='\033[42;30m'; BG_RED='\033[41;97m'; BG_YELLOW='\033[43;30m'

BG_ROW1='\033[48;5;17;97m'
BG_ROW2='\033[48;5;117;30m'

C1='\033[38;5;39m';  C2='\033[38;5;135m'; C3='\033[38;5;214m'
C4='\033[38;5;51m';  C5='\033[38;5;200m'; C6='\033[38;5;118m'
C7='\033[38;5;45m';  C8='\033[38;5;220m'; C9='\033[38;5;165m'
C10='\033[38;5;87m'; NC='\033[0m'

G1='\033[38;5;21m';  G2='\033[38;5;27m';  G3='\033[38;5;33m'
G4='\033[38;5;39m';  G5='\033[38;5;45m';  G6='\033[38;5;51m'
ORANGE='\033[38;5;214m'
SEP='\033[38;5;240m'

print_success() { echo -e "${BG_GREEN}  [OK]  $1  ${NC}"; }
print_error()   { echo -e "${BG_RED}  [ERR] $1  ${NC}"; }
print_warn()    { echo -e "${BG_YELLOW}  [>>>] $1  ${NC}"; }
_LI=0
print_line() {
    local a=("$C1" "$C2" "$C3" "$C4" "$C5" "$C6" "$C7" "$C8" "$C9" "$C10")
    echo -e "${a[$((_LI%10))]}$1${NC}"; ((_LI++))
}
mitem() { echo -e "${1}  ${2})  ${3}${NC}"; }

[ "$EUID" -ne 0 ] && { echo -e "${BG_RED}  Run as root!  ${NC}"; exit 1; }

# ── Constants ─────────────────────────────────────────────────────
DB_FILE="/etc/x-ui/x-ui.db"
GOLDIP_CONF="/etc/x-ui/.goldip"
PANEL_DOMAIN="" PANEL_PORT="" PANEL_PATH="" PANEL_USER="" PANEL_PASS=""
CERT_FILE="" KEY_FILE="" SSL_OK=false CERT_ENTRY=""
XRAY_BIN="" GEN_PRIV="" GEN_PUB=""
CREATED=0 SKIPPED=0 PATH_IDX=0
NEXT_RPATH="" NEXT_XHTTP_HDR="" NEXT_WS_HDR="" NEXT_HU_HDR=""
NEXT_TCP_REQ="" NEXT_TCP_RES=""
NEXT_FP="" NEXT_PORT=0 RT_TARGET="" RT_SNS="" SESSION_KEY=""

# ── Config Persistence ────────────────────────────────────────────
save_conf() {
    mkdir -p "$(dirname "$GOLDIP_CONF")"
    printf 'PANEL_DOMAIN=%q\nPANEL_PORT=%q\nPANEL_PATH=%q\nSSL_OK=%s\nCERT_FILE=%q\nKEY_FILE=%q\nPANEL_USER=%q\nPANEL_PASS=%q\n' \
        "$PANEL_DOMAIN" "$PANEL_PORT" "$PANEL_PATH" "$SSL_OK" \
        "$CERT_FILE" "$KEY_FILE" "$PANEL_USER" "$PANEL_PASS" > "$GOLDIP_CONF"
}

load_conf() {
    [ -f "$GOLDIP_CONF" ] && source "$GOLDIP_CONF"
    if [ "$SSL_OK" != "true" ] && [ -f "$DB_FILE" ]; then
        local _C _K
        _C=$(sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='webCertFile';" 2>/dev/null)
        _K=$(sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='webKeyFile';"  2>/dev/null)
        if [ -n "$_C" ] && [ -f "$_C" ] && [ -n "$_K" ] && [ -f "$_K" ]; then
            CERT_FILE="$_C"; KEY_FILE="$_K"; SSL_OK=true
            save_conf
        fi
    fi
    _build_cert_entry
}

_build_cert_entry() {
    if [ "$SSL_OK" = true ] && [ -n "$CERT_FILE" ] && [ -n "$KEY_FILE" ]; then
        CERT_ENTRY="\"certificates\":[{\"certificateFile\":\"${CERT_FILE}\",\"keyFile\":\"${KEY_FILE}\",\"ocspStapling\":3600,\"oneTimeLoading\":false,\"usage\":\"encipherment\",\"buildChain\":false}],"
    else
        CERT_ENTRY=""
    fi
}

get_db_val() { sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='$1';" 2>/dev/null; }

# ── Pools ─────────────────────────────────────────────────────────
ALL_PATHS=(
    "/assets/js/chunk-vendors.min.js"      "/static/css/app.chunk.min.css"
    "/api/v2/telemetry/events"             "/v3/auth/token/refresh"
    "/scripts/analytics/gtm.loader.js"     "/cdn-cgi/challenge-platform/h/g/scripts/alpha"
    "/api/beacon/collect"                  "/static/media/logo.a3b2c1d4.svg"
    "/pkg/api/v1/health"                   "/api/graphql/batch"
)
REALITY_TARGETS=("www.oracle.com:443" "www.nvidia.com:443" "www.cloudflare.com:443" "www.microsoft.com:443" "www.apple.com:443")
REALITY_SNS=('["www.oracle.com"]' '["www.nvidia.com","nvidia.com"]' '["www.cloudflare.com","cloudflare.com","one.one.one.one"]' '["www.microsoft.com","microsoft.com"]' '["www.apple.com","apple.com","icloud.com"]')
GRPC_SVCS=("GrpcService" "api.service.v1" "bing.api.v2" "cdn.asset.v3" "grpc.health.v1")
FP_POOL=("chrome" "chrome" "firefox" "edge" "android")

XHTTP_HDR_POOL=(
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"no-cache","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
)
WS_HDR_POOL=(
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"no-cache","Origin":"https://www.google.com","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
)
HU_HDR_POOL=(
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"max-age=0","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
)

SNIFF_TLS='{"enabled":true,"destOverride":["http","tls","quic"]}'
SNIFF_NONE='{"enabled":false}'

# ── Xray Native Key Generator ─────────────────────────────────────
gen_x25519() {
    if [ -z "$XRAY_BIN" ] || [ ! -x "$XRAY_BIN" ]; then
        XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f 2>/dev/null | head -n 1)
        [ -n "$XRAY_BIN" ] && chmod +x "$XRAY_BIN" 2>/dev/null
    fi
    GEN_PRIV=""; GEN_PUB=""
    if [ -n "$XRAY_BIN" ] && [ -x "$XRAY_BIN" ]; then
        local KEY_OUT
        KEY_OUT=$("$XRAY_BIN" x25519 2>/dev/null)
        GEN_PRIV=$(echo "$KEY_OUT" | grep -i "private" | awk '{print $NF}' | tr -d '[:space:]')
        GEN_PUB=$(echo  "$KEY_OUT" | grep -i "public"  | awk '{print $NF}' | tr -d '[:space:]')
    fi
}

# ── Core Engine ───────────────────────────────────────────────────
advance() {
    local BIDX=$(( PATH_IDX % ${#XHTTP_HDR_POOL[@]} ))
    local FP_IDX=$(( PATH_IDX % ${#FP_POOL[@]} ))
    NEXT_RPATH="${ALL_PATHS[$(( PATH_IDX % ${#ALL_PATHS[@]} ))]}"
    NEXT_XHTTP_HDR="${XHTTP_HDR_POOL[$BIDX]}"
    NEXT_WS_HDR="${WS_HDR_POOL[$BIDX]}"
    NEXT_HU_HDR="${HU_HDR_POOL[$BIDX]}"

    local H_HOST="${PANEL_DOMAIN:-www.bing.com}"
    local UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/12${BIDX}.0.0.0 Safari/537.36"

    NEXT_TCP_REQ="\"version\":\"1.1\",\"method\":\"GET\",\"path\":[\"${NEXT_RPATH}\"],\"headers\":{\"Host\":[\"${H_HOST}\"],\"User-Agent\":[\"${UA}\"],\"Accept\":[\"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\"],\"Accept-Encoding\":[\"gzip, deflate\"]}"
    NEXT_TCP_RES="\"version\":\"1.1\",\"status\":\"200\",\"reason\":\"OK\",\"headers\":{\"Content-Type\":[\"application/octet-stream\",\"text/html; charset=utf-8\"],\"Transfer-Encoding\":[\"chunked\"],\"Connection\":[\"keep-alive\"]}"

    NEXT_FP="${FP_POOL[$FP_IDX]}"
    local RI=$(( RANDOM % ${#REALITY_TARGETS[@]} ))
    RT_TARGET="${REALITY_TARGETS[$RI]}"; RT_SNS="${REALITY_SNS[$RI]}"
    NEXT_PORT=$(( RANDOM % 45000 + 10000 ))
    SESSION_KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c 32 || openssl rand -hex 16 | head -c 32)
    (( PATH_IDX++ ))
}

do_insert() {
    local REMARK="$1" PROTO="$2" PORT="$3" SETTINGS="$4" STREAM="$5" SNIFFING_ARG="$6"
    [ -z "$SNIFFING_ARG" ] && SNIFFING_ARG="$SNIFF_NONE"
    SETTINGS=$(echo "$SETTINGS" | tr -d '\n')
    STREAM=$(echo "$STREAM" | tr -d '\n')
    local S_ESC="${SETTINGS//\'/\'\'}"
    local ST_ESC="${STREAM//\'/\'\'}"
    local SN_ESC="${SNIFFING_ARG//\'/\'\'}"
    sqlite3 "$DB_FILE" \
"INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,listen,port,protocol,settings,stream_settings,tag,sniffing) \
VALUES (1,0,0,0,'${REMARK}',1,0,'',${PORT},'${PROTO}','${S_ESC}','${ST_ESC}','in-out-${PORT}','${SN_ESC}');"
    if [ $? -eq 0 ]; then
        local IID
        IID=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")
        sqlite3 "$DB_FILE" "INSERT INTO client_traffics (inbound_id,enable,email,up,down,expiry_time,total) \
VALUES (${IID},1,'${PROTO}_${PORT}',0,0,0,0);"
        print_success "Created [${REMARK}]  port=${PORT}"
        (( CREATED++ ))
    else
        print_error "Failed: ${REMARK}"; (( SKIPPED++ ))
    fi
}

mkuuid()         { cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16; }
reset_counters() { CREATED=0; SKIPPED=0; }

mk_vless() {
    cat <<J
{"clients":[{"id":"$1","flow":"$2","email":"$3","enable":true,"expiryTime":0,"limitIp":0,"reset":0,"subId":"uhe958xwoiq3u7g4","tgId":0,"totalGB":0,"comment":""}],"decryption":"none","encryption":"none"}
J
}
mk_trojan() {
    cat <<J
{"clients":[{"password":"$1","email":"$2","enable":true,"expiryTime":0,"limitIp":0,"reset":0,"subId":"uhe958xwoiq3u7g4","tgId":0,"totalGB":0,"comment":""}]}
J
}
mk_ss() {
    cat <<J
{"method":"$1","password":"$2","network":"tcp,udp","clients":[{"email":"$3","password":"$2","method":"$1","enable":true}]}
J
}
mk_hysteria() {
    cat <<J
{"clients":[{"auth":"$1","email":"$2","enable":true,"expiryTime":0,"limitIp":0,"reset":0,"subId":"uhe958xwoiq3u7g4","tgId":0,"totalGB":0,"comment":""}],"version":2}
J
}

_skip_ssl() { print_warn "SKIP: $1 (no SSL cert)"; (( SKIPPED++ )); }

# ── Inbound Creators ──────────────────────────────────────────────
create_vless_reality_tcp() {
    gen_x25519
    if [ -z "$GEN_PRIV" ]; then print_error "Failed to generate Reality Keys!"; (( SKIPPED++ )); return; fi
    advance
    local UUID SID1 SID2 SID3 S ST
    UUID=$(mkuuid)
    SID1=$(openssl rand -hex 4); SID2=$(openssl rand -hex 4); SID3=$(openssl rand -hex 8)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"tcp","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"http","request":{${NEXT_TCP_REQ}},"response":{${NEXT_TCP_RES}}}},"security":"reality","realitySettings":{"show":false,"xver":0,"target":"${RT_TARGET}","serverNames":${RT_SNS},"privateKey":"${GEN_PRIV}","minClientVer":"","maxClientVer":"","maxTimediff":0,"shortIds":["${SID1}","${SID2}","${SID3}"],"settings":{"publicKey":"${GEN_PUB}","fingerprint":"${NEXT_FP}","serverName":"","spiderX":"/","mldsa65Verify":""}}}
ENDJSON
)
    do_insert "VLESS_Reality_TCP_HTTP" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_vless_reality_xhttp() {
    gen_x25519
    if [ -z "$GEN_PRIV" ]; then print_error "Failed to generate Reality Keys!"; (( SKIPPED++ )); return; fi
    advance
    local UUID SID1 SID2 SID3 S ST
    UUID=$(mkuuid)
    SID1=$(openssl rand -hex 4); SID2=$(openssl rand -hex 4); SID3=$(openssl rand -hex 8)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","headers":${NEXT_XHTTP_HDR}},"security":"reality","realitySettings":{"show":false,"xver":0,"target":"${RT_TARGET}","serverNames":${RT_SNS},"privateKey":"${GEN_PRIV}","minClientVer":"","maxClientVer":"","maxTimediff":0,"shortIds":["${SID1}","${SID2}","${SID3}"],"settings":{"publicKey":"${GEN_PUB}","fingerprint":"${NEXT_FP}","serverName":"","spiderX":"/"}}}
ENDJSON
)
    do_insert "VLESS_Reality_XHTTP" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_vless_xhttp() {
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","headers":${NEXT_XHTTP_HDR}},"security":"none"}
ENDJSON
)
    do_insert "VLESS_XHTTP" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_vless_ws_plain() {
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"ws","wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"security":"none"}
ENDJSON
)
    do_insert "VLESS_WS_Plain" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_vless_ws_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "VLESS-WS-TLS"; return; }
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"ws","wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h2","http/1.1"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}}}
ENDJSON
)
    do_insert "VLESS_WS_TLS" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_vless_grpc_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "VLESS-gRPC-TLS"; return; }
    advance
    local UUID SVC S ST
    UUID=$(mkuuid)
    SVC="${GRPC_SVCS[$(( RANDOM % ${#GRPC_SVCS[@]} ))]}"
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"grpc","grpcSettings":{"serviceName":"${SVC}","authority":"${PANEL_DOMAIN}","multiMode":true},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h2","http/1.1"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}}}
ENDJSON
)
    do_insert "VLESS_gRPC_TLS" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_vless_hu_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "VLESS-HU-TLS"; return; }
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "vless_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"httpupgrade","httpupgradeSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_HU_HDR}},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h2","http/1.1"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}}}
ENDJSON
)
    do_insert "VLESS_HU_TLS" "vless" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_trojan_tcp_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "Trojan-TCP-TLS"; return; }
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"tcp","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"http","request":{${NEXT_TCP_REQ}},"response":{${NEXT_TCP_RES}}}},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h2","http/1.1"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}}}
ENDJSON
)
    do_insert "Trojan_TCP_TLS" "trojan" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_trojan_ws_plain() {
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"ws","wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"security":"none"}
ENDJSON
)
    do_insert "Trojan_WS_Plain" "trojan" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_trojan_ws_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "Trojan-WS-TLS"; return; }
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"ws","wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h2","http/1.1"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}}}
ENDJSON
)
    do_insert "Trojan_WS_TLS" "trojan" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_trojan_grpc_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "Trojan-gRPC-TLS"; return; }
    advance
    local PASS SVC S ST
    PASS=$(openssl rand -hex 16)
    SVC="${GRPC_SVCS[$(( RANDOM % ${#GRPC_SVCS[@]} ))]}"
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"grpc","grpcSettings":{"serviceName":"${SVC}","authority":"${PANEL_DOMAIN}","multiMode":true},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h2","http/1.1"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}}}
ENDJSON
)
    do_insert "Trojan_gRPC_TLS" "trojan" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_trojan_xhttp() {
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "trojan_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"xhttp","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","headers":${NEXT_XHTTP_HDR}},"security":"none"}
ENDJSON
)
    do_insert "Trojan_XHTTP" "trojan" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_ss_tcp() {
    local METHOD="${1:-aes-256-gcm}"
    advance
    local PASS S ST MU
    PASS=$(openssl rand -base64 24 | tr -d '=+/\n' | head -c 24)
    S=$(mk_ss "$METHOD" "$PASS" "ss_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"tcp","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"http","request":{${NEXT_TCP_REQ}},"response":{${NEXT_TCP_RES}}}},"security":"none"}
ENDJSON
)
    MU=$(echo "$METHOD" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    do_insert "SS_TCP_${MU}" "shadowsocks" "$NEXT_PORT" "$S" "$ST" "$SNIFF_NONE"
}

create_hysteria_tls() {
    [ "$SSL_OK" = false ] && { _skip_ssl "Hysteria_V2"; return; }
    advance
    local AUTH PASS S ST
    AUTH=$(openssl rand -hex 8); PASS=$(openssl rand -hex 8)
    S=$(mk_hysteria "$AUTH" "hysteria_${NEXT_PORT}")
    ST=$(cat <<ENDJSON
{"network":"hysteria","hysteriaSettings":{"version":2,"udpIdleTimeout":60,"masquerade":{"type":"","dir":"","url":"","rewriteHost":false,"insecure":false,"content":"","headers":{},"statusCode":0}},"security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","minVersion":"1.2","maxVersion":"1.3","cipherSuites":"","rejectUnknownSni":false,"disableSystemRoot":false,"enableSessionResumption":false,${CERT_ENTRY}"alpn":["h3"],"echServerKeys":"","settings":{"fingerprint":"${NEXT_FP}","echConfigList":"","pinnedPeerCertSha256":[]}},"finalmask":{"udp":[{"type":"salamander","settings":{"password":"${PASS}"}}]}}
ENDJSON
)
    do_insert "Hysteria_V2" "hysteria" "$NEXT_PORT" "$S" "$ST" "$SNIFF_TLS"
}

create_wireguard() {
    gen_x25519
    if [ -z "$GEN_PRIV" ]; then print_error "Failed to generate WG Keys!"; (( SKIPPED++ )); return; fi
    local S_SK="$GEN_PRIV" S_PK="$GEN_PUB"
    gen_x25519
    if [ -z "$GEN_PRIV" ]; then print_error "Failed to generate WG Peer Keys!"; (( SKIPPED++ )); return; fi
    local P_SK="$GEN_PRIV" P_PK="$GEN_PUB"
    advance
    local S ST WG_SNIFF
    S=$(cat <<ENDJSON
{"mtu":1420,"secretKey":"${S_SK}","peers":[{"privateKey":"${P_SK}","publicKey":"${P_PK}","allowedIPs":["10.0.0.2/32"],"keepAlive":0}],"noKernelTun":false}
ENDJSON
)
    ST='{"security":"none"}'
    WG_SNIFF='{"enabled":true,"destOverride":["http","tls","quic","fakedns"]}'
    do_insert "Wireguard" "wireguard" "$NEXT_PORT" "$S" "$ST" "$WG_SNIFF"
}

# ── Preset Loaders ────────────────────────────────────────────────
run_preset_3()        { create_vless_ws_tls; create_vless_grpc_tls; create_vless_reality_tcp; }
run_preset_5()        { create_vless_ws_tls; create_vless_grpc_tls; create_vless_xhttp; create_trojan_ws_tls; create_ss_tcp "aes-256-gcm"; }
run_preset_6_lb()     { create_vless_xhttp; create_vless_xhttp; create_vless_xhttp; create_vless_ws_tls; create_vless_grpc_tls; create_trojan_ws_tls; }
run_preset_6_custom() { create_vless_ws_plain; create_vless_xhttp; create_vless_grpc_tls; create_vless_hu_tls; create_hysteria_tls; create_vless_reality_tcp; }
run_preset_7()        { create_vless_reality_tcp; create_hysteria_tls; create_vless_xhttp; create_vless_grpc_tls; create_trojan_ws_tls; create_ss_tcp "chacha20-poly1305"; create_wireguard; }
run_preset_10()       { create_vless_reality_tcp; create_vless_reality_xhttp; create_vless_xhttp; create_vless_ws_tls; create_vless_grpc_tls; create_vless_hu_tls; create_trojan_ws_tls; create_ss_tcp "chacha20-poly1305"; create_hysteria_tls; create_wireguard; }

# ── SSL: Core logic from 3xui-setup.sh (working, direct, no prompts) ──
# Called internally with PANEL_DOMAIN already set.
get_ssl() {
    [ -z "$PANEL_DOMAIN" ] && { print_error "No domain set."; return 1; }

    # Re-use existing valid cert without re-issuing
    local EC="/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
    local EK="/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem"
    if [ -f "$EC" ] && [ -f "$EK" ]; then
        CERT_FILE="$EC"; KEY_FILE="$EK"; SSL_OK=true
        _build_cert_entry
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webCertFile','${CERT_FILE}');" 2>/dev/null
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webKeyFile','${KEY_FILE}');"  2>/dev/null
        /usr/local/x-ui/x-ui setting -certFile "${CERT_FILE}" 2>/dev/null
        /usr/local/x-ui/x-ui setting -keyFile  "${KEY_FILE}"  2>/dev/null
        save_conf
        print_success "Existing SSL cert found and applied for ${PANEL_DOMAIN}."
        return 0
    fi

    print_warn "Getting SSL for ${PANEL_DOMAIN}..."

    # Ensure certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        print_warn "certbot not found — installing..."
        apt-get update -y -q 2>/dev/null
        apt-get install -y -q certbot 2>/dev/null
    fi
    if ! command -v certbot >/dev/null 2>&1; then
        apt-get install -y -q snapd 2>/dev/null
        snap install core 2>/dev/null; snap refresh core 2>/dev/null
        snap install --classic certbot 2>/dev/null
        ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null
    fi
    if ! command -v certbot >/dev/null 2>&1; then
        print_error "Could not install certbot. SSL failed."
        SSL_OK=false; CERT_ENTRY=""
        return 1
    fi

    # Free port 80
    for SVC in nginx apache2 caddy lighttpd; do systemctl stop "$SVC" 2>/dev/null; done
    fuser -k 80/tcp 2>/dev/null; sleep 1

    certbot certonly --standalone --non-interactive --agree-tos \
        --register-unsafely-without-email -d "${PANEL_DOMAIN}" 2>&1 \
        | while IFS= read -r l; do echo -e "${C4}  [certbot] ${l}${NC}"; done

    if [ -f "$EC" ] && [ -f "$EK" ]; then
        CERT_FILE="$EC"; KEY_FILE="$EK"; SSL_OK=true
        _build_cert_entry
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webCertFile','${CERT_FILE}');" 2>/dev/null
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webKeyFile','${KEY_FILE}');"  2>/dev/null
        /usr/local/x-ui/x-ui setting -certFile "${CERT_FILE}" 2>/dev/null
        /usr/local/x-ui/x-ui setting -keyFile  "${KEY_FILE}"  2>/dev/null
        save_conf
        print_success "SSL obtained for ${PANEL_DOMAIN}."
        echo -e "${C6}  Cert: ${C8}${CERT_FILE}${NC}"
        echo -e "${C6}  Key:  ${C8}${KEY_FILE}${NC}"
    else
        SSL_OK=false; CERT_ENTRY=""
        print_error "SSL FAILED — DNS must point to this server and port 80 must be open."
    fi
}

# ── SSL: Interactive menu function (asks for domain, then calls get_ssl) ──
get_ssl_interactive() {
    local OLD_DOMAIN="$PANEL_DOMAIN"
    echo -n -e "${C4}  Domain (leave blank to use current [${PANEL_DOMAIN}]): ${NC}"
    read -r INPUT_DOMAIN
    [ -n "$INPUT_DOMAIN" ] && PANEL_DOMAIN="$INPUT_DOMAIN"
    if [ -z "$PANEL_DOMAIN" ]; then
        print_error "Domain cannot be empty."
        PANEL_DOMAIN="$OLD_DOMAIN"
        sleep 2; return
    fi
    get_ssl
    echo -e "${C7}  Press Enter...${NC}"; read -r
}

# ── SSL: Manual cert/key path entry ──────────────────────────────
set_ssl_manual() {
    echo -n -e "${C4}  Domain: ${NC}"; read -r D
    echo -n -e "${C4}  Cert Path (fullchain.pem): ${NC}"; read -r CF
    echo -n -e "${C4}  Key Path (privkey.pem): ${NC}"; read -r KF
    if [ -f "$CF" ] && [ -f "$KF" ]; then
        PANEL_DOMAIN="$D"; CERT_FILE="$CF"; KEY_FILE="$KF"; SSL_OK=true
        _build_cert_entry
        sqlite3 "$DB_FILE" \
            "INSERT OR REPLACE INTO settings (key,value) \
             VALUES ('webCertFile','${CF}'), ('webKeyFile','${KF}');" 2>/dev/null
        /usr/local/x-ui/x-ui setting -certFile "$CF" 2>/dev/null
        /usr/local/x-ui/x-ui setting -keyFile  "$KF" 2>/dev/null
        save_conf; systemctl restart x-ui
        print_success "Custom SSL applied for ${D}"
    else
        print_error "Cert or Key file not found at the given path."
    fi
    echo -e "${C7}  Press Enter...${NC}"; read -r
}

# ── Installation Logic ────────────────────────────────────────────
do_install() {
    clear; echo -e "${C1}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║  GoldIP 3X-UI Auto Install  v9.8                        ║"
    echo "  ╚══════════════════════════════════════════════════════════╝${NC}"

    PANEL_DOMAIN=""
    while [ -z "$PANEL_DOMAIN" ]; do
        echo -e "${BG_NAVY}  Panel Domain (e.g. panel.example.com):  ${NC}"
        echo -n -e "${C4}  domain > ${NC}"; read -r PANEL_DOMAIN
    done
    PANEL_PATH=""
    while [ -z "$PANEL_PATH" ]; do
        echo -e "${BG_DPURPLE}  Web Path (e.g. /new-path/):  ${NC}"
        echo -n -e "${C2}  path > ${NC}"; read -r PANEL_PATH
    done
    [[ ! "$PANEL_PATH" =~ ^/ ]] && PANEL_PATH="/$PANEL_PATH"
    [[ ! "$PANEL_PATH" =~ /$ ]] && PANEL_PATH="$PANEL_PATH/"
    PANEL_USER=""
    while [ -z "$PANEL_USER" ]; do
        echo -e "${BG_DTEAL}  Admin Username:  ${NC}"
        echo -n -e "${C7}  username > ${NC}"; read -r PANEL_USER
    done
    PANEL_PASS=""
    while [ -z "$PANEL_PASS" ]; do
        echo -e "${BG_DMAROON}  Admin Password:  ${NC}"
        echo -n -e "${C5}  password > ${NC}"; read -r PANEL_PASS
    done
    PANEL_PORT=""
    while [ -z "$PANEL_PORT" ]; do
        echo -e "${BG_DOLIVE}  Panel Port (e.g. 2053):  ${NC}"
        echo -n -e "${C8}  port > ${NC}"; read -r PANEL_PORT
    done

    echo ""; print_line "  ══ INSTALLING DEPENDENCIES ══"
    apt-get update -y -q 2>/dev/null
    apt-get install -y -q curl sqlite3 openssl certbot psmisc 2>/dev/null
    systemctl disable ufw 2>/dev/null; systemctl stop ufw 2>/dev/null
    print_success "Dependencies installed."

    if command -v x-ui >/dev/null 2>&1 && [ -f /usr/local/x-ui/x-ui ]; then
        print_success "3x-ui already installed."
    else
        echo -e "${BG_DINDIGO}  Downloading and installing 3x-ui... Please wait  ${NC}"

        export DEBIAN_FRONTEND=noninteractive
        export XUI_NONINTERACTIVE=1

        # Download installer to file so yes can feed all prompts reliably
        curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh \
            -o /tmp/xui_install.sh 2>/dev/null
        chmod +x /tmp/xui_install.sh

        # yes feeds every prompt; stdin closed after; all output captured
        yes 2>/dev/null | bash /tmp/xui_install.sh </dev/null >/tmp/xui_install.log 2>&1 &
        local INSTALL_PID=$!

        echo -n -e "${C4}  Progress: [${NC}"
        local TIMEOUT=300 ELAPSED=0
        while kill -0 $INSTALL_PID 2>/dev/null; do
            echo -n -e "${C3}█${NC}"
            sleep 3; ELAPSED=$(( ELAPSED + 3 ))
            if [ $ELAPSED -ge $TIMEOUT ]; then
                kill -9 $INSTALL_PID 2>/dev/null
                echo -e "${C4}] TIMEOUT!${NC}"
                print_error "Installation timed out after ${TIMEOUT}s"
                echo -e "${C9}  ── Last 30 lines of install log ──${NC}"
                tail -n 30 /tmp/xui_install.log 2>/dev/null
                exit 1
            fi
        done
        wait $INSTALL_PID
        local INSTALL_RC=$?
        echo -e "${C4}] Done!${NC}"
        rm -f /tmp/xui_install.sh

        if command -v x-ui >/dev/null 2>&1 && [ -f /usr/local/x-ui/x-ui ]; then
            print_success "3x-ui installed successfully."
        else
            print_error "Installation failed! (exit code: ${INSTALL_RC})"
            echo -e "${C9}  ── Last 30 lines of install log ──${NC}"
            tail -n 30 /tmp/xui_install.log 2>/dev/null
            exit 1
        fi
    fi

    systemctl stop x-ui 2>/dev/null; sleep 2
    /usr/local/x-ui/x-ui setting -username "${PANEL_USER}" -password "${PANEL_PASS}" 2>/dev/null
    sleep 1
    /usr/local/x-ui/x-ui setting -port "${PANEL_PORT}" 2>/dev/null
    /usr/local/x-ui/x-ui setting -webBasePath "${PANEL_PATH}" 2>/dev/null
    sleep 1
    print_success "Credentials applied."

    sqlite3 "$DB_FILE" "DELETE FROM client_traffics;" 2>/dev/null
    sqlite3 "$DB_FILE" "DELETE FROM inbounds WHERE user_id=1;" 2>/dev/null
    print_success "DB cleaned."

    save_conf

    # ── SSL: uses get_ssl() from 3xui-setup.sh — works with PANEL_DOMAIN already set ──
    get_ssl

    gen_x25519

    echo ""; print_line "  ══ INSTALL COMPLETE ══"; echo ""
    if [ "$SSL_OK" = true ]; then
        echo -e "${C4}  Panel: ${C1}https://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    else
        echo -e "${C3}  Panel: ${C8}http://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    fi
    echo -e "${C2}  User: ${C7}${PANEL_USER}${NC}   ${C5}Pass: ${C9}${PANEL_PASS}${NC}"
    echo ""

    systemctl restart x-ui; sleep 3

    echo -e "${BG_DMAGENTA}  Do you want to create inbounds right now? (yes/no):  ${NC}"
    echo -n -e "${C3}  > ${NC}"; read -r CREATE_NOW
    if [[ "${CREATE_NOW,,}" == "y" || "${CREATE_NOW,,}" == "yes" ]]; then
        menu_inbounds
    else
        print_success "Returning to Main Menu..."; sleep 2
    fi
}

# ── Menus and Navigation ──────────────────────────────────────────
ensure_domain() {
    if [ -z "$PANEL_DOMAIN" ]; then
        print_error "No domain set yet! Set it from 'Change Panel Domain & SSL' first."
        sleep 2; return 1
    fi
    return 0
}

list_inbounds() {
    print_line "  ══ CURRENT INBOUNDS ══"; echo ""
    if [ ! -f "$DB_FILE" ]; then print_error "Database not found."; return; fi
    local ROWS
    ROWS=$(sqlite3 -separator '|' "$DB_FILE" \
        "SELECT id, remark, protocol, port, enable FROM inbounds ORDER BY id;" 2>/dev/null)
    if [ -z "$ROWS" ]; then print_warn "No inbounds found yet."; return; fi
    printf "${C4}  %-4s %-30s %-14s %-7s %-4s${NC}\n" "ID" "Remark" "Protocol" "Port" "On"
    echo -e "${SEP}  ───────────────────────────────────────────────────────${NC}"
    local i=0 ID REMARK PROTO PORT ENABLE
    while IFS='|' read -r ID REMARK PROTO PORT ENABLE; do
        [ -z "$ID" ] && continue
        local ROWBG STATE
        (( i % 2 == 0 )) && ROWBG="$BG_ROW1" || ROWBG="$BG_ROW2"
        STATE="OFF"; [ "$ENABLE" = "1" ] && STATE="ON"
        printf "${ROWBG}  %-4s %-30s %-14s %-7s %-4s ${NC}\n" "$ID" "$REMARK" "$PROTO" "$PORT" "$STATE"
        (( i++ ))
    done <<< "$ROWS"
    echo ""
}

menu_inbounds() {
    while true; do
        clear; show_header; print_line "  ══ INBOUND CREATOR ══"; echo ""
        mitem "$G1" "1" "Preset 1: 3-Config    │ WS-TLS + gRPC-TLS + Reality-TCP"
        mitem "$G2" "2" "Preset 2: 5-Config    │ WS-TLS + gRPC-TLS + XHTTP + Trojan-WS + SS-TCP"
        mitem "$G3" "3" "Preset 3: 6-Config LB │ XHTTP+WS+gRPC+Trojan"
        mitem "$G4" "4" "Preset 4: 7-Config    │ Reality + Hysteria + XHTTP + gRPC + SS + WG"
        mitem "$G5" "5" "Preset 5: 10-Config   │ Full Coverage"
        mitem "$G6" "6" "Preset 6: 6-Package   │ WS+XHTTP+gRPC+HU+Hysteria+Reality"
        echo -e "${SEP}  ──────────────────────────────────────────────────────────${NC}"
        mitem "$ORANGE" "I" "All Inbound        │ Pick single inbounds manually"
        mitem "$C8"     "L" "My Inbound         │ View current inbounds"
        mitem "$C9"     "0" "Back"
        echo ""; echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case "${CH^^}" in
            1|2|3|4|5|6)
                ensure_domain || continue
                reset_counters; PATH_IDX=0
                case "${CH^^}" in
                    1) run_preset_3  ;; 2) run_preset_5     ;;
                    3) run_preset_6_lb ;; 4) run_preset_7   ;;
                    5) run_preset_10 ;; 6) run_preset_6_custom ;;
                esac
                after_inbounds ;;
            I) menu_individual_inbound ;;
            L) clear; list_inbounds; echo -e "${C7}  Press Enter...${NC}"; read -r ;;
            0) return ;;
        esac
    done
}

_ROW_CT=0
p_item() {
    local NUM; NUM=$(printf "%2s" "$1")
    local LBL; LBL=$(printf "%-22s" "$2")
    local DESC; DESC=$(printf "%-34s" "$3")
    if (( _ROW_CT % 2 == 0 )); then echo -e "${BG_ROW1}   ${NUM}   ${LBL}  ${DESC} ${NC}"
    else echo -e "${BG_ROW2}   ${NUM}   ${LBL}  ${DESC} ${NC}"; fi
    (( _ROW_CT++ ))
}
p_head() {
    echo -e "${BG_NAVY}  ── $1 ───────────────────────────────────────────────  ${NC}"
    _ROW_CT=0
}

menu_individual_inbound() {
    ensure_domain || return
    while true; do
        clear; show_header; print_line "  ══ INDIVIDUAL INBOUND ══"; echo ""
        p_head "VLESS"
        p_item "1"  "VLESS-Reality-TCP"   "HTTP Headers, No Vision"
        p_item "2"  "VLESS-Reality-XHTTP" "Reality+XHTTP, no TLS"
        p_item "3"  "VLESS-XHTTP"         "plain, host+padding+xmux"
        p_item "4"  "VLESS-WS-Plain"      "plain WS + heartbeat"
        p_item "5"  "VLESS-WS-TLS"        "WS+TLS+fingerprint+ALPN"
        p_item "6"  "VLESS-gRPC-TLS"      "gRPC+TLS+authority+heartbeat"
        p_item "7"  "VLESS-HU-TLS"        "HttpUpgrade+TLS+ALPN"
        p_head "TROJAN"
        p_item "8"  "Trojan-TCP-TLS"      "TCP + HTTP Headers + TLS"
        p_item "9"  "Trojan-WS-Plain"     "plain WS + heartbeat"
        p_item "10" "Trojan-WS-TLS"       "WS+TLS+fingerprint+ALPN"
        p_item "11" "Trojan-gRPC-TLS"     "gRPC+TLS+authority"
        p_head "SHADOWSOCKS"
        p_item "12" "SS-TCP-AES256"       "TCP + HTTP Headers"
        p_item "13" "SS-TCP-ChaCha"       "TCP + HTTP Headers"
        p_head "HYSTERIA & WIREGUARD"
        p_item "14" "Hysteria-V2"         "UDP, salamander obfs, TLS"
        p_item "15" "Wireguard"           "UDP, X25519 Native Keys"
        p_head "OPTIONS"
        p_item "0"  "Back"                "Return to Inbound Creator"
        echo ""; echo -n -e "${C3}  Enter numbers (e.g. 1,5,14) > ${NC}"; read -r CH_INPUT
        case "${CH_INPUT^^}" in
            0) return ;;
            *)
                reset_counters
                local VALID=false
                IFS=',' read -ra CHOICES <<< "$CH_INPUT"
                for N in "${CHOICES[@]}"; do
                    N=$(echo "$N" | tr -d ' ')
                    if [[ "$N" =~ ^[0-9]+$ ]]; then
                        VALID=true
                        case $N in
                            1)  create_vless_reality_tcp  ;;
                            2)  create_vless_reality_xhttp ;;
                            3)  create_vless_xhttp        ;;
                            4)  create_vless_ws_plain     ;;
                            5)  create_vless_ws_tls       ;;
                            6)  create_vless_grpc_tls     ;;
                            7)  create_vless_hu_tls       ;;
                            8)  create_trojan_tcp_tls     ;;
                            9)  create_trojan_ws_plain    ;;
                            10) create_trojan_ws_tls      ;;
                            11) create_trojan_grpc_tls    ;;
                            12) create_ss_tcp "aes-256-gcm"       ;;
                            13) create_ss_tcp "chacha20-poly1305" ;;
                            14) create_hysteria_tls       ;;
                            15) create_wireguard          ;;
                        esac
                    fi
                done
                if [ "$VALID" = false ]; then
                    print_warn "Invalid selection."; sleep 2
                else
                    after_inbounds
                fi
                ;;
        esac
    done
}

menu_panel_settings() {
    while true; do
        clear; show_header; print_line "  ══ PANEL SETTINGS ══"; echo ""
        local CUR_PORT CUR_PATH
        CUR_PORT=$(get_db_val "webPort" 2>/dev/null || echo "$PANEL_PORT")
        CUR_PATH=$(get_db_val "webBasePath" 2>/dev/null || echo "$PANEL_PATH")
        mitem "$C1" "1" "Change Path       [${CUR_PATH}]"
        mitem "$C2" "2" "Change Username"
        mitem "$C3" "3" "Change Password"
        mitem "$C4" "4" "Change Port       [${CUR_PORT}]"
        mitem "$C9" "0" "Back"
        echo ""; echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1)
                echo -e "${BG_DINDIGO}  New Path (e.g. /new-path/):  ${NC}"
                echo -n -e "${C4}  > ${NC}"; read -r NP
                [ -z "$NP" ] && continue
                [[ ! "$NP" =~ ^/ ]] && NP="/$NP"
                [[ ! "$NP" =~ /$ ]] && NP="$NP/"
                /usr/local/x-ui/x-ui setting -webBasePath "$NP"
                PANEL_PATH="$NP"; save_conf; systemctl restart x-ui
                print_success "Path updated to ${NP}"; sleep 2 ;;
            2)
                echo -e "${BG_DINDIGO}  New Username:  ${NC}"
                echo -n -e "${C4}  > ${NC}"; read -r NU
                [ -z "$NU" ] && continue
                /usr/local/x-ui/x-ui setting -username "$NU"
                systemctl restart x-ui; print_success "Username updated."; sleep 2 ;;
            3)
                echo -e "${BG_DINDIGO}  New Password:  ${NC}"
                echo -n -e "${C4}  > ${NC}"; read -r NP
                [ -z "$NP" ] && continue
                /usr/local/x-ui/x-ui setting -password "$NP"
                systemctl restart x-ui; print_success "Password updated."; sleep 2 ;;
            4)
                echo -e "${BG_DINDIGO}  New Port:  ${NC}"
                echo -n -e "${C4}  > ${NC}"; read -r NP
                [ -z "$NP" ] && continue
                /usr/local/x-ui/x-ui setting -port "$NP"
                PANEL_PORT="$NP"; save_conf; systemctl restart x-ui
                print_success "Port updated to ${NP}"; sleep 2 ;;
            0) return ;;
        esac
    done
}

menu_domain_ssl() {
    while true; do
        clear; show_header; print_line "  ══ DOMAIN & SSL ══"; echo ""
        mitem "$C1" "1" "Auto SSL via Certbot  (domain prompt → certbot standalone)"
        mitem "$C2" "2" "Manual SSL            (provide cert/key paths)"
        mitem "$C9" "0" "Back"
        echo ""; echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1) get_ssl_interactive ;;
            2) set_ssl_manual ;;
            0) return ;;
        esac
    done
}

menu_service() {
    while true; do
        clear; show_header; print_line "  ══ SERVICE CONTROL ══"; echo ""
        mitem "$C1" "1" "Start x-ui"
        mitem "$C2" "2" "Stop x-ui"
        mitem "$C3" "3" "Restart x-ui"
        mitem "$C4" "4" "Status (live)"
        mitem "$C5" "5" "Logs (last 50 lines)"
        mitem "$C9" "0" "Back"
        echo ""; echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1) systemctl start   x-ui; print_success "Started."; sleep 2 ;;
            2) systemctl stop    x-ui; print_success "Stopped."; sleep 2 ;;
            3) systemctl restart x-ui; print_success "Restarted."; sleep 2 ;;
            4) clear; systemctl status x-ui -l --no-pager; echo ""; echo -e "${C7}  Press Enter...${NC}"; read -r ;;
            5) clear; journalctl -u x-ui -n 50 --no-pager; echo ""; echo -e "${C7}  Press Enter...${NC}"; read -r ;;
            0) return ;;
        esac
    done
}

show_header() {
    echo -e "${C1}  ╔══════════════════════════════════════════════════════════╗"
    echo -e "  ║  GoldIP  3X-UI Manager  v9.8  |  xray-core               ║"
    echo -e "  ╚══════════════════════════════════════════════════════════╝${NC}"
    local ST_COLOR="${BG_RED}" ST_TEXT=" STOPPED "
    systemctl is-active --quiet x-ui 2>/dev/null && ST_COLOR="${BG_GREEN}" ST_TEXT=" RUNNING "
    echo -e "  ${C6}● xray:${NC} ${ST_COLOR}${ST_TEXT}${NC}  ${C4}${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    if [ "$SSL_OK" = true ]; then
        echo -e "  ${C6}● SSL:${NC}  ${BG_GREEN}  VALID  ${NC}  ${C7}${CERT_FILE}${NC}"
    else
        echo -e "  ${C6}● SSL:${NC}  ${BG_RED}  NONE   ${NC}"
    fi
    local PROTO="http"; [ "$SSL_OK" = true ] && PROTO="https"
    [ -n "$PANEL_DOMAIN" ] && [ -n "$PANEL_PORT" ] && \
        echo -e "  ${C6}● Panel:${NC} ${C4}${PROTO}://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
    echo ""
}

after_inbounds() {
    echo ""
    systemctl restart x-ui
    echo -e "${C1}  Created: ${CREATED}${NC}   ${C3}Skipped: ${SKIPPED}${NC}"
    [ "$SKIPPED" -gt 0 ] && print_warn "Some inbounds skipped — SSL required but not available."
    echo -e "${C7}  Press Enter to return...${NC}"; read -r
}

main_menu() {
    while true; do
        clear; show_header; print_line "  ══ MAIN MENU ══"; echo ""
        mitem "$C1" "1" "Install 3x-ui"
        mitem "$C2" "2" "Panel Settings    (path / user / pass / port)"
        mitem "$C3" "3" "Domain & SSL      (certbot auto or manual cert)"
        mitem "$C4" "4" "Inbound Creator"
        mitem "$C5" "5" "Service Control   (start / stop / restart / logs)"
        mitem "$C9" "0" "Exit"
        echo ""; echo -n -e "${C3}  choice > ${NC}"; read -r CH
        case $CH in
            1) do_install       ;;
            2) menu_panel_settings ;;
            3) menu_domain_ssl  ;;
            4) menu_inbounds    ;;
            5) menu_service     ;;
            0) exit 0           ;;
        esac
    done
}

load_conf
gen_x25519
main_menu
