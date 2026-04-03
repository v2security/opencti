# connector-monitor — OpenCTI Connector Monitor

Tools giám sát các OpenCTI connector, tự động gửi báo cáo hàng ngày qua Telegram.


1 tiếng check 1 lần lấy thời gian hiện trừ đi 1 tiếng
## Luồng xử lý

```
Elasticsearch ──GET opencti_internal_objects-*──→ Danh sách connector + heartbeat (refreshed_at)
    → Đánh giá trạng thái: inactive nếu updated_at > 5 phút trước
    → (Parallel goroutine/connector) GET opencti_history-* → work stats 24h (runs / items / errors)
    → (Parallel × 5) GET stix_domain_objects / stix_cyber_observables / stix_core_relationships
        → tổng và số mới 24h của Vulnerability, Indicator, Organization, Software, Relationship
    → Format báo cáo MarkdownV2
    → Telegram Bot API ──sendMessage──→ Group/Channel nhận báo cáo
```

**Scheduler:** Cron expression, mặc định `0 8 * * *` (08:00 ICT mỗi ngày).
**Graceful shutdown:** Bắt `SIGINT` / `SIGTERM`, dừng scheduler sạch trước khi thoát.

## 2 chế độ hoạt động

| Chế độ | Flag | Mô tả |
|--------|------|-------|
| **Scheduled** | *(mặc định)* | Chạy theo cron, gửi báo cáo đúng giờ mỗi ngày |
| **One-shot** | `--run-now` | Chạy một lần, gửi báo cáo ngay rồi thoát |

## Logic giám sát

### Phát hiện connector lỗi

| Trạng thái | Điều kiện | Nguồn dữ liệu |
|------------|-----------|---------------|
| **inactive** | `updated_at` > **5 phút** trước | `opencti_internal_objects-*` → trường `updated_at` |
| **stalled** | Có job trong 24h nhưng `completed_number` = 0 | `opencti_history-*` → aggregation `sum(completed_number)` |

Connector lỗi → đánh dấu `🔴` + liệt kê lý do cụ thể (`AlertReasons`) trong báo cáo.

### STIX entity theo dõi

| Entity | Index | Ghi chú |
|--------|-------|---------|
| Vulnerability | `opencti_stix_domain_objects-*` | CVE từ NVD connector |
| Indicator | `opencti_stix_domain_objects-*` | IOC từ botnet connector |
| Organization | `opencti_stix_domain_objects-*` | Vendor từ CPE |
| Software (CPE) | `opencti_stix_cyber_observables-*` | CPE configs từ NVD |
| Relationship | `opencti_stix_core_relationships-*` | `has`, `related-to`... |

Với mỗi loại: hiển thị **tổng số** và **số mới tạo trong 24h** (filter `created_at >= now-24h`).

## Cấu trúc

```
connector-monitor/
├── main.go                      ← Entry point: parse --run-now, validate config, khởi tạo scheduler, graceful shutdown
├── config.yml                   ← Cấu hình (override bằng env vars)
├── go.mod / go.sum
└── src/
    ├── config/
    │   └── config.go            ← Load config: đọc YAML rồi override bằng env vars
    ├── domain/
    │   ├── types.go             ← ConnectorStatus, WorkStats, ConnectorReport, STIXCount
    │   └── rules.go             ← IsInactive (5min), IsStalled, ShouldAlert, AlertReasons
    ├── gateway/
    │   ├── es.go                ← ESClient: GetConnectors, GetWorks24h, GetStixCounts (parallel × 5)
    │   └── telegram.go          ← TelegramSender: Send MarkdownV2, timeout 10s
    └── service/
        └── report.go            ← Reporter: fetch → format → gửi; escape MarkdownV2 special chars
```


## Elasticsearch indexes sử dụng

Tất cả index dùng pattern `<prefix>_<name>-*` để hỗ trợ ILM rollover:

| Index pattern | Mục đích | Trường dùng |
|---------------|----------|-------------|
| `opencti_internal_objects-*` | Connector status + heartbeat | `entity_type=connector`, `refreshed_at`, `connector_info.{last,next}_run_datetime` |
| `opencti_history-*` | Work job stats 24h | `entity_type=work`, `connector_id`, `completed_number`, `received_time` |
| `opencti_stix_domain_objects-*` | Vulnerability, Indicator, Organization | `entity_type`, `created_at` |
| `opencti_stix_cyber_observables-*` | Software (CPE) | `entity_type=software`, `created_at` |
| `opencti_stix_core_relationships-*` | Relationships | `created_at` |


 Logic:                                  
  - Nếu connector là built-in: dùng giá   
  trị active lưu trong DB (mặc định true) 
  - Nếu connector là non built-in (như "Botnet IOC (V2Secure)"): active = true nếu updated_at < 5 phút trước, ngược lại là false                               
                                          
  Connector trong JSON có active: true nghĩa là thời điểm query,updated_at (2026-03-31T06:38:27.020Z) vẫn còn trong vòng 5 phút. Nếu connector không heartbeat/update trong 5 phút thì active sẽ tự động là false. 

Elasticsearch lưu updated_at trong index opencti_internal_objects, còn active chỉ là derivedfield được tính on-the-fly khi API trả về response như dưới đây:
```
curl -X GET "http://163.223.58.7:8686/opencti_internal_objects/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "term": {
        "entity_type.keyword": "Connector"
      }
    },
    "_source": ["name", "updated_at", "built_in"]
  }' | jq

{
  "took": 4,
  "timed_out": false,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  },
  "hits": {
    "total": {
      "value": 3,
      "relation": "eq"
    },
    "max_score": 5.983355,
    "hits": [
      {
        "_index": "opencti_internal_objects-000001",
        "_id": "91ebe800-f2c9-46f3-9c41-02790b0579f1",
        "_score": 5.983355,
        "_source": {
          "name": "OpenCTI LLM/RAG Connector",
          "built_in": false,
          "updated_at": "2026-03-31T06:52:19.227Z"
        }
      },
      {
        "_index": "opencti_internal_objects-000001",
        "_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "_score": 5.983355,
        "_source": {
          "name": "Botnet IOC (V2Secure)",
          "built_in": false,
          "updated_at": "2026-03-31T06:52:30.280Z"
        }
      },
      {
        "_index": "opencti_internal_objects-000001",
        "_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "_score": 5.983355,
        "_source": {
          "name": "NVD CVE (V2Secure)",
          "built_in": false,
          "updated_at": "2026-03-31T06:52:30.303Z"
        }
      }
    ]
  }
}
```

```
export const completeConnector = (connector) => {
  if (connector) {
    const completed = { ...connector };
    completed.title = connector.title ? connector.title : connector.name;
    completed.is_managed = isNotEmptyField(connector.catalog_id);
    completed.connector_scope = connector.connector_scope ? connector.connector_scope.split(',') : [];
    completed.config = connectorConfig(connector.id, connector.listen_callback_uri);
    completed.active = connector.built_in ? (connector.active ?? true) : (sinceNowInMinutes(connector.updated_at) < 5);
    return completed;
  }
  return null;
};
```

 1. Lấy danh sách Connector              
                                          
  Index: opencti_internal_objects-*
```                                      
  curl -X POST "http://localhost:8686/open
  cti_internal_objects-*/_search" \       
    -H "Content-Type: application/json" \
    -d '{                                 
      "size": 1000,                       
      "query": {                          
        "term": { "entity_type.keyword":  
  "connector" }                           
      },                                  
      "_source": ["internal_id", "name",  
  "refreshed_at", "connector_info"]       
    }' 
```                                   
                                          
  ---                                     
  2. Lấy Work Stats 24h của một Connector
                                          
  Index: opencti_history-*

```                                 
  curl -X POST "http://localhost:8686/open
  cti_history-*/_search" \                
    -H "Content-Type: application/json" \
    -d '{                                 
      "size": 0,                          
      "query": {                          
        "bool": {                         
          "must": [                       
            { "term": {                   
  "entity_type.keyword": "work" } },      
            { "term": { 
  "connector_id.keyword":                 
  "b2c3d4e5-f6a7-8901-bcde-f12345678901" }
   },                                     
            { "range": { "received_time": 
  { "gte": "now-24h" } } }                
          ]
        }                                 
      },                                  
      "aggs": {
        "total_items":  { "sum":    {     
  "field": "completed_number" } },        
        "total_errors": { "filter": {     
  "term": { "status.keyword": "error" } } 
  }               
      }                                   
    }'            
```                                         
  Kết quả trả về:                         
  - hits.total.value → số lần chạy        
  (works_count)                           
  - aggregations.total_items.value → tổng
  items đã import                         
  - aggregations.total_errors.doc_count → 
  số lần lỗi
                                          
  ---             
  3. Đếm STIX Entities                    
                                          
  Vulnerability — tổng:

```
  curl -X POST "http://localhost:8686/open
  cti_stix_domain_objects-*/_search" \    
    -H "Content-Type: application/json" \ 
    -d '{                                
      "size": 0,                          
      "query": { "term": { 
  "entity_type.keyword": "vulnerability" }
   }                                      
    }'                                    
```                                        
  Vulnerability — mới 24h:

```
  curl -X POST "http://localhost:8686/open
  cti_stix_domain_objects-*/_search" \    
    -H "Content-Type: application/json" \ 
    -d '{                                 
      "size": 0,                          
      "query": {  
        "bool": {                         
          "must": [                       
            { "term": {                   
  "entity_type.keyword": "vulnerability" }
   },                                     
            { "range": { "created_at": { 
  "gte": "now-24h" } } }                  
          ]                               
        }  
      }                                   
    }'            
 ```                                         
  Indicator, Organization — thay
  "vulnerability" bằng "indicator" /      
  "organization" (cùng index
  stix_domain_objects)                    
                  
  Software (CPE):

```                      
  curl -X POST "http://localhost:8686/open
  cti_stix_cyber_observables-*/_search" \ 
    -H "Content-Type: application/json" \ 
    -d '{                                
      "size": 0,                          
      "query": { "term": {                
  "entity_type.keyword": "software" } }   
    }'                                    
```                                      
  Relationship — tổng:  

```                  
  curl -X POST "http://localhost:8686/open
  cti_stix_core_relationships-*/_search" \
    -H "Content-Type: application/json" \ 
    -d '{ "size": 0, "query": {           
  "match_all": {} } }'     
```               
                                          
  Relationship — mới 24h:   

```            
  curl -X POST "http://localhost:8686/open
  cti_stix_core_relationships-*/_search" \
    -H "Content-Type: application/json" \ 
    -d '{                                
      "size": 0,                          
      "query": { "range": { "created_at": 
  { "gte": "now-24h" } } }                
    }'              
```                      
                                        
  ---                                     
  Bảng tóm tắt                            
                                          
  Số liệu: Danh sách connector            
  Index: opencti_internal_objects-*       
  Filter chính: entity_type = connector
  ────────────────────────────────────────
  Số liệu: Work runs 24h              
  Index: opencti_history-*                
  Filter chính: entity_type = work +  
    connector_id + received_time ≥ now-24h
  ────────────────────────────────────────
  Số liệu: Items imported                 
  Index: opencti_history-*                
  Filter chính: agg sum(completed_number) 
  ────────────────────────────────────────
  Số liệu: Errors                         
  Index: opencti_history-*
  Filter chính: agg filter(status = error)
  ────────────────────────────────────────
  Số liệu: Vulnerability                  
  Index: opencti_stix_domain_objects-*
  Filter chính: entity_type =             
  vulnerability   
  ────────────────────────────────────────
  Số liệu: Indicator                      
  Index: opencti_stix_domain_objects-*
  Filter chính: entity_type = indicator   
  ────────────────────────────────────────
  Số liệu: Organization                   
  Index: opencti_stix_domain_objects-*
  Filter chính: entity_type = organization
  ────────────────────────────────────────
  Số liệu: Software/CPE                   
  Index: opencti_stix_cyber_observables-*
  Filter chính: entity_type = software    
  ────────────────────────────────────────
  Số liệu: Relationship                   
  Index: opencti_stix_core_relationships-*
  Filter chính: match_all 


```
// opencti-platform/opencti-graphql/src/domain/connector.ts
export const pingConnector = async (context: AuthContext, user: AuthUser, id: string, state: string, connectorInfo: ConnectorInfo) => {
  const connectorEntity = await storeLoadById(context, user, id, ENTITY_TYPE_CONNECTOR) as unknown as BasicStoreEntityConnector;
  if (!connectorEntity) {
    throw FunctionalError('No connector found with the specified ID', { id });
  }
  // Ensure queue are correctly setup
  const scopes = connectorEntity.connector_scope ? connectorEntity.connector_scope.split(',') : [];
  await registerConnectorQueues(connectorEntity.id, connectorEntity.name, connectorEntity.connector_type, scopes);

  await updateConnectorWithConnectorInfo(context, user, connectorEntity, state, connectorInfo);
  return storeLoadById(context, user, id, 'Connector').then((data) => completeConnector(data));
};
```