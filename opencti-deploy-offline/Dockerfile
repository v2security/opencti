# syntax=docker/dockerfile:1
###############################################################################
# Rocky Linux 9 — Môi trường test cho offline deployment
#
# Container giả lập máy đích (bare-metal Rocky 9) để test deploy-offline.sh.
# KHÔNG cài sẵn gì ngoài systemd + tools cơ bản.
# Tất cả (ES, Redis, RabbitMQ, MinIO, OpenCTI) do deploy-offline.sh cài.
#
# Máy triển khai thật: Rocky 9 bare-metal, KHÔNG có Docker.
# Container này chỉ để TEST trước khi deploy lên máy thật.
#
# Usage:
#   make build && make up
#   make deploy            # hoặc: make exec → bash scripts/deploy-offline.sh
#   make status
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

# ── Tools cơ bản (có sẵn trên Rocky 9 thật) ─────────────────
# Chỉ cài những gì máy Rocky 9 minimal đã có hoặc cần cho deploy script
RUN dnf install -y --allowerasing \
        procps-ng \
        iproute \
        net-tools \
        hostname \
        tar \
        gzip \
        xz \
        which \
        vim-minimal \
        curl \
        wget \
        tree \
        telnet \
        nmap-ncat \
        findutils \
        && dnf clean all

# KHÔNG cài sẵn: Node.js, Elasticsearch, Redis, RabbitMQ, Python
# deploy-offline.sh sẽ cài tất cả từ offline package

# ── Thư mục deploy (mount từ host) ──────────────────────────
RUN mkdir -p /root/opencti-deploy

VOLUME ["/sys/fs/cgroup"]
WORKDIR /root

CMD ["/usr/sbin/init"]
