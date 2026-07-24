FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates python3 python3-pip jq unzip bash procps \
    && pip3 install --break-system-packages speedtest-cli \
    && rm -rf /var/lib/apt/lists/*

ARG XRAY_VERSION
RUN XRAY_VERSION=${XRAY_VERSION:-$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)} \
    && echo "Installing xray-core ${XRAY_VERSION}" \
    && ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64)  XRAY_ARCH="64" ;; \
        aarch64) XRAY_ARCH="arm64-v8a" ;; \
        armv7l)  XRAY_ARCH="arm32-v7a" ;; \
        *)       echo "Unsupported arch: $ARCH"; exit 1 ;; \
    esac \
    && curl -sL "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip \
    && unzip /tmp/xray.zip xray -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm /tmp/xray.zip

COPY v2ray-speedtest.sh /usr/local/bin/v2ray-speedtest
RUN chmod +x /usr/local/bin/v2ray-speedtest

ENTRYPOINT ["v2ray-speedtest"]
