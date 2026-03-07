#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 05-copy-source.sh — Copy OpenCTI source + build artifacts
#
# Copies source + build artifacts (from 03 + 04) into a single
# tarball for offline deployment.
#
# Requires:  build/ + node_modules/ from step 03
#            builder/prod/build/ from step 04 (frontend → public/)
# Output:    files/opencti-source.tar.gz
#
# Contents:
#   platform/        ← opencti-graphql (src, config, build, node_modules, public)
#   worker/src/      ← opencti-worker source
#   client-python/   ← pycti library
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BASE_DIR/.." && pwd)"
FILES_DIR="$BASE_DIR/files"

OUTPUT="opencti-source.tar.gz"
STAGING="/tmp/opencti-source-staging"

GRAPHQL="$REPO_ROOT/opencti-platform/opencti-graphql"
FRONT="$REPO_ROOT/opencti-platform/opencti-front"
WORKER="$REPO_ROOT/opencti-worker"
CLIENT="$REPO_ROOT/client-python"

log() { echo "  $1 $2"; }

echo "▸ Copying OpenCTI source → files/$OUTPUT"

rm -rf "$STAGING"
mkdir -p "$STAGING/platform" "$STAGING/worker" "$STAGING/client-python"

# ── Platform (opencti-graphql) ───────────────────────────────
log "→" "platform/ (src, config, build, node_modules)"
cp -r "$GRAPHQL/src"          "$STAGING/platform/"
cp -r "$GRAPHQL/config"       "$STAGING/platform/"
cp    "$GRAPHQL/package.json" "$STAGING/platform/"

[[ -f "$REPO_ROOT/opencti-platform/.yarnrc.yml" ]] && \
    cp "$REPO_ROOT/opencti-platform/.yarnrc.yml" "$STAGING/platform/"

for dir in build node_modules static script; do
    [[ -d "$GRAPHQL/$dir" ]] && cp -r "$GRAPHQL/$dir" "$STAGING/platform/"
done

# Frontend build → platform/public/ (from 04-build-frontend.sh)
if [[ -d "$FRONT/builder/prod/build" ]]; then
    log "→" "platform/public/ (frontend build)"
    cp -r "$FRONT/builder/prod/build" "$STAGING/platform/public"
else
    log "⚠" "WARNING: frontend build not found at $FRONT/builder/prod/build/"
    log "⚠" "Run 04-build-frontend.sh first! Platform will return 404 on /dashboard"
fi

# ── Worker ───────────────────────────────────────────────────
log "→" "worker/src/"
cp -r "$WORKER/src" "$STAGING/worker/"

# ── Client Python (pycti) ───────────────────────────────────
if [[ -d "$CLIENT/pycti" ]]; then
    log "→" "client-python/"
    cp -r "$CLIENT/pycti"       "$STAGING/client-python/"
    cp "$CLIENT/pyproject.toml" "$STAGING/client-python/" 2>/dev/null || true
    cp "$CLIENT/setup.cfg"      "$STAGING/client-python/" 2>/dev/null || true
    cp "$CLIENT/README.md"      "$STAGING/client-python/" 2>/dev/null || true
fi

# ── Create tarball ───────────────────────────────────────────
mkdir -p "$FILES_DIR"
cd "$STAGING"
tar -czf "$FILES_DIR/$OUTPUT" .
rm -rf "$STAGING"

log "✓" "Source: $(du -h "$FILES_DIR/$OUTPUT" | cut -f1) → files/$OUTPUT"
