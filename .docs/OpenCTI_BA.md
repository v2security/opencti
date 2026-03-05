## 📘 1️⃣ Bảng thuật ngữ trong Threat Intelligence (TI)
| Thuật ngữ | Viết tắt | Nghĩa | Vai trò |
| --------- | -------- | ----- | ------- |
| Common Vulnerabilities and Exposures | **CVE**  | Mã định danh lỗ hổng bảo mật           | Xác định lỗ hổng cụ thể       |
| Common Platform Enumeration          | **CPE**  | Chuẩn định danh sản phẩm bị ảnh hưởng  | Xác định hệ thống bị tác động |
| Common Weakness Enumeration          | **CWE**  | Chuẩn phân loại loại lỗi bảo mật       | Xác định bản chất lỗi         |
| Common Vulnerability Scoring System  | **CVSS** | Hệ thống chấm điểm mức độ nghiêm trọng | Đánh giá mức độ nguy hiểm     |
| Indicator of Compromise              | **IOC**  | Dấu hiệu xâm nhập (IP, domain, hash…)  | Phát hiện tấn công            |
| Tactics, Techniques and Procedures   | **TTP**  | Chiến thuật & kỹ thuật tấn công        | Mô tả hành vi attacker        |
| Advanced Persistent Threat           | **APT**  | Nhóm tấn công có tổ chức               | Actor cấp cao                 |
| Malware                              | —        | Phần mềm độc hại                       | Công cụ tấn công              |
| Exploit                              | —        | Code khai thác lỗ hổng                 | Cách attacker tận dụng CVE    |
| Vulnerability                        | —        | Lỗ hổng bảo mật                        | Điểm yếu hệ thống             |

## 🧠 2️⃣ Bảng thuật ngữ trong OpenCTI (theo STIX Model)

OpenCTI dựa trên **STIX 2.1**, nên mọi thứ được chia thành:

- **SDO (STIX Domain Object)**

- **SCO (STIX Cyber Observable)**

- **SRO (STIX Relationship Object)**

### 📌 A. STIX Domain Objects (SDO)
| OpenCTI Type | Description | Tương ứng TI | Ví dụ |
| ------------ | ----------- | ------------ | ----- |
| Vulnerability    | Đại diện một lỗ hổng bảo mật đã được công bố (thường có CVE ID) | CVE          | CVE-2024-1234       |
| Malware          | Phần mềm độc hại được sử dụng trong tấn công                    | Malware      | WannaCry            |
| Intrusion Set    | Nhóm hoạt động tấn công có mục tiêu dài hạn                     | APT          | APT29               |
| Threat Actor     | Cá nhân hoặc tổ chức đứng sau hoạt động tấn công                | Attacker     | Lazarus Group       |
| Attack Pattern   | Kỹ thuật/phương pháp tấn công cụ thể                            | TTP          | Phishing            |
| Campaign         | Chuỗi hoạt động tấn công trong một khoảng thời gian             | Campaign     | SolarWinds Campaign |
| Tool             | Công cụ hợp pháp hoặc bán hợp pháp dùng trong tấn công          | Tool         | Mimikatz            |
| Report           | Tài liệu tổng hợp thông tin tình báo                            | Report       | Incident report PDF |
| Course of Action | Biện pháp phòng ngừa/khắc phục                                  | Mitigation   | Apply patch         |
| Identity         | Tổ chức hoặc cá nhân liên quan                                  | Organization | Microsoft           |

**📌 Index ES:**
> opencti_stix_domain_objects-*

### 📌 B. STIX Cyber Observables (SCO)
| OpenCTI Type | Description | Tương ứng TI | Ví dụ |
| ------------ | ----------- | ------------ | ----- |
| IPv4-Addr    | Địa chỉ IP quan sát được trong sự kiện | IOC          | 8.8.8.8                                        |
| Domain-Name  | Tên miền xuất hiện trong tấn công      | IOC          | evil.com                                       |
| URL          | Đường dẫn web độc hại                  | IOC          | [http://evil.com/login](http://evil.com/login) |
| File         | File quan sát được (hash, name, size…) | IOC          | SHA256                                         |
| Software     | Phần mềm/hệ thống bị ảnh hưởng         | CPE          | Windows 10                                     |
| Email-Addr   | Email liên quan tới tấn công           | IOC          | [attacker@mail.com](mailto:attacker@mail.com)  |

**📌 Index ES:**
> opencti_stix_cyber_observables-*

### 📌 C. Relationship (SRO)
| Relationship Type | Description | Ví dụ |
| ----------------- | ----------- | ----- |
| exploits          | Một malware/tool khai thác vulnerability | WannaCry exploits CVE-2017-0144   |
| targets           | Actor nhắm vào tổ chức                   | APT29 targets Microsoft           |
| uses              | Actor sử dụng malware/tool               | Lazarus uses Mimikatz             |
| indicates         | IOC chỉ ra malware/actor                 | IP indicates malware              |
| related-to        | Quan hệ chung không xác định rõ loại     | Software related-to Vulnerability |

**📌 Index ES:**
> opencti_stix_relationships-*
