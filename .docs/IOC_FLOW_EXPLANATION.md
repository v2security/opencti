# 🎯 OpenCTI IOC (Indicator) Flow - Chi Tiết Toàn Trình

> **Phân tích chi tiết từ source code**  
> Các flow quan trọng từ tạo indicator → lưu Elasticsearch → query → decay

---

## 📊 **1. OVERALL ARCHITECTURE**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         OpenCTI Platform (Node.js)                      │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  GraphQL API Layer                                                │  │
│  │  ├─ Query: indicator(id), indicators(args)                        │  │
│  │  ├─ Mutation: indicatorAdd, indicatorFieldPatch, indicatorDelete  │  │
│  │  └─ Subscription: Real-time sighting updates                      │  │
│  └────────────────┬──────────────────────────────────────────────────┘  │
│                   │                                                     │
│  ┌────────────────▼────────────────────────────────────────────────┐  │
│  │  Domain Logic Layer (indicator-domain.ts)                        │  │
│  │  ├─ addIndicator()          ─→ Create new IOC                     │  │
│  │  ├─ indicatorEditField()    ─→ Update IOC properties              │  │
│  │  ├─ validateIndicatorPattern() ─→ STIX pattern validation         │  │
│  │  ├─ createObservablesFromIndicator()                              │  │
│  │  ├─ getDecayDetails()       ─→ Score decay calculation            │  │
│  │  └─ promoteIndicatorToObservables()                               │  │
│  └────────────────┬────────────────────────────────────────────────┘  │
│                   │                                                     │
│  ┌────────────────▼────────────────────────────────────────────────┐  │
│  │  Data Access Layer (Database Middleware)                        │  │
│  │  ├─ createEntity()    ─→ Persist to Elasticsearch                │  │
│  │  ├─ createRelation()  ─→ Link indicator ↔ observable              │  │
│  │  ├─ patchAttribute()  ─→ Update indicator fields                 │  │
│  │  ├─ elUpdateElement() ─→ Bulk update                             │  │
│  │  └─ elPaginate()      ─→ Query with pagination                   │  │
│  └────────────────┬────────────────────────────────────────────────┘  │
│                   │                                                     │
└───────────────────┼─────────────────────────────────────────────────────┘
                    │
        ┌───────────┴────────────┐
        │                        │
        ▼                        ▼
   ┌─────────────┐          ┌──────────┐
   │Elasticsearch│          │ RabbitMQ │
   │Port 9200    │          │(Events)  │
   │             │          │          │
   │Index:       │          │Topics:   │
   │ - stix_     │          │- ADDED   │
   │   domain_   │          │- UPDATED │
   │   objects   │          │- DELETED │
   │ - stix_     │          │- MERGED  │
   │   cyber_    │          │          │
   │   observ.   │          └──────────┘
   │ - stix_core │
   │   rels      │
   └─────────────┘
```

---

## 🔄 **2. IOC CREATION FLOW (addIndicator)**

### **Step-by-Step Process**

```
┌─────────────────────────────────────────────────────────────────┐
│ GraphQL Mutation: indicatorAdd(input: IndicatorAddInput)       │
│                                                                 │
│ Input Example:                                                  │
│ {                                                               │
│   name: "C2 Server IP",                                         │
│   pattern: "[ipv4-addr:value = '192.168.1.100']",            │
│   pattern_type: "stix2",                                        │
│   indicator_types: ["malicious-activity"],                     │
│   x_opencti_main_observable_type: "IPv4-Addr",                 │
│   x_opencti_score: 75,                                          │
│   x_opencti_detection: true,                                    │
│   valid_from: "2026-03-01T00:00:00Z",                          │
│   basedOn: ["observable-id-1"],  // Optional link               │
│   createObservables: true        // Auto-create from pattern    │
│ }                                                               │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: VALIDATION                                              │
│                                                                 │
│ 1. Check observable type is valid                               │
│    ├─ IPv4-Addr, Domain-Name, File, URL, Email-Addr...         │
│    └─ Reject if unknown (unless YARA pattern)                   │
│                                                                 │
│ 2. Validate STIX Pattern                                        │
│    ├─ Pattern syntax check via Python bridge                    │
│    ├─ Format: [ipv4-addr:value = '...'], [file:hashes.MD5]     │
│    ├─ Check if indicator is in exclusion list (whitelist)       │
│    └─ Return formattedPattern (normalized)                      │
│                                                                 │
│ 3. Check Score                                                  │
│    └─ Must be 0-100, default: 50                                │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2: DECAY RULE LOOKUP & COMPUTATION                         │
│                                                                 │
│ 1. Find decay rule for observable type (e.g., IPv4)             │
│    └─ Lookup from decayRule collection                          │
│       Example: { lifetime: 90 days, pound: 2, points: [70...] }│
│                                                                 │
│ 2. Compute valid_from & valid_until dates                       │
│    ├─ If decay enabled:                                         │
│    │  └─ valid_until = today + decay.lifetime                   │
│    ├─ If decay disabled:                                        │
│    │  └─ valid_until = today + 90 days (default)                │
│    └─ revoked = false (initially)                               │
│                                                                 │
│ 3. Initialize decay tracking (if enabled)                       │
│    ├─ decay_applied_rule: { id, lifetime, pound, points... }   │
│    ├─ decay_base_score: initial score (75)                     │
│    ├─ decay_base_score_date: today                             │
│    ├─ decay_history: [{ updated_at, score, updated_by }]        │
│    └─ decay_next_reaction_date: when score drops to next point  │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: BUILD INDICATOR OBJECT                                  │
│                                                                 │
│ BaseIndicator = {                                               │
│   // STIX properties                                             │
│   name: "C2 Server IP",                                          │
│   pattern: "[ipv4-addr:value = '192.168.1.100']",               │
│   pattern_type: "stix2",                                         │
│   indicator_types: ["malicious-activity"],                      │
│   valid_from: "2026-03-01T00:00:00Z",                           │
│   valid_until: "2026-06-29T00:00:00Z",  // Computed              │
│   x_opencti_score: 75,                                           │
│   x_opencti_detection: true,                                     │
│   x_opencti_main_observable_type: "IPv4-Addr",                  │
│   revoked: false,                                                │
│                                                                 │
│   // Metadata                                                    │
│   created_at: NOW(),                                             │
│   updated_at: NOW(),                                             │
│   created_by: "user-id",                                         │
│   objectMarking: [TLP:AMBER],                                    │
│                                                                 │
│   // Decay info (if enabled)                                     │
│   decay_applied_rule: { decay_rule_id, lifetime: 90 },           │
│   decay_base_score: 75,                                          │
│   decay_base_score_date: "2026-03-01T00:00:00Z",                │
│   decay_next_reaction_date: "2026-04-10T00:00:00Z",             │
│   decay_history: [{ updated_at, score: 75, updated_by }]        │
│ }                                                               │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 4: ELASTICSEARCH INDEX                                     │
│                                                                 │
│ createEntity(context, user, finalIndicatorObject, "Indicator")  │
│                                                                 │
│ Action in ES:                                                   │
│ ├─ Generate internal_id (UUID)                                  │
│ ├─ Generate standard_id (from pattern + created_at)             │
│ ├─ Index into: opencti_stix_domain_objects-XXXXXX               │
│ ├─ Set mapping with dynamic=strict (all fields predefined)      │
│ ├─ Add to-filter by entity_type="Indicator"                    │
│ └─ Return created object with internal_id                       │
│                                                                 │
│ ES Document Structure:                                           │
│ {                                                               │
│   "_id": "indicator--uuid1",                                     │
│   "_index": "opencti_stix_domain_objects-000001",                │
│   "_source": {                                                  │
│     "entity_type": "Indicator",                                  │
│     "internal_id": "uuid1",                                      │
│     "standard_id": "indicator--hash-of-pattern",                 │
│     "name": "C2 Server IP",                                      │
│     "pattern": "[ipv4-addr:value = '192.168.1.100']",            │
│     "x_opencti_score": 75,                                       │
│     "x_opencti_main_observable_type": "IPv4-Addr",              │
│     "created_at": 1677830400000,  // timestamp ms                │
│     "updated_at": 1677830400000,                                 │
│     "revoked": false,                                            │
│     "decay_next_reaction_date": 1680508800000,                   │
│     ... (all other fields)                                       │
│   }                                                              │
│ }                                                               │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 5: RELATIONSHIP CREATION (Optional)                        │
│                                                                 │
│ If basedOn observables provided:                                │
│ ├─ For each observable_id in basedOn:                           │
│ │  ├─ Create relationship:                                      │
│ │  │  {                                                         │
│ │  │    fromId: indicator.internal_id,                          │
│ │  │    toId: observable.internal_id,                           │
│ │  │    relationship_type: "based-on",                          │
│ │  │    created_at: NOW()                                       │
│ │  │  }                                                         │
│ │  └─ Index in: opencti_stix_core_relationships                 │
│ │                                                               │
│ If createObservables = true:                                    │
│ ├─ Extract observables from pattern:                            │
│ │  └─ "[ipv4-addr:value = '192.168.1.100']"                     │
│ │     → Creates observable type="IPv4-Addr", value="192.168..."  │
│ └─ Auto-link created observables to indicator                   │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 6: PUBLISH EVENT                                           │
│                                                                 │
│ notify(BUS_TOPICS.STIX_DOMAIN_OBJECTS.ADDED_TOPIC, created)    │
│                                                                 │
│ Event sent to RabbitMQ:                                          │
│ {                                                               │
│   type: "ADDED",                                                │
│   entity_type: "Indicator",                                      │
│   id: "indicator--uuid1",                                        │
│   object: { ... full indicator data ... }                       │
│ }                                                               │
│                                                                 │
│ Subscribers (Workers, Rules):                                   │
│ ├─ Decay Rule Manager ─→ Monitors decay_next_reaction_date     │
│ ├─ Sighting Propagation ─→ Creates incident on first sighting  │
│ └─ Custom Workflows ─→ Trigger automations                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔍 **3. IOC QUERY & RETRIEVAL FLOW**

### **Query: Fetch Confirmed Indicators**

```
┌─────────────────────────────────────────────────────────────────┐
│ GraphQL Query:                                                  │
│ query {                                                         │
│   indicators(                                                   │
│     first: 100,                                                 │
│     after: "cursor",                                            │
│     filters: [                                                  │
│       { key: ["status.template.name"], values: ["Confirmed"] }, │
│       { key: ["revoked"], values: ["false"] },                  │
│       { key: ["updated_at"], values: ["2026-03-06"], operator: "gte" }
│     ]                                                           │
│   ) { edges { node { id, name, pattern, ... } } }              │
│ }                                                               │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: ELASTICSEARCH QUERY                                     │
│                                                                 │
│ index: ["opencti_stix_domain_objects-*"]                        │
│                                                                 │
│ Query DSL:                                                      │
│ {                                                               │
│   "query": {                                                    │
│     "bool": {                                                   │
│       "must": [                                                 │
│         { "term": { "entity_type.keyword": "Indicator" } },     │
│         { "term": { "status.template.name.keyword": "Confirmed"}},
│         { "term": { "revoked": false } },                       │
│         { "range": { "updated_at": { "gte": 1678080000000 } } } │
│       ]                                                         │
│     }                                                           │
│   },                                                            │
│   "sort": [                                                     │
│     { "updated_at": { "order": "desc" } }                       │
│   ],                                                            │
│   "size": 100,                                                  │
│   "from": 0  // For pagination                                  │
│ }                                                               │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2: ELASTICSEARCH RESPONSE                                  │
│                                                                 │
│ Response:                                                       │
│ {                                                               │
│   "hits": {                                                     │
│     "total": { "value": 2543 },                                 │
│     "hits": [                                                   │
│       {                                                         │
│         "_id": "indicator--uuid1",                               │
│         "_source": {                                            │
│           "entity_type": "Indicator",                           │
│           "internal_id": "uuid1",                               │
│           "name": "C2 Server IP",                                │
│           "pattern": "[ipv4-addr:value = '192.168.1.100']",    │
│           "pattern_type": "stix2",                              │
│           "x_opencti_score": 75,                                │
│           "x_opencti_main_observable_type": "IPv4-Addr",        │
│           "x_opencti_detection": true,                          │
│           "valid_from": "2026-03-01T00:00:00Z",                │
│           "valid_until": "2026-06-29T00:00:00Z",               │
│           "revoked": false,                                     │
│           "created_at": 1677830400000,                          │
│           "updated_at": 1678080123456                          │
│         }                                                       │
│       },                                                        │
│       { ... next indicator ... },                              │
│       ...                                                       │
│     ]                                                           │
│   }                                                             │
│ }                                                               │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: BUILD CONNECTION RESPONSE                              │
│                                                                 │
│ GraphQL Connection (Relay Spec):                                │
│ {                                                               │
│   "indicators": {                                               │
│     "pageInfo": {                                               │
│       "startCursor": "cursor-0",                                │
│       "endCursor": "cursor-99",                                 │
│       "hasNextPage": true,                                      │
│       "hasPreviousPage": false                                  │
│     },                                                          │
│     "edges": [                                                  │
│       {                                                         │
│         "cursor": "cursor-0",                                   │
│         "node": {                                               │
│           "id": "indicator--uuid1",                             │
│           "name": "C2 Server IP",                               │
│           "pattern": "[ipv4-addr:value = '192.168.1.100']",    │
│           "pattern_type": "stix2",                              │
│           "x_opencti_score": 75,                                │
│           "x_opencti_main_observable_type": "IPv4-Addr",        │
│           "x_opencti_detection": true,                          │
│           "valid_from": "2026-03-01T00:00:00Z",                │
│           "valid_until": "2026-06-29T00:00:00Z",               │
│           "revoked": false,                                     │
│           "created_at": "2026-03-01T00:00:00Z",                │
│           "updated_at": "2026-03-06T14:22:03.456Z",            │
│           "observables": { ... linked observables ... }        │
│           "decayLiveDetails": {                                 │
│             "live_score": 73,  // Current score after decay      │
│             "live_points": [...]  // Future score checkpoints    │
│           }                                                     │
│         }                                                       │
│       },                                                        │
│       ...                                                       │
│     ]                                                           │
│   }                                                             │
│ }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📈 **4. SCORE DECAY MECHANISM**

### **Automatic Score Degradation Over Time**

```
Timeline Example:
┌─────────────────────────────────────────────────────────────┐
│ Indicator created: March 1, 2026, Score: 75                 │
│ Decay Lifetime: 90 days                                      │
│ Decay Rule Points: [70, 60, 50, 40, 30, 20, 10]             │
│ Revoke Score: 0                                              │
│                                                             │
│ Score Timeline (Over 90+ days):                             │
│                                                             │
│ Score                                                       │
│ 75  ┌─────────────────────────────                          │
│     │ Initial: created March 1                              │
│     │                                                       │
│ 70  │         ┌────────────────                             │
│     │ Drop1: ~April 10 (40 days in)                         │
│     │                                                       │
│ 60  │               ┌────────────                           │
│     │ Drop2: ~May 5 (65 days in)                            │
│     │                                                       │
│ 50  │                   ┌────────                           │
│     │ Drop3: ~May 29 (90 days in) ← valid_until = revoke   │
│     │                                                       │
│ 40  │                       ┌────                           │
│ 30  │                           ┌                           │
│ 20  │                           │                           │
│ 10  │                           ├─ Beyond valid_until       │
│  0  │                           │   → revoked=true          │
│     └───────────────────────────┴─────────                  │
│ Mar  Apr  May  Jun  Jul  Aug  Sep  Oct                      │
│                                                             │
│ decay_history entries:                                       │
│ 1. { updated_at: 2026-03-01, score: 75, updated_by: ... }  │
│ 2. { updated_at: 2026-04-10, score: 70, updated_by: ... }  │
│ 3. { updated_at: 2026-05-05, score: 60, updated_by: ... }  │
│ 4. { updated_at: 2026-05-29, score: 50, updated_by: ... }  │
│ 5. { updated_at: 2026-05-30, score: 0, updated_by: ... }   │
│                                                             │
│ Stored in Elasticsearch:                                   │
│ {                                                           │
│   "decay_applied_rule": {                                   │
│     "decay_rule_id": "...",                                 │
│     "decay_lifetime": 90,  // days                          │
│     "decay_pound": 2,      // strength of decay             │
│     "decay_points": [70, 60, 50, 40, 30, 20, 10],          │
│     "decay_revoke_score": 0                                 │
│   },                                                        │
│   "decay_base_score": 75,                                   │
│   "decay_base_score_date": "2026-03-01T00:00:00Z",         │
│   "decay_next_reaction_date": "2026-04-10T00:00:00Z",      │
│   "decay_history": [...],                                   │
│   "valid_until": "2026-05-30T00:00:00Z",  // Auto-updated  │
│   "x_opencti_score": 50,  // Current effective score        │
│   "revoked": true  // After decay finishes                  │
│ }                                                           │
└─────────────────────────────────────────────────────────────┘
```

### **Decay Computation (computeLiveScore)**

```typescript
// Real-time score calculation
function computeLiveScore(indicator) {
  if (indicator.decay_applied_rule && indicator.decay_base_score_date) {
    const daysSinceCreation = NOW - indicator.decay_base_score_date
    const currentScore = decayAlgorithm(
      baseScore = 75,
      daysSince = 5,  // 5 days passed
      decayRule = { lifetime: 90, pound: 2, points: [...] }
    )
    return Math.round(currentScore)  // e.g., 72.5 → 73
  }
  return indicator.x_opencti_score  // If no decay
}
```

---

## 🔗 **5. INDICATOR ↔ OBSERVABLE RELATIONSHIP**

### **How Indicators Link to Observables**

```
Pattern: "[ipv4-addr:value = '192.168.1.100']"
                 │
                 ▼ Extract observable
         ┌───────────────────┐
         │ Observable Type   │
         │ IPv4-Addr         │
         │ Value: 192.168... │
         └───────┬───────────┘
                 │
         ┌───────▼────────────────────────────────┐
         │ OPTION 1: basedOn explicit observables │
         │ User provides: observable-id-1         │
         │                observable-id-2         │
         │                                        │
         │ Relationship: Indicator --based-on--> │
         │              Observable                │
         └────────────────────────────────────────┘
                 │
         ┌───────▼────────────────────────────────┐
         │ OPTION 2: createObservables = true     │
         │ Automatically extract from pattern     │
         │ and create new observables             │
         │                                        │
         │ Flow:                                  │
         │ 1. Parse pattern                       │
         │ 2. Create Observable entity            │
         │ 3. Link via based-on relationship      │
         │ 4. Return created observables          │
         └────────────────────────────────────────┘

Elasticsearch Indices Involved:
─────────────────────────────────

Indicator stored in:
  opencti_stix_domain_objects-XXXXXX
  {
    "entity_type": "Indicator",
    "pattern": "[ipv4-addr:value = '192.168.1.100']",
    "x_opencti_main_observable_type": "IPv4-Addr"
  }

Observable stored in:
  opencti_stix_cyber_observables-XXXXXX
  {
    "entity_type": "IPv4-Addr",
    "value": "192.168.1.100",
    "x_opencti_description": "Simple observable of indicator..."
  }

Relationship stored in:
  opencti_stix_core_relationships-XXXXXX
  {
    "from_id": "indicator--uuid1",
    "to_id": "observable--uuid2",
    "relationship_type": "based-on",
    "entity_type": "Relationship"
  }
```

---

## ✏️ **6. IOC UPDATE/PATCH FLOW (indicatorEditField)**

### **Updating Indicator Properties**

```
┌──────────────────────────────────────────────────────┐
│ Mutation: indicatorFieldPatch(id, input)             │
│                                                      │
│ Example input:                                       │
│ [                                                    │
│   { key: "x_opencti_score", value: [85] },          │
│   { key: "valid_until", value: ["2026-07-06"] },    │
│   { key: "pattern", value: ["[...new pattern...]"]} │
│ ]                                                    │
└──────────────────────────────────────┬───────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
           ┌────────────────┐  ┌──────────────┐  ┌──────────────┐
           │ Pattern Change │  │ Score Change │  │ Date Change  │
           └────────┬────────┘  └──────┬───────┘  └──────┬───────┘
                    │                  │                  │
                    ▼                  ▼                  ▼
         Validate STIX syntax  Validate range(0-100)  Check coherence
              ↓                        ↓               (until > from)
         Check exclusion list  Check decay update    Auto-revoke if
                                                     until < now
                    │                  │                  │
                    └──────────────────┼──────────────────┘
                                       │
                                       ▼
                    ┌──────────────────────────────────┐
                    │ Special Decay Logic (if enabled) │
                    │                                  │
                    │ When score changes:              │
                    │ 1. Validate score not already    │
                    │    updated by same user          │
                    │ 2. Reset decay computation:      │
                    │    - New decay_base_score        │
                    │    - New decay_base_score_date   │
                    │    - New decay_next_reaction...  │
                    │    - Recalculate valid_until     │
                    │ 3. Push new point to            │
                    │    decay_history array           │
                    │                                  │
                    │ Result:                          │
                    │ The indicator decay starts       │
                    │ fresh from the new score         │
                    └──────────────┬───────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────┐
                    │ Elasticsearch Update              │
                    │                                  │
                    │ elUpdateElement():               │
                    │ - Find indicator by internal_id  │
                    │ - Apply patches via JSON Patch   │
                    │ - Update updated_at timestamp    │
                    │ - Increment version (_version)   │
                    │                                  │
                    │ ES Query:                        │
                    │ POST /.../_update/indicator--u.. │
                    │ {                                │
                    │   "doc": {                       │
                    │     "x_opencti_score": 85,       │
                    │     "decay_base_score": 85,      │
                    │     "decay_base_score_date": NOW │
                    │     "valid_until": "2026-07-06", │
                    │     "updated_at": NOW            │
                    │   }                              │
                    │ }                                │
                    └──────────────┬───────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────────┐
                    │ Publish UPDATE Event              │
                    │                                  │
                    │ RabbitMQ Topic:                  │
                    │ STIX_DOMAIN_OBJECTS.UPDATED      │
                    │                                  │
                    │ Subscribers:                     │
                    │ - Decay Manager (recalculate)    │
                    │ - Sighting Rules (triggered)     │
                    │ - Frontend (real-time update)    │
                    └──────────────────────────────────┘
```

---

## 🗑️ **7. IOC DELETION FLOW**

### **Soft vs Hard Delete**

```
┌──────────────────────────────────────────────────────┐
│ Mutation: indicatorDelete(id)                        │
└──────────────────────────────┬───────────────────────┘
                               │
                               ▼
                ┌──────────────────────────────┐
                │ Step 1: Find indicator       │
                │ by internal_id               │
                │ Check permissions            │
                │ Validate exists              │
                └──────────────┬───────────────┘
                               │
                               ▼
                ┌──────────────────────────────┐
                │ Step 2: Process deletion     │
                │                              │
                │ - Delete all relationships:  │
                │   Indicator --based-on-->    │
                │   Observable                 │
                │   Indicator --indicates-->   │
                │   Malware/Campaign/etc.      │
                │                              │
                │ - Hard delete from ES:       │
                │   DELETE /.../_doc/indic...  │
                │                              │
                │ - Move to deleted_objects    │
                │   index (soft copy)          │
                └──────────────┬───────────────┘
                               │
                               ▼
                ┌──────────────────────────────┐
                │ Step 3: Cascade effects      │
                │                              │
                │ - Sighting rules affected    │
                │ - Reports referencing this   │
                │   indicator become invalid   │
                │ - Decay manager stops        │
                │   monitoring                 │
                └──────────────┬───────────────┘
                               │
                               ▼
                ┌──────────────────────────────┐
                │ Step 4: Publish DELETE event │
                │                              │
                │ RabbitMQ:                    │
                │ STIX_DOMAIN_OBJECTS.DELETED  │
                │ { id, object_id, user }      │
                │                              │
                │ Subscribers clean up refs    │
                └──────────────────────────────┘
```

---

## 📊 **8. ELASTICSEARCH MAPPING FOR INDICATORS**

### **Index Schema Structure**

```json
{
  "opencti_stix_domain_objects-000001": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "stix-domain-objects-policy"
    },
    "mappings": {
      "dynamic": "strict",
      "date_detection": false,
      "properties": {
        // Core STIX properties
        "name": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword" } }
        },
        "pattern": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword", "ignore_above": 512 } }
        },
        "pattern_type": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword" } }
        },
        "indicator_types": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword" } }
        },
        
        // Validity
        "valid_from": {
          "type": "date"
        },
        "valid_until": {
          "type": "date"
        },
        
        // OpenCTI Custom
        "x_opencti_score": {
          "type": "integer"
        },
        "x_opencti_detection": {
          "type": "boolean"
        },
        "x_opencti_main_observable_type": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword" } }
        },
        
        // Decay fields
        "decay_applied_rule": {
          "type": "flattened"
        },
        "decay_base_score": {
          "type": "integer"
        },
        "decay_base_score_date": {
          "type": "date"
        },
        "decay_next_reaction_date": {
          "type": "date"
        },
        "decay_history": {
          "type": "flattened"
        },
        
        // Metadata
        "entity_type": {
          "type": "keyword"
        },
        "internal_id": {
          "type": "keyword"
        },
        "standard_id": {
          "type": "keyword"
        },
        "created_at": {
          "type": "date"
        },
        "updated_at": {
          "type": "date"
        },
        "revoked": {
          "type": "boolean"
        },
        
        // Relationships (denormalized)
        "i_rule_sighting_indicator": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword" } }
        }
      }
    }
  }
}
```

---

## 🔧 **9. KEY FUNCTIONS SUMMARY**

| Function | Location | Purpose |
|----------|----------|---------|
| `addIndicator()` | indicator-domain.ts:259 | Create new indicator with validation & decay setup |
| `indicatorEditField()` | indicator-domain.ts:429 | Update indicator properties with decay restart |
| `validateIndicatorPattern()` | indicator-domain.ts:229 | Validate STIX pattern syntax & exclusion list |
| `createObservablesFromIndicator()` | indicator-domain.ts:169 | Extract & create observables from pattern |
| `computeLiveScore()` | indicator-domain.ts:56 | Calculate current score after decay |
| `findIndicatorPaginated()` | indicator-domain.ts:47 | Query indicators with filters & pagination |
| `checkIndicatorSyntax()` | Python bridge | Validate pattern via Python STIX library |
| `createEntity()` | middleware.ts | Persist entity to Elasticsearch |
| `patchAttribute()` | middleware.ts | Update single attribute |
| `elPaginate()` | engine.ts | Execute paginated ES query |

---

## 📋 **10. STIX PATTERN EXAMPLES**

```
Simple IPv4:
[ipv4-addr:value = '192.168.1.100']

Domain Name:
[domain-name:value = 'malware.com']

File Hash (MD5):
[file:hashes.MD5 = '5d41402abc4b2a76b9719d911017c592']

File Hash (SHA256):
[file:hashes.SHA-256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855']

URL:
[url:value = 'http://evil.com/payload.exe']

Email:
[email-addr:value = 'attacker@example.com']

Complex (OR condition):
[ipv4-addr:value = '192.168.1.100' OR ipv4-addr:value = '10.0.0.5']

YARA Pattern:
rule malware_x {
  strings:
    $a = "MZ"
    $b = "This program cannot be run"
  condition: all of them
}
```

---

## 🎯 **SUMMARY: Data Flow for MySQL Sync Tool**

```
When building Go tool to sync IOC to MySQL:

1. Query ES:
   GET /opencti_stix_domain_objects/_search
   {
     query: { bool: { must: [
       { term: { entity_type: "Indicator" } },
       { term: { "status.template.name": "Confirmed" } },
       { term: { revoked: false } },
       { range: { updated_at: { gte: "2026-03-06T00:00:00Z" } } }
     ] } }
   }

2. For each Indicator hit:
   ├─ Extract: id, name, pattern, pattern_type, x_opencti_score
   ├─ Extract: valid_from, valid_until, x_opencti_detection
   ├─ Extract: x_opencti_main_observable_type, created_at, updated_at
   ├─ Parse pattern to get IOC value & type
   └─ Normalize IOC type (IPv4-Addr → ipv4, Domain-Name → domain)

3. UPSERT to MySQL:
   INSERT INTO ioc_indicators (...)
   VALUES (...)
   ON DUPLICATE KEY UPDATE
     version = version + 1,
     synced_at = NOW()

4. Update version tracking:
   INSERT INTO ioc_versions (...)

5. Track sync state:
   SELECT MAX(updated_at) FROM ioc_indicators
   → Use as next sync filter
```

---

**All source code validated against:**
- `/workspace/tunv_opencti/opencti-platform/opencti-graphql/src/modules/indicator/`
- `/workspace/tunv_opencti/opencti-platform/opencti-graphql/src/database/`
- `/workspace/tunv_opencti/.docs/OpenCTI_Core_Infrastructure.md`

