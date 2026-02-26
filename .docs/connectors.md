https://www.gartner.com/en

**Source-Domain:**
+ https://www.kryptoslogic.com/products/telltale/
+ https://nvd.nist.gov/vuln/data-feeds
+ https://www.misp-project.org/
+ https://otx.alienvault.com/ 
+ https://www.shodan.io/
+ https://socradar.io/ 

# Source

    Các nguồn có cần đăng ký tài khoản hay không?


| STT | Nguồn dữ liệu | Loại dữ liệu | Có connector sẵn cho OpenCTI? | Loại connector | Ghi chú triển khai |
| --- | ------------- | ------------ | ----------------------------- | -------------- | ------------------ |
|  1  | **MISP OSINT Feed (Public Feeds)** | IOC (IP, domain, hash), blocklist, OSINT events | ✅ Có | External Import (Feed-based) | Phù hợp cho lab & bổ sung IOC, không phải nguồn CTI chiến lược cho production. |
|  2  | **NVD / NIST (CVE Feeds)** | CVE, CPE, CVSS | ✅ Có | External Import | Có connector chính thức ingest CVE/NVD → STIX. |
|  3  | **AlienVault OTX** | IOCs, pulses | ✅ Có | External Import | Có connector chính thức. Cần API key OTX. |
|  4  | **Shodan** | Dữ liệu scan IP, port, banner, SSL | ✅ Có | Internal Enrichment | Dùng để enrich IP/domain đã có trong OpenCTI (không ingest bulk feed). |
|  5  | **Kryptoslogic Telltale**  | Exposed credentials, threat data | ❌ Không chính thức | Custom | Cần API + tự viết connector nếu muốn ingest. |
|  6  | **SOCRadar** | Threat intel, dark web, brand monitoring | ❌ Không chính thức | Custom | Có API/STIX nhưng cần build connector riêng hoặc import STIX thủ công. |



# Planing

TI Server: V2 Server, Server khách hàng
+ Cloud (V2 Cloud Server)
+ On-premise (server khách hàng)

Cloud -> On-premise: Đồng bộ cho khách hàng với dữ liệu mới nhất

Rule: Oke
AI-Agent: Detect ?