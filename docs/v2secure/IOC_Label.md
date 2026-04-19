# Phương án phân loại IOC Labels

> Ngày tạo: 2026-04-12
> Nguồn dữ liệu: Maltrail (~2,958 labels), External feeds (5 labels)

---

## 1. Tổng quan

### 1.1. Vấn đề

Hiện tại hệ thống có **~2,963 labels** từ nhiều nguồn, không có phân nhóm → không quản lý, filter, report được hiệu quả.

### 1.2. Phương án

Phân thành **2 lớp** (layer) theo hướng traffic, mỗi lớp chia thành **các nhóm** (group) theo chuẩn phân loại mối đe dọa phổ biến (MITRE ATT&CK, STIX 2.1, CrowdStrike, Mandiant).

| Lớp | Tag | Hướng traffic | Ý nghĩa |
|---|---|---|---|
| **Lớp 1** | `dst-ioc` | Trong → Ngoài (outbound) | IOC là **đích đến** — host/user nội bộ kết nối ra ngoài tới địa chỉ độc hại (C2, malware download, phishing, mining pool...) |
| **Lớp 2** | `src-ioc` | Ngoài → Trong (inbound) | IOC là **nguồn tấn công** — IP bên ngoài tấn công vào mạng nội bộ (scan, brute force, DDoS, bot...) |

### 1.3. Tổng số nhóm

| Lớp | Số nhóm | Dải |
|---|---|---|
| dst-ioc | 11 | dst.malware → dst.suspicious |
| src-ioc | 5 | src.scanner → src.anonymizer |
| **Tổng** | **16** | |

> Từ ~2,963 labels giảm xuống **16 nhóm** quản lý — mỗi IOC sẽ có 1 tag lớp + 1 tag nhóm.

---

## 2. Phân loại chi tiết

### 2.1. Lớp 1: `dst-ioc` — Outbound (Trong → Ngoài)

| # | Nhóm | Mô tả | Ví dụ mối đe dọa |
|---|---|---|---|
| 1 | **dst.malware** | Malware tổng hợp: trojan, worm, backdoor, loader, spyware, mobile malware, macOS malware | emotet, formbook, cobalt_strike, android_anubis, osx_lazarus |
| 2 | **dst.ransomware** | Ransomware families và hạ tầng | lockbit, ryuk, wannacry, akira, blacksuit |
| 3 | **dst.rat** | Remote Access Trojan — agent gọi về C2 | asyncrat, njrat, remcos, quasarrat, darkcomet |
| 4 | **dst.stealer** | Info stealer, credential theft, form grabber | redline, vidar, raccoon, lumma, 44caliber |
| 5 | **dst.botnet** | Botnet C&C — bot gọi về command server | mirai, hajime, bashlite, mozi, gafgyt |
| 6 | **dst.c2** | C2 framework / red-team tool bị lạm dụng | havoc, sliver, mythic, merlin_c2, metasploit |
| 7 | **dst.miner** | Cryptomining pool, cryptojacking | xmrig, coinhive, crypto_mining |
| 8 | **dst.exploit_kit** | Exploit kit, TDS (Traffic Direction System), malvertising | ek_rig, ek_angler, socgholish, parrot_tds, keitaro_tds |
| 9 | **dst.phishing** | Phishing, scam, spam tool, social engineering | evilginx, gophish, telekopye_scamtool, browser_locker, scareware |
| 10 | **dst.anonymizer** | Dịch vụ ẩn danh, tunnel, proxy — dùng để trốn phát hiện | onion, i2p, anonymous_web_proxy, dns_tunneling_service, port_proxy |
| 11 | **dst.suspicious** | PUA, domain đáng ngờ, RMM abuse, chưa xác nhận | pua, dynamic_domain, connectwise, meshagent, parking_site |

### 2.2. Lớp 2: `src-ioc` — Inbound (Ngoài → Trong)

| # | Nhóm | Mô tả | Ví dụ mối đe dọa |
|---|---|---|---|
| 1 | **src.scanner** | Mass scanner, port scanner, vulnerability scanner, recon | Mass Scanner, Shodan, Censys, ZMap |
| 2 | **src.attacker** | Known threat actor, known attacker IP | Known Attacker, APT infrastructure |
| 3 | **src.bot** | Malicious bot, crawler, scraper | Bot, Crawler (malicious automated access) |
| 4 | **src.ddos** | DDoS attack source | Amplification, volumetric, application-layer DDoS |
| 5 | **src.anonymizer** | Tor exit node, anonymizer network (inbound) | Tor Exit Node, Anonymizer (VPN/proxy attack source) |

---

## 3. Quy tắc mapping tự động

### 3.1. Mapping theo pattern (ưu tiên cao → thấp)

Các rule áp dụng theo thứ tự, rule đầu tiên match sẽ được dùng:

| # | Pattern (filename/label) | → Nhóm | Ghi chú |
|---|---|---|---|
| 1 | `*_ransomware` | dst.ransomware | Suffix match |
| 2 | `*rat` hoặc `*_rat` | dst.rat | Suffix match |
| 3 | `*_stealer` hoặc `*stealer` | dst.stealer | Suffix match |
| 4 | `*_miner` | dst.miner | Suffix match |
| 5 | `*_c2` | dst.c2 | Suffix match |
| 6 | `ek_*` | dst.exploit_kit | Prefix match |
| 7 | `*_tds` | dst.exploit_kit | Suffix match (TDS gộp chung exploit kit) |
| 8 | `*_spamtool` | dst.phishing | Suffix match |
| 9 | `*_phishtool` | dst.phishing | Suffix match |
| 10 | `*_scamtool` | dst.phishing | Suffix match |
| 11 | `*core` (CMS inject) | dst.malware | magentocore, wp_inject... |

### 3.2. Mapping theo danh sách tên cụ thể

#### dst.ransomware — Tên nổi tiếng (không có suffix `_ransomware`)

```
akira, alphav, avaddon, avoslocker, babuk, blackbasta, blackcat, blackmatter,
cerber, clop, conti, cuba, darkside, dharma, egregor, gandcrab, hive, 
lockbit, lorenz, lv, maze, medusa, mespinoza, nefilim, netwalker, nokoyawa,
phobos, play, pysa, ragnarok, ransomedvc, revil, rhysida, royal, ryuk,
sodinokibi, stop, teslacrypt, trigona, vice_society, wannacry
```

#### dst.rat — Tên nổi tiếng (không có suffix `rat`/`_rat`)

```
agenttesla, remcos, nanocore, warzone, adwind, orcus, gh0st, xworm,
poison_ivy, bitrat, limerat, dcrat, venom, havex
```

#### dst.stealer — Tên nổi tiếng (không có suffix `stealer`)

```
redline, vidar, raccoon, lumma, formbook, azorult, predator, pony, 
loki, aurora, stealc, rhadamanthys, mystic, risepro, meduza
```

#### dst.botnet — Botnet/loader nổi tiếng

```
mirai, hajime, bashlite, gafgyt, mozi, tsunami, kaiten, zergeca,
emotet, trickbot, qakbot, icedid, bumblebee, pikabot, danabot,
amadey, smokeloader, guloader, ursnif, dridex, zloader
```

#### dst.c2 — C2 framework / pentest tool (nằm trong malicious/ hoặc malware/)

```
cobalt_strike, havoc, sliver, mythic, metasploit, merlin_c2, brute_ratel,
caldera_c2, covenant, nighthawk, nimplant, brc4, viper, interactsh,
psransom_c2, pyramid_c2, supershell_c2, villian_c2, xiebroc2, zoro_c2,
shellcodec2, phonyc2, nameless_c2, mini_c2, khepri_c2, hak5cloud_c2,
ghostshell_c2, deimos_c2, cloakndagger_c2, anarchy_c2, adaptix_c2,
alchimist_c2, swat_c2, zshell_c2, ligolo_tunnel, python_byob,
redguard, redwarden, spiderlabs_responder, wraithnet
```

#### dst.phishing — Phishing/scam/spam (ngoài pattern match)

```
evilginx, gophish, georgeginx, browser_locker, scareware,
perswaysion, install_capital, install_cube, pushbug, katyabot,
supremebot, sms_flooder
```

#### dst.exploit_kit — Exploit kit / TDS (ngoài pattern match)

```
socgholish (SocGholish thuộc TDS), araneida
```

### 3.3. Mapping cho suspicious/ folder

| Label gốc | → Nhóm | Lý do |
|---|---|---|
| `anonymous_web_proxy` | dst.anonymizer | Proxy ẩn danh |
| `i2p` | dst.anonymizer | I2P network |
| `onion` | dst.anonymizer | Tor .onion |
| `port_proxy` | dst.anonymizer | Port forwarding / proxy |
| `dns_tunneling_service` | dst.anonymizer | DNS tunnel dùng để trốn |
| `blockchain_dns` | dst.anonymizer | DNS phi tập trung (trốn kiểm duyệt) |
| `crypto_mining` | dst.miner | Mining pool |
| `web_shells` | dst.malware | Web shell (backdoor trên server) |
| `dprk_silivaccine` | dst.malware | State-sponsored malware |
| `superfish` | dst.malware | Adware/MITM |
| `android_pua` | dst.suspicious | Android PUA |
| `osx_pua` | dst.suspicious | macOS PUA |
| `pua` | dst.suspicious | Generic PUA |
| `bad_history` | dst.suspicious | Domain lịch sử xấu |
| `bad_wpad` | dst.suspicious | WPAD abuse |
| `computrace` | dst.suspicious | Legit tool bị lạm dụng |
| `connectwise` | dst.suspicious | RMM abuse |
| `dnspod` | dst.suspicious | Free DNS (hay bị lạm dụng) |
| `domain` | dst.suspicious | Domain đáng ngờ chung |
| `dynamic_domain` | dst.suspicious | Dynamic DNS |
| `free_web_hosting` | dst.suspicious | Free hosting (hay bị phishing) |
| `ipinfo` | dst.suspicious | IP recon service |
| `meshagent` | dst.suspicious | RMM abuse |
| `nezha_rmmtool` | dst.suspicious | RMM abuse |
| `parking_site` | dst.suspicious | Domain parking |
| `simplehelp` | dst.suspicious | RMM abuse |
| `suspended_domain` | dst.suspicious | Domain bị tạm ngưng |
| `xenarmor` | dst.suspicious | Dual-use tool |

### 3.4. Mapping cho nguồn ngoài (External feeds)

| Label gốc | → Nhóm | Lý do |
|---|---|---|
| `Mass Scanner` | src.scanner | Quét hàng loạt từ ngoài vào |
| `Known Attacker` | src.attacker | IP tấn công đã biết |
| `Bot, Crawler` | src.bot | Bot/crawler độc hại |
| `Tor Exit Node` | src.anonymizer | Tor exit kết nối vào |
| `Anonymizer` | src.anonymizer | VPN/proxy ẩn danh kết nối vào |

### 3.5. Default rule

| Folder gốc | Default nhóm | Điều kiện |
|---|---|---|
| `malware/` | **dst.malware** | Nếu không match bất kỳ rule nào ở trên |
| `malicious/` | **dst.malware** | Nếu không match bất kỳ rule nào ở trên |
| `suspicious/` | **dst.suspicious** | Nếu không match bất kỳ rule nào ở trên |

---

## 4. Mapping tổng hợp: Label cũ → Nhóm mới

### 4.1. malware/ → dst-ioc (2,806 files)

| Nhóm mới | Số lượng (ước tính) | Label cũ đại diện |
|---|---|---|
| dst.malware | ~2,160 | android_*, osx_*, emotet (nếu ko ở botnet), formbook, cobalt_strike (nếu ko ở c2), trojan chung... |
| dst.ransomware | ~150 | *_ransomware + tên nổi tiếng (lockbit, ryuk, wannacry, akira...) |
| dst.rat | ~230 | *rat, *_rat + agenttesla, remcos, nanocore... |
| dst.stealer | ~50 | *_stealer, *stealer + redline, vidar, raccoon, lumma... |
| dst.botnet | ~60 | mirai, emotet, trickbot, qakbot, amadey, smokeloader... |
| dst.c2 | ~15 | cobalt_strike (từ malware/) |
| dst.miner | ~41 | *_miner |

### 4.2. malicious/ → dst-ioc (124 files)

| Nhóm mới | Số lượng | Label cũ đại diện |
|---|---|---|
| dst.c2 | ~35 | *_c2 + havoc, sliver, mythic, metasploit, nimplant... |
| dst.exploit_kit | ~36 | ek_* + *_tds + socgholish |
| dst.phishing | ~15 | *_spamtool, *_phishtool, evilginx, gophish, browser_locker, scareware... |
| dst.malware | ~38 | *core, bad_proxy, bad_script, bad_service, domain_shadowing... |

### 4.3. suspicious/ → dst-ioc (28 files)

| Nhóm mới | Số lượng | Label cũ đại diện |
|---|---|---|
| dst.anonymizer | 6 | anonymous_web_proxy, i2p, onion, port_proxy, dns_tunneling_service, blockchain_dns |
| dst.miner | 1 | crypto_mining |
| dst.malware | 3 | web_shells, dprk_silivaccine, superfish |
| dst.suspicious | 18 | pua, android_pua, osx_pua, connectwise, meshagent, dynamic_domain... |

### 4.4. External feeds → src-ioc (5 labels)

| Nhóm mới | Số lượng | Label cũ |
|---|---|---|
| src.scanner | 1 | Mass Scanner |
| src.attacker | 1 | Known Attacker |
| src.bot | 1 | Bot, Crawler |
| src.anonymizer | 2 | Tor Exit Node, Anonymizer |

---

## 5. Tổng hợp phân bổ

| Nhóm | Lớp | Số IOC labels (ước tính) | Tỷ lệ |
|---|---|---|---|
| dst.malware | dst-ioc | ~2,216 | 74.8% |
| dst.ransomware | dst-ioc | ~150 | 5.1% |
| dst.rat | dst-ioc | ~230 | 7.8% |
| dst.stealer | dst-ioc | ~50 | 1.7% |
| dst.botnet | dst-ioc | ~60 | 2.0% |
| dst.c2 | dst-ioc | ~50 | 1.7% |
| dst.miner | dst-ioc | ~42 | 1.4% |
| dst.exploit_kit | dst-ioc | ~36 | 1.2% |
| dst.phishing | dst-ioc | ~15 | 0.5% |
| dst.anonymizer | dst-ioc | ~6 | 0.2% |
| dst.suspicious | dst-ioc | ~18 | 0.6% |
| src.scanner | src-ioc | mass_scanner | — |
| src.attacker | src-ioc | known_attacker | — |
| src.bot | src-ioc | bot_crawler | — |
| src.ddos | src-ioc | (mở rộng) | — |
| src.anonymizer | src-ioc | tor_exit + anonymizer | — |

---

## 6. Cấu trúc label cho mỗi IOC

Mỗi IOC sẽ được gán **4 labels**:

```
┌─ Label 1: "v2secure"          (tổ chức)
├─ Label 2: "<source>"           (nguồn: maltrail, abuseipdb, ...)
├─ Label 3: "<layer>"            (lớp: dst-ioc hoặc src-ioc)
└─ Label 4: "<group>"            (nhóm: dst.malware, src.scanner, ...)
```

**Ví dụ:**

| IOC | Label 1 | Label 2 | Label 3 | Label 4 | Family (description) |
|---|---|---|---|---|---|
| `192.168.1.100` | v2 secure | maltrail | dst-ioc | dst.ransomware | lockbit |
| `evil.example.com` | v2 secure | maltrail | dst-ioc | dst.c2 | cobalt_strike |
| `45.33.32.0/24` | v2 secure | abuseipdb | src-ioc | src.scanner | Mass Scanner |
| `mining-pool.com` | v2 secure | maltrail | dst-ioc | dst.miner | xmrig |
| `tor-exit.node.ip` | v2 secure | ext_feed | src-ioc | src.anonymizer | Tor Exit Node |

> **Tên malware family cụ thể** (lockbit, emotet, cobalt_strike...) giữ trong **description**, không dùng làm label → tránh bùng nổ số lượng label.

---

## 7. Ưu tiên Score mapping

| Nhóm | x_opencti_score | Lý do |
|---|---|---|
| dst.ransomware | **95** | Ransomware là mối đe dọa cao nhất |
| dst.c2 | **90** | C2 active = đang bị kiểm soát |
| dst.rat | **90** | RAT active = bị remote control |
| dst.stealer | **85** | Đang bị đánh cắp credentials |
| dst.botnet | **85** | Host thành bot |
| dst.malware | **80** | Malware chung |
| dst.exploit_kit | **80** | Exploit kit / drive-by |
| dst.phishing | **75** | Phishing / social engineering |
| dst.miner | **60** | Cryptomining (ảnh hưởng hiệu năng) |
| dst.anonymizer | **50** | Có thể hợp pháp |
| dst.suspicious | **40** | Chưa xác nhận |
| src.attacker | **90** | Known threat actor |
| src.ddos | **85** | DDoS đang diễn ra |
| src.scanner | **60** | Recon (chưa tấn công) |
| src.bot | **55** | Bot tự động |
| src.anonymizer | **50** | Tor/VPN (có thể hợp pháp) |

---

## 8. Mapping MITRE ATT&CK Tactics

### 8.1. Tổng quan 14 chiến thuật MITRE ATT&CK Enterprise

| # | Tactic ID | Tactic | Mô tả |
|---|---|---|---|
| 1 | TA0043 | **Reconnaissance** | Thu thập thông tin về mục tiêu |
| 2 | TA0042 | **Resource Development** | Xây dựng hạ tầng & tài nguyên tấn công |
| 3 | TA0001 | **Initial Access** | Xâm nhập ban đầu vào hệ thống |
| 4 | TA0002 | **Execution** | Thực thi mã độc |
| 5 | TA0003 | **Persistence** | Duy trì quyền truy cập |
| 6 | TA0004 | **Privilege Escalation** | Leo thang đặc quyền |
| 7 | TA0005 | **Defense Evasion** | Né tránh phòng thủ / phát hiện |
| 8 | TA0006 | **Credential Access** | Đánh cắp thông tin xác thực |
| 9 | TA0007 | **Discovery** | Khám phá hệ thống & mạng nội bộ |
| 10 | TA0008 | **Lateral Movement** | Di chuyển ngang trong mạng |
| 11 | TA0009 | **Collection** | Thu thập dữ liệu mục tiêu |
| 12 | TA0011 | **Command and Control** | Thiết lập kênh điều khiển (C2) |
| 13 | TA0010 | **Exfiltration** | Rút trích dữ liệu ra ngoài |
| 14 | TA0040 | **Impact** | Gây thiệt hại / phá hoại |

> Tham khảo: https://attack.mitre.org/tactics/enterprise/

### 8.2. Mapping nhóm IOC → Chiến thuật chính & phụ

#### Lớp 1: dst-ioc (Outbound)

| Nhóm | Chiến thuật chính | Chiến thuật phụ | Kỹ thuật MITRE tiêu biểu |
|---|---|---|---|
| **dst.malware** | TA0002 Execution | TA0003 Persistence, TA0005 Defense Evasion | T1204 User Execution, T1059 Command and Scripting Interpreter, T1547 Boot/Logon Autostart, T1027 Obfuscated Files |
| **dst.ransomware** | TA0040 Impact | TA0002 Execution, TA0005 Defense Evasion | T1486 Data Encrypted for Impact, T1490 Inhibit System Recovery, T1489 Service Stop |
| **dst.rat** | TA0011 Command and Control | TA0009 Collection, TA0002 Execution | T1219 Remote Access Software, T1071 Application Layer Protocol, T1113 Screen Capture, T1056 Input Capture |
| **dst.stealer** | TA0006 Credential Access | TA0010 Exfiltration, TA0009 Collection | T1555 Credentials from Password Stores, T1539 Steal Web Session Cookie, T1041 Exfiltration Over C2 Channel, T1005 Data from Local System |
| **dst.botnet** | TA0011 Command and Control | TA0040 Impact, TA0002 Execution | T1071 Application Layer Protocol, T1573 Encrypted Channel, T1498 Network Denial of Service |
| **dst.c2** | TA0011 Command and Control | TA0042 Resource Development | T1071 Application Layer Protocol, T1573 Encrypted Channel, T1572 Protocol Tunneling, T1583 Acquire Infrastructure |
| **dst.miner** | TA0040 Impact | TA0002 Execution | T1496 Resource Hijacking, T1059 Command and Scripting Interpreter |
| **dst.exploit_kit** | TA0001 Initial Access | TA0042 Resource Development | T1189 Drive-by Compromise, T1608 Stage Capabilities, T1583 Acquire Infrastructure |
| **dst.phishing** | TA0001 Initial Access | TA0043 Reconnaissance | T1566 Phishing (.001 Attachment, .002 Link), T1598 Phishing for Information |
| **dst.anonymizer** | TA0005 Defense Evasion | TA0011 Command and Control | T1090 Proxy (.003 Multi-hop Proxy), T1572 Protocol Tunneling, T1573 Encrypted Channel |
| **dst.suspicious** | TA0042 Resource Development | TA0005 Defense Evasion | T1583.006 Web Services, T1584 Compromise Infrastructure, T1036 Masquerading |

#### Lớp 2: src-ioc (Inbound)

| Nhóm | Chiến thuật chính | Chiến thuật phụ | Kỹ thuật MITRE tiêu biểu |
|---|---|---|---|
| **src.scanner** | TA0043 Reconnaissance | — | T1595 Active Scanning (.001 Scanning IP Blocks, .002 Vulnerability Scanning) |
| **src.attacker** | TA0001 Initial Access | TA0043 Reconnaissance | T1190 Exploit Public-Facing Application, T1133 External Remote Services |
| **src.bot** | TA0043 Reconnaissance | TA0001 Initial Access | T1595 Active Scanning, T1190 Exploit Public-Facing Application |
| **src.ddos** | TA0040 Impact | — | T1498 Network Denial of Service, T1499 Endpoint Denial of Service |
| **src.anonymizer** | TA0005 Defense Evasion | TA0001 Initial Access | T1090.003 Multi-hop Proxy (ẩn nguồn tấn công) |

### 8.3. Ma trận tổng hợp: Nhóm × Chiến thuật

```
                  TA0043  TA0042  TA0001  TA0002  TA0003  TA0004  TA0005  TA0006  TA0007  TA0008  TA0009  TA0011  TA0010  TA0040
                  Recon   ResDev  InitAcc Exec    Persist PrivEsc DefEvas CredAcc Discov  LatMov  Collect C2      Exfil   Impact
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
dst.malware        .       .       .      ██       ██      .       ██      .       .       .       .       .       .       .
dst.ransomware     .       .       .      ░░       .       .       ░░      .       .       .       .       .       .      ██
dst.rat            .       .       .      ░░       .       .       .       .       .       .       ░░     ██       .       .
dst.stealer        .       .       .       .       .       .       .      ██       .       .       ░░      .      ░░       .
dst.botnet         .       .       .      ░░       .       .       .       .       .       .       .      ██       .      ░░
dst.c2             .      ░░       .       .       .       .       .       .       .       .       .      ██       .       .
dst.miner          .       .       .      ░░       .       .       .       .       .       .       .       .       .      ██
dst.exploit_kit    .      ░░      ██       .       .       .       .       .       .       .       .       .       .       .
dst.phishing      ░░       .      ██       .       .       .       .       .       .       .       .       .       .       .
dst.anonymizer     .       .       .       .       .       .      ██       .       .       .       .      ░░       .       .
dst.suspicious     .      ██       .       .       .       .      ░░       .       .       .       .       .       .       .
src.scanner       ██       .       .       .       .       .       .       .       .       .       .       .       .       .
src.attacker      ░░       .      ██       .       .       .       .       .       .       .       .       .       .       .
src.bot           ██       .      ░░       .       .       .       .       .       .       .       .       .       .       .
src.ddos           .       .       .       .       .       .       .       .       .       .       .       .       .      ██
src.anonymizer     .       .      ░░       .       .       .      ██       .       .       .       .       .       .       .

██ = Chiến thuật chính    ░░ = Chiến thuật phụ    . = Không liên quan
```

### 8.4. Phân bổ theo chiến thuật

| Chiến thuật | Số nhóm liên quan | Nhóm chính | Nhóm phụ |
|---|---|---|---|
| TA0043 Reconnaissance | 4 | src.scanner, src.bot | dst.phishing, src.attacker |
| TA0042 Resource Development | 3 | dst.suspicious | dst.c2, dst.exploit_kit |
| TA0001 Initial Access | 5 | dst.exploit_kit, dst.phishing, src.attacker | src.bot, src.anonymizer |
| TA0002 Execution | 4 | dst.malware | dst.ransomware, dst.rat, dst.botnet, dst.miner |
| TA0003 Persistence | 1 | dst.malware | — |
| TA0005 Defense Evasion | 4 | dst.malware, dst.anonymizer, src.anonymizer | dst.ransomware, dst.suspicious |
| TA0006 Credential Access | 1 | dst.stealer | — |
| TA0009 Collection | 2 | — | dst.rat, dst.stealer |
| TA0010 Exfiltration | 1 | — | dst.stealer |
| TA0011 Command and Control | 4 | dst.rat, dst.botnet, dst.c2 | dst.anonymizer |
| TA0040 Impact | 4 | dst.ransomware, dst.miner, src.ddos | dst.botnet |
| TA0004, TA0007, TA0008 | 0 | — | (Không áp dụng cho IOC network-level) |

> **Ghi chú:** TA0004 (Privilege Escalation), TA0007 (Discovery), TA0008 (Lateral Movement) không mapping trực tiếp vì các chiến thuật này xảy ra **bên trong host** sau khi đã xâm nhập — không thể phát hiện qua IOC ở tầng network (IP/domain). Các chiến thuật này phù hợp hơn với EDR/HIDS.

### 8.5. Ứng dụng trong OpenCTI

Khi tạo IOC trong OpenCTI, gán thêm **Kill Chain Phase** theo mapping trên:

```json
{
  "type": "indicator",
  "name": "evil-c2.example.com",
  "labels": ["v2secure", "v2-ioc", "dst-ioc", "dst.c2"],
  "description": "cobalt_strike",
  "x_opencti_score": 90,
  "kill_chain_phases": [
    {
      "kill_chain_name": "mitre-attack",
      "phase_name": "command-and-control"
    }
  ]
}
```

| Nhóm | `kill_chain_phases.phase_name` |
|---|---|
| dst.malware | `execution` |
| dst.ransomware | `impact` |
| dst.rat | `command-and-control` |
| dst.stealer | `credential-access` |
| dst.botnet | `command-and-control` |
| dst.c2 | `command-and-control` |
| dst.miner | `impact` |
| dst.exploit_kit | `initial-access` |
| dst.phishing | `initial-access` |
| dst.anonymizer | `defense-evasion` |
| dst.suspicious | `resource-development` |
| src.scanner | `reconnaissance` |
| src.attacker | `initial-access` |
| src.bot | `reconnaissance` |
| src.ddos | `impact` |
| src.anonymizer | `defense-evasion` |

---

## 9. So sánh trước/sau

| Hạng mục | Trước | Sau |
|---|---|---|
| Tổng labels | ~2,963 (không quản lý được) | **16 nhóm** + family name trong description |
| Phân lớp | Không có | **2 lớp** (dst-ioc / src-ioc) |
| Phân nhóm | Chỉ 3 (malware/malicious/suspicious) | **16 nhóm** theo chuẩn ngành |
| Hướng traffic | Không phân biệt | Rõ ràng inbound / outbound |
| Score mapping | 3 mức (90/70/50) | **16 mức** chi tiết theo mức độ nguy hiểm |
| Filter/Report | Chỉ filter theo category | Filter theo lớp + nhóm + source |
| Label dropdown | Quá dài (2,963 items) | Gọn (16 items) |

---

## 10. Sơ đồ tổng quan

```
IOC Labels
├── dst-ioc (Outbound: Trong → Ngoài)
│   │                                                          MITRE ATT&CK
│   │                                                          Tactic chính           Tactic phụ
│   ├── dst.malware        ← malware/*, malicious/*core...    TA0002 Execution       TA0003 Persistence, TA0005 Defense Evasion
│   ├── dst.ransomware     ← *_ransomware, lockbit, ryuk...   TA0040 Impact          TA0002 Execution, TA0005 Defense Evasion
│   ├── dst.rat            ← *rat, remcos, agenttesla...      TA0011 C2              TA0009 Collection, TA0002 Execution
│   ├── dst.stealer        ← *_stealer, redline, vidar...     TA0006 Credential Acc  TA0010 Exfiltration, TA0009 Collection
│   ├── dst.botnet         ← mirai, emotet, trickbot...       TA0011 C2              TA0040 Impact, TA0002 Execution
│   ├── dst.c2             ← *_c2, havoc, sliver, mythic...   TA0011 C2              TA0042 Resource Development
│   ├── dst.miner          ← *_miner, crypto_mining           TA0040 Impact          TA0002 Execution
│   ├── dst.exploit_kit    ← ek_*, *_tds, socgholish          TA0001 Initial Access  TA0042 Resource Development
│   ├── dst.phishing       ← *_spamtool, evilginx, gophish   TA0001 Initial Access  TA0043 Reconnaissance
│   ├── dst.anonymizer     ← onion, i2p, port_proxy...        TA0005 Defense Evasion TA0011 C2
│   └── dst.suspicious     ← pua, dynamic_domain, RMM...      TA0042 Resource Dev    TA0005 Defense Evasion
│
└── src-ioc (Inbound: Ngoài → Trong)
    │                                                          MITRE ATT&CK
    │                                                          Tactic chính           Tactic phụ
    ├── src.scanner        ← Mass Scanner                     TA0043 Reconnaissance  —
    ├── src.attacker       ← Known Attacker                   TA0001 Initial Access  TA0043 Reconnaissance
    ├── src.bot            ← Bot, Crawler                     TA0043 Reconnaissance  TA0001 Initial Access
    ├── src.ddos           ← (mở rộng khi có nguồn DDoS)     TA0040 Impact          —
    └── src.anonymizer     ← Tor Exit Node, Anonymizer        TA0005 Defense Evasion TA0001 Initial Access
```

---

## 11. Khuyến nghị triển khai

1. **Bước 1:** Cấu hình mapping rules (pattern match + known names) vào connector
2. **Bước 2:** Mỗi IOC nhận 4 labels: `v2 secure` + `<source>` + `<layer>` + `<group>`
3. **Bước 3:** Family name cụ thể (lockbit, emotet...) giữ trong description, KHÔNG tạo label
4. **Bước 4:** Xóa dần labels cũ (2,963 labels) đã tạo trong OpenCTI
5. **Bước 5:** Cập nhật dashboard/report filter theo 16 nhóm mới

> **Lưu ý:** Nhóm `src.ddos` hiện chưa có nguồn dữ liệu. Giữ sẵn để bổ sung khi tích hợp thêm feed DDoS (Spamhaus, AbuseIPDB...).
