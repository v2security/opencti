## Question 1
> Nghiên cứu xem TI có API ko nhé, bài toán là đưa 1 IOC vào API để hỏi TI, nếu có dữ liệu thì nó trả về thông tin của IOC đó, Ý là tích hợp được với bên ngoài (Một module do tôi tự dev thêm chẳng hạn)

**Trả lời: CÓ.** OpenCTI cung cấp đầy đủ API để query IOC từ bên ngoài.

### Các cách tích hợp

| Cách | Endpoint | Mô tả |
|------|----------|-------|
| **GraphQL API** | `POST /graphql` | API chính — query IOC bằng filter, search, pagination |
| **Python SDK (pycti)** | Thư viện Python | Wrapper cao cấp, dễ dùng nhất cho module tự dev |
| **TAXII 2.1** | `GET /taxii2/...` | Chuẩn quốc tế chia sẻ CTI |

### Ví dụ nhanh: Query IOC bằng Python

```python
from pycti import OpenCTIApiClient

client = OpenCTIApiClient("http://opencti:4000", "YOUR_API_TOKEN")

# Tìm IOC theo IP (full-text search)
results = client.stix_cyber_observable.list(search="1.2.3.4")

# Tìm chính xác theo IP
result = client.stix_cyber_observable.read(
    filters={"mode": "and", "filters": [{"key": "value", "values": ["1.2.3.4"]}], "filterGroups": []}
)

# Tìm chính xác theo MD5 hash
result = client.stix_cyber_observable.read(
    filters={"mode": "and", "filters": [{"key": "hashes.MD5", "values": ["abc123..."]}], "filterGroups": []}
)

# Tìm indicator
indicators = client.indicator.list(search="1.2.3.4")
```

### Ví dụ nhanh: Query IOC bằng GraphQL (curl / bất kỳ ngôn ngữ nào)

```graphql
# POST /graphql với header: Authorization: Bearer YOUR_TOKEN
query {
  stixCyberObservables(search: "1.2.3.4", first: 10) {
    edges {
      node { id, entity_type, observable_value, x_opencti_score }
    }
  }
}
```

### Dẫn chứng code

- **GraphQL schema cho Indicator**: [indicator.graphql](opencti-platform/opencti-graphql/src/modules/indicator/indicator.graphql) — query `indicators(search, filters)` tại [L265](opencti-platform/opencti-graphql/src/modules/indicator/indicator.graphql#L265)
- **GraphQL schema cho Observable**: [opencti.graphql#L14811](opencti-platform/opencti-graphql/config/schema/opencti.graphql#L14811) — query `stixCyberObservables(search, filters)`
- **Python SDK — Indicator**: [opencti_indicator.py](client-python/pycti/entities/opencti_indicator.py) — method `list()` tại [L58](client-python/pycti/entities/opencti_indicator.py#L58), `read()` tại [L171](client-python/pycti/entities/opencti_indicator.py#L171)
- **Python SDK — Observable**: [opencti_stix_cyber_observable.py](client-python/pycti/entities/opencti_stix_cyber_observable.py) — method `list()` tại [L39](client-python/pycti/entities/opencti_stix_cyber_observable.py#L39), `read()` tại [L153](client-python/pycti/entities/opencti_stix_cyber_observable.py#L153)
- **Ví dụ tìm IP chính xác**: [get_observable_exact_match.py](client-python/examples/get_observable_exact_match.py) — [L19-L55](client-python/examples/get_observable_exact_match.py#L19-L55)
- **Ví dụ search IOC**: [get_observables_search.py](client-python/examples/get_observables_search.py) — [L14-L19](client-python/examples/get_observables_search.py#L14-L19)
- **TAXII 2.1 REST API**: [httpTaxii.js](opencti-platform/opencti-graphql/src/http/httpTaxii.js) — endpoint `/taxii2/root/collections/:id/objects/` tại [L159](opencti-platform/opencti-graphql/src/http/httpTaxii.js#L159)

**Kết luận:** Hoàn toàn tích hợp được. Cách nhanh nhất là dùng Python SDK (`pycti`), hoặc gọi GraphQL trực tiếp bằng HTTP POST từ bất kỳ ngôn ngữ nào.