# EMS · Workflow inspection actions

`list_workflows`、`list_pending_approval_workflows`、`list_related_resource_workflows`、`get_workflow`。全部 read-only：浏览 schema-change workflow + 看 pipeline / BPM 状态。**写流程**（创建/批准/推进/关闭 workflow）见 `references/schema_change.md`。

## 三个 list 动作怎么选

| 动作 | 后端 | mode | 关键字段 | 选用场景 |
|---|---|---|---|---|
| `list_workflows` | `GET /api/platform/v1/schema_change` | 1=ALL / 2=作者 | `key` 模糊匹配资源名 + `type/type_list` | 想按 storage / entity 过滤工作流，或者要看自己作为 **author** 提的工作流 |
| `list_pending_approval_workflows` | `POST /api/platform/openapi/v1/schema_change/list` | 1=PENDING_APPROVAL | 我作为 reviewer 且 **尚未** 批准（state=Remote）| "我现在该批哪些 workflow"，最常用的待办视图 |
| `list_related_resource_workflows` | `POST /api/platform/openapi/v1/schema_change/list` | 2=RELATED_RESOURCE | 我 **订阅 / Owner** 的 resource 上的所有 workflow | "我相关资源最近发生了什么变更"，更宽的浏览视角 |

> 直觉助记：
> - `list_workflows` = 我**写**的 workflow（按 author / 资源筛）
> - `list_pending_approval_workflows` = 等我**批**的 workflow
> - `list_related_resource_workflows` = 跟我**资源**有关的 workflow

## `list_workflows`

List schema-change workflows. Maps to `GET /api/platform/v1/schema_change`.

Three common modes of use:

1. **"my workflows"** — no filters. Defaults to `mode=2`, backend derives the author from JWT. Skill echoes `query_user`.
2. **"workflows on this storage"** — pass `storage_uri`. Mirrors the EMS UI Storage → Workflow tab: skill auto-fills `key=<storage_uri>`, `exact=true`, `type_list=[<storage_resource_type>, 11=Topology]`, and switches `mode` to `1` (ALL).
3. **"workflows on this entity"** — pass `entity_uri`. Mirrors the EMS UI Entity → Workflow tab: skill auto-fills `key=<entity_uri>`, `exact=true`, `type=1` (Entity), and switches `mode` to `1`.

Any explicit `key` / `type` / `type_list` / `mode` / `exact` you pass **overrides** the convenience defaults, so advanced callers can hand-craft the exact query shape.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `storage_uri` | string | No (convenience) | Shortcut for the Storage → Workflow tab. Mutually exclusive with `entity_uri`. |
| `entity_uri` | string | No (convenience) | Shortcut for the Entity → Workflow tab. Mutually exclusive with `storage_uri`. |
| `mode` | int | Defaulted | `1`=all visible workflows, `2`=only workflows authored by the JWT user. Default `2` when no convenience URI is set; `1` when `storage_uri` / `entity_uri` is set. |
| `key` | string | No | Fuzzy keyword match on the changed resource name (entity name / storage uri). Auto-filled from `storage_uri` / `entity_uri`. |
| `exact` | bool | No | Whether `key` must match exactly. Auto-set to `true` when `storage_uri` / `entity_uri` is used. |
| `type` | int | No | `ResourceType` enum. `1`=Entity, `2`=MySQL, `3`=Redis, `4`=Abase, `5`=ByteKV, `6`=ByteGraph, `7`=ByteDoc, `8`=EntStore, `9`=BCache2, `11`=Topology. |
| `type_list` | []int or csv | No | Multiple `ResourceType` filters; sent as `type_list[]=...&type_list[]=...`. Used internally when resolving `storage_uri`. |
| `change_state` | int | No | `SchemaChangeRequestState` enum filter (see table below). |
| `page_num` | int | No | Default `1` |
| `page_size` | int | No | Default `20` |

### `SchemaChangeRequestState` enum

Applies to both the `change_state` filter and the `state` field on returned workflows.

| Value | Name | Meaning |
|-------|------|---------|
| 0 | Unknown | — |
| 1 | Local | Draft stored locally |
| 2 | Remote | Pushed to remote, awaiting review |
| 3 | Merged | Code merged into master, change not yet executed on the storage |
| 4 | Applied | Schema change executed on the target storage |
| 5 | Closed | Terminal — finished (often after Applied) |
| 6 | Rejected | Review rejected |
| 7 | Approved | Review approved, not yet merged |

### Examples

```bash
# "my workflows"
gdpa-cli run ems --input '{"action":"list_workflows"}'

# Workflows on a MySQL storage (UI Storage → Workflow tab)
gdpa-cli run ems --input '{"action":"list_workflows","storage_uri":"tiktok/mysql/hw0318testa"}'

# Workflows on an Abase storage (type_list auto-becomes [4, 11])
gdpa-cli run ems --input '{"action":"list_workflows","storage_uri":"tiktok/abase/demo_ns"}'

# Workflows on an entity (UI Entity → Workflow tab)
gdpa-cli run ems --input '{"action":"list_workflows","entity_uri":"tiktok/user_replica"}'

# Only merged-but-not-yet-applied workflows on an entity (change_state=3)
gdpa-cli run ems --input '{"action":"list_workflows","entity_uri":"tiktok/user_replica","change_state":3}'

# Low-level escape hatch: hand-craft the exact query
gdpa-cli run ems --input '{"action":"list_workflows","mode":1,"key":"tiktok","type_list":[2,11],"page_size":50}'
```

## `list_pending_approval_workflows` / `list_related_resource_workflows`

Personal-inbox views via the EMS OpenAPI v1 endpoint
`POST /api/platform/openapi/v1/schema_change/list`. Each action pins a
different `mode` so the LLM doesn't have to learn an enum.

### Backend判定规则

`list_pending_approval_workflows` (mode=1) — the JWT user **is one of the
reviewers** of an `approvals[]` entry **AND** has not yet approved
**AND** the workflow is in `state=Remote` (awaiting review). Once the
user approves, the workflow drops out of this list automatically.

`list_related_resource_workflows` (mode=2) — the JWT user has subscribed
to a resource (entity / storage) OR is recorded as an Owner on the
resource_meta of an entity (`resource_snapshot.entity_mapping.entity.owners`)
or storage (`resource_snapshot.storage.owners`) in `state=Prod`. Backend
pre-collects the user's resource set then lists every schema-change
whose `changedResources.resourceName` falls into that set — sorted by
`createTime` desc.

### 参数

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `page_num` | int | No | Default `1` |
| `page_size` | int | No | Default `20` |

> No filter / mode parameter — the action name is the filter. Use
> `list_workflows` if you need keyword / type / change_state-style
> filtering; the openapi-v1 inbox endpoint does NOT expose them.

### 返回字段

```json
{
  "mode": 1,
  "mode_name": "PENDING_APPROVAL",
  "page_num": 1,
  "page_size": 20,
  "query_user": "alice",
  "total": 7,
  "workflow_count": 7,
  "workflows": [
    {
      "id": "229489180419",
      "state": 2,
      "state_label": "REMOTE",
      "change_type": 1,
      "author": "bob",
      "created_at": "2026-05-12T03:11:00Z",
      "changed_resources": [{"type": 2, "name": "tiktok/mysql/foo"}],
      "approvals": [{"reviewers": ["alice", "carol"]}],
      "detail_url": "https://ent.tiktok-row.net/workflow/detail/229489180419"
    }
  ],
  "data": { /* original {list, page_info} backend envelope */ }
}
```

`workflows[]` is the flattened convenience view — for any field not in
the table above, fall back to `data.list[i]`.

### 用法示例

```bash
# Default: my approval inbox (state=Remote, I'm in approvals.reviewers)
gdpa-cli run ems --input '{"action":"list_pending_approval_workflows"}'

# Same, but page 2 with smaller page size
gdpa-cli run ems --input '{"action":"list_pending_approval_workflows","page_num":2,"page_size":10}'

# All workflows touching resources I subscribe to / own
gdpa-cli run ems --input '{"action":"list_related_resource_workflows"}'
```

## `get_workflow`

Get workflow detail by id. Maps to `GET /api/platform/v1/schema_change/:id`.

On top of the raw workflow payload, the skill also aggregates what the UI shows on the right-hand side of `https://ent.tiktok-row.net/workflow/detail/<id>`:

1. **Pipeline status** — fetched from `GET /api/platform/v1/siacflow/:id` (`build_id`, `status`, `active_jobs`) and then from BITS `GET /api/v1/pipelines/open/runs/:build_id` to expose the full job list (with `status_label` per node and any nested sub-pipeline URLs).
2. **BPM tickets** — for each nested sub-pipeline discovered inside the main pipeline (e.g. the "资源部署" / IaC Deployment node), the skill walks the sub-pipeline's jobs and extracts every entry from `jobAtom.output.bpm_ticket_info_map`, so you get a flat list of BPM ticket IDs, statuses, and links (`https://bpm-i18n.tiktok-row.net/record/<id>`) grouped by parent job + sub job.

Authentication note: `bits.bytedance.net` is a CN service and rejects the default I18N JWT. The skill therefore prefers the CN JWT (falling back to I18N). If no BITS-compatible JWT is available (e.g. you have only logged into ent.tiktok-row.net), pipeline / BPM enrichment is skipped with a `pipeline.detail_error` string instead of failing the whole call. If the outer siacflow lookup itself fails (rare), a `pipeline_error` field is added at the root of `data` instead.

**Closed / fully-finished workflow fallback**: once a workflow reaches a terminal state (`state=5 Closed`, and occasionally `state=4 Applied` long after completion), the EMS `siacflow` endpoint starts returning an empty payload (`build_id=0`, `active_jobs=null`, `status=""`). The skill detects that and falls back to `data.schema_change.build_id` from the GetWorkflow response itself, so Pipeline + BPM history stays visible for terminated workflows (matching the EMS UI). When the fallback fires, `pipeline.build_id_source = "schema_change"` is set (vs `"siacflow"` for the normal path) and `pipeline.top_status` is derived from `schema_change_request.state` (e.g. `"CLOSED"`, `"APPLIED"`). Use the `build_id_source` field if you need to know whether the pipeline view came from live siacflow data or was reconstructed from the workflow detail.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | Yes | Workflow ID, e.g. `119090688003`. **NOTE**: the param name is `id` (not `workflow_id`), to match the URL `.../workflow/detail/<id>`. The DDL-change actions (`approve_workflow_owner_gate` / `advance_workflow_bpm_ticket` / `close_workflow`) take `workflow_id` instead — that's deliberate (those operate on a workflow), but `get_workflow` reads it as a resource. |
| `include_pipeline` | bool | No | Default `true`. Set `false` to skip the siacflow + BITS pipeline fetch (plain schema_change only). |
| `include_bpm_tickets` | bool | No | Default `true`. Set `false` to skip the nested sub-pipeline traversal (keeps the main pipeline summary but omits `bpm_tickets`). Automatically forced off when `include_pipeline=false`. |

### Example response shape (trimmed)

```json
{
  "id": "119090688003",
  "data": { },
  "pipeline": {
    "build_id": 1141866277890,
    "build_id_source": "siacflow",
    "build_url": "https://bits.bytedance.net/devops/4085329154/pipeline/open_build/1141866277890",
    "top_status": "RUNNING",
    "run_status": 2,
    "run_status_label": "RUNNING",
    "active_jobs": [
      {"id": 2633133476, "atomic_service_name": "IaC Deployment OpenAPIv2", "status": "RUNNING", "priority": 1}
    ],
    "jobs": [
      {"job_name": "Schema 校验", "job_status": 14, "status_label": "SUCCEEDED"},
      {"job_name": "资源部署",   "job_status": 3,  "status_label": "RUNNING",
       "sub_pipelines": [
         {"label": "Singapore-Central (Running)", "build_id": 1142010722050, "space_id": "1071185616642",
          "url": "https://bits.bytedance.net/devops/1071185616642/pipeline/open_build/1142010722050"}
       ]}
    ]
  },
  "bpm_tickets": [
    {"parent_job": "资源部署", "sub_job": "Execute DDL SQL",
     "id": "40927815", "vregion": "Singapore-Central",
     "status": "start", "is_finished": false, "creator": "qinmingshuai",
     "url": "https://bpm-i18n.tiktok-row.net/record/40927815"}
  ]
}
```

### Usage examples

```bash
# Default — full detail + pipeline + BPM tickets
gdpa-cli run ems --input '{"action":"get_workflow","id":"119090688003"}'

# Only the workflow payload (no BITS enrichment at all)
gdpa-cli run ems --input '{"action":"get_workflow","id":"119090688003","include_pipeline":false}'

# Keep the main pipeline summary, but skip drilling into nested sub-pipelines
gdpa-cli run ems --input '{"action":"get_workflow","id":"119090688003","include_bpm_tickets":false}'
```
