#!/usr/bin/env bash

# This script generates a self-signed SSL certificate for the Nginx server used in the v2 connectors.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CERT_DIR="${SCRIPT_DIR}/certs"
CERT_FILE="${CERT_DIR}/tls.crt"
KEY_FILE="${CERT_DIR}/tls.key"
COMMON_NAME="${1:-localhost}"
VALID_DAYS="${VALID_DAYS:-365}"

mkdir -p "${CERT_DIR}"

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -days "${VALID_DAYS}" \
  -subj "/CN=${COMMON_NAME}"

chmod 600 "${KEY_FILE}"

echo "Generated ${CERT_FILE} and ${KEY_FILE} for CN=${COMMON_NAME}"