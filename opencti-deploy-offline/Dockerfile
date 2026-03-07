# syntax=docker/dockerfile:1
###############################################################################
# Rocky Linux 9 — Test container cho Infrastructure (MinIO + Redis + RabbitMQ)
#
# Container giả lập máy đích (bare-metal Rocky 9) với systemd.
# Mount files/, rpm/, scripts/, systemd/ từ host.
#
# Usage:
#   cd opencti-deploy-offline
#   docker compose up -d
#   docker exec opencti-test bash /root/opencti-deploy/scripts/setup_infra.sh
#   docker exec opencti-test bash /root/opencti-deploy/scripts/setup_app.sh
#   docker exec opencti-test systemctl status redis minio rabbitmq-server
###############################################################################

FROM rockylinux:9

# ── Systemd — cho phép chạy services trong container ─────────
ENV container=docker
STOPSIGNAL SIGRTMIN+3

RUN SYSD=/usr/lib/systemd/system; \
    if [ ! -d "$SYSD/sysinit.target.wants" ]; then SYSD=/lib/systemd/system; fi && \
    (cd "$SYSD/sysinit.target.wants/" 2>/dev/null && \
     for i in *; do [ "$i" = "systemd-tmpfiles-setup.service" ] && continue; rm -f "$i"; done) || true && \
    rm -f "$SYSD"/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f "$SYSD"/local-fs.target.wants/* && \
    rm -f "$SYSD"/sockets.target.wants/*udev* && \
    rm -f "$SYSD"/sockets.target.wants/*initctl* && \
    rm -f "$SYSD"/basic.target.wants/* && \
    rm -f "$SYSD"/anaconda.target.wants/* 2>/dev/null || true

# ── Minimal packages — bắt buộc để container hoạt động ───────
# systemd: boot với /usr/sbin/init (base image không có)
# xz:      extract .tar.xz (base image chỉ có xz-libs, không có binary)
RUN dnf install -y systemd xz && dnf clean all

# ── Packages ─────────────────────────────────────────────────
# Base image đã có sẵn: tar, gzip, findutils, hostname,
# curl-minimal, vim-minimal, xz-libs, dnf.
# Các gói còn lại (make, gcc, gcc-c++, procps-ng, iproute,
# net-tools, which, erlang...) nằm trong rpm/ và được
# setup_infra.sh cài offline qua dnf localinstall.

# ── Node.js 22 (cho OpenCTI Platform runtime) ───────────────
# Node.js sẽ được cài tự động từ opencti-app-package.tar.gz khi chạy setup_app.sh.
# Không cần cài Node.js trong Dockerfile — giả lập đúng môi trường offline.
# Nếu muốn pre-install: uncomment 2 dòng dưới:
# RUN curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - \
#     && dnf install -y nodejs && dnf clean all

# ── Working directory ────────────────────────────────────────
RUN mkdir -p /root/opencti-deploy

VOLUME ["/sys/fs/cgroup"]
WORKDIR /root

CMD ["/usr/sbin/init"]
