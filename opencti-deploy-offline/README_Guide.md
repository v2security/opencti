## Template deploy-offline (rất nhiều hãng dùng)

ISO chỉ chứa: ELK

```sh
ISO
 ├─ rpms/
 ├─ configs/
 ├─ systemd/
 ├─ bootstrap.sh
 └─ kickstart.ks
```

Khi client boot ISO:

```sh
1. cài OS
2. copy rpm
3. install rpm
4. enable services
```

Flow:
```sh
ISO boot
   │
   ├─ Kickstart install OS
   ├─ install local RPM
   ├─ copy config
   └─ enable systemd
```

Kickstart ví dụ:
```sh
%post
dnf install -y /run/install/repo/rpms/*.rpm
cp /run/install/repo/config/* /etc/myapp/
systemctl enable myapp
%end
```

> 👉 Cách này ổn định hơn rất nhiều.

## V2 deploy-offline


cd /workspace/tunv_opencti/opencti-deploy-offline/rpm && rm -v \
  nodejs-22.22.0-1.module+el9.7.0+40083+285810cf.x86_64.rpm \
  nodejs-docs-22.22.0-1.module+el9.7.0+40083+285810cf.noarch.rpm \
  nodejs-full-i18n-22.22.0-1.module+el9.7.0+40083+285810cf.x86_64.rpm \
  nodejs-libs-22.22.0-1.module+el9.7.0+40083+285810cf.x86_64.rpm \
  python3.11-3.11.13-5.el9_7.x86_64.rpm \
  python3.11-libs-3.11.13-5.el9_7.x86_64.rpm \
  python3.11-pip-22.3.1-6.el9.noarch.rpm \
  python3.11-pip-wheel-22.3.1-6.el9.noarch.rpm \
  python3.11-setuptools-65.5.1-5.el9.noarch.rpm \
  python3.11-setuptools-wheel-65.5.1-5.el9.noarch.rpm \
  mpdecimal-2.5.1-3.el9.x86_64.rpm \
  redis-6.2.20-3.el9_7.x86_64.rpm \
  rsyslog-8.2506.0-2.el9.x86_64.rpm \
  logrotate-3.18.0-12.el9.x86_64.rpm \
  libbrotli-1.0.9-9.el9_7.x86_64.rpm \
  libestr-0.1.11-4.el9.x86_64.rpm \
  libfastjson-0.99.9-5.el9.x86_64.rpm && echo "---" && echo "Remaining: $(ls -1 *.rpm | wc -l) RPMs"
