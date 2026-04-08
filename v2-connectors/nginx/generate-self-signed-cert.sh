#!/usr/bin/env bash

# Generate a self-signed server certificate for the Nginx reverse proxy.
# Usage: ./generate-self-signed-cert.sh [common-name]
#
# Output:
#   certs/cert.pem  – server certificate (public)
#   certs/key.pem   – private key
#
# Client only needs to connect via HTTPS; no client certificate required.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CERT_DIR="${SCRIPT_DIR}/certs"
CERT_FILE="${CERT_DIR}/cert.pem"
KEY_FILE="${CERT_DIR}/key.pem"
COMMON_NAME="${1:-localhost}"
VALID_DAYS="${VALID_DAYS:-365}"

mkdir -p "${CERT_DIR}"

# Generate with SAN so modern clients accept the certificate.
openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -days "${VALID_DAYS}" \
  -subj "/CN=${COMMON_NAME}" \
  -addext "subjectAltName=DNS:${COMMON_NAME},IP:127.0.0.1"

chmod 600 "${KEY_FILE}"

echo "Generated ${CERT_FILE} and ${KEY_FILE} for CN=${COMMON_NAME}"