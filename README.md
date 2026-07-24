# V2Ray Speedtest

A Docker-based tool to test download and upload speed through a V2Ray/Xray proxy. Give it a proxy config URI and it tells you the real speed.

## Supported Protocols

| Protocol | URI Format |
|---|---|
| VLESS | `vless://uuid@host:port?params#name` |
| VMess | `vmess://base64encoded` |
| Trojan | `trojan://password@host:port?params#name` |
| Shadowsocks | `ss://base64encoded@host:port#name` |

## Quick Start

```bash
# 1. Build the Docker image (one time)
docker build -t v2ray-speedtest .

# 2. Run with your config
docker run --rm v2ray-speedtest "vless://uuid@host:port?params#name"
```

## Examples

### VLESS with Reality
```bash
docker run --rm v2ray-speedtest \
  "vless://0b4261b3-bd2c-478f-a41a-5e9bd8f44f61@server.com:16993?encryption=none&flow=xtls-rprx-vision&security=reality&sni=play.google.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&spx=%2F&type=tcp&headerType=none#reality"
```

### VMess
```bash
docker run --rm v2ray-speedtest "vmess://eyJhZGQiOi..."
```

### Trojan
```bash
docker run --rm v2ray-speedtest \
  "trojan://password@server.com:443?security=tls&sni=example.com&type=tcp#trojan"
```

### Shadowsocks
```bash
docker run --rm v2ray-speedtest "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@server.com:8388#ss"
```

## How It Works

1. Parses your config URI and extracts connection parameters
2. Generates an xray-core JSON config (local SOCKS5 proxy on port 1080)
3. Starts xray-core inside the container
4. Runs `speedtest-cli` through the SOCKS5 proxy (Ookla servers)
5. Reports download speed, upload speed, and ping
6. Cleans up and exits

If `speedtest-cli` fails, it falls back to a curl-based download test.

## Requirements

- Docker (that's it)

## Output Example

```
[*] Protocol: VLESS
[*] Server: server.com:16993
[*] Security: REALITY (sni: play.google.com)
[*] Flow: xtls-rprx-vision
[+] Proxy is ready

───────────────────────────────────────────────
  Running speed test...
───────────────────────────────────────────────

───────────────────────────────────────────────
  Speed Test Results
───────────────────────────────────────────────

  Ping: 120.456 ms
  Download: 45.67 Mbit/s
  Upload: 12.34 Mbit/s

═══════════════════════════════════════════════
```

---

# V2Ray Speedtest (فارسی)

ابزاری مبتنی بر Docker برای تست سرعت دانلود و آپلود از طریق پروکسی V2Ray/Xray. کافیه کانفیگ پروکسی خودتون رو بدید تا سرعت واقعی رو نشون بده.

## پروتکل‌های پشتیبانی شده

| پروتکل | فرمت URI |
|---|---|
| VLESS | `vless://uuid@host:port?params#name` |
| VMess | `vmess://base64encoded` |
| Trojan | `trojan://password@host:port?params#name` |
| Shadowsocks | `ss://base64encoded@host:port#name` |

## شروع سریع

```bash
# ۱. ساخت ایمیج Docker (یک بار)
docker build -t v2ray-speedtest .

# ۲. اجرا با کانفیگ شما
docker run --rm v2ray-speedtest "vless://uuid@host:port?params#name"
```

## مثال‌ها

### VLESS با Reality
```bash
docker run --rm v2ray-speedtest \
  "vless://0b4261b3-bd2c-478f-a41a-5e9bd8f44f61@server.com:16993?encryption=none&flow=xtls-rprx-vision&security=reality&sni=play.google.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&spx=%2F&type=tcp&headerType=none#reality"
```

### VMess
```bash
docker run --rm v2ray-speedtest "vmess://eyJhZGQiOi..."
```

### Trojan
```bash
docker run --rm v2ray-speedtest \
  "trojan://password@server.com:443?security=tls&sni=example.com&type=tcp#trojan"
```

### Shadowsocks
```bash
docker run --rm v2ray-speedtest "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@server.com:8388#ss"
```

## نحوه کارکرد

۱. کانفیگ URI شما رو پردازش می‌کنه و پارامترهای اتصال رو استخراج می‌کنه
۲. یک فایل کانفیگ JSON برای xray-core می‌سازه (پروکسی SOCKS5 محلی روی پورت ۱۰۸۰)
۳. xray-core رو داخل کانتینر اجرا می‌کنه
۴. `speedtest-cli` رو از طریق پروکسی SOCKS5 اجرا می‌کنه (سرورهای Ookla)
۵. سرعت دانلود، آپلود و پینگ رو نمایش می‌ده
۶. تمیزکاری می‌کنه و خارج می‌شه

اگه `speedtest-cli` کار نکنه، به تست دانلود با curl برمی‌گرده.

## پیش‌نیاز

- Docker (همین)

## نمونه خروجی

```
[*] Protocol: VLESS
[*] Server: server.com:16993
[*] Security: REALITY (sni: play.google.com)
[*] Flow: xtls-rprx-vision
[+] Proxy is ready

───────────────────────────────────────────────
  Running speed test...
───────────────────────────────────────────────

───────────────────────────────────────────────
  Speed Test Results
───────────────────────────────────────────────

  Ping: 120.456 ms
  Download: 45.67 Mbit/s
  Upload: 12.34 Mbit/s

═══════════════════════════════════════════════
```
