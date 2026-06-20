#!/bin/bash

BG_NAVY='\033[48;5;17;97m'; BG_DPURPLE='\033[48;5;54;97m'; BG_DTEAL='\033[48;5;23;97m'
BG_DMAROON='\033[48;5;52;97m'; BG_DOLIVE='\033[48;5;58;97m'; BG_DMAGENTA='\033[48;5;90;97m'
BG_DSLATE='\033[48;5;237;97m'; BG_DINDIGO='\033[48;5;18;97m'
BG_DFOREST='\033[48;5;22;97m'; BG_DCRIMSON='\033[48;5;88;97m'
BG_GREEN='\033[42;97m'; BG_RED='\033[41;97m'; BG_YELLOW='\033[43;97m'
C1='\033[38;5;39m'; C2='\033[38;5;135m'; C3='\033[38;5;214m'; C4='\033[38;5;51m'
C5='\033[38;5;200m'; C6='\033[38;5;118m'; C7='\033[38;5;45m'; C8='\033[38;5;220m'
C9='\033[38;5;165m'; C10='\033[38;5;87m'; NC='\033[0m'

print_success() { echo -e "${BG_GREEN}  [OK]  $1  ${NC}"; }
print_error()   { echo -e "${BG_RED}  [ERR] $1  ${NC}"; }
print_warn()    { echo -e "${BG_YELLOW}  [>>>] $1  ${NC}"; }
_LI=0
print_line() {
    local a=("$C1" "$C2" "$C3" "$C4" "$C5" "$C6" "$C7" "$C8" "$C9" "$C10")
    echo -e "${a[$((_LI%10))]}$1${NC}"; ((_LI++))
}

[ "$EUID" -ne 0 ] && { echo -e "\033[41;97m  [ERR] Run as root!  \033[0m"; exit 1; }
clear

echo -e "${C1}"
echo "  +----------------------------------------------------------+"
echo "  |  3X-UI AUTO SETUP  v7.0  |  GoldIP VPN Manager          |"
echo "  |  sockopt+BBR | host field | WS heartbeat | gRPC health   |"
echo "  |  xPaddingObfsMode | authority | permit_without_stream     |"
echo "  +----------------------------------------------------------+"
echo -e "${NC}"
print_line "  Source: xray-core infra/conf — exact field names verified"
print_line "  +----------------------------------------------------------+"
echo ""

PANEL_DOMAIN=""
while [ -z "$PANEL_DOMAIN" ]; do
    echo -e "${BG_NAVY}  [1/5]  Panel Domain:  ${NC}"
    echo -n -e "${C4}  domain > ${NC}"; read -r PANEL_DOMAIN
done
PANEL_PATH=""
while [ -z "$PANEL_PATH" ]; do
    echo -e "${BG_DPURPLE}  [2/5]  Web Base Path (e.g. /secret/):  ${NC}"
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
    echo -e "${BG_DOLIVE}  [5/5]  Panel Port:  ${NC}"
    echo -n -e "${C8}  port > ${NC}"; read -r PANEL_PORT
done

echo ""; print_line "  +----------------------------------------------------------+"
print_line "  SYSTEM PREPARATION"; print_line "  +----------------------------------------------------------+"

apt-get update -y -q 2>/dev/null
apt-get install -y -q curl sqlite3 openssl certbot ufw 2>/dev/null
print_success "Dependencies ready."
ufw allow 80/tcp >/dev/null 2>&1; ufw allow 443/tcp >/dev/null 2>&1
ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1; ufw --force enable >/dev/null 2>&1
print_success "Firewall OK."

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
sleep 1; print_success "Credentials, port, path applied."

print_warn "Requesting SSL for ${PANEL_DOMAIN}..."
systemctl stop nginx 2>/dev/null; systemctl stop apache2 2>/dev/null
certbot certonly --standalone --non-interactive --agree-tos \
    --register-unsafely-without-email -d "${PANEL_DOMAIN}" 2>&1 \
    | while IFS= read -r l; do echo -e "${C4}  [certbot] ${l}${NC}"; done

CERT_FILE="/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem"
DB_FILE="/etc/x-ui/x-ui.db"
SSL_OK=false; CERT_ENTRY=""
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webCertFile','${CERT_FILE}');" 2>/dev/null
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO settings (key,value) VALUES ('webKeyFile','${KEY_FILE}');"  2>/dev/null
    SSL_OK=true
    CERT_ENTRY="\"certificates\":[{\"certificateFile\":\"${CERT_FILE}\",\"keyFile\":\"${KEY_FILE}\"}],"
    print_success "SSL certificate obtained and applied."
else
    print_error "SSL FAILED — TLS inbounds will be skipped."
fi

print_warn "Cleaning ALL existing inbounds from database..."
sqlite3 "$DB_FILE" "DELETE FROM client_traffics;" 2>/dev/null
sqlite3 "$DB_FILE" "DELETE FROM inbounds WHERE user_id=1;" 2>/dev/null
print_success "Database cleaned."

XRAY_BIN=""
for p in "/usr/local/x-ui/bin/xray-linux-amd64" "/usr/local/x-ui/bin/xray-linux-arm64" \
         "/usr/local/x-ui/bin/xray" "/usr/local/bin/xray" "/usr/bin/xray"; do
    [ -f "$p" ] && [ -x "$p" ] && { XRAY_BIN="$p"; break; }
done
[ -z "$XRAY_BIN" ] && XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f 2>/dev/null | head -n 1)
[ -n "$XRAY_BIN" ] && chmod +x "$XRAY_BIN"
PRIVATE_KEY="" PUBLIC_KEY="" REALITY_OK=false
if [ -n "$XRAY_BIN" ]; then
    KEY_OUT=$("$XRAY_BIN" x25519 2>/dev/null)
    PRIVATE_KEY=$(echo "$KEY_OUT" | grep -i "private" | awk '{print $NF}' | tr -d '[:space:]')
    PUBLIC_KEY=$(echo  "$KEY_OUT" | grep -i "public"  | awk '{print $NF}' | tr -d '[:space:]')
    if [[ ${#PRIVATE_KEY} -ge 40 && ${#PUBLIC_KEY} -ge 40 ]]; then
        REALITY_OK=true; print_success "Reality keys generated."
    else
        print_error "Reality key generation failed."
    fi
else
    print_error "xray binary not found — Reality skipped."
fi

# ══════════════════════════════════════════════════════════════════════════════
#  sockopt — exact JSON field names from xray-core infra/conf/transport.go
#  mark, tcpFastOpen, tproxy, domainStrategy, tcpKeepAliveInterval,
#  tcpKeepAliveIdle, tcpCongestion, tcpWindowClamp, v6only, tcpMptcp
# ══════════════════════════════════════════════════════════════════════════════
SO_STD='"mark":0,"tcpFastOpen":true,"tproxy":"off","domainStrategy":"UseIP","tcpKeepAliveInterval":30,"tcpKeepAliveIdle":100,"tcpCongestion":"bbr","tcpWindowClamp":0,"v6only":false,"tcpMptcp":false'
# gRPC uses shorter keepalive for persistent H2 streams
SO_GRPC='"mark":0,"tcpFastOpen":true,"tproxy":"off","domainStrategy":"UseIP","tcpKeepAliveInterval":15,"tcpKeepAliveIdle":60,"tcpCongestion":"bbr","tcpWindowClamp":0,"v6only":false,"tcpMptcp":false'

# ══════════════════════════════════════════════════════════════════════════════
#  Pools
# ══════════════════════════════════════════════════════════════════════════════
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
# gRPC user_agent: looks like real gRPC client libraries
GRPC_UA_POOL=("grpc-go/1.63.2" "grpc-java/1.62.2" "grpc-node/1.46.6" "grpc-python/1.62.1" "grpc-dotnet/2.62.0")

FP_POOL=("chrome" "chrome" "firefox" "edge" "android")

# ══════════════════════════════════════════════════════════════════════════════
#  Browser-family header pools (5 profiles, all string values — xray requirement)
#  Profile: 0=Chrome/Win  1=Chrome/Mac  2=Firefox/Win  3=Edge/Win  4=Chrome/Android
# ══════════════════════════════════════════════════════════════════════════════

# XHTTP headers — JS script loading context (Sec-Fetch-Dest:script)
XHTTP_HDR_POOL=(
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"macOS\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Pragma":"no-cache","Sec-Ch-Ua":"\"Microsoft Edge\";v=\"124\", \"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"}'
    '{"Accept":"*/*","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?1","Sec-Ch-Ua-Platform":"\"Android\"","Sec-Fetch-Dest":"script","Sec-Fetch-Mode":"no-cors","Sec-Fetch-Site":"same-origin","User-Agent":"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.82 Mobile Safari/537.36"}'
)

# WS headers — WebSocket upgrade context
WS_HDR_POOL=(
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"macOS\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Pragma":"no-cache","Sec-Ch-Ua":"\"Microsoft Edge\";v=\"124\", \"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"}'
    '{"Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"no-cache","Origin":"https://www.google.com","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?1","Sec-Ch-Ua-Platform":"\"Android\"","Sec-Fetch-Dest":"websocket","Sec-Fetch-Mode":"websocket","Sec-Fetch-Site":"cross-site","Sec-WebSocket-Extensions":"permessage-deflate; client_max_window_bits","User-Agent":"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.82 Mobile Safari/537.36"}'
)

# HttpUpgrade headers — page navigation context
HU_HDR_POOL=(
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"macOS\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br","Accept-Language":"en-US,en;q=0.5","Cache-Control":"max-age=0","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Microsoft Edge\";v=\"124\", \"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"","Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":"\"Windows\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"}'
    '{"Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8","Accept-Encoding":"gzip, deflate, br, zstd","Accept-Language":"en-US,en;q=0.9","Cache-Control":"max-age=0","Sec-Ch-Ua":"\"Google Chrome\";v=\"125\", \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"","Sec-Ch-Ua-Mobile":"?1","Sec-Ch-Ua-Platform":"\"Android\"","Sec-Fetch-Dest":"document","Sec-Fetch-Mode":"navigate","Sec-Fetch-Site":"none","Sec-Fetch-User":"?1","Upgrade-Insecure-Requests":"1","User-Agent":"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.6422.82 Mobile Safari/537.36"}'
)

SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'
PATH_IDX=0; CREATED=0; SKIPPED=0
NEXT_RPATH="" NEXT_XHTTP_HDR="" NEXT_WS_HDR="" NEXT_HU_HDR=""
NEXT_FP="" NEXT_PORT=0 RT_TARGET="" RT_SNS=""

advance() {
    local BIDX=$((PATH_IDX % ${#FP_POOL[@]}))
    NEXT_RPATH="${ALL_PATHS[$((PATH_IDX % ${#ALL_PATHS[@]}))]}"
    NEXT_XHTTP_HDR="${XHTTP_HDR_POOL[$BIDX]}"
    NEXT_WS_HDR="${WS_HDR_POOL[$BIDX]}"
    NEXT_HU_HDR="${HU_HDR_POOL[$BIDX]}"
    NEXT_FP="${FP_POOL[$BIDX]}"
    local RI=$((RANDOM % ${#REALITY_TARGETS[@]}))
    RT_TARGET="${REALITY_TARGETS[$RI]}"
    RT_SNS="${REALITY_SNS[$RI]}"
    NEXT_PORT=$((RANDOM % 45000 + 10000))
    ((PATH_IDX++))
}

do_insert() {
    local REMARK="$1" PROTO="$2" PORT="$3" SETTINGS="$4" STREAM="$5"
    SETTINGS=$(echo "$SETTINGS" | tr -d '\n')
    STREAM=$(echo "$STREAM" | tr -d '\n')
    local S_ESC="${SETTINGS//\'/\'\'}"; local ST_ESC="${STREAM//\'/\'\'}"
    local SN_ESC="${SNIFFING//\'/\'\'}"
    sqlite3 "$DB_FILE" \
"INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,listen,port,protocol,settings,stream_settings,tag,sniffing) \
VALUES (1,0,0,0,'${REMARK}',1,0,'',${PORT},'${PROTO}','${S_ESC}','${ST_ESC}','inbound-${PORT}','${SN_ESC}');"
    if [ $? -eq 0 ]; then
        local IID; IID=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")
        sqlite3 "$DB_FILE" \
"INSERT INTO client_traffics (inbound_id,enable,email,up,down,expiry_time,total) \
VALUES (${IID},1,'${PROTO}_${PORT}',0,0,0,0);"
        print_success "Created [${REMARK}]  port=${PORT}  fp=${NEXT_FP}"
        ((CREATED++))
    else
        print_error "DB insert failed: ${REMARK}"; ((SKIPPED++))
    fi
}

mkuuid()  { cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16; }
mk_vless() {
    local U="$1" F="$2" P="$3"; cat <<E
{"clients":[{"id":"${U}","flow":"${F}","email":"vless_${P}","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":"","subId":"","comment":"","reset":0}],"decryption":"none","fallbacks":[]}
E
}
mk_trojan() {
    local P="$1" PRT="$2"; cat <<E
{"clients":[{"password":"${P}","email":"trojan_${PRT}","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":"","subId":"","comment":"","reset":0}],"fallbacks":[]}
E
}
mk_ss() {
    local M="$1" P="$2" PRT="$3"; cat <<E
{"method":"${M}","password":"${P}","network":"tcp,udp","clients":[{"email":"ss_${PRT}","password":"${P}","method":"${M}","enable":true}]}
E
}

# ── VLESS Reality TCP ─────────────────────────────────────────────────────────
# sockopt: BBR + TFO | no host (Reality handles TLS layer)
create_vless_reality_tcp() {
    [ "$REALITY_OK" = false ] && { print_warn "SKIP: Reality keys unavailable"; ((SKIPPED++)); return; }
    advance
    local UUID SID1 SID2 SID3 S ST
    UUID=$(mkuuid); SID1=$(openssl rand -hex 4); SID2=$(openssl rand -hex 4); SID3=$(openssl rand -hex 8)
    S=$(mk_vless "$UUID" "xtls-rprx-vision" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"tcp","security":"reality","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"none"}},"realitySettings":{"show":false,"xver":0,"target":"${RT_TARGET}","serverNames":${RT_SNS},"privateKey":"${PRIVATE_KEY}","minClientVer":"","maxClientVer":"","maxTimediff":60,"shortIds":["${SID1}","${SID2}","${SID3}"],"settings":{"publicKey":"${PUBLIC_KEY}","fingerprint":"${NEXT_FP}","serverName":"","spiderX":"/"}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_Reality_TCP" "vless" "$NEXT_PORT" "$S" "$ST"
}

# ── VLESS Reality XHTTP ───────────────────────────────────────────────────────
# host="" (Reality SNI takes priority) | xPaddingObfsMode:true | sockopt
create_vless_reality_xhttp() {
    [ "$REALITY_OK" = false ] && { print_warn "SKIP: Reality keys unavailable"; ((SKIPPED++)); return; }
    advance
    local UUID SID1 SID2 SID3 S ST
    UUID=$(mkuuid); SID1=$(openssl rand -hex 4); SID2=$(openssl rand -hex 4); SID3=$(openssl rand -hex 8)
    S=$(mk_vless "$UUID" "" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"reality","xhttpSettings":{"path":"${NEXT_RPATH}","host":"","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"realitySettings":{"show":false,"xver":0,"target":"${RT_TARGET}","serverNames":${RT_SNS},"privateKey":"${PRIVATE_KEY}","minClientVer":"","maxClientVer":"","maxTimediff":60,"shortIds":["${SID1}","${SID2}","${SID3}"],"settings":{"publicKey":"${PUBLIC_KEY}","fingerprint":"${NEXT_FP}","serverName":"","spiderX":"/"}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_Reality_XHTTP" "vless" "$NEXT_PORT" "$S" "$ST"
}

# ── VLESS XHTTP plain ─────────────────────────────────────────────────────────
# host=PANEL_DOMAIN | xPaddingObfsMode:true | full browser headers | sockopt
create_vless_xhttp() {
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"none","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_XHTTP" "vless" "$NEXT_PORT" "$S" "$ST"
}

# ── VLESS WS TLS ──────────────────────────────────────────────────────────────
# host=PANEL_DOMAIN | heartbeatPeriod:30 | full WS headers | sockopt+BBR
create_vless_ws_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: VLESS-WS-TLS (no SSL cert)"; ((SKIPPED++)); return; }
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"ws","security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["http/1.1"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_WS_TLS" "vless" "$NEXT_PORT" "$S" "$ST"
}

# ── VLESS gRPC TLS ────────────────────────────────────────────────────────────
# authority=PANEL_DOMAIN | permit_without_stream:true (heartbeat) |
# health_check_timeout | idle_timeout | initial_windows_size | user_agent | sockopt
create_vless_grpc_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: VLESS-gRPC-TLS (no SSL cert)"; ((SKIPPED++)); return; }
    advance
    local UUID S ST SVC GRPC_UA
    UUID=$(mkuuid)
    SVC="${GRPC_SVCS[$((RANDOM % ${#GRPC_SVCS[@]}))]}"
    GRPC_UA="${GRPC_UA_POOL[$((RANDOM % ${#GRPC_UA_POOL[@]}))]}"
    S=$(mk_vless "$UUID" "" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"grpc","security":"tls","grpcSettings":{"authority":"${PANEL_DOMAIN}","serviceName":"${SVC}","multiMode":false,"idle_timeout":60,"health_check_timeout":20,"permit_without_stream":true,"initial_windows_size":65536,"user_agent":"${GRPC_UA}"},"tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["h2"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"sockopt":{${SO_GRPC}}}
ENDJSON
)
    do_insert "VLESS_gRPC_TLS" "vless" "$NEXT_PORT" "$S" "$ST"
}

# ── VLESS HttpUpgrade TLS ─────────────────────────────────────────────────────
# host=PANEL_DOMAIN | full HU headers | sockopt
create_vless_hu_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: VLESS-HU-TLS (no SSL cert)"; ((SKIPPED++)); return; }
    advance
    local UUID S ST
    UUID=$(mkuuid)
    S=$(mk_vless "$UUID" "" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"httpupgrade","security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["http/1.1"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"httpupgradeSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_HU_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "VLESS_HttpUpgrade_TLS" "vless" "$NEXT_PORT" "$S" "$ST"
}

# ── Trojan WS TLS ─────────────────────────────────────────────────────────────
# host=PANEL_DOMAIN | heartbeatPeriod:30 | full WS headers | sockopt
create_trojan_ws_tls() {
    [ "$SSL_OK" = false ] && { print_warn "SKIP: Trojan-WS-TLS (no SSL cert)"; ((SKIPPED++)); return; }
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"ws","security":"tls","tlsSettings":{"serverName":"${PANEL_DOMAIN}","allowInsecure":false,"fingerprint":"${NEXT_FP}","alpn":["http/1.1"],"minVersion":"1.2","maxVersion":"1.3","cipherSuites":"",${CERT_ENTRY}"rejectUnknownSni":false},"wsSettings":{"acceptProxyProtocol":false,"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","headers":${NEXT_WS_HDR},"heartbeatPeriod":30},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "Trojan_WS_TLS" "trojan" "$NEXT_PORT" "$S" "$ST"
}

# ── Trojan XHTTP ──────────────────────────────────────────────────────────────
# host=PANEL_DOMAIN | xPaddingObfsMode:true | full headers | sockopt
create_trojan_xhttp() {
    advance
    local PASS S ST
    PASS=$(openssl rand -hex 16)
    S=$(mk_trojan "$PASS" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"none","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "Trojan_XHTTP" "trojan" "$NEXT_PORT" "$S" "$ST"
}

# ── Shadowsocks TCP ───────────────────────────────────────────────────────────
# plain TCP | sockopt+BBR
create_ss_tcp() {
    local METHOD="${1:-aes-256-gcm}"
    advance
    local PASS S ST MU
    PASS=$(openssl rand -base64 24 | tr -d '=+/\n' | head -c 24)
    S=$(mk_ss "$METHOD" "$PASS" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"tcp","security":"none","tcpSettings":{"acceptProxyProtocol":false,"header":{"type":"none"}},"sockopt":{${SO_STD}}}
ENDJSON
)
    MU=$(echo "$METHOD" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    do_insert "SS_${MU}" "shadowsocks" "$NEXT_PORT" "$S" "$ST"
}

# ── Shadowsocks XHTTP ─────────────────────────────────────────────────────────
# host=PANEL_DOMAIN | xPaddingObfsMode:true | full headers | sockopt
create_ss_xhttp() {
    advance
    local PASS S ST
    PASS=$(openssl rand -base64 24 | tr -d '=+/\n' | head -c 24)
    S=$(mk_ss "aes-256-gcm" "$PASS" "$NEXT_PORT")
    ST=$(cat <<ENDJSON
{"network":"xhttp","security":"none","xhttpSettings":{"path":"${NEXT_RPATH}","host":"${PANEL_DOMAIN}","mode":"auto","scMaxEachPostBytes":"1000000","scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80","xPaddingBytes":"100-1000","xPaddingObfsMode":true,"noSSEHeader":false,"scMinPostsIntervalMs":"10","headers":${NEXT_XHTTP_HDR}},"sockopt":{${SO_STD}}}
ENDJSON
)
    do_insert "SS_XHTTP" "shadowsocks" "$NEXT_PORT" "$S" "$ST"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Preset Menu
# ══════════════════════════════════════════════════════════════════════════════
echo ""; print_line "  +----------------------------------------------------------+"
print_line "  SELECT INBOUND PRESET"; print_line "  +----------------------------------------------------------+"; echo ""
echo -e "${C1}  1)${NC} Direct / Anti-DPI"
echo -e "${C1}     ${NC}VLESS-Reality-TCP | VLESS-XHTTP | SS-AES256-TCP"
echo ""
echo -e "${C2}  2)${NC} CDN / Cloudflare"
echo -e "${C2}     ${NC}VLESS-WS-TLS | VLESS-gRPC-TLS | VLESS-HU-TLS | Trojan-WS-TLS"
echo ""
echo -e "${C3}  3)${NC} Balanced Redundancy"
echo -e "${C3}     ${NC}VLESS-XHTTP | VLESS-WS-TLS | VLESS-gRPC-TLS | SS-XHTTP"
echo ""
echo -e "${C4}  4)${NC} Full 5-Layer Stack"
echo -e "${C4}     ${NC}VLESS-WS-TLS | VLESS-gRPC-TLS | VLESS-XHTTP | Trojan-WS-TLS | SS-TCP"
echo ""
echo -e "${C5}  5)${NC} CDN + Direct Hybrid  [Iran load-balance]"
echo -e "${C5}     ${NC}VLESS-WS-TLS | VLESS-gRPC-TLS | VLESS-Reality-TCP"
echo ""
echo -e "${C6}  6)${NC} Stealth Balanced  [GoldIP recommended]"
echo -e "${C6}     ${NC}VLESS-Reality-TCP | VLESS-Reality-XHTTP | Trojan-WS-TLS | SS-ChaCha20"
echo ""

PRESET=""
while [[ ! "$PRESET" =~ ^[1-6]$ ]]; do
    echo -e "${BG_DMAGENTA}  Select preset (1-6):  ${NC}"
    echo -n -e "${C3}  preset > ${NC}"; read -r PRESET
done

echo ""; print_line "  +----------------------------------------------------------+"
print_line "  CREATING INBOUNDS — Preset ${PRESET}"
print_line "  +----------------------------------------------------------+"; echo ""

case $PRESET in
    1) create_vless_reality_tcp; create_vless_xhttp; create_ss_tcp "aes-256-gcm" ;;
    2) create_vless_ws_tls; create_vless_grpc_tls; create_vless_hu_tls; create_trojan_ws_tls ;;
    3) create_vless_xhttp; create_vless_ws_tls; create_vless_grpc_tls; create_ss_xhttp ;;
    4) create_vless_ws_tls; create_vless_grpc_tls; create_vless_xhttp; create_trojan_ws_tls; create_ss_tcp "aes-256-gcm" ;;
    5) create_vless_ws_tls; create_vless_grpc_tls; create_vless_reality_tcp ;;
    6) create_vless_reality_tcp; create_vless_reality_xhttp; create_trojan_ws_tls; create_ss_tcp "chacha20-poly1305" ;;
esac

echo ""; print_warn "Restarting x-ui..."
x-ui restart 2>/dev/null || systemctl restart x-ui
sleep 4
if systemctl is-active --quiet x-ui; then
    print_success "x-ui is running!"
else
    print_error "x-ui failed. Check: journalctl -u x-ui -n 80"
fi

echo ""; print_line "  +----------------------------------------------------------+"
print_line "  SETUP COMPLETE"; print_line "  +----------------------------------------------------------+"; echo ""
if [ "$SSL_OK" = true ]; then
    echo -e "${C4}  Panel URL : ${C1}https://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
else
    echo -e "${C3}  Panel URL : ${C8}http://${PANEL_DOMAIN}:${PANEL_PORT}${PANEL_PATH}${NC}"
fi
echo -e "${C2}  Username  : ${C7}${PANEL_USER}${NC}"; echo -e "${C5}  Password  : ${C9}${PANEL_PASS}${NC}"
echo -e "${C6}  Port      : ${C10}${PANEL_PORT}${NC}"; echo -e "${C8}  Path      : ${C3}${PANEL_PATH}${NC}"
echo ""; echo -e "${C1}  Inbounds created : ${CREATED}${NC}"; echo -e "${C3}  Skipped : ${SKIPPED}${NC}"
[ "$REALITY_OK" = true ] && echo -e "${C4}  Reality PubKey : ${NC}${PUBLIC_KEY}"
echo ""; print_success "Done! xray-core online."
print_line "  +----------------------------------------------------------+"
