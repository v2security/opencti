# Connector Monitor

Giám sát connector OpenCTI qua Elasticsearch và gửi thông báo Telegram.

Gồm 2 chương trình độc lập:

| Chương trình | Mục đích | Lịch chạy |
|---|---|---|
| `connector-status` | Kiểm tra trạng thái hoạt động (active/down) của tất cả connector | Mỗi giờ |
| `connector-stats` | Tổng hợp thống kê chạy của ngày hôm qua (runs, items, errors) | Hàng ngày 08:00 ICT |

## Cấu trúc thư mục

```
monitor/
├── cmd/
│   ├── connector-status/main.go   # Chương trình 1: kiểm tra trạng thái
│   └── connector-stats/main.go    # Chương trình 2: thống kê sự kiện
├── internal/
│   ├── config/config.go           # Đọc config.yml + env override
│   ├── connstatus/                # Model + repo: trạng thái connector
│   │   ├── model.go               #   Connector struct, IsActive()
│   │   └── repo.go                #   Query ES internal_objects
│   ├── connstats/                 # Model + repo: thống kê work
│   │   ├── model.go               #   WorkStats struct
│   │   └── repo.go                #   Query ES history (aggregation)
│   ├── es/client.go               # HTTP client Elasticsearch dùng chung
│   └── telegram/sender.go         # Gửi message Telegram (MarkdownV2)
├── deploy/                        # Systemd service + timer
├── config.yml                     # Cấu hình
├── Makefile
└── go.mod
```

## Yêu cầu

- Go 1.21+
- Elasticsearch (cùng cluster với OpenCTI)
- Telegram Bot Token + Chat ID

## Cấu hình

File `config.yml`:

```yaml
elasticsearch:
  url: http://localhost:9200
  index_prefix: opencti

telegram:
  bot_token: "<BOT_TOKEN>"
  chat_id: "<CHAT_ID>"
  format: table  # "table", "text", hoặc "both"
```

- **table** (mặc định) — Bảng monospace, đẹp trên PC/tablet
- **text** — Danh sách text thường, dễ đọc trên điện thoại màn hình nhỏ
- **both** — Gửi cả 2 message liên tiếp

Có thể override bằng biến môi trường (ưu tiên cao hơn file):

| Biến môi trường | Ghi đè |
|---|---|
| `ES_URL` | `elasticsearch.url` |
| `TELEGRAM_BOT_TOKEN` | `telegram.bot_token` |
| `TELEGRAM_CHAT_ID` | `telegram.chat_id` |
| `TELEGRAM_FORMAT` | `telegram.format` |

## Build

```bash
make build
# Output: deploy/connector-status, deploy/connector-stats
```

## Chạy thử

```bash
# In ra terminal, không gửi Telegram
./deploy/connector-status --stdout-only
./deploy/connector-stats --stdout-only

# Gửi Telegram thật
./deploy/connector-status
./deploy/connector-stats
```

## Mẫu tin nhắn

### connector-status

**Dạng table** (format: table):
```
🔔 Connector Status
03/04/2026 11:00 +07
Total: 17  |  Active: 16  |  Inactive: 1

 Connector                  │ Status   │ Last Ping
────────────────────────────┼──────────┼────────────────
 NVD CVE (V2Secure)         │ ● OK     │ 11:00
 OpenCTI LLM/RAG Connector  │ ○ DOWN   │ 11:49 (23 giờ)
```

**Dạng text** (format: text) — dễ đọc trên điện thoại:
```
🔔 Connector Status
03/04/2026 11:00 +07
Total: 17  |  Active: 16  |  Inactive: 1

⚠️ DOWN:
  ○ OpenCTI LLM/RAG Connector
     Ping: 11:49 (23 giờ trước)

✅ Active:
  ● NVD CVE (V2Secure) — 11:00
  ● MISP OSINT Feed — 11:00
  ...
```

- **● OK** — Connector đang hoạt động bình thường (heartbeat trong 5 phút gần nhất)
- **○ DOWN** — Connector không phản hồi, kèm thời gian kể từ lần ping cuối

### connector-stats

**Dạng table** (format: table):
```
📊 Connector Stats
02/04/2026  (02/04 00:00 → 02/04 23:59)

• Runs — Số lần connector chạy (work cycle)
• Items — Số đối tượng STIX đã xử lý
• Errors — Số lỗi phát sinh khi import

Tổng: 16 runs  |  191,779 items  |  2 errors

 Connector                  │  Runs │   Items │ Errors
────────────────────────────┼───────┼─────────┼────────
 NVD CVE (V2Secure)         │     6 │  27,664 │      0
 MISP OSINT Feed            │     2 │ 163,392 │ !    2
────────────────────────────┼───────┼─────────┼────────
 TOTAL                      │    16 │ 191,779 │      2
```

**Dạng text** (format: text) — dễ đọc trên điện thoại:
```
📊 Connector Stats
02/04/2026  (02/04 00:00 → 02/04 23:59)

Tổng: 16 runs  |  191,779 items  |  2 errors

⚠️ Có lỗi:
  ❌ MISP OSINT Feed
     2 runs · 163,392 items · 2 errors

📦 Đã xử lý:
  ✅ NVD CVE (V2Secure)
     6 runs · 27,664 items

💤 Idle (không có runs):
  Shodan, SOCRadar, ImportDocument, ...
```

- **Runs** — Số lần connector thực hiện 1 chu kỳ work
- **Items** — Tổng số đối tượng STIX (indicator, malware, relationship...) đã xử lý
- **Errors** — Số lỗi trong quá trình import, dòng có `!` là connector có lỗi

## Deploy (systemd)

```bash
# Tạo thư mục
sudo mkdir -p /opt/connector/monitor

# Copy binary và config
cd v2-connectors/monitor
sudo cp deploy/connector-status deploy/connector-stats /opt/connector/monitor/
sudo cp config.yml /opt/connector/monitor/config.yml

# Copy systemd units
sudo cp deploy/*.service deploy/*.timer /etc/systemd/system/

# Enable timers
sudo systemctl daemon-reload
sudo systemctl enable --now connector-status.timer
sudo systemctl enable --now connector-stats.timer

# Kiểm tra
systemctl list-timers connector-*
```

| Timer | Lịch | Mô tả |
|---|---|---|
| `connector-status.timer` | Mỗi giờ (`*:00:00`) | Kiểm tra trạng thái connector |
| `connector-stats.timer` | 01:00 UTC = 08:00 ICT | Thống kê ngày hôm qua |

## Xem log

```bash
journalctl -u connector-status --since today
journalctl -u connector-stats --since today
```
