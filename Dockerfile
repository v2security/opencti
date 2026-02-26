# syntax=docker/dockerfile:1
###############################################################################
# OpenCTI Full Build — Frontend + Backend + Python từ source code
#
# Pure build — KHÔNG patch bên trong Docker.
# Chạy ./patch_ee.sh TRƯỚC KHI build.
#
# Không phụ thuộc image opencti/platform gốc.
# Sẵn sàng cho RPM packaging.
#
# Usage:
#   docker compose build opencti
#   make build
###############################################################################

FROM node:22-alpine AS base
RUN corepack enable
ARG BUILD_DEPS="git tini gcc g++ make musl-dev cargo python3 python3-dev postfix postfix-pcre"

# ── Backend deps (node_modules cho runtime) ──
FROM base AS graphql-deps
WORKDIR /opt/build/graphql
COPY opencti-platform/opencti-graphql/package.json opencti-platform/opencti-graphql/yarn.lock opencti-platform/.yarnrc.yml ./
COPY opencti-platform/opencti-graphql/patch ./patch
RUN apk add --no-cache $BUILD_DEPS && npm i -g node-gyp \
    && yarn install && yarn cache clean --all

# ── Backend build (back.js) ──
FROM base AS graphql-builder
WORKDIR /opt/build/graphql
COPY opencti-platform/opencti-graphql/package.json opencti-platform/opencti-graphql/yarn.lock opencti-platform/.yarnrc.yml ./
COPY opencti-platform/opencti-graphql/patch ./patch
RUN apk add --no-cache $BUILD_DEPS \
    && rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED \
    && npm i -g node-gyp && yarn install
COPY opencti-platform/opencti-graphql .
RUN yarn build:prod

# ── Frontend build ──
FROM base AS front-builder
WORKDIR /opt/build/front
COPY opencti-platform/opencti-front/package.json opencti-platform/opencti-front/yarn.lock opencti-platform/.yarnrc.yml ./
COPY opencti-platform/opencti-front/packages ./packages
RUN apk add --no-cache $BUILD_DEPS \
    && rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED \
    && npm i -g node-gyp && yarn install
COPY opencti-platform/opencti-front .
COPY opencti-platform/opencti-graphql/config/schema/opencti.graphql /opt/build/graphql/config/schema/opencti.graphql
RUN yarn build:standalone

# ── Runtime ──
FROM base AS app
RUN apk add --no-cache $BUILD_DEPS \
    && rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED \
    && python3 -m ensurepip && rm -r /usr/lib/python*/ensurepip \
    && pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && ln -sf python3 /usr/bin/python
WORKDIR /opt/opencti
COPY opencti-platform/opencti-graphql/src/python/requirements.txt src/python/requirements.txt
RUN pip3 install --no-cache-dir -r src/python/requirements.txt && apk del git gcc musl-dev

COPY --from=graphql-deps    /opt/build/graphql/node_modules ./node_modules
COPY --from=graphql-builder /opt/build/graphql/build        ./build
COPY --from=graphql-builder /opt/build/graphql/static       ./static
COPY --from=front-builder   /opt/build/front/builder/prod/build ./public
COPY opencti-platform/opencti-graphql/src    ./src
COPY opencti-platform/opencti-graphql/config ./config
COPY opencti-platform/opencti-graphql/script ./script

ENV PYTHONUNBUFFERED=1 NODE_OPTIONS=--max_old_space_size=12288 NODE_ENV=production
RUN install -m 0777 -d /opt/opencti/logs /opt/opencti/telemetry /opt/opencti/.support
VOLUME ["/opt/opencti/logs", "/opt/opencti/telemetry", "/opt/opencti/.support"]
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "build/back.js"]
