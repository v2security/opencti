#!/bin/bash
###############################################################################
# OpenCTI EE Bypass — Patch source trực tiếp
#
# Sed trên opencti-platform/, sau đó build bình thường.
# Chạy 1 lần (hoặc mỗi khi git pull/upgrade version).
#
# Sử dụng:
#   ./patch_ee.sh           # Patch source
#   ./patch_ee.sh --check   # Kiểm tra đã patch chưa
#   ./patch_ee.sh --revert  # Revert về bản gốc (git checkout)
###############################################################################

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EE="$ROOT/opencti-platform/opencti-graphql/src/enterprise-edition/ee.ts"
LIC="$ROOT/opencti-platform/opencti-graphql/src/modules/settings/licensing.ts"

case "${1:-patch}" in
--check)
  echo "=== EE Bypass Status ==="
  grep -q 'return true;' "$EE" && echo "  ✅ ee.ts" || echo "  ❌ ee.ts"
  grep -q 'license_validated: true,' "$LIC" && echo "  ✅ licensing.ts" || echo "  ❌ licensing.ts"
  ;;
--revert)
  cd "$ROOT" && git checkout -- "$EE" "$LIC"
  echo "✅ Reverted"
  ;;
*)
  # [1/2] ee.ts → always return true
  cat > "$EE" << 'TS'
import type { AuthContext } from '../types/user';
import type { BasicStoreSettings } from '../types/settings';

export const isEnterpriseEdition = async (_context: AuthContext) => true;
export const isEnterpriseEditionFromSettings = (_settings?: Pick<BasicStoreSettings, 'valid_enterprise_edition'>): boolean => true;
export const checkEnterpriseEdition = async (_context: AuthContext) => { return; };
TS
  echo "✅ ee.ts patched"

  # [2/2] licensing.ts → fallback block
  sed -i \
    -e 's|license_validated: false,|license_validated: true,|' \
    -e 's|license_valid_cert: false,|license_valid_cert: true,|' \
    -e 's|license_expired: true,|license_expired: false,|' \
    -e "s|license_type: 'trial',|license_type: 'standard',|" \
    -e 's|license_global: false,|license_global: true,|' \
    "$LIC"
  echo "✅ licensing.ts patched"
  echo "→ make build"
  ;;
esac
