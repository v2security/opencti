# syntax=docker/dockerfile:1
###############################################################################
# Rocky Linux 9 — Test container cho OpenCTI Offline Deployment
#
# Container giả lập máy đích (bare-metal Rocky 9) với systemd.
# Mọi thứ được mount trực tiếp vào đúng path bởi docker-compose.yml:
#   - Binaries + scripts   → /usr/local/bin/
#   - Tarballs + setup     → /tmp/<component>/
#   - Configs              → /etc/<service>/
#   - Systemd units        → /etc/systemd/system/
#
# Usage:
#   docker compose up -d
#   docker exec -it opencti-test bash
#
#   cd /tmp/rpms && ./v2_install_rpms.sh
#   cd /tmp/runtime && ./v2_install_python.sh && ./v2_install_nodejs.sh
#   v2_setup_minio.sh
#   cd /tmp/rabbitmq && ./v2_setup_rabbitmq.sh
#   cd /tmp/opencti && ./v2_setup_cti.sh
#   systemctl enable redis minio rabbitmq
#   systemctl start redis minio rabbitmq
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

# ── Minimal packages ─────────────────────────────────────────
RUN dnf install -y systemd xz && dnf clean all

# ── Create user 'admin' — owner cho MinIO, RabbitMQ ──────────
RUN groupadd -r admin && useradd -r -g admin -d /home/admin -s /bin/bash admin \
    && mkdir -p /home/admin && chown admin:admin /home/admin

# ── Directories — giống ISO tạo sẵn trên bare-metal ──────────
RUN mkdir -p /tmp/rpms /tmp/runtime /tmp/rabbitmq /tmp/opencti \
    && mkdir -p /etc/redis /etc/minio /etc/rabbitmq \
    && mkdir -p /etc/saids/opencti /etc/saids/opencti-worker \
    && mkdir -p /var/log/opencti /var/log/opencti-worker \
    && mkdir -p /opt/rabbitmq /opt/python312 /opt/nodejs

VOLUME ["/sys/fs/cgroup"]
WORKDIR /root

CMD ["/usr/sbin/init"]
