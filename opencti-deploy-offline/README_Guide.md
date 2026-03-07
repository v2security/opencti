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