# OpenCTI NLQ (Natural Language Query) Generation - Phân tích chi tiết

## 1. Tổng quan

NLQ (Natural Language Query) là tính năng **Enterprise Edition** của OpenCTI cho phép người dùng nhập câu hỏi bằng ngôn ngữ tự nhiên (ví dụ: *"Who is behind T1082?"*) và hệ thống tự động chuyển đổi thành các filter truy vấn chuẩn của OpenCTI để tìm kiếm dữ liệu CTI (Cyber Threat Intelligence).

**Luồng tổng quát:**

```
[User Input] → [Frontend GraphQL Mutation] → [Backend Prompt Engineering] → [AI Model (LLM)] → [Parse + Validate Response] → [Map Entity IDs] → [Return Filters] → [Frontend Navigate + Apply Filters]
```

**Luồng NLQ hoạt động:**

1. **Frontend** (TopBar.tsx): User nhập câu hỏi → gọi GraphQL mutation `aiNLQ(search: "...")`
2. **Backend** (ai-domain.ts): Xây dựng prompt 3 phần gửi **cùng lúc** đến AI model mỗi request:

   **Phần A - System Prompt** (`ai-nlq-utils.ts → systemPrompt`)
   
   Là một đoạn text dài cố định, đóng vai "hướng dẫn sử dụng" cho model AI. Nội dung chính:
   - Khai báo vai trò: *"You are an expert in CTI and OpenCTI query filters"*
   - Bắt buộc trả về JSON đúng schema, không kèm giải thích
   - **Quy tắc mapping ngôn ngữ tự nhiên → filter key cụ thể:**
     - Nhắc đến entity STIX (Malware, Threat-Actor...) → dùng filter key `entity_type`
     - Nhắc đến relationship (uses, targets, located-at...) → dùng filter key `relationship_type`
     - Nhắc đến CVSS score → dùng `x_opencti_cvss_base_score` + operator `gt/gte/lt/lte`
     - Nhắc đến TLP (RED, AMBER...) → dùng `objectMarking`
     - Hỏi về 1 entity cụ thể (VD: "APT28") → dùng `regardingOf`, KHÔNG thêm `entity_type`
     - Hỏi về victim → dùng `regardingOf` + `relationship_type: targets`
     - Hỏi về attack pattern → dùng `regardingOf` + `relationship_type: uses`
     - Không liên quan CTI → trả filter rỗng `{ filters: [] }`
   
   → **Muốn cải thiện NLQ cho loại câu hỏi mới?** Thêm quy tắc mapping vào system prompt tại file `ai-nlq-utils.ts`.

   **Phần B - Few-Shot Examples** (`ai-nlq-few-shot-examples.ts`)
   
   ~15 cặp `{ input, output }` được gửi kèm **mỗi lần gọi** model (few-shot learning). Mỗi cặp là một câu hỏi mẫu + JSON filter đúng tương ứng. Ví dụ tiêu biểu:
   
   | Input mẫu | Output filter (rút gọn) |
   |---|---|
   | "Who's behind T1082?" | `regardingOf: T1082` + `entity_type: Threat-Actor-Group, Intrusion-Set` |
   | "Victims affected by 134.175.104.84?" | `regardingOf: targets + id: 134.175.104.84` |
   | "Malware used by MustardMan?" | `regardingOf: uses + id: MustardMan` + `entity_type: Malware` |
   | "Vulnerabilities CVSS > 3.5 and ≤ 7?" | `cvss_base_score gt 3.5` + `cvss_base_score lte 7` + `entity_type: Vulnerability` |
   | "Actors located in Russia?" | `regardingOf: located-at + id: Russia` + `entity_type: Threat-Actor` |
   | "Reports by Cambridge Group?" | `creator_id: Cambridge Group` + `entity_type: Report` |
   | "Impact of quantum computing?" (non-CTI) | `{ filters: [] }` (filter rỗng) |
   
   → **Muốn model trả đúng hơn cho 1 dạng câu hỏi?** Thêm cặp input/output mẫu vào file `ai-nlq-few-shot-examples.ts`.

   **Phần C - User Input**: Câu hỏi gốc của người dùng, truyền vào vị trí `{text}` trong template.
   
   > **Tóm lại**: Muốn cải thiện NLQ → sửa 2 file: `ai-nlq-utils.ts` (thêm quy tắc) và `ai-nlq-few-shot-examples.ts` (thêm ví dụ mẫu). Cả system prompt + few-shot examples đều gửi kèm mỗi request, nên thêm càng nhiều examples thì prompt càng dài và tốn token hơn.
3. **AI Model**: Gọi qua LangChain với `temperature=0`, ép structured output bằng Zod schema (hoặc tool binding cho Anthropic). Model trả về JSON filters chuẩn
4. **Validate + Map IDs**: Validate filters → search DB để chuyển entity names (VD: "APT28") thành internal UUIDs
5. **Frontend nhận response**: `{ filters: "...", notResolvedValues: [...] }` → navigate đến `/dashboard/search/nlq/{filters}/{keyword}` → apply filters lên global search

---
>>> USER QUERY: List all CVE in 2002 | 
<<< Response: {
  "filters": [
    {
      "key": "entity_type",
      "values": [
        "Vulnerability"
      ],
      "operator": "eq",
      "mode": "or"
    },
    {
      "key": "created_at",
      "values": [
        "2002"
      ],
      "operator": "contains",
      "mode": "or"
    }
  ],
  "mode": "and"
}  [tokens: prompt=4203, completion=117, total=4320]  finish=stop

Đúng rồi, model sai vì **không có rule nào trong system prompt** và **không có few-shot example nào** dạy nó cách xử lý "CVE by year". Nhìn lại log full:

**System prompt** có nói về Vulnerability nhưng chỉ dạy filter theo `entity_type` và `x_opencti_cvss_base_score` — **không nhắc gì đến filter CVE theo năm qua `name`**.

**23 few-shot examples** — không có cặp nào về "all CVE in year X".

Nên model tự bịa ra `created_at contains "2002"` — sai hoàn toàn vì:
- `created_at` = ngày import vào OpenCTI (2026), không phải năm CVE
- CVE year nằm trong **tên**: `CVE-2002-0001`, nên phải filter `name contains "CVE-2002"`

**Fix cần làm bên OpenCTI** — 2 chỗ:

**1) Thêm rule vào system prompt** (`ai-nlq-utils.ts`), thêm vào section "Context Awareness":

```
#### When filtering CVEs/vulnerabilities by year:
- CVE identifiers contain the year in their name (e.g., CVE-2024-12345).
- Use `name` filter with `contains` operator and value "CVE-{YEAR}".
- Do NOT use `created_at` — that is the date the entity was imported into OpenCTI, not the CVE publication year.
- Example for "all CVE in 2024":
  {
    "key": "name",
    "values": ["CVE-2024"],
    "operator": "contains",
    "mode": "or"
  }
```

**2) Thêm few-shot examples** (`ai-nlq-few-shot-examples.ts`), thêm 2-3 cặp:

```
{ input: "List all CVE in 2024",
  output: { filters: [
    { key: "entity_type", values: ["Vulnerability"], operator: "eq", mode: "or" },
    { key: "name", values: ["CVE-2024"], operator: "contains", mode: "or" }
  ], mode: "and" }}

{ input: "Show me vulnerabilities from 2002",
  output: { filters: [
    { key: "entity_type", values: ["Vulnerability"], operator: "eq", mode: "or" },
    { key: "name", values: ["CVE-2002"], operator: "contains", mode: "or" }
  ], mode: "and" }}

{ input: "CVE in 2025 with CVSS > 8",
  output: { filters: [
    { key: "entity_type", values: ["Vulnerability"], operator: "eq", mode: "or" },
    { key: "name", values: ["CVE-2025"], operator: "contains", mode: "or" },
    { key: "x_opencti_cvss_base_score", values: ["8"], operator: "gt", mode: "or" }
  ], mode: "and" }}
```

Hai file này nằm trong source code OpenCTI backend — bạn có access để sửa không?