#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TMPDIR="/tmp/v2ray-speedtest-$$"
XRAY_CONFIG="${TMPDIR}/config.json"
XRAY_PID=""
SOCKS_PORT=1080
HTTP_PORT=1081
USE_HTTP_PROXY=false

# ─── Cleanup ──────────────────────────────────────────────
cleanup() {
    [[ -n "$XRAY_PID" ]] && kill "$XRAY_PID" 2>/dev/null || true
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ─── Helpers ──────────────────────────────────────────────
log()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[+]${NC} $*"; }
err()  { echo -e "${RED}[!]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[~]${NC} $*"; }

usage() {
    cat <<EOF
${BOLD}V2Ray Speedtest${NC} — Test download/upload speed through a v2ray proxy

${BOLD}Usage:${NC}
    $0 "<config-uri>"

${BOLD}Supported protocols:${NC}
    vless://    vmess://    trojan://    ss://

${BOLD}Examples:${NC}
    $0 "vless://uuid@host:port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=example.com&fp=chrome&pbk=KEY&sid=ID&type=tcp#name"
    $0 "vmess://base64encoded"
    $0 "trojan://password@host:port?security=tls&sni=example.com#name"
    $0 "ss://base64encoded@host:port#name"

EOF
    exit 1
}

# ─── URL Decode ───────────────────────────────────────────
urldecode() {
    local encoded="${1//+/ }"
    printf '%b' "${encoded//%/\\x}"
}

# ─── Parse vless:// ───────────────────────────────────────
parse_vless() {
    local uri="$1"
    # vless://uuid@host:port?params#name
    local after_proto="${uri#vless://}"
    local fragment="${after_proto##*#}"
    [[ "$fragment" == "$after_proto" ]] && fragment=""
    local without_frag="${after_proto%%#*}"

    VLESS_UUID="${without_frag%%@*}"
    local after_uuid="${without_frag#*@}"
    local host_port="${after_uuid%%\?*}"
    VLESS_HOST="${host_port%%:*}"
    VLESS_PORT="${host_port##*:}"

    local query=""
    [[ "$after_uuid" == *"?"* ]] && query="${after_uuid#*\?}"

    # Defaults
    VLESS_FLOW=""
    VLESS_SECURITY="none"
    VLESS_SNI=""
    VLESS_FP="chrome"
    VLESS_PBK=""
    VLESS_SID=""
    VLESS_SPX=""
    VLESS_NET="tcp"
    VLESS_HEADER_TYPE=""
    VLESS_HOST_NAME=""

    # Parse query params
    IFS='&' read -ra params <<< "$query"
    for param in "${params[@]}"; do
        local key="${param%%=*}"
        local val="$(urldecode "${param#*=}")"
        case "$key" in
            flow)       VLESS_FLOW="$val" ;;
            encryption) ;; # always "none" for vless
            security)   VLESS_SECURITY="$val" ;;
            sni)        VLESS_SNI="$val" ;;
            fp)         VLESS_FP="$val" ;;
            pbk)        VLESS_PBK="$val" ;;
            sid)        VLESS_SID="$val" ;;
            spx)        VLESS_SPX="$val" ;;
            type)       VLESS_NET="$val" ;;
            headerType) VLESS_HEADER_TYPE="$val" ;;
            host)       VLESS_HOST_NAME="$val" ;;
            path)       VLESS_PATH="$val" ;;
        esac
    done

    CONFIG_NAME="$fragment"
}

# ─── Parse vmess:// ──────────────────────────────────────
parse_vmess() {
    local uri="$1"
    local b64="${uri#vmess://}"
    # Fix padding
    local mod=$((${#b64} % 4))
    if [[ $mod -eq 2 ]]; then b64="${b64}=="
    elif [[ $mod -eq 3 ]]; then b64="${b64}="
    fi
    local json
    json=$(echo "$b64" | base64 -d 2>/dev/null || echo "$b64" | base64 -d -i 2>/dev/null || echo "")

    VMESS_HOST=$(echo "$json" | jq -r '.add // .addr // empty')
    VMESS_PORT=$(echo "$json" | jq -r '.port // empty')
    VMESS_ID=$(echo "$json" | jq -r '.id // empty')
    VMESS_AID=$(echo "$json" | jq -r '.aid // "0"')
    VMESS_NET=$(echo "$json" | jq -r '.net // "tcp"')
    VMESS_TLS=$(echo "$json" | jq -r '.tls // "none"')
    VMESS_SNI=$(echo "$json" | jq -r '.sni // .host // empty')
    VMESS_HOST_NAME=$(echo "$json" | jq -r '.host // empty')
    VMESS_PATH=$(echo "$json" | jq -r '.path // empty')
    VMESS_FP=$(echo "$json" | jq -r '.fp // "chrome"')
    CONFIG_NAME=$(echo "$json" | jq -r '.ps // "vmess"')
}

# ─── Parse trojan:// ─────────────────────────────────────
parse_trojan() {
    local uri="$1"
    local after_proto="${uri#trojan://}"
    local fragment="${after_proto##*#}"
    [[ "$fragment" == "$after_proto" ]] && fragment=""
    local without_frag="${after_proto%%#*}"

    TROJAN_PASS="${without_frag%%@*}"
    local after_pass="${without_frag#*@}"
    local host_port="${after_pass%%\?*}"
    TROJAN_HOST="${host_port%%:*}"
    TROJAN_PORT="${host_port##*:}"

    local query=""
    [[ "$after_pass" == *"?"* ]] && query="${after_pass#*\?}"

    TROJAN_SNI=""
    TROJAN_SECURITY="tls"
    TROJAN_NET="tcp"
    TROJAN_FP="chrome"

    IFS='&' read -ra params <<< "$query"
    for param in "${params[@]}"; do
        local key="${param%%=*}"
        local val="$(urldecode "${param#*=}")"
        case "$key" in
            security)   TROJAN_SECURITY="$val" ;;
            sni)        TROJAN_SNI="$val" ;;
            type)       TROJAN_NET="$val" ;;
            fp)         TROJAN_FP="$val" ;;
            host)       TROJAN_HOST_NAME="$val" ;;
            path)       TROJAN_PATH="$val" ;;
        esac
    done

    CONFIG_NAME="$fragment"
}

# ─── Parse ss:// ──────────────────────────────────────────
parse_ss() {
    local uri="$1"
    local after_proto="${uri#ss://}"
    local fragment="${after_proto##*#}"
    [[ "$fragment" == "$after_proto" ]] && fragment=""
    local without_frag="${after_proto%%#*}"

    if [[ "$without_frag" == *"@"* ]]; then
        # ss://method:password@host:port
        local userinfo="${without_frag%%@*}"
        local host_port="${without_frag#*@}"
        # Try base64 decode userinfo
        local decoded
        decoded=$(echo "$userinfo" | base64 -d 2>/dev/null || echo "$userinfo")
        SS_METHOD="${decoded%%:*}"
        SS_PASS="${decoded#*:}"
        SS_HOST="${host_port%%:*}"
        local port_part="${host_port##*:}"
        SS_PORT="${port_part%%\?*}"
    else
        # ss://base64(method:password@host:port)
        local mod=$((${#without_frag} % 4))
        if [[ $mod -eq 2 ]]; then without_frag="${without_frag}=="
        elif [[ $mod -eq 3 ]]; then without_frag="${without_frag}="
        fi
        local decoded
        decoded=$(echo "$without_frag" | base64 -d 2>/dev/null || echo "")
        SS_METHOD="${decoded%%:*}"
        local rest="${decoded#*:}"
        SS_PASS="${rest%%@*}"
        local host_port="${rest#*@}"
        SS_HOST="${host_port%%:*}"
        SS_PORT="${host_port##*:}"
    fi

    CONFIG_NAME="$fragment"
}

# ─── Generate xray config JSON ───────────────────────────
generate_xray_config_vless() {
    local stream_settings
    if [[ "$VLESS_SECURITY" == "reality" ]]; then
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${VLESS_NET}",
            "security": "reality",
            "realitySettings": {
                "fingerprint": "${VLESS_FP}",
                "serverName": "${VLESS_SNI}",
                "publicKey": "${VLESS_PBK}",
                "shortId": "${VLESS_SID}",
                "spiderX": "${VLESS_SPX}"
            }
        }
SEOF
)
    elif [[ "$VLESS_SECURITY" == "tls" ]]; then
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${VLESS_NET}",
            "security": "tls",
            "tlsSettings": {
                "fingerprint": "${VLESS_FP}",
                "serverName": "${VLESS_SNI}"
            }
        }
SEOF
)
    else
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${VLESS_NET}",
            "security": "none"
        }
SEOF
)
    fi

    local flow_line=""
    [[ -n "$VLESS_FLOW" ]] && flow_line="\"flow\": \"${VLESS_FLOW}\","

    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": ${SOCKS_PORT},
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        },
        {
            "listen": "127.0.0.1",
            "port": ${HTTP_PORT},
            "protocol": "http"
        }
    ],
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "${VLESS_HOST}",
                        "port": ${VLESS_PORT},
                        "users": [
                            {
                                "id": "${VLESS_UUID}",
                                ${flow_line}
                                "encryption": "none"
                            }
                        ]
                    }
                ]
            },
            ${stream_settings}
        }
    ]
}
EOF
}

generate_xray_config_vmess() {
    local tls_sec="none"
    [[ "$VMESS_TLS" == "tls" ]] && tls_sec="tls"

    local stream_settings
    if [[ "$VMESS_TLS" == "tls" ]]; then
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${VMESS_NET}",
            "security": "tls",
            "tlsSettings": {
                "fingerprint": "${VMESS_FP}",
                "serverName": "${VMESS_SNI}"
            }
        }
SEOF
)
    else
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${VMESS_NET}",
            "security": "none"
        }
SEOF
)
    fi

    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": ${SOCKS_PORT},
            "protocol": "socks",
            "settings": { "udp": true }
        },
        {
            "listen": "127.0.0.1",
            "port": ${HTTP_PORT},
            "protocol": "http"
        }
    ],
    "outbounds": [
        {
            "protocol": "vmess",
            "settings": {
                "vnext": [
                    {
                        "address": "${VMESS_HOST}",
                        "port": ${VMESS_PORT},
                        "users": [
                            {
                                "id": "${VMESS_ID}",
                                "alterId": ${VMESS_AID},
                                "security": "auto"
                            }
                        ]
                    }
                ]
            },
            ${stream_settings}
        }
    ]
}
EOF
}

generate_xray_config_trojan() {
    local stream_settings
    if [[ "$TROJAN_SECURITY" == "tls" ]]; then
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${TROJAN_NET}",
            "security": "tls",
            "tlsSettings": {
                "fingerprint": "${TROJAN_FP}",
                "serverName": "${TROJAN_SNI}"
            }
        }
SEOF
)
    else
        stream_settings=$(cat <<SEOF
        "streamSettings": {
            "network": "${TROJAN_NET}",
            "security": "none"
        }
SEOF
)
    fi

    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": ${SOCKS_PORT},
            "protocol": "socks",
            "settings": { "udp": true }
        },
        {
            "listen": "127.0.0.1",
            "port": ${HTTP_PORT},
            "protocol": "http"
        }
    ],
    "outbounds": [
        {
            "protocol": "trojan",
            "settings": {
                "servers": [
                    {
                        "address": "${TROJAN_HOST}",
                        "port": ${TROJAN_PORT},
                        "password": "${TROJAN_PASS}"
                    }
                ]
            },
            ${stream_settings}
        }
    ]
}
EOF
}

generate_xray_config_ss() {
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": ${SOCKS_PORT},
            "protocol": "socks",
            "settings": { "udp": true }
        },
        {
            "listen": "127.0.0.1",
            "port": ${HTTP_PORT},
            "protocol": "http"
        }
    ],
    "outbounds": [
        {
            "protocol": "shadowsocks",
            "settings": {
                "servers": [
                    {
                        "address": "${SS_HOST}",
                        "port": ${SS_PORT},
                        "method": "${SS_METHOD}",
                        "password": "${SS_PASS}"
                    }
                ]
            }
        }
    ]
}
EOF
}

# ─── Wait for port ────────────────────────────────────────
wait_for_port() {
    local port=$1
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
        ((retries--))
    done
    return 1
}

# ─── Main ─────────────────────────────────────────────────
main() {
    local uri="${1:-}"

    [[ -z "$uri" ]] && usage

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}       V2Ray Speedtest via Proxy${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo ""

    # Detect protocol
    local proto
    proto=$(echo "$uri" | grep -oP '^[a-z]+(?=://)' || true)

    CONFIG_NAME=""
    local server_info=""

    case "$proto" in
        vless)
            log "Protocol: ${BOLD}VLESS${NC}"
            parse_vless "$uri"
            server_info="${VLESS_HOST}:${VLESS_PORT}"
            log "Server: ${BOLD}${server_info}${NC}"
            [[ "$VLESS_SECURITY" == "reality" ]] && log "Security: ${BOLD}REALITY${NC} (sni: ${VLESS_SNI})"
            [[ "$VLESS_SECURITY" == "tls" ]] && log "Security: ${BOLD}TLS${NC}"
            [[ -n "$VLESS_FLOW" ]] && log "Flow: ${BOLD}${VLESS_FLOW}${NC}"
            mkdir -p "$TMPDIR"
            generate_xray_config_vless
            ;;
        vmess)
            log "Protocol: ${BOLD}VMess${NC}"
            parse_vmess "$uri"
            server_info="${VMESS_HOST}:${VMESS_PORT}"
            log "Server: ${BOLD}${server_info}${NC}"
            [[ "$VMESS_TLS" == "tls" ]] && log "Security: ${BOLD}TLS${NC}"
            mkdir -p "$TMPDIR"
            generate_xray_config_vmess
            ;;
        trojan)
            log "Protocol: ${BOLD}Trojan${NC}"
            parse_trojan "$uri"
            server_info="${TROJAN_HOST}:${TROJAN_PORT}"
            log "Server: ${BOLD}${server_info}${NC}"
            mkdir -p "$TMPDIR"
            generate_xray_config_trojan
            ;;
        ss)
            log "Protocol: ${BOLD}Shadowsocks${NC}"
            parse_ss "$uri"
            server_info="${SS_HOST}:${SS_PORT}"
            log "Server: ${BOLD}${server_info}${NC}"
            log "Method: ${BOLD}${SS_METHOD}${NC}"
            mkdir -p "$TMPDIR"
            generate_xray_config_ss
            ;;
        *)
            err "Unsupported protocol: ${proto}://"
            err "Supported: vless://, vmess://, trojan://, ss://"
            exit 1
            ;;
    esac

    [[ -n "$CONFIG_NAME" ]] && log "Name: ${CONFIG_NAME}"

    # Start xray-core
    local xray_log="${TMPDIR}/xray.log"
    log "Starting xray-core..."
    xray run -c "$XRAY_CONFIG" > "$xray_log" 2>&1 &
    XRAY_PID=$!

    log "Waiting for SOCKS5 proxy on port ${SOCKS_PORT}..."
    if ! wait_for_port "$SOCKS_PORT"; then
        err "xray-core failed to start. Log:"
        cat "$xray_log" >&2
        err "Config:"
        cat "$XRAY_CONFIG" >&2
        exit 1
    fi
    ok "Proxy is ready"

    # Test proxy connectivity (SOCKS5)
    log "Testing SOCKS5 proxy on port ${SOCKS_PORT} (timeout 15s)..."
    local test_result test_code
    test_result=$(timeout 15 curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -v --connect-timeout 10 --max-time 12 -o /dev/null "http://cp.cloudflare.com/generate_204" 2>&1 || true)
    test_code=$(echo "$test_result" | grep -oP 'HTTP/\S+ \K\d+' | tail -1)
    if [[ "$test_code" == "204" || "$test_code" == "200" ]]; then
        ok "SOCKS5 proxy working (HTTP $test_code)"
    else
        warn "SOCKS5 test HTTP code: ${test_code:-none}"
        echo "$test_result" | grep -E "connect|error|refused|timed|fail" | tail -3
        # Try HTTP proxy on port 1081 as fallback
        log "Testing HTTP proxy on port ${HTTP_PORT} (timeout 15s)..."
        test_result=$(timeout 15 curl -x "http://127.0.0.1:${HTTP_PORT}" -v --connect-timeout 10 --max-time 12 -o /dev/null "http://cp.cloudflare.com/generate_204" 2>&1 || true)
        test_code=$(echo "$test_result" | grep -oP 'HTTP/\S+ \K\d+' | tail -1)
        if [[ "$test_code" == "204" || "$test_code" == "200" ]]; then
            ok "HTTP proxy working (HTTP $test_code)"
            log "Switching to HTTP proxy for tests..."
            USE_HTTP_PROXY=true
        else
            warn "HTTP proxy test code: ${test_code:-none}"
            echo "$test_result" | grep -E "connect|error|refused|timed|fail" | tail -3
        fi
    fi

    echo ""
    echo -e "${BOLD}───────────────────────────────────────────────${NC}"
    echo -e "${BOLD}  Running speed test...${NC}"
    echo -e "${BOLD}───────────────────────────────────────────────${NC}"
    echo ""

    # Run speedtest (official Ookla binary via SOCKS5 proxy env vars)
    log "Running speedtest through proxy..."
    local result=""
    local speedtest_exit=0
    result=$(ALL_PROXY="socks5://127.0.0.1:${SOCKS_PORT}" \
        http_proxy="socks5://127.0.0.1:${SOCKS_PORT}" \
        https_proxy="socks5://127.0.0.1:${SOCKS_PORT}" \
        speedtest --format=json --accept-license --accept-gdpr --progress=no 2>&1) || speedtest_exit=$?

    echo ""
    echo -e "${BOLD}───────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${BOLD}  Speed Test Results${NC}"
    echo -e "${BOLD}───────────────────────────────────────────────${NC}"
    echo ""

    # Show raw output for debugging
    if [[ -n "$result" ]]; then
        log "Speedtest raw output (first 5 lines):"
        echo "$result" | head -5 | while IFS= read -r line; do
            echo -e "  ${CYAN}${line}${NC}"
        done
    else
        warn "Speedtest produced no output (exit code: $speedtest_exit)"
    fi

    # Try to parse JSON output
    local ping_ms="" dl_bps="" ul_bps="" dl_mbps="" ul_mbps="" server_name=""
    if [[ -n "$result" ]]; then
        ping_ms=$(echo "$result" | jq -r '.ping.latency // empty' 2>/dev/null)
        dl_bps=$(echo "$result" | jq -r '.download.bandwidth // empty' 2>/dev/null)
        ul_bps=$(echo "$result" | jq -r '.upload.bandwidth // empty' 2>/dev/null)
        server_name=$(echo "$result" | jq -r '.server.name // empty' 2>/dev/null)
        local server_country
        server_country=$(echo "$result" | jq -r '.server.country // empty' 2>/dev/null)

        # Convert bytes/sec to Mbit/s (bandwidth is in bytes/sec)
        if [[ -n "$dl_bps" && "$dl_bps" != "0" ]]; then
            dl_mbps=$(echo "scale=2; ${dl_bps} * 8 / 1000000" | bc)
        fi
        if [[ -n "$ul_bps" && "$ul_bps" != "0" ]]; then
            ul_mbps=$(echo "scale=2; ${ul_bps} * 8 / 1000000" | bc)
        fi
    fi

    if [[ -n "$dl_mbps" ]]; then
        [[ -n "$server_name" ]] && echo -e "  Server: ${BOLD}${server_name}${NC} (${server_country})"
        [[ -n "$ping_ms" ]]     && echo -e "  ${CYAN}Ping: ${ping_ms} ms${NC}"
        echo -e "  ${GREEN}Download: ${dl_mbps} Mbit/s${NC}"
        echo -e "  ${YELLOW}Upload: ${ul_mbps} Mbit/s${NC}"
        echo ""
    else
        warn "Could not parse speedtest results, falling back to curl download test..."
        echo ""

        # Fallback: curl download test
        local test_urls=(
            "https://speed.cloudflare.com/__down?bytes=52428800"
            "http://speedtest.tele2.net/10MB.zip"
            "http://proof.ovh.net/files/10Mb.dat"
            "http://cachefly.cachefly.net/10mb.test"
        )

        local proxy_flag
        if [[ "${USE_HTTP_PROXY:-}" == "true" ]]; then
            proxy_flag="-x http://127.0.0.1:${HTTP_PORT}"
        else
            proxy_flag="--socks5-hostname 127.0.0.1:${SOCKS_PORT}"
        fi

        local dl_speed=""
        for url in "${test_urls[@]}"; do
            log "Trying: ${url}"
            local curl_out curl_err
            curl_err=$(curl $proxy_flag \
                -w "\n%{speed_download}" \
                -o /dev/null \
                --connect-timeout 10 --max-time 60 \
                "$url" 2>&1) || true
            curl_out=$(echo "$curl_err" | tail -1)

            if [[ -n "$curl_out" && "$curl_out" =~ ^[0-9] && "$curl_out" != "0" ]]; then
                local bytes_per_sec
                bytes_per_sec=$(printf "%.0f" "$curl_out")
                local mbps
                mbps=$(echo "scale=2; ${bytes_per_sec} * 8 / 1000000" | bc 2>/dev/null || echo "0")
                dl_speed="$mbps"
                break
            fi
        done

        echo -e "${BOLD}───────────────────────────────────────────────${NC}"
        echo -e "${GREEN}${BOLD}  Speed Test Results (curl fallback)${NC}"
        echo -e "${BOLD}───────────────────────────────────────────────${NC}"
        echo ""
        if [[ -n "$dl_speed" && "$dl_speed" != "0" ]]; then
            echo -e "  ${GREEN}Download: ${dl_speed} Mbit/s${NC}"
        else
            echo -e "  ${RED}Download: Failed${NC}"
        fi
        echo ""
    fi

    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
}

main "$@"
