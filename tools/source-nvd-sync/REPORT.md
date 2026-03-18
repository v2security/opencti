# Logic chuẩn OpenCTI — NVD CVE Connector

So sánh với connector chính thức: `OpenCTI-Platform/connectors/external-import/cve`

## revoked

Không set. Platform tự gán `false` — đúng chuẩn.

## confidence

```
100  — CVE có description
 60  — CVE không có description
```

Set trên cả Vulnerability và Relationship.

## createdBy

Identity `"The MITRE Corporation"` (`identity_class="organization"`).

- `created_by_ref` gắn trên Vulnerability + Relationship
- Identity object đưa vào mỗi bundle

## CVSS v4.0 Vector

OpenCTI chỉ nhận 12 base metrics. NVD trả 26+. Code tự strip, chỉ giữ: `AV, AC, AT, PR, UI, VC, VI, VA, SC, SI, SA, E`.

## x_opencti_score

`best CVSS baseScore × 10` (ưu tiên v4 > v3.1 > v3.0 > v2.0).