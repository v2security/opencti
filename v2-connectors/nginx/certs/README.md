# Certificates

Đặt certificate và private key cho các proxy tại đây.

Nginx chỉ cần **server certificate** để HTTPS hoạt động — client không cần cung cấp certificate.

Nếu cần dựng nhanh môi trường nội bộ, chạy:

```bash
../generate-self-signed-cert.sh <common-name>
```

Hiện tại proxy dùng tên generic:

- `cert.pem` — server certificate (public)
- `key.pem` — private key

Mount vào container:

- `/etc/nginx/certs/cert.pem`
- `/etc/nginx/certs/key.pem`

Không commit private key thật vào git.