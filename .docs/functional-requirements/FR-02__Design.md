# FR-02 Design: CPE–CVE Mapping — Optimal Solution

> **Mục tiêu**: Hỗ trợ truy vấn 2 chiều CVE↔CPE với version range và điều kiện môi trường, **không sửa schema OpenCTI**, tận dụng tối đa data model có sẵn.

---

## 1. Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                        NVD JSON Feed                            │
│  CVE-2025-21102 → configurations (AND/OR, version ranges)       │
└──────────────────────────┬──────────────────────────────────────┘
                           │  NVD Connector (import)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     OpenCTI Platform                            │
│                                                                 │
│  ┌──────────────┐   has (description=    ┌──────────────────┐   │
│  │  Software A  │──── version range) ──▶│  Vulnerability    │   │
│  │  (vulnerable)│                       │  (CVE)            │   │
│  └──────┬───────┘                        └────────┬─────────┘   │
│         │ related-to                              │             │
│  ┌──────▼───────┐                        ┌────────▼─────────┐   │
│  │  Software B  │                       │  Note             │   │
│  │  (platform)  │                       │  (NVD config JSON)│   │
│  └──────────────┘                        └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Nguyên tắc thiết kế

| # | Nguyên tắc | Lý do |
|---|---|---|
| 1 | **Zero schema modification** | Không fork/patch OpenCTI — dễ upgrade, dễ bảo trì |
| 2 | **Dùng relationship `description`** cho version range | Field có sẵn, indexed trong ES, searchable |
| 3 | **Dùng Note entity** cho full NVD config | Giữ nguyên vẹn dữ liệu gốc, phục vụ audit & complex matching |
| 4 | **1 Software entity = 1 CPE product** | Dedup theo `name+cpe+vendor`, không tạo N entity cho N version |
| 5 | **Phân biệt vulnerable vs platform** bằng relationship type | `has` = bị ảnh hưởng, `related-to` = môi trường chạy |

---

## 2. Data Model chi tiết

### 2.1 Software Entity (SCO) — 1 entity per CPE product

Mỗi CPE **product** duy nhất tạo **1 Software entity**. Không tạo entity riêng cho mỗi version.

**Ví dụ CVE-2025-21102** tạo 2 Software entities:

| # | Field | Software A (Firmware) | Software B (Hardware) |
|---|---|---|---|
| 1 | `name` | `Dell VxRail D560 Firmware` | `Dell VxRail D560` |
| 2 | `cpe` | `cpe:2.3:o:dell:vxrail_d560_firmware:*:*:*:*:*:*:*:*` | `cpe:2.3:h:dell:vxrail_d560:-:*:*:*:*:*:*:*` |
| 3 | `vendor` | `dell` | `dell` |
| 4 | `version` | _(empty — đại diện cho product, không phải version cụ thể)_ | `-` |
| 5 | `x_opencti_product` | `vxrail_d560_firmware` | `vxrail_d560` |

> **Tại sao `version` để trống?** Vì version range thuộc về **mối quan hệ** giữa Software và CVE, không thuộc về bản thân Software. Cùng 1 product `vxrail_d560_firmware` có thể bị nhiều CVE khác nhau ảnh hưởng ở các version range khác nhau.

### 2.2 Vulnerability Entity (SDO) — giữ nguyên

Không thay đổi gì. CVE-2025-21102 đã được import bởi connector CVE hiện tại.

### 2.3 Relationship: `Software --[has]--> Vulnerability`

Đây là relationship chính — **Software bị ảnh hưởng bởi Vulnerability**.

| Field | Giá trị | Mục đích |
|---|---|---|
| `relationship_type` | `has` | Phần mềm **có** lỗ hổng này |
| `source` | Software A (firmware) | CPE với `vulnerable: true` |
| `target` | Vulnerability (CVE) | CVE entity |
| `confidence` | `100` | Dữ liệu từ NVD, high confidence |
| `description` | **(Xem format bên dưới)** | Chứa version range có cấu trúc |

#### Format `description` — Version Range Structured Text

```
[CPE-MATCH]
versionStartIncluding: 7.0.000
versionEndExcluding: 7.0.533
platform: cpe:2.3:h:dell:vxrail_d560:-:*:*:*:*:*:*:*
platformName: Dell VxRail D560
matchCriteriaId: 1B33332D-FCD9-40E0-A104-C61BE6E661E5
[/CPE-MATCH]

Firmware Dell VxRail D560 phiên bản 7.0.000 đến trước 7.0.533, chạy trên phần cứng Dell VxRail D560.
```

**Tại sao format này?**

| Yêu cầu | Giải pháp |
|---|---|
| Máy đọc được (parse) | Block `[CPE-MATCH]...[/CPE-MATCH]` dễ regex parse |
| Người đọc được | Dòng mô tả tự nhiên bên dưới block |
| ES searchable | Toàn bộ text được index, tìm `7.0.000` hoặc `vxrail_d560` đều hit |
| Không cần schema change | `description` là field có sẵn trên mọi relationship |

#### Parse regex cho connector/tool

```python
import re

CPE_MATCH_PATTERN = re.compile(
    r'\[CPE-MATCH\]\s*'
    r'(?:versionStartIncluding:\s*(?P<vsi>[^\n]+)\n)?'
    r'(?:versionStartExcluding:\s*(?P<vse>[^\n]+)\n)?'
    r'(?:versionEndIncluding:\s*(?P<vei>[^\n]+)\n)?'
    r'(?:versionEndExcluding:\s*(?P<vee>[^\n]+)\n)?'
    r'(?:platform:\s*(?P<platform>[^\n]+)\n)?'
    r'(?:platformName:\s*(?P<platformName>[^\n]+)\n)?'
    r'(?:matchCriteriaId:\s*(?P<matchId>[^\n]+)\n)?'
    r'\[/CPE-MATCH\]',
    re.MULTILINE
)
```

### 2.4 Relationship: `Software(firmware) --[related-to]--> Software(hardware)`

Mô hình hóa điều kiện AND — firmware **chạy trên** hardware.

| Field | Giá trị |
|---|---|
| `relationship_type` | `related-to` |
| `source` | Software A (firmware) |
| `target` | Software B (hardware) |
| `description` | `Firmware runs on this hardware platform (NVD AND condition)` |

> Relationship này tồn tại **độc lập với CVE** — nó mô tả quan hệ vật lý giữa firmware và hardware. Có thể dùng lại cho nhiều CVE khác nhau.

### 2.5 Note Entity — Full NVD Configuration

Lưu nguyên vẹn JSON `configurations` từ NVD, đính kèm vào Vulnerability.

| Field | Giá trị |
|---|---|
| `entity_type` | `Note` |
| `attribute_abstract` | `NVD CPE Configuration for CVE-2025-21102` |
| `content` | Full JSON `configurations` (xem bên dưới) |
| `note_types` | `["external"]` |
| `objectRefs` | `[Vulnerability(CVE-2025-21102)]` |

```json
{
  "source": "NVD",
  "cveId": "CVE-2025-21102",
  "configurations": [
    {
      "operator": "AND",
      "nodes": [
        {
          "operator": "OR",
          "negate": false,
          "cpeMatch": [{
            "vulnerable": true,
            "criteria": "cpe:2.3:o:dell:vxrail_d560_firmware:*:*:*:*:*:*:*:*",
            "versionStartIncluding": "7.0.000",
            "versionEndExcluding": "7.0.533",
            "matchCriteriaId": "1B33332D-FCD9-40E0-A104-C61BE6E661E5"
          }]
        },
        {
          "operator": "OR",
          "negate": false,
          "cpeMatch": [{
            "vulnerable": false,
            "criteria": "cpe:2.3:h:dell:vxrail_d560:-:*:*:*:*:*:*:*",
            "matchCriteriaId": "0B547BDB-12A9-40AC-B4CA-040F413C5F05"
          }]
        }
      ]
    }
  ]
}
```

**Tại sao cần Note?**
- `description` trên relationship đã đủ cho 80% use case (forward/reverse lookup)
- Note giữ lại **100% dữ liệu gốc** cho complex matching, audit, và edge case (nested AND/OR, multiple CPE groups)
- Nếu sau này cần implement CPE matching engine, Note là single source of truth

---

## 3. Tổng kết Data Model — Ví dụ CVE-2025-21102

```
┌─────────────────────────────┐
│ Software (SCO)              │
│ name: Dell VxRail D560 FW   │
│ cpe: cpe:2.3:o:dell:        │
│   vxrail_d560_firmware:*... │
│ vendor: dell                │
│ x_opencti_product:          │
│   vxrail_d560_firmware      │
├─────────────────────────────┤
│         │                   │
│         │ has               │
│         │ (description =    │
│         │  version range    │
│         │  + platform info) │
│         ▼                   │
│ ┌───────────────────────┐   │
│ │ Vulnerability (SDO)   │   │
│ │ name: CVE-2025-21102  │◀──── Note (full NVD config JSON)
│ │ cvss: ...             │   │
│ └───────────────────────┘   │
│         ▲                   │
│         │                   │
│ related-to                  │
│         │                   │
│ ┌───────────────────────┐   │
│ │ Software (SCO)        │   │
│ │ name: Dell VxRail D560│   │
│ │ cpe: cpe:2.3:h:dell:  │   │
│ │   vxrail_d560:-:*...  │   │
│ │ vendor: dell          │   │
│ └───────────────────────┘   │
└─────────────────────────────┘
```

Chính xác hơn, mô hình relationship:

| # | Source | Rel Type | Target | Description |
|---|---|---|---|---|
| R1 | Software (firmware) | `has` | Vulnerability (CVE) | Version range + platform info |
| R2 | Software (firmware) | `related-to` | Software (hardware) | "Firmware runs on this hardware" |

---

## 4. Import Flow (NVD Connector)

### Algorithm — Xử lý 1 CVE

```
INPUT:  NVD CVE JSON entry
OUTPUT: OpenCTI entities + relationships

FOR each configuration_group in cve.configurations:
  
  // Phân loại CPE theo vulnerable flag
  vulnerable_cpes = []    // vulnerable: true  → bị ảnh hưởng
  platform_cpes   = []    // vulnerable: false → môi trường

  FOR each node in configuration_group.nodes:
    FOR each cpeMatch in node.cpeMatch:
      IF cpeMatch.vulnerable == true:
        vulnerable_cpes.append(cpeMatch)
      ELSE:
        platform_cpes.append(cpeMatch)

  // Tạo Software entities
  FOR each vcpe in vulnerable_cpes:
    software = UPSERT Software(
      name     = humanize(vcpe.criteria),     // "Dell VxRail D560 Firmware"
      cpe      = normalize_cpe(vcpe.criteria), // wildcard version
      vendor   = extract_vendor(vcpe.criteria),
      x_opencti_product = extract_product(vcpe.criteria)
    )

    // Tạo relationship has → Vulnerability
    description = format_description(
      versionStartIncluding = vcpe.versionStartIncluding,
      versionEndExcluding   = vcpe.versionEndExcluding,
      versionStartExcluding = vcpe.versionStartExcluding,
      versionEndIncluding   = vcpe.versionEndIncluding,
      platforms             = platform_cpes
    )
    
    CREATE Relationship(
      type        = "has",
      source      = software,
      target      = vulnerability,
      confidence  = 100,
      description = description
    )

    // Tạo platform Software + related-to
    FOR each pcpe in platform_cpes:
      platform_sw = UPSERT Software(
        name     = humanize(pcpe.criteria),
        cpe      = pcpe.criteria,
        vendor   = extract_vendor(pcpe.criteria),
        x_opencti_product = extract_product(pcpe.criteria)
      )
      
      CREATE Relationship(
        type        = "related-to",
        source      = software,
        target      = platform_sw,
        description = "Firmware runs on this hardware platform (NVD AND condition)"
      )

  // Lưu full configuration JSON as Note
  CREATE Note(
    abstract    = "NVD CPE Configuration for {cve.id}",
    content     = JSON.stringify({source: "NVD", cveId: cve.id, configurations: cve.configurations}),
    note_types  = ["external"],
    objectRefs  = [vulnerability]
  )
```

### Helper Functions

```python
def humanize(cpe_string: str) -> str:
    """cpe:2.3:o:dell:vxrail_d560_firmware:*:... → 'Dell VxRail D560 Firmware'"""
    parts = cpe_string.split(":")
    vendor  = parts[3].replace("_", " ").title()   # "Dell"
    product = parts[4].replace("_", " ").title()    # "Vxrail D560 Firmware"
    return f"{vendor} {product}"

def normalize_cpe(cpe_string: str) -> str:
    """Giữ nguyên CPE nhưng đảm bảo version = * (product-level)"""
    parts = cpe_string.split(":")
    parts[5] = "*"  # version → wildcard
    return ":".join(parts)

def extract_vendor(cpe_string: str) -> str:
    return cpe_string.split(":")[3]

def extract_product(cpe_string: str) -> str:
    return cpe_string.split(":")[4]

def format_description(vsi, vee, vse, vei, platforms) -> str:
    lines = ["[CPE-MATCH]"]
    if vsi: lines.append(f"versionStartIncluding: {vsi}")
    if vse: lines.append(f"versionStartExcluding: {vse}")
    if vei: lines.append(f"versionEndIncluding: {vei}")
    if vee: lines.append(f"versionEndExcluding: {vee}")
    for p in platforms:
        lines.append(f"platform: {p['criteria']}")
        lines.append(f"platformName: {humanize(p['criteria'])}")
    lines.append("[/CPE-MATCH]")
    
    # Human readable summary
    version_text = ""
    if vsi and vee: version_text = f"phiên bản {vsi} đến trước {vee}"
    elif vsi and vei: version_text = f"phiên bản {vsi} đến {vei}"
    elif vee: version_text = f"phiên bản trước {vee}"
    elif vei: version_text = f"phiên bản đến {vei}"
    
    platform_text = ", ".join(humanize(p['criteria']) for p in platforms)
    if platform_text:
        lines.append(f"\n{humanize_product} {version_text}, chạy trên {platform_text}.")
    else:
        lines.append(f"\n{humanize_product} {version_text}.")
    
    return "\n".join(lines)
```

---

## 5. Query Patterns

### 5.1 Chiều thuận: CVE → CPEs + Môi trường

**GraphQL Query:**

```graphql
query CVE_to_CPEs($cveId: String!) {
  vulnerabilities(
    filters: {
      mode: and
      filters: [{ key: "name", values: [$cveId] }]
    }
  ) {
    edges {
      node {
        name                          # CVE-2025-21102
        description
        x_opencti_cvss_base_score
        
        # Software bị ảnh hưởng (has relationship)
        softwares(relationshipType: "has") {
          edges {
            node {
              name                    # Dell VxRail D560 Firmware
              cpe                     # cpe:2.3:o:dell:vxrail_d560_firmware:*:...
              vendor                  # dell
              x_opencti_product       # vxrail_d560_firmware
            }
            relation {
              description             # [CPE-MATCH] version range + platform
            }
          }
        }
        
        # Full NVD config (Note)
        notes {
          edges {
            node {
              attribute_abstract      # "NVD CPE Configuration for CVE-2025-21102"
              content                 # Full JSON
            }
          }
        }
      }
    }
  }
}
```

**Output xử lý (parse description):**

```
CVE-2025-21102 ảnh hưởng:
├── Dell VxRail D560 Firmware (cpe:2.3:o:dell:vxrail_d560_firmware)
│   ├── Version range: 7.0.000 ≤ v < 7.0.533
│   └── Platform: Dell VxRail D560 (hardware)
├── Dell VxRail D560F Firmware
│   ├── Version range: 7.0.000 ≤ v < 7.0.533
│   └── Platform: Dell VxRail D560F (hardware)
└── ... (các firmware khác)
```

### 5.2 Chiều ngược: Product → CVEs

**GraphQL Query:**

```graphql
query Product_to_CVEs($productName: String!) {
  stixCyberObservables(
    types: ["Software"]
    filters: {
      mode: or
      filters: [
        { key: "name", values: [$productName] }
        { key: "x_opencti_product", values: [$productName] }
      ]
    }
  ) {
    edges {
      node {
        ... on Software {
          name                        # Dell VxRail D560 Firmware
          cpe
          vendor
          
          vulnerabilities {
            edges {
              node {
                name                  # CVE-2025-21102
                description
                x_opencti_cvss_base_score
              }
              relation {
                description           # [CPE-MATCH] version range
              }
            }
          }
        }
      }
    }
  }
}
```

**Output xử lý:**

```
Dell VxRail D560 Firmware bị ảnh hưởng bởi:
├── CVE-2025-21102
│   └── Version range: 7.0.000 ≤ v < 7.0.533
├── CVE-2025-XXXXX (nếu có thêm)
│   └── Version range: ...
└── ...
```

### 5.3 Tìm kiếm nhanh qua ES (cho tool/integration)

Nếu cần query trực tiếp ES thay vì qua GraphQL:

```json
// Tìm tất cả relationship "has" có version range chứa "7.0.000"
POST /opencti_stix_core_relationships/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "relationship_type": "has" } },
        { "match": { "description": "versionStartIncluding: 7.0.000" } }
      ]
    }
  }
}
```

---

## 6. Đánh giá Solution

### Checklist Input/Output

| Yêu cầu | Đáp ứng? | Cách thực hiện |
|---|---|---|
| CVE → CPE bị ảnh hưởng | ✅ | `Vulnerability.softwares` (rel type `has`) |
| CVE → Version range | ✅ | Parse `description` trên relationship `has` |
| CVE → Môi trường (hardware) | ✅ | `platform` field trong description + `related-to` relationship |
| Product → CVEs | ✅ | `Software.vulnerabilities` |
| Product → Version range per CVE | ✅ | Parse `description` trên relationship `has` |
| Phân biệt vulnerable vs platform | ✅ | `vulnerable=true` → `has`, `vulnerable=false` → `related-to` |
| Giữ nguyên full NVD data | ✅ | Note entity với JSON đầy đủ |

### Trade-offs

| Aspect | Ưu điểm | Hạn chế |
|---|---|---|
| **Schema** | Zero modification — upgrade-safe | — |
| **Version range** | Searchable qua ES full-text | Không structured query (e.g. "tìm tất cả CPE có version < 8.0") |
| **AND/OR logic** | Preserved trong Note JSON | Cần parse Note để reconstruct complex logic |
| **Dedup** | 1 Software per product, tái sử dụng across CVEs | Cùng product nhiều relationship, mỗi rel có description riêng |
| **Performance** | Dùng existing indexes, không thêm index mới | Relationship description search chậm hơn structured field search |

### So sánh với các phương án khác

| Phương án | Ưu điểm | Nhược điểm | Đánh giá |
|---|---|---|---|
| **A. Extend schema** (thêm field `versionStartIncluding` lên Software) | Structured query | Fork OpenCTI, khó upgrade, version thuộc relationship không phải entity | ❌ Không nên |
| **B. Extend relationship schema** (thêm custom field lên `has`) | Structured query trên relationship | Cần patch OpenCTI core, mỗi lần upgrade phải re-apply | ❌ Rủi ro cao |
| **C. Chỉ dùng Note** (không tạo relationship) | Giữ 100% NVD data | Mất bi-directional query, không navigable từ Software↔Vulnerability | ❌ Không đủ |
| **D. Hybrid (Solution này)** | Zero schema change, bi-directional, searchable, full data preserved | Version range là text, cần parse | ✅ **Optimal** |

---

## 7. Scope triển khai

### Phase 1 — Core (đủ cho Input/Output)

| Task | Mô tả | Output |
|---|---|---|
| T1 | NVD Connector: Parse `configurations` → tạo Software entities | Software entities trong OpenCTI |
| T2 | NVD Connector: Tạo `has` relationship với description chứa version range | Relationships searchable |
| T3 | NVD Connector: Tạo `related-to` relationship cho platform CPEs | Environment modeling |
| T4 | NVD Connector: Tạo Note entity cho full NVD config | Audit trail |

### Phase 2 — Enhancement (nếu cần)

| Task | Mô tả |
|---|---|
| T5 | API wrapper: Parse description → trả structured JSON (version range object) |
| T6 | Frontend: Hiển thị version range + platform trên Vulnerability detail page |
| T7 | Matching engine: So sánh CPE version cụ thể với version range để xác nhận affected |
