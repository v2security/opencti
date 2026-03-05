## Bài toán

Từ NVD JSON (ví dụ CVE-2025-21102 trong `.docs/data/nvdcve-2.0-2025-sample.json`), dữ liệu `configurations` chứa:

```json
{
  "operator": "AND",
  "nodes": [
    { "operator": "OR", "cpeMatch": [{
        "vulnerable": true,
        "criteria": "cpe:2.3:o:dell:vxrail_d560_firmware:*:*:*:*:*:*:*:*",
        "versionStartIncluding": "7.0.000",
        "versionEndExcluding": "7.0.533"
    }]},
    { "operator": "OR", "cpeMatch": [{
        "vulnerable": false,
        "criteria": "cpe:2.3:h:dell:vxrail_d560:-:*:*:*:*:*:*:*"
    }]}
  ]
}
```

### Input/Output yêu cầu

**Chiều thuận — CVE_ID → CPEs + Môi trường:**
> Lỗ hổng **CVE-2025-21102** ảnh hưởng trực tiếp đến **Firmware Dell VxRail D560** với các phiên bản từ **7.0.000** đến trước **7.0.533**, chạy trên phần cứng **Dell VxRail D560**.

**Chiều ngược — Tên sản phẩm → CVEs (không kèm môi trường):**
> **Firmware Dell VxRail D560** trong các phiên bản từ **7.0.000** đến trước **7.0.533** có thể bị lỗ hổng **CVE-2025-21102** ảnh hưởng. 

| Chiều | Input | Output |
|---|---|---|
| Thuận | CVE ID (e.g. `CVE-2025-21102`) | Danh sách CPE bị ảnh hưởng + version range + môi trường (hardware/OS) |
| Ngược | Tên sản phẩm (`vxrail_d560_firmware` hoặc `Firmware Dell VxRail D560`) | Danh sách CVE ảnh hưởng + version range (không bắt buộc môi trường) |

## 1. CPE được lưu như thế nào trong OpenCTI? Có đủ để truy vấn các thông tin liên quan như mô tả phần Input/Output hay không?

### OpenCTI Software entity lưu được gì?

> **Minh chứng:** `opencti-graphql/src/schema/stixCyberObservable.ts` — mục `[ENTITY_SOFTWARE]`

| Field | Type | Lưu được? | Ví dụ |
|---|---|---|---|
| `name` | string | ✅ | `VxRail D560 Firmware` |
| `cpe` | string | ✅ | `cpe:2.3:o:dell:vxrail_d560_firmware:*:*:*:*:*:*:*:*` |
| `vendor` | string | ✅ | `dell` |
| `version` | string | ✅ | `*` (hoặc version cụ thể) |
| `swid` | string | ✅ | (SWID tag nếu có) |
| `x_opencti_product` | string | ✅ | `vxrail_d560_firmware` |
| `x_opencti_description` | string | ✅ | Mô tả tự do |
| `x_opencti_score` | int | ✅ | Điểm đánh giá |
| `languages` | string[] | ✅ | Ngôn ngữ hỗ trợ |
| `internal_id` | string (UUID) | ✅ | ID nội bộ — resolver dùng field này để query sang index `opencti_stix_core_relationships` lấy CVE liên quan |
| `standard_id` | string | ✅ | STIX standard ID, sinh từ tổ hợp `name+cpe+swid+vendor+version` |

> ⚠️ `vulnerabilities` **không phải field lưu trữ** trên Software — đây là **GraphQL resolved field**. Khi gọi `Software.vulnerabilities`, resolver truyền `software.id` (`internal_id`) vào hàm `vulnerabilitiesPaginated()`, hàm này query index `opencti_stix_core_relationships` tìm relationship `has` có `connections.internal_id = <software_id>` → trả về danh sách CVE.

### Dữ liệu NVD **KHÔNG** lưu native được

| Field NVD | Có field tương ứng? | Ghi chú |
|---|---|---|
| `versionStartIncluding` | ❌ **Không** | Không có field riêng |
| `versionEndExcluding` | ❌ **Không** | Không có field riêng |
| `versionStartExcluding` | ❌ **Không** | Không có field riêng |
| `versionEndIncluding` | ❌ **Không** | Không có field riêng |
| `vulnerable` (boolean) | ❌ **Không** | Không phân biệt "bị ảnh hưởng" vs "điều kiện" |
| `matchCriteriaId` | ❌ **Không** | UUID NVD dùng nội bộ |
| `operator` (AND/OR) | ❌ **Không** | Logic nhóm CPE |

### Kết luận: Lưu được CPE cơ bản, nhưng **MẤT version range và logic AND/OR**

**Lưu được:**
- CPE string, name, vendor, version, relationship `has` tới Vulnerability

**Mất:**
- Version range (`7.0.000 → trước 7.0.533`) — đây là thông tin quan trọng nhất để cảnh báo
- Logic AND/OR giữa firmware + hardware (biết firmware BỊ lỗi, hardware chỉ là điều kiện)
- Flag `vulnerable: true/false` để phân biệt CPE bị ảnh hưởng vs CPE chỉ là platform

### Trả lời: Có đủ dữ liệu cho Input/Output không?

**Không đủ nếu chỉ dùng native fields** — thiếu version range và logic AND/OR. Tuy nhiên, CÓ THỂ giải quyết bằng cách tận dụng relationship `description` + Note entity mà **không cần sửa schema OpenCTI**. Chi tiết xem [FR-02__Design.md](FR-02__Design.md).

---

## 2. Tạo quan hệ giữa CPE (Software) và CVE (Vulnerability)

### Có thể tạo relationship giữa CPE và CVE không?

**CÓ.** OpenCTI hỗ trợ 2 loại relationship giữa Software và Vulnerability:

| Relationship type | Hướng | Ý nghĩa |
|---|---|---|
| `has` | **Software → Vulnerability** | Phần mềm này **có** lỗ hổng này |
| `remediates` | **Software → Vulnerability** | Phần mềm này **khắc phục** lỗ hổng này |

### Hướng relationship

**Từ CPE (Software) tới CVE (Vulnerability)**, không phải ngược lại.

Dẫn chứng — định nghĩa trong source code (`opencti-platform/opencti-graphql/src/schema/stixCoreRelationship.ts`):

```ts
[`${ENTITY_SOFTWARE}_${ENTITY_TYPE_VULNERABILITY}`]: [
    { name: RELATION_HAS, type: REL_EXTENDED },
    { name: RELATION_REMEDIATES, type: REL_EXTENDED },
],
```

Không tồn tại mapping ngược `Vulnerability → Software` trong bảng relationship definitions.

### Có thể truy từ CVE tới CPE không?

**CÓ.** Mặc dù hướng relationship chính là `Software → Vulnerability`, OpenCTI hỗ trợ **truy ngược cả 2 chiều**:

| Chiều truy vấn | GraphQL field | Nơi định nghĩa |
|---|---|---|
| Software → Vulnerability | `vulnerabilities` trên type `Software` | `opencti.graphql` — `Software { vulnerabilities: VulnerabilityConnection }` |
| Vulnerability → Software (ngược) | `softwares` trên type `Vulnerability` | `opencti.graphql` — `Vulnerability { softwares(...): StixCyberObservableConnection }` |

Truy ngược hoạt động nhờ resolver `softwarePaginated()` trong `vulnerability-domain.ts` sử dụng **reverse traversal** — tìm các Software là source của relationship `has` mà target là Vulnerability đang xét.

### Tóm tắt chính xác

```
Software (CPE)  ──has──▶  Vulnerability (CVE)     ← hướng relationship chính
Software (CPE)  ◀──softwares──  Vulnerability (CVE)  ← truy ngược qua GraphQL field
```

**Cả 2 chiều đều query được.** Relationship lưu trong index `opencti_stix_core_relationships`.

