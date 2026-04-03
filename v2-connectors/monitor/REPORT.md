# OpenCTI Connector — Phân tích luồng hoạt động từ Backend Code

## 1. Danh sách Connector — Lấy từ đâu, lấy như thế nào

### Source code

- **Resolver**: `opencti-platform/opencti-graphql/src/resolvers/connector.js` — `Query.connectors`
- **Repository**: `opencti-platform/opencti-graphql/src/database/repository.js` — hàm `connectors()`

### Luồng lấy danh sách

```
GraphQL Query connectors
  → connectors(context, user)                          // repository.js
    → topEntitiesList(context, user, [ENTITY_TYPE_CONNECTOR])  // Lấy từ Elasticsearch
    → builtInConnectorsRuntime(context, user)                  // Connector built-in (CSV import, Draft validation...)
    → merge 2 danh sách
    → map completeConnector() cho từng connector               // Bổ sung thêm trường active, config, scope...
```

### Hàm `completeConnector()` — Bổ sung thông tin runtime

File: `opencti-platform/opencti-graphql/src/database/repository.js`, dòng 22–33

```javascript
export const completeConnector = (connector) => {
  if (connector) {
    const completed = { ...connector };
    completed.title = connector.title ? connector.title : connector.name;
    completed.is_managed = isNotEmptyField(connector.catalog_id);
    completed.connector_scope = connector.connector_scope ? connector.connector_scope.split(',') : [];
    completed.config = connectorConfig(connector.id, connector.listen_callback_uri);
    completed.active = connector.built_in
      ? (connector.active ?? true)
      : (sinceNowInMinutes(connector.updated_at) < 5);   // ← ACTIVE nếu updated_at < 5 phút
    return completed;
  }
  return null;
};
```

**Kết luận**: Connector được lưu trong Elasticsearch index `opencti_internal_objects-*` với `entity_type = "Connector"`. Platform lấy tất cả connector từ Elasticsearch + merge với connector built-in, rồi tính toán trường `active` on-the-fly.

---

## 2. Kiểm tra Connector Active hay Inactive — Cơ chế Heartbeat

### Cơ chế hoạt động: Connector tự ping lên platform mỗi 40 giây

Connector (viết bằng Python) chạy một **daemon thread tên `PingAlive`** gọi GraphQL mutation `pingConnector` mỗi **40 giây**.

#### a) Phía Connector (Python Client) — Thread PingAlive

File: `client-python/pycti/connector/opencti_connector_helper.py`, dòng 901–1007

```python
class PingAlive(threading.Thread):
    """Daemon thread that maintains connector heartbeat with OpenCTI platform."""

    def ping(self) -> None:
        while not self.exit_event.is_set():
            try:
                initial_state = self.get_state()
                connector_info = self.connector_info.all_details
                result = self.api.connector.ping(
                    self.connector_id, initial_state, connector_info
                )
                # Nếu state trên platform khác local → sync lại (hỗ trợ reset state từ UI)
                remote_state = json.loads(result["connector_state"]) if result["connector_state"] else None
                if initial_state != remote_state:
                    self.set_state(result["connector_state"])
            except Exception as e:
                self.connector_logger.error("Error pinging the API", {"reason": str(e)})

            self.exit_event.wait(40)  # ← CHỜ 40 GIÂY GIỮA MỖI LẦN PING
```

**Tần suất**: Mỗi **40 giây** connector gửi 1 ping lên platform.

#### b) GraphQL Mutation được gọi

File: `client-python/pycti/api/opencti_api_connector.py`, dòng 120–128

```graphql
mutation PingConnector($id: ID!, $state: String, $connectorInfo: ConnectorInfoInput) {
    pingConnector(id: $id, state: $state, connectorInfo: $connectorInfo) {
        id
        connector_state
        connector_info {
            run_and_terminate
            buffering
            queue_threshold
            queue_messages_size
            next_run_datetime
            last_run_datetime
        }
    }
}
```

Dữ liệu gửi kèm mỗi lần ping (`ConnectorInfo`):

| Trường | Kiểu | Ý nghĩa |
|--------|------|---------|
| `run_and_terminate` | bool | Connector chạy xong thì tắt hay chạy liên tục |
| `buffering` | bool | Có đang buffer dữ liệu không |
| `queue_threshold` | float | Ngưỡng queue (MB), mặc định 500MB |
| `queue_messages_size` | float | Kích thước hiện tại của queue (MB) |
| `next_run_datetime` | datetime | Lần chạy tiếp theo |
| `last_run_datetime` | datetime | Lần chạy gần nhất |

#### c) Phía Backend — Nhận ping và cập nhật `updated_at`

File: `opencti-platform/opencti-graphql/src/domain/connector.ts`, dòng 144–156

```typescript
export const pingConnector = async (context, user, id, state, connectorInfo) => {
  const connectorEntity = await storeLoadById(context, user, id, ENTITY_TYPE_CONNECTOR);
  if (!connectorEntity) {
    throw FunctionalError('No connector found with the specified ID', { id });
  }
  // Đảm bảo RabbitMQ queue đúng
  const scopes = connectorEntity.connector_scope ? connectorEntity.connector_scope.split(',') : [];
  await registerConnectorQueues(connectorEntity.id, connectorEntity.name, connectorEntity.connector_type, scopes);

  // CẬP NHẬT updated_at = now() + connector_state + connector_info
  await updateConnectorWithConnectorInfo(context, user, connectorEntity, state, connectorInfo);
  return storeLoadById(context, user, id, 'Connector').then((data) => completeConnector(data));
};
```

File: `opencti-platform/opencti-graphql/src/domain/connector.ts`, dòng 115–142

```typescript
export const updateConnectorWithConnectorInfo = async (context, user, connectorEntity, state, connectorInfo) => {
  let connectorPatch;

  if (connectorEntity.connector_state_reset) {
    connectorPatch = { connector_state_reset: false };        // Nếu đang reset state → chỉ clear flag
  } else {
    connectorPatch = { updated_at: now(), connector_state: state };  // ← CẬP NHẬT updated_at = now()
  }

  if (connectorInfo) {
    connectorPatch = { ...connectorPatch, connector_info: { ...connectorInfo } };
  }

  await patchAttribute(context, user, connectorEntity.id, ENTITY_TYPE_CONNECTOR, connectorPatch);
};
```

### Tóm tắt cơ chế heartbeat

```
Connector (Python)                          OpenCTI Platform (Node.js)
     │                                              │
     │──── pingConnector (mỗi 40s) ───────────────→│
     │     {id, state, connectorInfo}               │
     │                                              │── updateConnectorWithConnectorInfo()
     │                                              │   → updated_at = now()     ← GHI VÀO ES
     │                                              │   → connector_state = state
     │                                              │   → connector_info = {...}
     │                                              │
     │←── response {connector_state} ──────────────│
     │                                              │
     │  (nếu state khác → sync lại local)           │
     │                                              │
     │  ... chờ 40 giây ...                         │
     │                                              │
     │──── pingConnector (lần tiếp) ──────────────→│
```

---

## 3. Query trạng thái Connector — Tính Active/Inactive

### Logic tính active

File: `opencti-platform/opencti-graphql/src/database/repository.js`, dòng 29

```javascript
completed.active = connector.built_in
  ? (connector.active ?? true)                        // Built-in: luôn active (trừ khi set khác)
  : (sinceNowInMinutes(connector.updated_at) < 5);   // Non built-in: active nếu updated_at < 5 phút
```

### Hàm `sinceNowInMinutes()`

File: `opencti-platform/opencti-graphql/src/utils/format.js`, dòng 99–103

```javascript
export const sinceNowInMinutes = (lastModified) => {
  const diff = utcDate().diff(utcDate(lastModified));
  const duration = moment.duration(diff);
  return Math.floor(duration.asMinutes());
};
```

### Khi nào trạng thái được tính?

**Không có scheduled job tính trạng thái connector.** Trạng thái `active` được tính **on-the-fly** (on-demand) mỗi khi có request lấy thông tin connector:

| Trigger | Mô tả |
|---------|--------|
| GraphQL query `connectors` | UI dashboard gọi, list tất cả connector |
| GraphQL query `connector(id)` | Xem chi tiết 1 connector |
| Sau khi `pingConnector` | Platform trả về connector đã update |
| `connectorManager` chạy mỗi 60s | Lấy danh sách connector để dọn dẹp work cũ |

**Tần suất thực tế**: Phụ thuộc vào frontend polling hoặc subscription. Không có cron riêng để check active/inactive.

### Bảng tổng hợp ngưỡng thời gian

| Loại connector | Điều kiện Active | Điều kiện Inactive |
|----------------|------------------|--------------------|
| **Built-in** (CSV import, Draft validation...) | Luôn `true` (mặc định) | Chỉ khi bị set `active = false` thủ công |
| **Non built-in** (NVD, Botnet, LLM/RAG...) | `updated_at` < **5 phút** trước | `updated_at` ≥ **5 phút** trước |

### Mối quan hệ 40s ping vs 5 phút threshold

```
Ping 1   Ping 2   Ping 3   Ping 4   Ping 5   Ping 6   Ping 7   ...
  0s       40s      80s     120s     160s     200s     240s
  │        │        │        │        │        │        │
  ▼        ▼        ▼        ▼        ▼        ▼        ▼
  ✅       ✅       ✅       ✅       ✅       ✅       ✅  ← Connector liên tục active!

Nếu connector chết tại thời điểm 100s:
  0s       40s      80s     (chết)                      300s
  │        │        │                                    │
  ▼        ▼        ▼                                    ▼
  ✅       ✅       ✅  ← updated_at = 80s              Lúc này: now - 80s = 220s = 3.7 phút → VẪN ACTIVE
                                                         
                                                         380s → now - 80s = 300s = 5 phút → INACTIVE ❌
```

**Kết luận**: Sau khi connector chết, phải chờ tối đa **~5 phút 40 giây** (5 phút threshold + 40 giây interval ping cuối) mới phát hiện inactive.

---

## 4. Work (Job) — Theo dõi xử lý IOC của Connector

### Work là gì?

Mỗi lần connector thực hiện 1 tác vụ (import file, enrichment, export...), platform tạo 1 **Work** entity trong Elasticsearch index `opencti_history-*`.

### Vòng đời của 1 Work

```
                  createWork()
                      │
                      ▼
              ┌──────────────┐
              │ status: wait │   import_expected_number = 0
              │ completed: 0 │   completed_number = 0
              └──────┬───────┘
                     │
          updateReceivedTime()  ─→  status: progress
                     │
         ┌───────────┴────────────┐
         │                        │
  updateExpectationsNumber()   pingWork() (mỗi 5 phút)
  (tăng import_expected_number)  (cập nhật updated_at)
         │                        │
         └───────────┬────────────┘
                     │
           reportExpectation()
           (mỗi khi xử lý xong 1 item)
                     │
                     ▼
            ┌─────────────────┐
            │ status: complete│   completed_number = total items đã xử lý
            │ completed_time  │   errors = danh sách lỗi (tối đa 100)
            └─────────────────┘
```

### a) Tạo Work — `createWork()`

File: `opencti-platform/opencti-graphql/src/domain/work.js`, dòng 206–241

```javascript
export const createWork = async (context, user, connector, friendlyName, sourceId, args = {}) => {
  const { id: workId, timestamp } = generateWorkId(connector.internal_id);
  const work = {
    internal_id: workId,
    timestamp,
    updated_at: now(),
    name: friendlyName,
    entity_type: 'Work',
    event_type: connector.connector_type,      // Loại tác vụ: INTERNAL_IMPORT_FILE, INTERNAL_ENRICHMENT...
    event_source_id: sourceId,                 // File/entity trigger tác vụ
    connector_id: connector.internal_id,
    status: receivedTime ? 'progress' : 'wait',
    import_expected_number: 0,                 // Ban đầu = 0, tăng dần
    completed_number: 0,                       // Ban đầu = 0, set khi complete
    messages: [],
    errors: [],
  };
  await elIndex(INDEX_HISTORY, work);             // Ghi vào Elasticsearch
  await redisInitializeWork(createdWork.id);      // Track trên Redis
  return createdWork;
};
```

### b) Tăng số lượng expected — `updateExpectationsNumber()`

File: `opencti-platform/opencti-graphql/src/domain/work.js`, dòng 309–330

Khi worker parse được bundle STIX và biết sẽ phải xử lý bao nhiêu entity, nó gọi hàm này để **cộng dồn** `import_expected_number`.

```javascript
export const updateExpectationsNumber = async (context, user, workId, expectations) => {
  const params = { updated_at: now(), import_expected_number: expectations };
  // Painless script: cộng dồn vào import_expected_number hiện tại
  let source = 'ctx._source.updated_at = params.updated_at;';
  source += 'ctx._source["import_expected_number"] = ctx._source["import_expected_number"] + params.import_expected_number;';
  await elUpdate(currentWork._index, workId, { script: { source, lang: 'painless', params } });
  await redisUpdateActionExpectation(user, workId, expectations);  // Cập nhật Redis counter
};
```

### c) Báo cáo hoàn thành từng item — `reportExpectation()`

File: `opencti-platform/opencti-graphql/src/domain/work.js`, dòng 267–305

Mỗi khi worker xử lý xong 1 entity (hoặc gặp lỗi), nó gọi `reportExpectation()`:

```javascript
export const reportExpectation = async (context, user, workId, errorData) => {
  const { isComplete, total } = await redisUpdateWorkFigures(workId);
  // isComplete = true khi tất cả expected items đã được xử lý

  if (isComplete || errorData) {
    if (isComplete) {
      // Đánh dấu work hoàn thành
      params.completed_number = total;
      sourceScript += `ctx._source['status'] = "complete";
        ctx._source['completed_number'] = params.completed_number;
        ctx._source['completed_time'] = params.now;`;
    }
    if (errorData) {
      // Ghi lỗi (tối đa 100 lỗi)
      sourceScript += 'if (ctx._source.errors.length < 100) { ctx._source.errors.add(...); }';
    }
    await elUpdate(currentWork._index, workId, { script: { source: sourceScript, ... } });
  }
};
```

### d) Ping Work — Giữ work alive trong quá trình xử lý

File: `opencti-platform/opencti-graphql/src/domain/work.js`, dòng 143–148

```javascript
export const pingWork = async (context, user, workId) => {
  const currentWork = await loadWorkById(context, user, workId);
  const params = { updated_at: now() };
  const source = 'ctx._source["updated_at"] = params.updated_at;';
  await elUpdate(currentWork._index, workId, { script: { source, lang: 'painless', params } });
};
```

Được gọi từ Python connector helper mỗi **5 phút** trong khi đang xử lý message:

File: `client-python/pycti/connector/opencti_connector_helper.py`, dòng ~593–604

```python
# Trong khi thread xử lý message còn sống, ping work mỗi 5 phút
if self.helper.work_id is not None and time_wait > five_minutes:
    self.helper.api.work.ping(self.helper.work_id)
```

### e) Tính số liệu realtime — `computeWorkStatus()`

File: `opencti-platform/opencti-graphql/src/domain/connector.ts`, dòng 101–108

```typescript
export const computeWorkStatus = async (work) => {
  if (work.status === 'complete') {
    // Work đã xong → lấy từ Elasticsearch
    return { import_processed_number: work.completed_number, import_expected_number: work.import_expected_number };
  }
  // Work đang chạy → lấy từ Redis (realtime)
  const redisData = await redisGetWork(work.id);
  return redisData ?? { import_processed_number: null, import_expected_number: null };
};
```

### f) Connector Manager — Dọn dẹp work cũ

File: `opencti-platform/opencti-graphql/src/manager/connectorManager.js`

Chạy mỗi **60 giây** (cấu hình `connector_manager:interval`, mặc định 60000ms):

| Tác vụ | Logic |
|--------|-------|
| `closeOldWorks()` | Tìm work có status `wait`/`progress` tạo trước work hiện tại → nếu > 7 ngày: xóa; nếu < 7 ngày: đánh complete với `completed_number` từ Redis |
| `deleteCompletedWorks()` | Xóa work đã complete quá **7 ngày** (cấu hình `connector_manager:works_day_range`) |

---

## 5. Bảng tóm tắt tần suất các event

| Event | Tần suất | Ai trigger | File source |
|-------|----------|------------|-------------|
| **Connector ping (heartbeat)** | Mỗi **40 giây** | Connector (Python PingAlive thread) | `client-python/pycti/connector/opencti_connector_helper.py:1007` |
| **Cập nhật `updated_at` connector** | Mỗi **40 giây** (khi nhận ping) | Platform backend (pingConnector) | `opencti-platform/opencti-graphql/src/domain/connector.ts:132` |
| **Tính `active`/`inactive`** | **On-demand** (khi query) | Platform backend (completeConnector) | `opencti-platform/opencti-graphql/src/database/repository.js:29` |
| **Ngưỡng inactive** | **5 phút** không ping | — | `repository.js:29` — `sinceNowInMinutes(updated_at) < 5` |
| **Work ping (giữ alive)** | Mỗi **5 phút** (trong khi xử lý) | Connector (Python) | `client-python/pycti/connector/opencti_connector_helper.py:~600` |
| **Work timeout** | **20 phút** không activity | Platform (workToExportFile) | `opencti-platform/opencti-graphql/src/domain/work.js:21` |
| **Connector Manager cleanup** | Mỗi **60 giây** | Platform (connectorManager) | `opencti-platform/opencti-graphql/src/manager/connectorManager.js:14` |
| **Xóa work cũ** | Work complete > **7 ngày** | Connector Manager | `connectorManager.js:17` |

---

## 6. Luồng tổng thể: Từ Connector đăng ký → Xử lý IOC → Report

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                          1. ĐĂNG KÝ CONNECTOR                          │
 │                                                                         │
 │  Connector start                                                        │
 │    → registerConnector(id, name, type, scope)   [connector.ts:297]      │
 │       → registerConnectorQueues()  → tạo RabbitMQ queue listen + push   │
 │       → lưu connector vào Elasticsearch                                 │
 │    → PingAlive thread bắt đầu chạy (daemon)                            │
 └─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                       2. HEARTBEAT LIÊN TỤC                            │
 │                                                                         │
 │  Mỗi 40 giây:                                                          │
 │    Connector → pingConnector mutation → Platform                        │
 │      → updated_at = now()                                               │
 │      → connector_state = current state (JSON)                           │
 │      → connector_info = {run_and_terminate, buffering, queue_*, ...}    │
 │                                                                         │
 │  Platform tính active:                                                  │
 │    active = (now - updated_at) < 5 phút ? true : false                 │
 └─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                     3. CONNECTOR XỬ LÝ DỮ LIỆU                        │
 │                                                                         │
 │  Platform gửi message qua RabbitMQ (listen queue)                       │
 │    → Connector nhận message                                             │
 │    → createWork() → Work entity trong ES (status: wait)                 │
 │    → updateReceivedTime() → status: progress                            │
 │                                                                         │
 │  Worker parse STIX bundle:                                              │
 │    → updateExpectationsNumber(workId, N)                                │
 │      → import_expected_number += N                                      │
 │                                                                         │
 │  Worker xử lý từng entity:                                             │
 │    → reportExpectation(workId, errorData?)                              │
 │      → Redis: import_processed_number++                                 │
 │      → Khi processed == expected → Work complete!                       │
 │        → completed_number = total                                       │
 │        → status = "complete"                                            │
 │                                                                         │
 │  Trong khi xử lý: pingWork() mỗi 5 phút để giữ work alive             │
 └─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                    4. TRUY VẤN KẾT QUẢ XỬ LÝ                          │
 │                                                                         │
 │  GraphQL query worksForConnector(connectorId):                          │
 │    → Lấy danh sách Work từ ES (opencti_history-*)                       │
 │    → Mỗi Work có:                                                       │
 │      • status: wait / progress / complete                               │
 │      • import_expected_number: Tổng entity cần xử lý                   │
 │      • completed_number: Tổng entity đã xử lý (IOC đã import)          │
 │      • errors[]: Danh sách lỗi (tối đa 100)                            │
 │      • timestamp: Thời điểm tạo work                                   │
 │      • completed_time: Thời điểm hoàn thành                            │
 │                                                                         │
 │  computeWorkStatus(work):                                               │
 │    → Nếu complete: trả về từ ES                                        │
 │    → Nếu đang chạy: trả về realtime từ Redis                           │
 └─────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Elasticsearch Index & Trường dữ liệu

### Connector entity

| Index | Trường | Mô tả |
|-------|--------|-------|
| `opencti_internal_objects-*` | `entity_type` | `"Connector"` |
| | `name` | Tên connector |
| | `updated_at` | Timestamp lần ping cuối (ISO 8601) |
| | `built_in` | `true`/`false` — connector nội bộ hay bên ngoài |
| | `connector_state` | JSON state hiện tại của connector |
| | `connector_type` | `INTERNAL_IMPORT_FILE`, `INTERNAL_ENRICHMENT`, `EXTERNAL_IMPORT`... |
| | `connector_scope` | Scope xử lý, ví dụ `"application/pdf,text/plain"` |
| | `connector_info` | Object chứa `run_and_terminate`, `buffering`, `queue_threshold`, `queue_messages_size`, `next_run_datetime`, `last_run_datetime` |

### Work entity

| Index | Trường | Mô tả |
|-------|--------|-------|
| `opencti_history-*` | `entity_type` | `"Work"` |
| | `connector_id` | ID connector thực hiện |
| | `status` | `wait` → `progress` → `complete` |
| | `import_expected_number` | Tổng số entity cần xử lý |
| | `completed_number` | Tổng số entity đã xử lý xong (IOC đã import) |
| | `errors` | Array lỗi, mỗi lỗi có `{timestamp, message, source}` (tối đa 100) |
| | `timestamp` | Thời điểm tạo work |
| | `received_time` | Thời điểm nhận data |
| | `completed_time` | Thời điểm hoàn thành |
| | `updated_at` | Cập nhật khi pingWork (mỗi 5 phút) |
| | `event_type` | Loại tác vụ connector |
| | `event_source_id` | ID file/entity trigger |
