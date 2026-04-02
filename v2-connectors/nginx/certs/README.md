# Certificates

Đặt certificate và private key cho các proxy tại đây.

Nếu cần dựng nhanh môi trường nội bộ, chạy:

`../generate-self-signed-cert.sh <common-name>`

Hiện tại proxy dùng tên generic:

- `tls.crt`
- `tls.key`

Ví dụ mount trong container:

- `/etc/nginx/certs/tls.crt`
- `/etc/nginx/certs/tls.key`

Không commit private key thật vào git.