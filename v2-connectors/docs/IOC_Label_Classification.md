# V2 Secure — IOC Label Classification System

> Áp dụng chung cho tất cả v2-connectors (v2-maltrail, v2-botnet, v2-nvd, ...).
> Mọi connector khi tạo IOC trong OpenCTI đều PHẢI tuân theo chuẩn này.

---

## 1. Tổng quan

### 1.1. Vấn đề

Các connector tạo label trực tiếp từ tên file/nguồn dữ liệu → hàng nghìn labels không quản lý được, không filter/report hiệu quả.

### 1.2. Giải pháp

Phân thành **2 lớp** (layer) theo hướng traffic, mỗi lớp chia thành **các nhóm** (group):

| Lớp | Tag | Hướng traffic | Ý nghĩa |
|---|---|---|---|
| **Lớp 1** | `dst-ioc` | Trong → Ngoài (outbound) | IOC là **đích đến** — host nội bộ kết nối ra địa chỉ độc hại |
| **Lớp 2** | `src-ioc` | Ngoài → Trong (inbound) | IOC là **nguồn tấn công** — IP bên ngoài tấn công vào mạng nội bộ |

**Tổng: 16 nhóm** (11 dst-ioc + 5 src-ioc).

---

## 2. Phân loại chi tiết 16 nhóm

### 2.1. Lớp 1: `dst-ioc` — Outbound (11 nhóm)

| # | Nhóm | Mô tả | Ví dụ |
|---|---|---|---|
| 1 | **dst.malware** | Malware tổng hợp: trojan, worm, backdoor, loader, spyware | emotet, formbook, android_anubis |
| 2 | **dst.ransomware** | Ransomware families và hạ tầng | lockbit, ryuk, wannacry, akira |
| 3 | **dst.rat** | Remote Access Trojan | asyncrat, njrat, remcos, quasarrat |
| 4 | **dst.stealer** | Info stealer, credential theft | redline, vidar, raccoon, lumma |
| 5 | **dst.botnet** | Botnet C&C | mirai, emotet, trickbot, qakbot |
| 6 | **dst.c2** | C2 framework / red-team tool | havoc, sliver, mythic, cobalt_strike |
| 7 | **dst.miner** | Cryptomining pool, cryptojacking | xmrig, coinhive, crypto_mining |
| 8 | **dst.exploit_kit** | Exploit kit, TDS, malvertising | ek_rig, socgholish, keitaro_tds |
| 9 | **dst.phishing** | Phishing, scam, spam tool | evilginx, gophish, browser_locker |
| 10 | **dst.anonymizer** | Dịch vụ ẩn danh, tunnel, proxy | onion, i2p, anonymous_web_proxy |
| 11 | **dst.suspicious** | PUA, domain đáng ngờ, RMM abuse | pua, dynamic_domain, connectwise |

### 2.2. Lớp 2: `src-ioc` — Inbound (5 nhóm)

| # | Nhóm | Mô tả | Ví dụ |
|---|---|---|---|
| 1 | **src.scanner** | Mass scanner, port scanner, recon | Mass Scanner, Shodan, ZMap |
| 2 | **src.attacker** | Known threat actor IP | Known Attacker, APT infrastructure |
| 3 | **src.bot** | Malicious bot, crawler | Bot, Crawler |
| 4 | **src.ddos** | DDoS attack source | Amplification, volumetric DDoS |
| 5 | **src.anonymizer** | Tor exit node, anonymizer (inbound) | Tor Exit Node, VPN attack source |

---

## 3. Cấu trúc label cho mỗi IOC

Mỗi IOC được gán **4 labels**:

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

> **Tên malware family** (lockbit, emotet, ...) giữ trong **description**, KHÔNG dùng làm label.

---

## 4. Score mapping

Mỗi nhóm có `x_opencti_score` cố định, thể hiện mức độ nguy hiểm:

| Nhóm | Score | Lý do |
|---|---|---|
| dst.ransomware | **95** | Ransomware — mối đe dọa cao nhất |
| dst.c2 | **90** | C2 active = đang bị kiểm soát |
| dst.rat | **90** | RAT active = bị remote control |
| src.attacker | **90** | Known threat actor |
| dst.stealer | **85** | Đang bị đánh cắp credentials |
| dst.botnet | **85** | Host thành bot |
| src.ddos | **85** | DDoS đang diễn ra |
| dst.malware | **80** | Malware chung |
| dst.exploit_kit | **80** | Exploit kit / drive-by |
| dst.phishing | **75** | Phishing / social engineering |
| dst.miner | **60** | Cryptomining (ảnh hưởng hiệu năng) |
| src.scanner | **60** | Recon (chưa tấn công) |
| src.bot | **55** | Bot tự động |
| dst.anonymizer | **50** | Có thể hợp pháp |
| src.anonymizer | **50** | Tor/VPN (có thể hợp pháp) |
| dst.suspicious | **40** | Chưa xác nhận |

---

## 5. MITRE ATT&CK Kill Chain mapping

Mỗi nhóm map tới **1 chiến thuật chính** (dùng trong `kill_chain_phases`):

| Nhóm | `phase_name` | Tactic ID | Ghi chú |
|---|---|---|---|
| dst.malware | `execution` | TA0002 | Thực thi mã độc |
| dst.ransomware | `impact` | TA0040 | Mã hóa / phá hủy dữ liệu |
| dst.rat | `command-and-control` | TA0011 | RAT gọi về C2 |
| dst.stealer | `credential-access` | TA0006 | Đánh cắp credentials |
| dst.botnet | `command-and-control` | TA0011 | Bot gọi về C&C |
| dst.c2 | `command-and-control` | TA0011 | C2 framework |
| dst.miner | `impact` | TA0040 | Resource hijacking |
| dst.exploit_kit | `initial-access` | TA0001 | Drive-by compromise |
| dst.phishing | `initial-access` | TA0001 | Phishing link/attachment |
| dst.anonymizer | `defense-evasion` | TA0005 | Proxy / tunnel ẩn danh |
| dst.suspicious | `resource-development` | TA0042 | Hạ tầng đáng ngờ |
| src.scanner | `reconnaissance` | TA0043 | Active scanning |
| src.attacker | `initial-access` | TA0001 | Khai thác lỗ hổng |
| src.bot | `reconnaissance` | TA0043 | Bot scan / crawl |
| src.ddos | `impact` | TA0040 | Network DoS |
| src.anonymizer | `defense-evasion` | TA0005 | Ẩn nguồn tấn công |

**STIX JSON mẫu:**

```json
{
  "type": "indicator",
  "name": "evil-c2.example.com",
  "labels": ["v2secure", "v2-ioc", "dst-ioc", "dst.c2"],
  "description": "Maltrail threat intelligence: evil-c2.example.com classified as dst.c2 (cobalt_strike).",
  "x_opencti_score": 90,
  "kill_chain_phases": [
    {
      "kill_chain_name": "mitre-attack",
      "phase_name": "command-and-control"
    }
  ]
}
```

---

## 6. Quy tắc mapping tự động (cho connector)

### 6.1. Thứ tự ưu tiên (rule đầu tiên match → dùng)

1. **Root-level file** → dùng `ROOT_FILE_MAP` (e.g. mass_scanner → src.scanner)
2. **suspicious/ folder** → dùng `SUSPICIOUS_MAP` (28 entries cố định)
3. **malicious/ folder** → check `MALICIOUS_SPECIFIC`, known sets, CMS inject
4. **Pattern match** (tất cả folders):
   - `*_ransomware` → dst.ransomware
   - `*rat` / `*_rat` → dst.rat
   - `*_stealer` / `*stealer` → dst.stealer
   - `*_miner` → dst.miner
   - `*_c2` / `*c2` → dst.c2
   - `ek_*` → dst.exploit_kit
   - `*_tds` → dst.exploit_kit
   - `*_spamtool` / `*_phishtool` / `*_scamtool` → dst.phishing
5. **Known-name sets**: KNOWN_RANSOMWARE, KNOWN_RAT, KNOWN_STEALER, KNOWN_BOTNET, KNOWN_C2, KNOWN_PHISHING, KNOWN_EXPLOIT_KIT
6. **Folder default**: malware/ → dst.malware, malicious/ → dst.malware, suspicious/ → dst.suspicious

### 6.2. CSV override

Mỗi connector có thể dùng CSV file (`data/ioc_label_mapping.csv`) để override phân loại cho từng file. CSV được kiểm tra trước rules. Format:

```csv
folder,filename,layer,group,score,kill_chain
malware,lockbit,dst-ioc,dst.ransomware,95,impact
malicious,cobalt_strike,dst-ioc,dst.c2,90,command-and-control
```

---

## 7. Hướng dẫn áp dụng cho connector mới

### Bước 1: Import label_map

Mỗi connector chỉ cần import module `label_map`:

```python
from trail.label_map import lookup, IOCGroupInfo

info: IOCGroupInfo = lookup(filename, folder)
# info.layer  → "dst-ioc" / "src-ioc"
# info.group  → "dst.malware", "dst.ransomware", ...
# info.score  → 40-95
# info.kill_chain → "execution", "impact", ...
```

### Bước 2: Gán 4 labels

```python
labels = ["v2secure", "<source>", info.layer, info.group]
```

### Bước 3: Gán score + kill_chain

```python
x_opencti_score = info.score
kill_chain_phases = [
    KillChainPhase(
        kill_chain_name="mitre-attack",
        phase_name=info.kill_chain,
    )
]
```

### Bước 4: Family name → description

```python
description = f"... classified as {info.group} ({file_tag})."
```

---

## 8. Sơ đồ tổng quan

```
IOC Labels
├── dst-ioc (Outbound: Trong → Ngoài)
│   ├── dst.malware        score=80  execution            ← default cho malware/, malicious/
│   ├── dst.ransomware     score=95  impact               ← *_ransomware + known names
│   ├── dst.rat            score=90  command-and-control   ← *rat + known names
│   ├── dst.stealer        score=85  credential-access     ← *stealer + known names
│   ├── dst.botnet         score=85  command-and-control   ← known botnets
│   ├── dst.c2             score=90  command-and-control   ← *_c2 + known C2 frameworks
│   ├── dst.miner          score=60  impact               ← *_miner
│   ├── dst.exploit_kit    score=80  initial-access        ← ek_* + *_tds
│   ├── dst.phishing       score=75  initial-access        ← *_spamtool, *_phishtool
│   ├── dst.anonymizer     score=50  defense-evasion       ← onion, i2p, proxy
│   └── dst.suspicious     score=40  resource-development  ← pua, dynamic_domain
│
└── src-ioc (Inbound: Ngoài → Trong)
    ├── src.scanner        score=60  reconnaissance        ← mass_scanner
    ├── src.attacker       score=90  initial-access        ← known attacker
    ├── src.bot            score=55  reconnaissance        ← bot, crawler
    ├── src.ddos           score=85  impact               ← (reserved)
    └── src.anonymizer     score=50  defense-evasion       ← tor exit, anonymizer
```

---

## 9. So sánh trước/sau

| Hạng mục | Trước | Sau |
|---|---|---|
| Tổng labels | ~2,963 (không quản lý được) | **16 nhóm** + family name trong description |
| Phân lớp | Không có | **2 lớp** (dst-ioc / src-ioc) |
| Phân nhóm | Chỉ 3 (malware/malicious/suspicious) | **16 nhóm** theo chuẩn ngành |
| Score | 3 mức (90/70/50) | **16 mức** chi tiết |
| Kill chain | Hardcoded "command-and-control" | Per-group mapping theo MITRE ATT&CK |
| Filter/Report | Chỉ filter theo category | Filter theo lớp + nhóm + source |

---

## 10. Checklist khi update connector

- [ ] Import `label_map.lookup()` thay vì dùng label/score cũ
- [ ] IOC labels = `["v2secure", "<source>", layer, group]` (4 labels)
- [ ] Score từ `IOCGroupInfo.score` (không hardcode)
- [ ] Kill chain từ `IOCGroupInfo.kill_chain` (per-group, không dùng chung 1 giá trị)
- [ ] Family name chỉ nằm trong description
- [ ] Tạo/update CSV mapping nếu connector có file-based IOC data
- [ ] Test: verify labels, scores, kill_chain trên OpenCTI UI

> **Lưu ý:** Nhóm `src.ddos`, `src.attacker`, `src.bot`, `src.anonymizer` hiện chưa có nguồn dữ liệu từ maltrail. Các nhóm này sẵn sàng khi tích hợp thêm feed (Spamhaus, AbuseIPDB, OTX, ...).
