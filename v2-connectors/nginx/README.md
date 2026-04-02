# Nginx Reverse Proxies for Custom Connectors

Thư mục này chứa các reverse proxy dùng chung cho custom connectors trong `v2-connectors`.

## Convention

- Dùng **một** container Nginx chung cho tất cả connectors.
- Cấu hình được mount từ host, không build image riêng cho từng connector.
- Mỗi connector có thể có một file cấu hình riêng dưới `nginx/conf.d/`.
- Ví dụ hiện tại:
  - `nginx/conf.d/botnet.conf`

## Naming

- Tên service trong `docker-compose-connector.yml` nên theo kiểu hạ tầng dùng chung, ví dụ:
  - `reverse-proxy-connectors`
- Tên container nên phản ánh vai trò hạ tầng chung, không gắn chặt với một connector nếu sau này còn mở rộng.

## Responsibilities

Proxy layer nên xử lý các concern hạ tầng, không đẩy xuống app connector:

- HTTPS / TLS termination
- IP whitelist / deny rules
- request size limits
- forwarding headers (`X-Forwarded-For`, `X-Forwarded-Proto`)

App connector chỉ nên giữ logic nghiệp vụ:

- nhận file
- parse dữ liệu
- đẩy STIX vào OpenCTI
- retry / xóa file sau xử lý

## Current layout

```
nginx/
├── certs/
│   └── README.md
├── conf.d/
│   └── botnet.conf
└── nginx.conf
```

## Certificates

- Nginx đọc certificate từ `nginx/certs/`.
- Hiện tại các proxy dùng tên generic:
  - `/etc/nginx/certs/tls.crt`
  - `/etc/nginx/certs/tls.key`
- Thư mục này được mount read-only vào container.
- Không commit private key thật vào git.
- Nếu chưa có cert chính thức, có thể tạo self-signed cert nhanh bằng:
  - `./nginx/generate-self-signed-cert.sh <common-name>`

## Access control

- IP whitelist nên đặt trong `nginx/conf.d/*.conf`.
- Không đặt whitelist IP trong `config.yml` của connector app.
- App connector chỉ nên kiểm tra `X-Api-Key` hoặc rule nghiệp vụ nội bộ.

## Published ports

Để tránh đụng port khi thêm proxy mới, cần ghi rõ proxy nào đang publish port nào ra host.

| Proxy service | Purpose | Host port | Upstream |
|---|---|---:|---|
| `reverse-proxy-connectors` | HTTPS reverse proxy cho botnet upload API | `21000` | `127.0.0.1:20000` |

Khi thêm proxy mới, cập nhật bảng này ngay cùng lúc với thay đổi compose.