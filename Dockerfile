FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates jq unzip bash procps \
    && rm -rf /var/lib/apt/lists/*

# Install official Ookla speedtest binary (direct download)
RUN ARCH=$(uname -m) \
    && case "$ARCH" in \
        x86_64)  SPEEDTEST_ARCH="x86_64" ;; \
        aarch64) SPEEDTEST_ARCH="aarch64" ;; \
        *)       echo "Unsupported arch: $ARCH"; exit 1 ;; \
    esac \
    && curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${SPEEDTEST_ARCH}.tgz" -o /tmp/speedtest.tgz \
    && tar -xzf /tmp/speedtest.tgz -C /usr/local/bin/ speedtest \
    && chmod +x /usr/local/bin/speedtest \
    && rm /tmp/speedtest.tgz \
    && mkdir -p /root/.config/ookla \
    && echo '{"Settings":{"LicenseAccepted":"true"}}' > /root/.config/ookla/speedtest-cli.json

ARG XRAY_VERSION=v26.3.27
RUN echo "Installing xray-core ${XRAY_VERSION}" \
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
