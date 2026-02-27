#!/bin/bash
###############################################################################
# Generate SSL Certificate cho OpenCTI
#
# Tạo self-signed SSL cert (RSA-4096, SHA-256, 10 năm)
# với Subject Alternative Names cho localhost, hostname, IP.
#
# Usage:
#   bash scripts/gen-ssl-cert.sh                    # Gen vào cert/
#   bash scripts/gen-ssl-cert.sh /path/to/output    # Gen vào thư mục chỉ định
#   bash scripts/gen-ssl-cert.sh --force             # Ghi đè cert cũ
#
# Output:
#   <output_dir>/opencti.key   ← Private key (chmod 600)
#   <output_dir>/opencti.crt   ← Public certificate (chmod 644)
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Parse arguments ──────────────────────────────────────────
FORCE=false
CERT_DIR=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *)       CERT_DIR="$arg" ;;
  esac
done
[[ -z "$CERT_DIR" ]] && CERT_DIR="$BASE_DIR/cert"

KEY_FILE="$CERT_DIR/opencti.key"
CRT_FILE="$CERT_DIR/opencti.crt"

ok()     { echo "  ✓ $*"; }
detail() { echo "  → $*"; }
die()    { echo "  ✗ $*" >&2; exit 1; }

# ── Check existing ───────────────────────────────────────────
if [[ -f "$CRT_FILE" ]] && [[ -f "$KEY_FILE" ]] && [[ "$FORCE" != true ]]; then
  echo ""
  echo "  SSL cert đã tồn tại:"
  echo "    Key:  $KEY_FILE"
  echo "    Cert: $CRT_FILE"
  echo ""
  detail "Dùng --force để tạo lại"
  # Show cert info
  openssl x509 -in "$CRT_FILE" -noout -subject -dates -ext subjectAltName 2>/dev/null | sed 's/^/    /'
  echo ""
  exit 0
fi

# ── Check openssl ────────────────────────────────────────────
command -v openssl &>/dev/null || die "Cần openssl — cài: dnf install openssl"

# ── Detect hostname + IP ─────────────────────────────────────
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
SERVER_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "opencti")

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  GENERATE SSL CERTIFICATE"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "  Output:   $CERT_DIR/"
echo "  Hostname: $SERVER_HOSTNAME"
echo "  IP:       $SERVER_IP"
echo "  Key size: RSA-4096"
echo "  Validity: 3650 days (~10 years)"
echo ""

# ── Create output dir ────────────────────────────────────────
mkdir -p "$CERT_DIR"

# ── Generate OpenSSL config ──────────────────────────────────
TMPCONF=$(mktemp /tmp/opencti-ssl-XXXXXX.cnf)
trap "rm -f '$TMPCONF'" EXIT

cat > "$TMPCONF" <<SSLEOF
[req]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_ext

[dn]
C  = VN
O  = OpenCTI
CN = opencti

[v3_ext]
subjectAltName      = @alt_names
basicConstraints    = critical, CA:TRUE
keyUsage            = critical, digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage    = serverAuth, clientAuth

[alt_names]
DNS.1 = localhost
DNS.2 = ${SERVER_HOSTNAME}
DNS.3 = opencti
IP.1  = 127.0.0.1
IP.2  = ${SERVER_IP}
SSLEOF

# ── Generate cert ────────────────────────────────────────────
detail "Generating RSA-4096 key + self-signed certificate..."
openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
  -keyout "$KEY_FILE" \
  -out "$CRT_FILE" \
  -config "$TMPCONF" 2>/dev/null || die "openssl req failed"

# ── Set permissions ──────────────────────────────────────────
chmod 700 "$CERT_DIR"
chmod 600 "$KEY_FILE"
chmod 644 "$CRT_FILE"

# ── Verify ───────────────────────────────────────────────────
detail "Verifying certificate..."
openssl x509 -in "$CRT_FILE" -noout -text 2>/dev/null | \
  grep -E "Subject:|DNS:|IP Address:" | sed 's/^/    /'

echo ""
ok "SSL certificate generated successfully"
echo ""
echo "  📁 Files:"
echo "    🔒 Key:  $KEY_FILE (chmod 600 — private)"
echo "    📜 Cert: $CRT_FILE (chmod 644 — public)"
echo ""
echo "  📋 Usage trong start.sh:"
echo "    export APP__HTTPS_CERT__KEY=\"/opt/opencti/ssl/opencti.key\""
echo "    export APP__HTTPS_CERT__CRT=\"/opt/opencti/ssl/opencti.crt\""
echo ""
