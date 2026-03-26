## 📘 1️⃣ Bảng thuật ngữ trong Threat Intelligence (TI)
| Thuật ngữ                            | Viết tắt | Định nghĩa chuẩn                                                     | Vai trò trong TI                    |
| ------------------------------------ | -------- | -------------------------------------------------------------------- | ----------------------------------- |
| Common Vulnerabilities and Exposures | **CVE**  | Danh sách chuẩn hóa các lỗ hổng bảo mật công khai (do MITRE quản lý) | Định danh **lỗ hổng cụ thể**        |
| Common Platform Enumeration          | **CPE**  | Chuẩn mô tả sản phẩm/phần mềm/hệ thống (vendor, version…)            | Xác định **đối tượng bị ảnh hưởng** |
| Common Weakness Enumeration          | **CWE**  | Danh sách các **loại lỗi bảo mật** (root cause)                      | Phân loại bản chất lỗ hổng          |
| Common Vulnerability Scoring System  | **CVSS** | Hệ thống chấm điểm mức độ nghiêm trọng (0–10)                        | Đánh giá mức độ rủi ro              |
| Indicator of Compromise              | **IOC**  | Dữ liệu kỹ thuật quan sát được (IP, domain, hash…)                   | Phát hiện & hunting                 |
| Tactics, Techniques and Procedures   | **TTP**  | Cách attacker hành động (chiến thuật + kỹ thuật)                     | Hiểu hành vi tấn công               |
| Advanced Persistent Threat           | **APT**  | Nhóm attacker có tổ chức, hoạt động dài hạn                          | Actor cấp cao                       |
| Malware                              | —        | Phần mềm độc hại                                                     | Công cụ tấn công                    |
| Exploit                              | —        | Code/technique khai thác lỗ hổng                                     | Cách tận dụng CVE                   |
| Vulnerability                        | —        | Điểm yếu bảo mật trong hệ thống                                      | Nguồn gốc rủi ro                    |

👉 Lưu ý quan trọng:

+ **CVE ≠ Vulnerability**
    + → CVE chỉ là **ID**, còn vulnerability là **thực thể**
+ **CPE ≠ Software**
    + → CPE là **chuẩn định danh**, không phải object trực tiếp

## 🧠 2️⃣ Bảng thuật ngữ trong OpenCTI (theo STIX Model)

STIX chia toàn bộ Threat Intelligence thành 3 loại object chính:

+ **SDO (STIX Domain Objects)** → “kiến thức / intelligence”
+ **SCO (STIX Cyber Observable)** → “dữ liệu kỹ thuật / evidence”
+ **SRO (STIX Relationship Objects)** → “quan hệ giữa các object”

> 👉 STIX thực chất là graph model (node + edge)

### 📌 A. STIX Domain Objects (SDO) – “WHAT & WHO”
👉 Đại diện cho thực thể có ý nghĩa trong phân tích TI

| OpenCTI Type     | Định nghĩa chuẩn                   | Mapping TI          | Ví dụ                         |
| ---------------- | ---------------------------------- | ------------------- | ----------------------------- |
| Vulnerability    | Lỗ hổng bảo mật (có thể có CVE)    | CVE / Vulnerability | CVE-2024-1234                 |
| Malware          | Phần mềm độc hại                   | Malware             | WannaCry                      |
| Threat Actor     | Cá nhân/tổ chức tấn công           | Attacker            | Lazarus                       |
| Intrusion Set    | Nhóm hoạt động lâu dài (APT group) | APT                 | APT29                         |
| Attack Pattern   | Kỹ thuật tấn công                  | TTP                 | Phishing                      |
| Campaign         | Chuỗi attack theo thời gian        | Campaign            | SolarWinds                    |
| Tool             | Công cụ hỗ trợ tấn công            | Tool                | Mimikatz                      |
| Indicator        | Rule/phát hiện IOC (pattern)       | IOC logic           | `[ipv4-addr:value='1.1.1.1']` |
| Report           | Báo cáo tổng hợp TI                | Report              | PDF report                    |
| Course of Action | Biện pháp mitigation               | Mitigation          | Patch                         |
| Identity         | Tổ chức/cá nhân                    | Org/User            | Microsoft                     |

**📌 Index ES:**
> opencti_stix_domain_objects-*

### 📌 B. STIX Cyber Observables (SCO)
👉 Là dữ liệu kỹ thuật quan sát được trong thực tế

| OpenCTI Type | Định nghĩa chuẩn  | Mapping TI    | Ví dụ                                         |
| ------------ | ----------------- | ------------- | --------------------------------------------- |
| IPv4-Addr    | Địa chỉ IP        | IOC           | 8.8.8.8                                       |
| Domain-Name  | Domain            | IOC           | evil.com                                      |
| URL          | URL độc hại       | IOC           | [http://evil.com](http://evil.com)            |
| File         | File + hash       | IOC           | SHA256                                        |
| Email-Addr   | Email             | IOC           | [attacker@mail.com](mailto:attacker@mail.com) |
| Software     | Phần mềm hệ thống | CPE (mapping) | Windows 10                                    |

**📌 Index ES:**
> opencti_stix_cyber_observables-*

### 📌 C. Relationship (SRO)
👉 Dùng để nối SDO ↔ SDO hoặc SDO ↔ SCO

| Relationship | Ý nghĩa           | Ví dụ                   |
| ------------ | ----------------- | ----------------------- |
| exploits     | Khai thác lỗ hổng | Malware exploits CVE    |
| uses         | Sử dụng công cụ   | Actor uses Tool         |
| targets      | Nhắm mục tiêu     | Actor targets Org       |
| indicates    | IOC → threat      | IP indicates Malware    |
| related-to   | Quan hệ chung     | Software related-to CVE |

**📌 Index ES:**
> opencti_stix_relationships-*
