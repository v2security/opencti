# 1. MISSING_REFERENCE_ERROR khi ingest STIX bundle lớn

## Mô tả lỗi

Platform log ghi nhận **18 warning** `MISSING_REFERENCE_ERROR` ngay sau khi start connectors.
Lỗi xảy ra ở 2 operation:

| Operation | Số lần | Object bị thiếu |
|-----------|--------|-----------------|
| `StixCoreRelationshipAdd` | 14 | `vulnerability--*` |
| `ReportAdd` | 4 | `relationship--*` |

**Level: `warn`** (không phải `error`) — platform vẫn chạy bình thường.

## Minh chứng

### Log platform (`/var/log/opencti/opencti-platform.log`)

```
03:20:39 WRITE_ERROR StixCoreRelationshipAdd unresolvedIds:["vulnerability--1540eb2d-ca78-551e-87bb-a144bd64de73"]
03:20:40 WRITE_ERROR StixCoreRelationshipAdd unresolvedIds:["vulnerability--f455e52a-44bf-593b-8f8e-0d84814391d4"]
...
03:21:26 WRITE_ERROR ReportAdd unresolvedIds:["relationship--df4d06c6-8305-5454-8eac-38d7023e6572"]
03:21:37 WRITE_ERROR ReportAdd unresolvedIds:["relationship--7f989ef5-3465-5b7c-bd58-ed66debc5256"]
03:30:16 WRITE_ERROR ReportAdd unresolvedIds:["relationship--a32a93fb-2ccd-59fb-b76e-3c4cd48a466e"]
03:30:37 WRITE_ERROR ReportAdd unresolvedIds:["relationship--7d4f09ec-799e-5265-b534-2694d8d924d6"]
```

### Kết luận sau khi đối chiếu lại log

Vấn đề này **không phải chỉ do 1 connector**.

- Nhóm lỗi `StixCoreRelationshipAdd` với `unresolvedIds:["vulnerability--..."]` nhiều khả năng đến từ **custom connector v2-nvd**
- Nhóm lỗi `ReportAdd` với `unresolvedIds:["relationship--..."]` **không** đến từ v2-nvd, mà đến từ connector khác có tạo `Report` (AlienVault OTX là ứng viên rõ nhất trong phiên này)

## Minh chứng

### 1. v2-nvd bắt đầu gửi bundle đúng ngay trước thời điểm phát sinh `StixCoreRelationshipAdd`

Timeline từ `docker logs connector-v2-nvd`:

```
03:20:28  NVD connector bắt đầu sync cycle
03:20:38  Initiate work
03:20:38  NVD CVE sending bundle to queue
03:20:39  NVD CVE sending bundle to queue liên tục
```

Timeline từ platform log:

```
03:20:39  WRITE_ERROR StixCoreRelationshipAdd unresolvedIds:["vulnerability--..."]
03:20:40  WRITE_ERROR StixCoreRelationshipAdd unresolvedIds:["vulnerability--..."]
03:20:41  WRITE_ERROR StixCoreRelationshipAdd unresolvedIds:["vulnerability--..."]
...
03:21:04  WRITE_ERROR StixCoreRelationshipAdd unresolvedIds:["vulnerability--..."]
```

Hai dải thời gian này khớp trực tiếp với nhau.

### 2. Code của v2-nvd đúng là có tạo `Relationship` tham chiếu sang `Vulnerability`

Trong `v2-nvd/src/connector.py`, mỗi CVE được build thành bundle gồm:

- `Identity`
- `Vulnerability`
- nhiều `Software`
- nhiều `Relationship`

Trong `v2-nvd/src/stix_builders/relationship.py`:

```python
kwargs: dict = {
	"relationship_type": "has",
	"source_ref": software.id,
	"target_ref": vuln.id,
	...
}
```

Tức là v2-nvd đang tạo `StixCoreRelationship` có `target_ref = vulnerability--...`.
Nếu worker xử lý relationship trước object vulnerability tương ứng, OpenCTI sẽ trả đúng lỗi đang thấy: `MISSING_REFERENCE_ERROR` cho `vulnerability--...`.

### 3. `ReportAdd` không thể đến từ v2-nvd

Code v2-nvd hiện tại **không tạo `Report` object**.
Vì vậy các warning dạng:

```
WRITE_ERROR ReportAdd unresolvedIds:["relationship--..."]
```

không thể do v2-nvd sinh ra trực tiếp.

### 4. AlienVault OTX vẫn là nguồn hợp lý cho nhóm `ReportAdd`

Timeline từ docker logs:

```
03:20:32  AlienVault bắt đầu gửi 11 pulses
03:20:37  Pulse "Funnull Resurfaces" — bundle 4200 objects (lớn nhất)
03:20:39  Platform bắt đầu log MISSING_REFERENCE_ERROR
03:20:48  AlienVault hoàn tất tất cả 11 pulses
```

AlienVault có tạo pulse/report-style data và bundle rất lớn, nên nhóm `ReportAdd unresolvedIds:["relationship--..."]` rất phù hợp với luồng này.

### 5. v2-botnet không phải nguồn gây lỗi trong phiên này

- v2-botnet chỉ mới register và start API server
- Không thấy log tạo `Report`
- Không có dấu hiệu liên quan tới `vulnerability--...`

### Worker logs (`/var/log/opencti-worker/`) — không có error

Workers hoạt động bình thường, chỉ ghi INFO level.

## Nguyên nhân gốc

Có **2 nhóm warning khác nhau**, nhưng cùng một bản chất:

- `StixCoreRelationshipAdd` của v2-nvd
- `ReportAdd` của connector khác có tạo report

Điểm chung là **race condition** khi 3 workers xử lý song song object có dependency:

1. Connector gửi bundle chứa object cha và object phụ thuộc cùng một đợt
2. OpenCTI tách bundle và đẩy vào RabbitMQ
3. 3 workers xử lý song song
4. Relationship hoặc Report bị xử lý trước object mà nó reference tới
5. Platform trả `MISSING_REFERENCE_ERROR`

Với phiên này:

- v2-nvd gây ra nhánh `relationship -> vulnerability`
- AlienVault hoặc connector tương tự gây ra nhánh `report -> relationship`

## Giải quyết

### 1. Giải pháp vận hành

- Khi chạy initial import, chỉ để **1 worker**:

```bash
systemctl stop opencti-worker@2 opencti-worker@3
```

Cách này giảm mạnh race condition khi ingest dữ liệu phụ thuộc lẫn nhau.

- Chạy **v2-nvd trước**, đợi historical import xong rồi mới start các connector report/pulse như AlienVault.

### 2. Giải pháp ở custom connector v2-nvd

Nếu muốn xử lý tận gốc trong code, cần tránh gửi `Vulnerability` và `Relationship` phụ thuộc vào nó trong cùng một đợt import song song.

Các hướng sửa hợp lý:

- Phase 1: import chỉ `Vulnerability`
- Phase 2: import `Software` + `Relationship`

Hoặc ít nhất:

- trong historical import đầu tiên, tạm bỏ tạo relationship software -> vulnerability
- để cycle sau hoặc job sau tạo bù relationship

### 3. Giải pháp với nhóm `ReportAdd`

- Start AlienVault sau khi platform đã ổn định và dữ liệu nền đã được tạo
- Hoặc chấp nhận warning ở first cycle, vì cycle sau thường sẽ tự hết