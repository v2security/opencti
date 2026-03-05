## 1️⃣ SDO – STIX Domain Objects

> opencti_stix_domain_objects

**👉 Là đối tượng mô tả “ý nghĩa” / khái niệm trong threat intelligence**
Tức là những thứ mang tính phân tích, chiến lược, hoặc thực thể logic.

### Ví dụ các SDO phổ biến
| Object         | Nghĩa               |
| -------------- | ------------------- |
| Vulnerability  | CVE                 |
| Malware        | Mã độc              |
| Attack Pattern | Kỹ thuật tấn công   |
| Intrusion Set  | Nhóm APT            |
| Campaign       | Chiến dịch tấn công |
| Tool           | Công cụ tấn công    |
| Threat Actor   | Tác nhân đe doạ     |

Ví dụ cụ thể trong OpenCTI:
- CVE → lưu trong opencti_stix_domain_objects
- CWE → cũng là SDO
- Threat Actor → SDO
- Malware → SDO

**👉 SDO trả lời câu hỏi: “Cái gì đang đe doạ?”**

## 2️⃣ SCO – STIX Cyber Observables

> opencti_stix_cyber_observables

**👉 Là dữ liệu quan sát được trong thực tế kỹ thuật**
Tức là artifact có thể thấy trên hệ thống, log, network…

### Ví dụ các SCO phổ biến
| Object      | Nghĩa                  |
| ----------- | ---------------------- |
| File        | file hash              |
| Domain-Name | domain                 |
| IPv4-Addr   | IP                     |
| URL         | link độc               |
| Email-Addr  | email                  |
| Software    | phần mềm (CPE mapping) |

**Ví dụ trong OpenCTI:**
- CPE → được map thành Software → nằm trong opencti_stix_cyber_observables
- IP address → SCO
- Hash file → SCO

**👉 SCO trả lời câu hỏi: “Quan sát được cái gì trong hệ thống?”**
