#!/bin/bash
# =============================================================================
# DEPLOY OPENCTI OFFLINE — Rocky Linux 9
# =============================================================================
#
# Tất cả services chạy bằng ROOT (trừ Elasticsearch — ES bắt buộc user riêng)
#
# File mapping (package → server):
# ┌─────────────────────────────────────────────┬──────────────────────────────────────────────────┐
# │ Source (trong package)                      │ Target (trên server)                             │
# ├─────────────────────────────────────────────┼──────────────────────────────────────────────────┤
# │ files/python312.tar.gz                      │ /opt/python312/                                  │
# │ files/elasticsearch-*.tar.gz                │ /opt/elasticsearch/                              │
# │ files/rabbitmq-server-*.tar.xz              │ /opt/rabbitmq/                                   │
# │ files/minio                                 │ /opt/minio/bin/minio                             │
# │ files/mc                                    │ /tmp/mc                                          │
# │ files/opencti.tar.gz                        │ /opt/opencti/                                    │
# │ files/opencti-worker.tar.gz                 │ /opt/opencti-worker/                             │
# │ rpm/*.rpm                                   │ system packages (dnf localinstall)               │
# ├─────────────────────────────────────────────┼──────────────────────────────────────────────────┤
# │ config/elasticsearch.yml                    │ /etc/elasticsearch/elasticsearch.yml             │
# │ config/elasticsearch-jvm.options            │ /etc/elasticsearch/jvm.options.d/opencti.options  │
# │ config/elasticsearch.service                │ /etc/systemd/system/elasticsearch.service        │
# │ config/rabbitmq-server.service              │ /etc/systemd/system/rabbitmq-server.service      │
# │ config/90-opencti.conf                      │ /etc/rabbitmq/rabbitmq.conf                      │
# │ config/minio.service                        │ /etc/systemd/system/minio.service                │
# │ config/start.sh                             │ /etc/opencti/start.sh                            │
# │ config/opencti.service                      │ /etc/systemd/system/opencti.service              │
# │ config/opencti-worker@.service              │ /etc/systemd/system/opencti-worker@.service      │
# │ config/opencti-logrotate.conf               │ /etc/logrotate.d/opencti                         │
# └─────────────────────────────────────────────┴──────────────────────────────────────────────────┘
#
# File layout sau khi deploy:
#   /opt/python312/                  ← Python 3.12.8 (compiled, --enable-shared, libpython3.12.so)
#   /opt/elasticsearch/              ← Elasticsearch 8.17.0 binaries (user: elasticsearch)
#   /opt/rabbitmq/                   ← RabbitMQ 4.1.0 binaries (user: root)
#   /opt/minio/                      ← MinIO server binary (user: root)
#   /opt/opencti/                    ← OpenCTI Platform code (user: root)
#   /opt/opencti-worker/             ← OpenCTI Worker code (user: root)
#   /etc/opencti/                    ← Platform config (start.sh, ssl/)
#   /etc/opencti-worker/             ← Worker config (config.yml, worker.env)
#   /etc/elasticsearch/              ← Elasticsearch config
#   /var/lib/elasticsearch/          ← Elasticsearch data
#   /var/lib/minio/                  ← MinIO data
#   /var/log/v2-ti/opencti/          ← Platform logs (logrotate daily, 30 ngày)
#   /var/log/v2-ti/opencti-worker/   ← Worker logs (logrotate daily, 30 ngày)
#   /var/log/v2-ti/elasticsearch/    ← Elasticsearch logs (logrotate daily, 14 ngày)
#   /var/log/v2-ti/rabbitmq/         ← RabbitMQ logs (logrotate daily, 14 ngày)
#
# =============================================================================
set -e

DEPLOY_DIR="${DEPLOY_DIR:-/root/opencti-deploy}"
WORKERS=3
TOTAL_STEPS=14

info()   { echo ""; echo "══════════════════════════════════════════════════════════════"; echo "  [STEP $1/$TOTAL_STEPS] $2"; echo "══════════════════════════════════════════════════════════════"; }
detail() { echo "  → $*"; }
ok()     { echo "  ✓ $*"; }
warn()   { echo "  ⚠ $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

wait_for() {
  local name=$1 cmd=$2 t=${3:-60}
  echo -n "  ⏳ Đợi $name"
  for _ in $(seq 1 "$t"); do
    eval "$cmd" &>/dev/null && { echo ""; ok "$name ready"; return 0; }
    echo -n "."
    sleep 1
  done
  echo ""
  warn "$name chưa sẵn sàng sau ${t}s"
  return 1
}

[[ $EUID -eq 0 ]] || die "Cần chạy với quyền root"
[[ -d "$DEPLOY_DIR" ]] || die "Không tìm thấy $DEPLOY_DIR"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        DEPLOY OPENCTI OFFLINE — Rocky Linux 9             ║"
echo "║        Tất cả services chạy bằng ROOT                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Source: $DEPLOY_DIR"
echo "  Code:   /opt/{python312,elasticsearch,rabbitmq,minio,opencti,opencti-worker}"
echo "  Config: /etc/{opencti,opencti-worker,elasticsearch,rabbitmq}"
echo "  Data:   /var/lib/{elasticsearch,minio,rabbitmq,redis}"
echo "  Logs:   /var/log/v2-ti/{opencti,opencti-worker,elasticsearch,rabbitmq}"
echo ""

# ══════════════════════════════════════════════════════════════
# PARSE VARIABLES from config/start.sh (nguồn sự thật duy nhất)
# ══════════════════════════════════════════════════════════════
START_SH="$DEPLOY_DIR/config/start.sh"
[[ -f "$START_SH" ]] || die "Không tìm thấy $START_SH — cần file này để đọc biến cấu hình"
detail "Đọc biến cấu hình từ: $START_SH"
while IFS= read -r line; do
  # Đọc tất cả biến OpenCTI: APP__, REDIS__, ELASTICSEARCH__, MINIO__, RABBITMQ__, SMTP__, PROVIDERS__, AI__, CHATBOT__
  if [[ "$line" =~ ^export[[:space:]]+(APP__|REDIS__|ELASTICSEARCH__|MINIO__|RABBITMQ__|SMTP__|PROVIDERS__|AI__|CHATBOT__) ]]; then
    eval "$line" 2>/dev/null || true
  fi
done < "$START_SH"

# Verify critical variables
[[ -n "${APP__PORT:-}" ]]            || die "Thiếu APP__PORT trong start.sh"
[[ -n "${APP__ADMIN__EMAIL:-}" ]]    || die "Thiếu APP__ADMIN__EMAIL trong start.sh"
[[ -n "${APP__ADMIN__PASSWORD:-}" ]] || die "Thiếu APP__ADMIN__PASSWORD trong start.sh"
[[ -n "${APP__ADMIN__TOKEN:-}" ]]    || die "Thiếu APP__ADMIN__TOKEN trong start.sh"
[[ -n "${REDIS__PASSWORD:-}" ]]      || die "Thiếu REDIS__PASSWORD trong start.sh"
[[ -n "${RABBITMQ__USERNAME:-}" ]]   || die "Thiếu RABBITMQ__USERNAME trong start.sh"
[[ -n "${RABBITMQ__PASSWORD:-}" ]]   || die "Thiếu RABBITMQ__PASSWORD trong start.sh"
[[ -n "${MINIO__ACCESS_KEY:-}" ]]    || die "Thiếu MINIO__ACCESS_KEY trong start.sh"
[[ -n "${MINIO__SECRET_KEY:-}" ]]    || die "Thiếu MINIO__SECRET_KEY trong start.sh"

# SSL paths (từ start.sh hoặc mặc định)
SSL_KEY_PATH="${APP__HTTPS_CERT__KEY:-/etc/opencti/ssl/opencti.key}"
SSL_CRT_PATH="${APP__HTTPS_CERT__CRT:-/etc/opencti/ssl/opencti.crt}"

ok "Đã đọc biến từ start.sh (Port=${APP__PORT}, Admin=${APP__ADMIN__EMAIL}, Token=${APP__ADMIN__TOKEN:0:8}...)"
echo ""

# ══════════════════════════════════════════════════════════════
# STEP 1: System configuration
# ══════════════════════════════════════════════════════════════
info 1 "Cấu hình hệ thống"
detail "Set vm.max_map_count=1048575 (yêu cầu bởi Elasticsearch)"
grep -q 'vm.max_map_count=1048575' /etc/sysctl.conf 2>/dev/null || \
  echo "vm.max_map_count=1048575" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=1048575 &>/dev/null || true
ok "sysctl configured"

# ══════════════════════════════════════════════════════════════
# STEP 2: Install RPM packages
# ══════════════════════════════════════════════════════════════
info 2 "Cài RPM packages"
detail "Source: $DEPLOY_DIR/rpm/*.rpm"
detail "Bao gồm: Node.js 22, Redis 6.2, Erlang 27, system libs"
cd "$DEPLOY_DIR/rpm"
dnf module enable -y nodejs:22 &>/dev/null || true
dnf localinstall -y --allowerasing *.rpm &>/dev/null || \
  yum localinstall -y --allowerasing *.rpm
ok "$(ls *.rpm | wc -l) RPMs installed"

# ══════════════════════════════════════════════════════════════
# STEP 3: Verify Node.js
# ══════════════════════════════════════════════════════════════
info 3 "Kiểm tra Node.js"
if ! command -v node &>/dev/null; then
  detail "Fallback: rpm -Uvh nodejs-*.rpm"
  cd "$DEPLOY_DIR/rpm"
  rpm -Uvh --force --nodeps nodejs-*.rpm &>/dev/null || true
fi
command -v node &>/dev/null || die "Node.js không cài được"
ok "Node.js $(node --version) → $(which node)"

# ══════════════════════════════════════════════════════════════
# STEP 4: Install Python 3.12
# ══════════════════════════════════════════════════════════════
info 4 "Cài Python 3.12 (compiled, --enable-shared)"
detail "Copy: $DEPLOY_DIR/files/python312.tar.gz → /opt/python312/"
if [[ ! -d /opt/python312 ]]; then
  [[ -f "$DEPLOY_DIR/files/python312.tar.gz" ]] || die "Thiếu files/python312.tar.gz"
  tar -xzf "$DEPLOY_DIR/files/python312.tar.gz" -C /opt/
fi
detail "Symlink: /opt/python312/bin/python3.12 → /usr/local/bin/python3.12"
ln -sf /opt/python312/bin/python3.12 /usr/local/bin/python3.12 2>/dev/null || true
detail "Symlink: /opt/python312/bin/python3.12 → /usr/local/bin/python3"
ln -sf /opt/python312/bin/python3.12 /usr/local/bin/python3 2>/dev/null || true
detail "Symlink: /opt/python312/bin/pip3.12 → /usr/local/bin/pip3"
ln -sf /opt/python312/bin/pip3.12 /usr/local/bin/pip3 2>/dev/null || true
detail "Verify Python 3.12..."
/opt/python312/bin/python3.12 --version || die "Python 3.12 lỗi"
/opt/python312/bin/python3.12 -c "import ctypes; print('ctypes OK')" || die "_ctypes lỗi"
ls /opt/python312/lib/libpython3.12.so.1.0 &>/dev/null || die "libpython3.12.so not found"
ok "Python $(/opt/python312/bin/python3.12 --version 2>&1 | awk '{print $2}') → /opt/python312"
ok "libpython3.12.so.1.0 → /opt/python312/lib/"

# ══════════════════════════════════════════════════════════════
# STEP 5: Install Elasticsearch
# ══════════════════════════════════════════════════════════════
info 5 "Cài Elasticsearch"
detail "Extract: $DEPLOY_DIR/files/elasticsearch-*.tar.gz → /opt/elasticsearch/"
if [[ ! -d /opt/elasticsearch ]]; then
  tar -xzf "$DEPLOY_DIR"/files/elasticsearch-*.tar.gz -C /opt/
  mv /opt/elasticsearch-* /opt/elasticsearch 2>/dev/null || true
fi
# ES bắt buộc chạy user riêng (hard-coded check trong bin/elasticsearch, không thể bypass)
detail "Tạo user: elasticsearch (ES bắt buộc user riêng, không thể chạy root)"
useradd -r -m -d /opt/elasticsearch elasticsearch -s /sbin/nologin 2>/dev/null || true
# Config → /etc/elasticsearch/ (tách khỏi binaries)
mkdir -p /etc/elasticsearch/jvm.options.d
detail "Copy: config/elasticsearch.yml → /etc/elasticsearch/"
cp "$DEPLOY_DIR"/config/elasticsearch.yml /etc/elasticsearch/
detail "Copy: config/elasticsearch-jvm.options → /etc/elasticsearch/jvm.options.d/opencti.options"
cp "$DEPLOY_DIR"/config/elasticsearch-jvm.options /etc/elasticsearch/jvm.options.d/opencti.options
# Copy các file config mặc định từ ES distribution (nếu chưa có)
for f in /opt/elasticsearch/config/*.yml /opt/elasticsearch/config/*.properties; do
  [[ -f "$f" ]] && [[ ! -f "/etc/elasticsearch/$(basename "$f")" ]] && \
    cp "$f" /etc/elasticsearch/ 2>/dev/null || true
done
[[ -d /opt/elasticsearch/config/jvm.options.d ]] && \
  cp -n /opt/elasticsearch/config/jvm.options.d/* /etc/elasticsearch/jvm.options.d/ 2>/dev/null || true
[[ -f /opt/elasticsearch/config/jvm.options ]] && \
  cp -n /opt/elasticsearch/config/jvm.options /etc/elasticsearch/ 2>/dev/null || true
chown -R elasticsearch:elasticsearch /etc/elasticsearch
# Data → /var/lib/elasticsearch/
mkdir -p /var/lib/elasticsearch
chown elasticsearch:elasticsearch /var/lib/elasticsearch
# Logs → /var/log/v2-ti/elasticsearch/
mkdir -p /var/log/v2-ti/elasticsearch
chown elasticsearch:elasticsearch /var/log/v2-ti/elasticsearch
# Tmp cho ES
mkdir -p /opt/elasticsearch/tmp
chown -R elasticsearch:elasticsearch /opt/elasticsearch
detail "Copy: config/elasticsearch.service → /etc/systemd/system/"
cp "$DEPLOY_DIR"/config/elasticsearch.service /etc/systemd/system/
ok "Elasticsearch → /opt/elasticsearch (config: /etc/elasticsearch, data: /var/lib/elasticsearch, logs: /var/log/v2-ti/elasticsearch)"

# ══════════════════════════════════════════════════════════════
# STEP 6: Install RabbitMQ
# ══════════════════════════════════════════════════════════════
info 6 "Cài RabbitMQ (chạy bằng root)"
detail "Extract: $DEPLOY_DIR/files/rabbitmq-server-generic-unix-*.tar.xz → /opt/rabbitmq/"
if [[ ! -d /opt/rabbitmq/sbin ]]; then
  mkdir -p /opt/rabbitmq
  tar -xf "$DEPLOY_DIR"/files/rabbitmq-server-generic-unix-*.tar.xz \
    --strip-components=1 -C /opt/rabbitmq
fi
mkdir -p /var/lib/rabbitmq/mnesia /var/log/v2-ti/rabbitmq /etc/rabbitmq
chmod 755 /var/lib/rabbitmq /var/lib/rabbitmq/mnesia /var/log/v2-ti/rabbitmq /etc/rabbitmq 2>/dev/null || true
detail "Symlink: /opt/rabbitmq/sbin/* → /usr/local/bin/"
for bin in /opt/rabbitmq/sbin/*; do
  ln -sf "$bin" /usr/local/bin/"$(basename "$bin")"
done
detail "Copy: config/90-opencti.conf → /etc/rabbitmq/rabbitmq.conf"
cp "$DEPLOY_DIR"/config/90-opencti.conf /etc/rabbitmq/rabbitmq.conf
detail "Copy: config/rabbitmq-server.service → /etc/systemd/system/"
cp "$DEPLOY_DIR"/config/rabbitmq-server.service /etc/systemd/system/
ok "RabbitMQ → /opt/rabbitmq (user: root, HOME=/root → Erlang cookie tại /root/.erlang.cookie)"

# ══════════════════════════════════════════════════════════════
# STEP 7: Install MinIO
# ══════════════════════════════════════════════════════════════
info 7 "Cài MinIO (chạy bằng root)"
mkdir -p /opt/minio/bin /var/lib/minio/data
chmod 755 /var/lib/minio/data
detail "Copy: $DEPLOY_DIR/files/minio → /opt/minio/bin/minio"
cp "$DEPLOY_DIR"/files/minio /opt/minio/bin/ && chmod +x /opt/minio/bin/minio
detail "Copy: $DEPLOY_DIR/files/mc → /tmp/mc"
cp "$DEPLOY_DIR"/files/mc /tmp/ && chmod +x /tmp/mc
detail "Write: /etc/default/minio (MINIO_ROOT_USER=${MINIO__ACCESS_KEY})"
cat > /etc/default/minio <<EOF
MINIO_ROOT_USER=${MINIO__ACCESS_KEY}
MINIO_ROOT_PASSWORD=${MINIO__SECRET_KEY}
MINIO_VOLUMES="/var/lib/minio/data"
MINIO_OPTS="--console-address :9001"
EOF
chmod 600 /etc/default/minio
detail "Copy: config/minio.service → /etc/systemd/system/"
cp "$DEPLOY_DIR"/config/minio.service /etc/systemd/system/
ok "MinIO → /opt/minio (user: root)"

# ══════════════════════════════════════════════════════════════
# STEP 8: Configure Redis
# ══════════════════════════════════════════════════════════════
info 8 "Cấu hình Redis (chạy bằng root)"
REDIS_CONF=""
for f in /etc/redis/redis.conf /etc/redis.conf; do
  [[ -f "$f" ]] && { REDIS_CONF="$f"; break; }
done
if [[ -n "$REDIS_CONF" ]]; then
  detail "Set password trong $REDIS_CONF (từ start.sh REDIS__PASSWORD)"
  if grep -q '^# *requirepass' "$REDIS_CONF"; then
    sed -i "s/^# *requirepass .*/requirepass ${REDIS__PASSWORD}/" "$REDIS_CONF"
  elif grep -q '^requirepass' "$REDIS_CONF"; then
    sed -i "s/^requirepass .*/requirepass ${REDIS__PASSWORD}/" "$REDIS_CONF"
  else
    echo "requirepass ${REDIS__PASSWORD}" >> "$REDIS_CONF"
  fi
  chmod 640 "$REDIS_CONF"
  # Đổi Redis service sang root
  detail "Modify Redis systemd service → User=root"
  REDIS_SVC=$(find /usr/lib/systemd/system /etc/systemd/system -name 'redis.service' 2>/dev/null | head -1)
  if [[ -n "$REDIS_SVC" ]]; then
    sed -i 's/^User=.*/User=root/' "$REDIS_SVC" 2>/dev/null || true
    sed -i 's/^Group=.*/Group=root/' "$REDIS_SVC" 2>/dev/null || true
    detail "Modified: $REDIS_SVC"
  fi
  # Fix Redis data dir permissions for root user
  for rdir in /var/lib/redis /var/lib/redis/data; do
    [[ -d "$rdir" ]] && chown root:root "$rdir" && chmod 755 "$rdir"
  done
  ok "Redis password set (user: root)"
else
  warn "Không tìm thấy redis.conf — Redis sẽ chạy không password"
fi

# ══════════════════════════════════════════════════════════════
# STEP 9: Firewall + systemd reload
# ══════════════════════════════════════════════════════════════
info 9 "Cấu hình firewall + systemd"
detail "Open ports: ${APP__PORT} (OpenCTI), ${RABBITMQ__PORT}/${RABBITMQ__PORT_MANAGEMENT} (RabbitMQ), ${MINIO__PORT}/9001 (MinIO), 9200 (ES)"
for port in ${APP__PORT} ${RABBITMQ__PORT} ${RABBITMQ__PORT_MANAGEMENT} ${MINIO__PORT} 9001 9200; do
  firewall-cmd --permanent --add-port=${port}/tcp &>/dev/null || true
done
firewall-cmd --reload &>/dev/null || true
detail "systemctl daemon-reload"
systemctl daemon-reload
ok "Firewall + systemd configured"

# ══════════════════════════════════════════════════════════════
# STEP 10: Start infrastructure services
# ══════════════════════════════════════════════════════════════
info 10 "Khởi động infrastructure services"
for svc in elasticsearch redis rabbitmq-server minio; do
  detail "systemctl enable + start $svc"
  systemctl enable "$svc" &>/dev/null || true
  systemctl start "$svc" &>/dev/null || true
done
echo ""
wait_for "Elasticsearch (${ELASTICSEARCH__URL})" "curl -sf ${ELASTICSEARCH__URL}" 120 || true
wait_for "Redis (${REDIS__HOSTNAME}:${REDIS__PORT})" "redis-cli -h ${REDIS__HOSTNAME} -p ${REDIS__PORT} -a '${REDIS__PASSWORD}' --no-auth-warning ping 2>/dev/null | grep -q PONG" 30 || true
wait_for "RabbitMQ (${RABBITMQ__HOSTNAME}:${RABBITMQ__PORT})" "rabbitmqctl status 2>/dev/null" 90 || true
wait_for "MinIO (http://${MINIO__ENDPOINT}:${MINIO__PORT})" "curl -sf http://${MINIO__ENDPOINT}:${MINIO__PORT}/minio/health/live" 30 || true

# ══════════════════════════════════════════════════════════════
# STEP 11: Configure RabbitMQ user + MinIO bucket
# ══════════════════════════════════════════════════════════════
info 11 "Cấu hình RabbitMQ user + MinIO bucket"
detail "RabbitMQ: enable management plugin"
rabbitmq-plugins enable rabbitmq_management &>/dev/null || true
detail "RabbitMQ: add_user ${RABBITMQ__USERNAME} (password: ${RABBITMQ__PASSWORD:0:4}****)"
rabbitmqctl add_user "${RABBITMQ__USERNAME}" "${RABBITMQ__PASSWORD}" &>/dev/null || \
  rabbitmqctl change_password "${RABBITMQ__USERNAME}" "${RABBITMQ__PASSWORD}" &>/dev/null || true
detail "RabbitMQ: set_user_tags ${RABBITMQ__USERNAME} administrator"
rabbitmqctl set_user_tags "${RABBITMQ__USERNAME}" administrator &>/dev/null || true
detail "RabbitMQ: set_permissions ${RABBITMQ__USERNAME} → full access"
rabbitmqctl set_permissions -p / "${RABBITMQ__USERNAME}" ".*" ".*" ".*" &>/dev/null || true
detail "RabbitMQ: restart sau khi enable management"
systemctl restart rabbitmq-server &>/dev/null || true
sleep 3
detail "Verify RabbitMQ users:"
rabbitmqctl list_users 2>/dev/null || warn "Không list được users"
echo ""
detail "MinIO: create bucket '${MINIO__BUCKET_NAME}'"
/tmp/mc alias set local "http://${MINIO__ENDPOINT}:${MINIO__PORT}" "${MINIO__ACCESS_KEY}" "${MINIO__SECRET_KEY}" &>/dev/null || true
/tmp/mc mb "local/${MINIO__BUCKET_NAME}" &>/dev/null || true
ok "RabbitMQ user + MinIO bucket configured"

# ══════════════════════════════════════════════════════════════
# STEP 12: Install OpenCTI Platform
# ══════════════════════════════════════════════════════════════
info 12 "Cài OpenCTI Platform (chạy bằng root)"
detail "Extract: $DEPLOY_DIR/files/opencti.tar.gz → /opt/opencti/"
tar -xzf "$DEPLOY_DIR"/files/opencti.tar.gz -C /opt/
# Config → /etc/opencti/ (tách code và config)
mkdir -p /etc/opencti
detail "Copy: config/start.sh → /etc/opencti/start.sh"
cp "$DEPLOY_DIR"/config/start.sh /etc/opencti/ && chmod +x /etc/opencti/start.sh
detail "Install SSL cert → $(dirname "$SSL_KEY_PATH")/"
SSL_DIR="$(dirname "$SSL_KEY_PATH")"
mkdir -p "$SSL_DIR"
if [[ ! -f "$SSL_CRT_PATH" ]]; then
  # Ưu tiên: dùng cert từ package (đã gen sẵn lúc đóng gói)
  if [[ -f "$DEPLOY_DIR/cert/opencti.key" ]] && [[ -f "$DEPLOY_DIR/cert/opencti.crt" ]]; then
    detail "Copy SSL cert từ package (cert/)"
    cp "$DEPLOY_DIR/cert/opencti.key" "$SSL_KEY_PATH"
    cp "$DEPLOY_DIR/cert/opencti.crt" "$SSL_CRT_PATH"
    ok "SSL cert installed from package"
  else
    # Fallback: gen trên máy đích nếu package không có cert
    detail "Không tìm thấy cert/ trong package → gen trên máy đích"
    if [[ -f "$DEPLOY_DIR/scripts/gen-ssl-cert.sh" ]]; then
      bash "$DEPLOY_DIR/scripts/gen-ssl-cert.sh" "$SSL_DIR"
    else
      # Inline fallback nếu script cũng không có
      SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
      SERVER_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "opencti")
      openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
        -keyout "$SSL_KEY_PATH" -out "$SSL_CRT_PATH" \
        -subj "/CN=opencti/O=OpenCTI/C=VN" \
        -addext "subjectAltName=DNS:localhost,DNS:${SERVER_HOSTNAME},IP:127.0.0.1,IP:${SERVER_IP}" \
        2>/dev/null
    fi
    ok "SSL cert generated on target"
  fi
else
  ok "SSL cert already exists → skip"
fi
# Fix SSL permissions (key chỉ root đọc được)
chmod 700 "$SSL_DIR"
chmod 600 "$SSL_KEY_PATH"
chmod 644 "$SSL_CRT_PATH"
detail "SSL permissions: dir=700, key=600, cert=644"
detail "Copy: config/opencti.service → /etc/systemd/system/"
cp "$DEPLOY_DIR"/config/opencti.service /etc/systemd/system/
detail "Tạo thư mục log: /var/log/v2-ti/{opencti,opencti-worker,elasticsearch,rabbitmq}"
mkdir -p /var/log/v2-ti/opencti /var/log/v2-ti/opencti-worker /var/log/v2-ti/elasticsearch /var/log/v2-ti/rabbitmq
chmod 755 /var/log/v2-ti/opencti /var/log/v2-ti/opencti-worker
detail "Copy: config/opencti-logrotate.conf → /etc/logrotate.d/opencti"
cp "$DEPLOY_DIR"/config/opencti-logrotate.conf /etc/logrotate.d/opencti
ok "Log directories + logrotate configured"
detail "Create Python venv → /opt/opencti/.python-venv (dùng Python 3.12)"
if [[ ! -d /opt/opencti/.python-venv ]]; then
  /opt/python312/bin/python3.12 -m venv /opt/opencti/.python-venv
  PIP_WHL=$(ls /opt/opencti/python-wheels/pip-*.whl 2>/dev/null | head -1)
  [[ -n "$PIP_WHL" ]] && /opt/opencti/.python-venv/bin/pip install "$PIP_WHL" -q &>/dev/null || true
  if [[ -d /opt/opencti/python-wheels ]] && [[ $(ls /opt/opencti/python-wheels/ | wc -l) -gt 0 ]]; then
    detail "pip install từ wheels (offline, --no-index)"
    /opt/opencti/.python-venv/bin/pip install \
      --no-index --find-links=/opt/opencti/python-wheels \
      -r /opt/opencti/src/python/requirements.txt -q
    ok "Python packages installed from wheels"
  else
    /opt/opencti/.python-venv/bin/pip install \
      -r /opt/opencti/src/python/requirements.txt -q 2>/dev/null || \
      warn "Python packages install failed"
  fi
else
  ok "Python venv already exists → skip"
fi
detail "Verify native module linking:"
NATIVE_MODULE=$(find /opt/opencti/build -maxdepth 1 -name "nodecallspython-*.node" -type f 2>/dev/null | head -1)
if [[ -n "$NATIVE_MODULE" ]]; then
  ldd "$NATIVE_MODULE" 2>/dev/null | grep -E "python|not.found" || detail "  (clean linking)"
fi
ok "Platform → /opt/opencti (user: root)"

# ══════════════════════════════════════════════════════════════
# STEP 13: Install OpenCTI Worker
# ══════════════════════════════════════════════════════════════
info 13 "Cài OpenCTI Worker (chạy bằng root)"
detail "Extract: $DEPLOY_DIR/files/opencti-worker.tar.gz → /opt/opencti-worker/"
tar -xzf "$DEPLOY_DIR"/files/opencti-worker.tar.gz -C /opt/
detail "Create Worker venv → /opt/opencti-worker/venv (dùng Python 3.12)"
if [[ ! -d /opt/opencti-worker/venv ]]; then
  /opt/python312/bin/python3.12 -m venv /opt/opencti-worker/venv
  PIP_WHL=$(ls /opt/opencti-worker/wheels/pip-*.whl 2>/dev/null | head -1)
  [[ -n "$PIP_WHL" ]] && /opt/opencti-worker/venv/bin/pip install "$PIP_WHL" -q &>/dev/null || true
  detail "pip install từ wheels (offline)"
  /opt/opencti-worker/venv/bin/pip install \
    --no-index --find-links=/opt/opencti-worker/wheels \
    -r /opt/opencti-worker/requirements.txt -q
  ok "Worker packages installed from wheels"
else
  ok "Worker venv already exists → skip"
fi
detail "Write: /etc/opencti-worker/config.yml (token: ${APP__ADMIN__TOKEN:0:8}...)"
mkdir -p /etc/opencti-worker
cat > /etc/opencti-worker/config.yml <<WEOF
opencti:
  url: 'https://localhost:${APP__PORT}'
  token: '${APP__ADMIN__TOKEN}'
  ssl_verify: false
worker:
  log_level: 'info'
WEOF
chmod 600 /etc/opencti-worker/config.yml
detail "Write: /etc/opencti-worker/worker.env"
cat > /etc/opencti-worker/worker.env <<ENVEOF
OPENCTI_URL=https://localhost:${APP__PORT}
OPENCTI_TOKEN=${APP__ADMIN__TOKEN}
OPENCTI_SSL_VERIFY=false
ENVEOF
chmod 600 /etc/opencti-worker/worker.env
# Symlink config.yml vào working dir để worker.py tìm được
ln -sf /etc/opencti-worker/config.yml /opt/opencti-worker/config.yml
detail "Copy: config/opencti-worker@.service → /etc/systemd/system/"
cp "$DEPLOY_DIR"/config/opencti-worker@.service /etc/systemd/system/
ok "Worker → /opt/opencti-worker ($WORKERS instances, user: root)"

# ══════════════════════════════════════════════════════════════
# STEP 14: Start OpenCTI Platform + Workers
# ══════════════════════════════════════════════════════════════
info 14 "Khởi động OpenCTI Platform + Workers"
systemctl daemon-reload
detail "systemctl enable + start opencti"
systemctl enable opencti &>/dev/null && systemctl start opencti || true
for i in $(seq 1 $WORKERS); do
  detail "systemctl enable + start opencti-worker@$i"
  systemctl enable "opencti-worker@$i" &>/dev/null || true
  systemctl start "opencti-worker@$i" &>/dev/null || true
done
echo ""
wait_for "OpenCTI Platform (https://localhost:${APP__PORT}/health)" \
  "curl -sf -k https://localhost:${APP__PORT}/health" 180 || \
  warn "Platform chưa ready — xem log: journalctl -u opencti -f"

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    DEPLOY HOÀN TẤT                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  📊 Service Status:"
for svc in elasticsearch redis rabbitmq-server minio opencti; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  if [[ "$STATUS" == "active" ]]; then
    printf "    ✅ %-20s %s\n" "$svc" "$STATUS"
  else
    printf "    ❌ %-20s %s\n" "$svc" "$STATUS"
  fi
done
for i in $(seq 1 $WORKERS); do
  STATUS=$(systemctl is-active "opencti-worker@$i" 2>/dev/null || echo "inactive")
  if [[ "$STATUS" == "active" ]]; then
    printf "    ✅ %-20s %s\n" "worker@$i" "$STATUS"
  else
    printf "    ❌ %-20s %s\n" "worker@$i" "$STATUS"
  fi
done
echo ""
echo "  📁 File Layout trên server:"
echo "    /opt/python312/              Python 3.12.8 (libpython3.12.so)"
echo "    /opt/elasticsearch/          Elasticsearch 8.17.0 binaries"
echo "    /opt/rabbitmq/               RabbitMQ 4.1.0 binaries"
echo "    /opt/minio/                  MinIO server binary"
echo "    /opt/opencti/                OpenCTI Platform code"
echo "    /opt/opencti/.python-venv/   Platform Python venv"
echo "    /opt/opencti-worker/         Worker x$WORKERS code"
echo "    /opt/opencti-worker/venv/    Worker Python venv"
echo ""
echo "  📝 Config Files:"
echo "    /etc/opencti/start.sh              Platform startup script"
echo "    /etc/opencti/ssl/                  SSL certificates"
echo "    /etc/opencti-worker/config.yml     Worker config"
echo "    /etc/opencti-worker/worker.env     Worker environment"
echo "    /etc/elasticsearch/                Elasticsearch config"
echo "    /etc/rabbitmq/                     RabbitMQ config"
echo "    /etc/default/minio                 MinIO config"
echo ""
echo "  💾 Data:"
echo "    /var/lib/elasticsearch/            Elasticsearch data"
echo "    /var/lib/minio/data/               MinIO object storage"
echo "    /var/lib/rabbitmq/mnesia/          RabbitMQ data"
echo "    /var/lib/redis/                    Redis data"
echo ""
echo "  📝 Log Files:"
echo "    /var/log/v2-ti/opencti/            Platform logs"
echo "    /var/log/v2-ti/opencti-worker/     Worker logs"
echo "    /var/log/v2-ti/elasticsearch/      Elasticsearch logs"
echo "    /var/log/v2-ti/rabbitmq/           RabbitMQ logs"
echo ""
echo "  🔧 Service Users:"
echo "    elasticsearch                user: elasticsearch (ES bắt buộc)"
echo "    redis, rabbitmq, minio       user: root"
echo "    opencti, worker              user: root"
echo ""
echo "  🌐 URL:  https://$(hostname -I 2>/dev/null | awk '{print $1}'):${APP__PORT}"
echo "  👤 User: ${APP__ADMIN__EMAIL}"
echo "  🔑 Pass: ${APP__ADMIN__PASSWORD}"
echo ""
echo "  📋 Commands:"
echo "    tail -f /var/log/v2-ti/opencti/opencti.log            # Platform logs"
echo "    tail -f /var/log/v2-ti/opencti/opencti-error.log      # Platform error logs"
echo "    tail -f /var/log/v2-ti/opencti-worker/worker-1.log    # Worker 1 logs"
echo "    tail -f /var/log/v2-ti/elasticsearch/*.log            # Elasticsearch logs"
echo "    systemctl status opencti                        # Platform status"
echo "    systemctl status opencti-worker@1               # Worker 1 status"
echo ""
