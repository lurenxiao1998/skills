# EMS · Entity actions

`list_entities`、`get_entity`、`get_entity_online_ddl`、`subscribe_entity`、`unsubscribe_entity` 是 entity 组的"老牌" 只读 + 单发幂等动作；本次新增了 4 个聚焦 RDS entity 写流程的动作：

| action | 关键字 | role |
|---|---|---|
| `precheck_entity` | dry-run / 预校验 | (read-only) 把候选 `EntityMappingWrapper` 丢给 EMS pre-publish 校验通道，返回 `is_valid` + `message`。本身就是 `update_rds_entity` / `change_rds_table_with_entity_edits` 发布前的内部步骤，也可以独立做 dry-run。 |
| `update_rds_entity` | 改字段描述 / PII / 标签 | (write, two-phase) Path 4 — 只改 **RDS** entity metadata，不改 DDL；底层 `CreateSchemaChangeV2(skip_iac=true)`，不会触发 IaC 部署。V1 `format_version` entity 直接拒绝；非 RDS storage 也直接拒绝（abase/redis 等会另起 `update_<storage>_entity`）。 |
| `list_online_tables` | 发现线上表 | (read-only) Path 5 — 枚举 RDS storage 上实际存在的表，标记 `already_imported` 与 `related_entity`。 |
| `import_online_table` | 把线上表注册成 entity | (write, two-phase) Path 5 — 把一张物理表升格成 EMS entity。`already_imported=true` 时短路返回 `no_change=true`。 |
| `update_entity_owners` | 改 entity 负责人 | (write, two-phase) 通过 EntityFastRelease 直接刷写 V2 entity 的 `owners` 列表，立即生效；不创建 workflow，也不需 Owner approve。caller 必须已经是 owner；V1 entity 拒绝；其它字段一律保留原值。|

> 🛑 **Renamed**: `update_entity` 在本次发布中改名为 `update_rds_entity`。入参形态（`uri` + `entity_overrides` + `confirm`）不变，只是动作字符串变了。继续用旧名会得到 `unsupported action: update_entity`。改名的动机是 abase / redis / 其它存储的 entity 的 `EntityMappingWrapper` 结构跟 RDS 完全不同，后续会以 `update_abase_entity` / `update_redis_entity` 等独立 action 接入，不会"复用"旧名。

先读 `SKILL.md` 拿全局 region / output envelope 约定 + 五条路径决策树，再回到这里。

`subscribe_entity` / `unsubscribe_entity` 是 entity 组里**单发幂等**的两个写动作（不走 preview/confirm）；详见底部对应章节。`update_rds_entity` / `import_online_table` 才是两阶段写动作，遵循 preview → `confirm=true` 公约。

## `list_entities`

List entities. Maps to `GET /api/platform/v1/entity` (the same path the EMS UI uses; the V2 path is intentionally avoided — it returns no `list` array under `mode=3` and uses a different array field name for `mode=1/2`). This one action covers both "browse my entities" and "list entities (tables) under a storage" — mode is inferred from whether `storage_uri` is set.

> **Smart mode inference** (applies when `mode` is NOT explicitly provided):
> - `storage_uri` set → `mode=1` (ALL entities under that storage; e.g. all tables under a MySQL storage)
> - `storage_uri` unset → `mode=2` (only entities owned by the JWT user — "my entities")
>
> Explicit `mode` always wins. To list entities **owned by a specific user**, use `mode=2` — the backend derives the user from JWT automatically. **Do NOT pass a free-form `owner` param.** In owner mode the skill echoes the resolved `query_user` in the response.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `mode` | int | No (inferred) | `1`=all, `2`=owned by JWT user, `3`=subscribed. If omitted, inferred from `storage_uri`. |
| `storage_uri` | string | No | Narrow to a specific storage. When set and `mode` is unset, triggers `mode=1` default. |
| `table_name` | string | No | Filter by underlying table name (MySQL) |
| `entity_name` | string | No | Fuzzy match on entity name |
| `serial` | string | No | Filter by entity serial id |
| `exact` | bool | No | V1-only flag controlling whether `entity_name` / filters match exactly. Default `false` (matches the EMS UI). |
| `page_num` | int | No | Default `1` |
| `page_size` | int | No | Default `20` |

Response shape (under `data.data`):
- `list`: array of `{entity, version, subscribed}`. Each `entity` is the standard entity envelope (`name`, `serial`, `owners`, `description`, `fields[]`, …) used by `get_entity`.
- `page_info`: `{page_num, page_size, total}`.

Examples:

```bash
# my entities (owner)
gdpa-cli run ems --input '{"action":"list_entities"}'

# all tables / entities under an RDS storage (previously list_storage_entity)
gdpa-cli run ems --input '{"action":"list_entities","storage_uri":"tiktok/mysql/new_one_rds"}'

# explicit override: my entities inside a specific storage
gdpa-cli run ems --input '{"action":"list_entities","storage_uri":"tiktok/mysql/new_one_rds","mode":2}'
```

## `get_entity`

Get entity detail (schema / columns). Maps to `GET /api/platform/v2/entity/:uri`.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | e.g. `tiktok/mysql__new_one_rds__new_table_1` |

```bash
gdpa-cli run ems --input '{
  "action": "get_entity",
  "uri": "tiktok/mysql__new_one_rds__new_table_1"
}'
```

## `get_entity_online_ddl`

Query an RDS table's online DDL across vregions. Maps to `POST /api/platform/v2/entity/ddl/query_online`.

The **backend** is scoped at `(storage_uri, table_name, vregions)`, NOT the entity uri. The skill provides a convenience layer: if you only pass the entity `uri`, it calls `GetEntity` first to resolve `storage_uri` + `table_name` from the entity mapping (`resource.entity_mapping.mapping.mysql.storageUri` / `tablename`).

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `storage_uri` | string | One of the two groups | e.g. `tiktok/mysql/ies_item` |
| `table_name` | string | One of the two groups | Physical MySQL table name (may differ from the entity name, e.g. entity `tiktok/item_info` → table `item`) |
| `uri` | string | Alternative | Entity URI; skill resolves storage_uri + table_name automatically |
| `vregions` | []string or csv | No | e.g. `["Singapore-Central", "US-East"]`; omitted → all vregions the storage is deployed to |

Response:
- `storage_uri`, `table_name`, `vregions`, `entity_uri` (if resolved via uri) are echoed in `data` for traceability.
- The actual DDLs are in `data.data.online_ddl_list` / `ddl_list` keyed by vregion.

```bash
# By entity uri (convenience — resolves storage_uri + table_name automatically).
gdpa-cli run ems --input '{
  "action": "get_entity_online_ddl",
  "uri": "tiktok/item_info",
  "vregions": ["Singapore-Central", "US-East"]
}'

# By storage_uri + table_name (skips the GetEntity hop).
gdpa-cli run ems --input '{
  "action": "get_entity_online_ddl",
  "storage_uri": "tiktok/mysql/ies_item",
  "table_name": "item",
  "vregions": ["Singapore-Central"]
}'
```

## `precheck_entity` (read-only)

Dry-run an EntityMappingWrapper through EMS' pre-publish validation pipeline. Maps to `POST /api/platform/v2/entity/precheck`.

`update_rds_entity` and `change_rds_table_with_entity_edits` 内部都会自动调一次 `precheck_entity` 再发布。把它独立暴露主要是为了两种场景：

- 手工 dry-run：在 `update_rds_entity` 前先看看 backend 是否会拒绝。
- 客户端构造 EntityMappingWrapper 后想确认字段拼写 / PII tag / 类型是否合法。

输入支持两种形态：

| Param | Type | Required | Notes |
|---|---|---|---|
| `entity_uri` | string | One of `entity_uri` / `entity_mapping` | 先 GetEntity 拿到当前 mapping，再叠加 `entity_overrides`，最后送去 precheck。 |
| `entity_overrides` | object | No | `{fields: [{name, description?, tags?, pii_labels?, ...}]}`。和 `update_rds_entity` / `change_rds_table_with_entity_edits` 完全一致。 |
| `entity_mapping` | object | One of `entity_uri` / `entity_mapping` | 已有现成的 `EntityMappingWrapper`，原样转发；忽略 `entity_overrides`。 |

输出：

```jsonc
{
  "valid":      true,
  "message":    "",
  "source":     "entity_uri",         // or "entity_mapping"
  "entity_uri": "tiktok/mysql__db__t"  // present when source == "entity_uri"
}
```

`valid=false` 时整个 action 报错 `ApiBizError`，并把 backend `message` 透传到 `error.message` 末尾。

## `update_rds_entity` (write, two-phase) — Path 4

RDS-entity-only metadata edit (no DDL, no IaC). Maps to `POST /api/platform/v2/schemaChange/create` (CreateSchemaChangeV2) with `skip_iac=true` — EMS 不会触发 IaC 部署，整个变更只走 EMS workflow 的元数据更新通道。

> 🛑 **Renamed**: 之前叫 `update_entity`。改名是为了在 action 名字层面就把"仅支持 RDS"这个事实硬编码进来 —— abase / redis / 其它存储的 entity 的 `EntityMappingWrapper` 结构跟 RDS 完全不同（mapping 段不是 `mysql.*`），无法走同一段 merge / precheck 代码。后续会以 `update_abase_entity` / `update_redis_entity` 等独立 action 接入。继续使用 `update_entity` 会直接报 `unsupported action`，不要做兜底重试，请改用新名字。

适用场景：

- 只想给 RDS 表的某个字段加 description / tag / PII label，物理表已经长好了。
- 想批量给 RDS entity 加 owner / 把 entity description 修正下，不需要 DDL。

约束：

- **RDS / MySQL only** — 非 RDS storage（abase / redis / …）直接拒绝；错误消息会明确指向"未来的 `update_<storage>_entity` 系列"。
- **V1 `format_version` entity 直接拒绝** — V1 是 legacy 只读，更新走老页面。
- 内部依次跑 `validateMySQLEntityRules`（客户端 8 条规则）→ `precheck_entity` → `CreateSchemaChangeV2(skip_iac=true)`；任何一步报错都不会发布。

### Inputs

| Param | Type | Required | Notes |
|---|---|---|---|
| `uri` | string | Yes | 目标 RDS entity URI。 |
| `entity_overrides` | object | No (但通常会传) | 见上面 `precheck_entity`。空对象 `{}` 视作 no-op，依然会触发一次预览 + dry-run。 |
| `confirm` | bool | No | `false`（默认）→ 预览 + dry-run；`true` → 发布。 |

### Preview (`confirm=false`)

`update_rds_entity` shares the **same fixed-schema preview** as the other change actions (see `schema_change.md` → `Response highlights`). The `tables[]` array contains a single row with `operation: "UPDATE_RDS_ENTITY"` and no DDL (`vregions`/`regional_sql_list` are empty); everything else — `field_diff`, `entity_schema`, `validation`, `next_steps` — uses the canonical shape:

```jsonc
{
  "action":             "update_rds_entity",
  "display_action":     "Update RDS Entity Metadata",
  "entity_uri":         "tiktok/mysql__db__t",
  "storage_uri":        "tiktok/mysql/db",
  "psm":                "tiktok.mysql.db",
  "shared_vregions":    [],
  "tables": [{
    "entity_uri":        "tiktok/mysql__db__t",
    "operation":         "UPDATE_RDS_ENTITY",
    "vregions":          [],
    "regional_sql_list": [],
    "entity_overrides":  { "fields": [ … ] },
    "entity_schema":     { "fields": [ … 合并后字段视图 … ], "primary_key": [...], "indices": [...] },
    "field_diff":        { "added": [], "removed": [], "modified": [...], "unchanged_count": N },
    "validation":        { "errors": [], "warnings": [], "regional": [] },
    "precheck_is_valid": true,
    "precheck_message":  "",
    "request_body":      { … }
  }],
  "summary": {
    "total": 1, "create_count": 0, "alter_count": 0, "vregion_count": 0,
    "errors_count": 0, "warnings_count": 0, "all_valid": true,
    "field_changes": N, "is_entity_only": true
  },
  "risk_warnings":      [],
  "skip_iac":           true,
  "current_hash":       "<hash_version>",
  "modification_label": "update (rds-entity-only)",
  "preview":            true,
  "confirm_required":   true,
  "published":          false,
  "next_steps": [
    {"id": "publish",            "label": "直接发布变更",                       "hint": "重新调用本 action（参数不变），加上 confirm=true"},
    {"id": "edit_entity_fields", "label": "进一步编辑 Entity Fields（例如给 JSON 字段添加 innerFields）",
                                 "hint": "传 entity_overrides 微调字段元数据（codec / innerFields / description / tags / pii_labels 等）"}
  ]
}
```

**Field diff** is computed against the live entity mapping (the entity record before applying overrides). For JSON / struct fields with `innerFields` changes, `field_diff.modified[*].inner_field_diff` recurses so the user sees exactly which sub-field changed (e.g. `inner_field_diff.added: [{name: "col_json_field3", type: "int32"}]`) rather than two opaque `innerFields` blobs side by side.

**Validation** is the same `{errors, warnings, regional}` triple as in `validate_ddl_change`; `update_rds_entity` populates `errors` from `entity_rules` (client-side MySQL invariants) and `precheck` (EMS pre-publish gate) when applicable. When `validation.errors` is non-empty the dispatcher returns the rich preview *and* an `ApiBizError` so the user can read every failure in one call (no short-circuit).

### Publish (`confirm=true`)

发布成功后的输出沿用 `change_rds_table` 的 published 形态（`workflow_id`、`workflow_url`、`owner_gate_preview` 等），多了一个 `skip_iac=true` 字段表示这次是 RDS entity-only 变更。

## `list_online_tables` (read-only) — Path 5 discovery

枚举一个 RDS storage 上实际存在的物理表。Maps to `POST /api/platform/v2/entity/online_table/list`。

| Param | Type | Required | Notes |
|---|---|---|---|
| `rds_uri` / `storage_uri` / `rds_psm` | string | One of three | 共享 storage 入口。 |
| `already_imported` | bool | No | `true` 只看已经被注册为 entity 的；`false` 只看尚未注册的；省略 → 两者都返回。 |

输出：

```jsonc
{
  "storage_uri": "tiktok/mysql/db",
  "psm":         "tiktok.mysql.db",
  "tables": [
    {"table_name": "user", "already_imported": true,  "related_entity": "tiktok/mysql__db__user"},
    {"table_name": "tmp",  "already_imported": false}
  ],
  "table_count": 2,
  "data":        { … raw backend payload … }
}
```

## `import_online_table` (write, two-phase) — Path 5 import

把一张物理 RDS 表升格成 EMS entity。Maps to `POST /api/platform/v2/entity/online_table/import`。

| Param | Type | Required | Notes |
|---|---|---|---|
| `rds_uri` / `storage_uri` / `rds_psm` | string | One of three | 共享 storage 入口（同 `list_online_tables`）。 |
| `table_name` | string | Yes | 物理表名。 |
| `rds_dcs` | []string | No | 限定参与导入的 RDS DC 列表，省略 → backend 自动决定。 |
| `confirm` | bool | No | `false`（默认）→ `just_build=true` 预览推断 entity；`true` → 实际持久化。 |

行为：

1. 先 `list_online_tables(already_imported=true)` 在结果中找 `table_name`。若已经存在且 `already_imported=true`，直接短路返回 `no_change=true` + 现存的 `entity_uri`，不发请求。
2. 否则按 `confirm` 决定 `just_build`：
   - `confirm=false` → backend 推断 mapping 不落库。
   - `confirm=true` → backend 推断 + 写库。

输出（preview）：

```jsonc
{
  "display_action":   "Import Online Table",
  "storage_uri":      "tiktok/mysql/db",
  "psm":              "tiktok.mysql.db",
  "table_name":       "foo",
  "rds_dcs":          [],
  "entity_uri":       "tiktok/mysql__db__foo",   // backend 推断
  "data":             { … raw backend payload … },
  "published":        false,
  "confirm_required": true,
  "next_steps":       ["确认后将把表 \"foo\" 注册为 EMS 实体（推断的 entity_uri=tiktok/mysql__db__foo）。"]
}
```

publish 成功后 `published=true`、`next_steps` 改成 `["已导入 EMS 实体 …，后续可通过 get_entity 查看详情。"]`。backend 返回 `err_reason` 非空时整个 action 直接报错并把 `error_reason` 透传出来。

> ⚠️ 若用户需求是 "建一张新表，让 EMS 把这张表也收录进来"，请走 `change_rds_table`（Path 2）— 一个 workflow 同时建表 + 注册。`import_online_table` 只解决 "表已经在线上但 EMS 还不知道" 这一种情况。`update_rds_entity` 仅用来改"已注册 entity 的 metadata"，既不建物理表、也不会把物理表升格成 entity —— 三个 action 用途不重叠。

## `subscribe_entity` (write, single-shot) / `unsubscribe_entity` (write, single-shot)

Add or remove the current JWT user from an entity's subscriber list. Maps to:

- `PUT /api/platform/v1/entity/{uri}/subscribe`
- `PUT /api/platform/v1/entity/{uri}/unsubscribe`

After subscribing, the entity shows up in `list_entities mode=3` (subscribed). Unsubscribing reverses that. The pair is the API counterpart of the **Subscribe / Unsubscribe** button on the entity detail page in the EMS UI.

> **⚠️ Single-shot exception** — these two actions **do NOT** use the two-phase preview/confirm flow. They go straight to PUT. Mirror of `subscribe_storage` / `unsubscribe_storage` in `references/storages.md`; the same justification applies:
>
> - Both endpoints are **idempotent** on the backend (re-subscribing / re-unsubscribing is a no-op).
> - The operation is **trivially reversible** by one call of the opposite action.
> - There is **no CAS / hash-version**, **no workflow conflict** surface, and **no permission coordination** — any user who can see the entity is allowed to (un)subscribe themselves.
>
> Forcing a preview gate here would add friction with no correctness benefit.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | Entity URI, e.g. `tiktok/sandbox` or `tiktok/mysql__new_one_rds__new_table_1`. URL-escaping is handled by the client; pass it un-escaped. |

### Response (success)

```json
{
  "success": true,
  "action": "subscribe_entity",
  "data": {
    "uri": "tiktok/sandbox",
    "kind": "entity",
    "operation": "subscribe",
    "current_user": "alice",
    "subscribed": true,
    "code": 0,
    "message": "",
    "data": null
  }
}
```

Field notes:

- `subscribed` reflects the **target state AFTER the call** (always `true` for `subscribe_entity`, always `false` for `unsubscribe_entity`). Because the backend is idempotent, this is the documented contract whether or not the user was already in (or out of) the subscriber list.
- `current_user` is the JWT-derived username (falls back to "unknown" rather than failing the call). Use it when phrasing the user-facing reply: "已为 alice 订阅 tiktok/sandbox".
- `kind` / `operation` are constant per-action — agents that consume the four subscribe/unsubscribe actions through a single code path can branch on them without re-discovering field names per RPC.
- Inner `data` is the EMS envelope's `data` field forwarded verbatim. Currently `null` for both endpoints; preserved for forward compatibility.

### Examples

```bash
# Subscribe to an entity — single shot, no confirm step.
gdpa-cli run ems --input '{
  "action": "subscribe_entity",
  "uri": "tiktok/sandbox"
}'

# Verify it shows up in the subscribed list.
gdpa-cli run ems --input '{
  "action": "list_entities",
  "mode": 3
}'

# Unsubscribe.
gdpa-cli run ems --input '{
  "action": "unsubscribe_entity",
  "uri": "tiktok/sandbox"
}'
```

### When talking to the user (agent guidance)

- Subscribe → "已为 `<current_user>` 订阅 entity `<uri>`，可在 `list_entities mode=3` 看到。"
- Unsubscribe → "已为 `<current_user>` 取消订阅 entity `<uri>`。"
- Idempotent retry → No special phrasing needed; the operation is a no-op so it's safe to omit. If the user explicitly asks ("再订阅一次会怎样？"), confirm that the backend treats it as a no-op.

## `update_entity_owners` (write, two-phase)

Modify a V2 entity's `owners` list (add / remove users). Maps to the EMS V2 `EntityFastRelease` endpoint:

- `POST /api/platform/v2/entity/fast_release`

This is the entity-side analogue of `update_storage_owners` (`references/storages.md`). The change applies **immediately** — there is **no schema-change workflow**, **no Owner-approval gate**, and **no IaC deployment**. Internally the dispatcher rebuilds the full `EntityMappingWrapper` from the live `GetEntity` response, mutates **only** `entity.owners`, and re-publishes via fast_release with the entity's `hash_version` carried as `previous_hash_version` for CAS protection.

> **Why not go through `change_rds_table` / `update_rds_entity`?** Both of those create workflows and trigger the full Owner approval / IaC deployment pipeline — heavyweight overkill for a single metadata field. `update_entity_owners` is the surgical path: it mirrors what the EMS UI does when you press "Add Owner" on an entity detail page.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | Entity URI, e.g. `tiktok/mysql__new_one_rds__new_table_1`. URL-escaping is handled by the client; pass it un-escaped. |
| `add_owners` | string \| []string | No | Users to add. Accepts a single string, JSON array, or comma-separated CSV. De-duped before diff. At least one of `add_owners` / `remove_owners` is required. |
| `remove_owners` | string \| []string | No | Users to remove. Same accepted shapes as `add_owners`. |
| `confirm` | bool | No | `true` to actually publish (and call `EntityFastRelease`); default `false` returns a preview only. |

### Server-side rules (EMS backend)

These are the rules the EMS handler enforces; the skill mirrors them with friendly errors so you do not have to read raw EMS error codes.

- **JWT required** — caller's identity drives both the audit log and the client-side ownership gate.
- **Entity must already exist online** — fast_release does NOT create entities.
- **CAS protection** — `previous_hash_version` must match the live `entity.version`. When it doesn't, the dispatcher folds the EMS `-128` error into a structured `cas_conflict` block + a `next_steps[0]` re-fetch hint.
- **Workflow conflict** — if another open workflow already targets this entity, fast_release is rejected with EMS `-703`. The dispatcher folds that into a structured `conflict` block with the blocking workflow's deep link, exactly like `update_storage_owners`.
- **V2 schema only** — V1 entities (`format_version=V1`) are **rejected client-side** before any HTTP hop, with a message pointing at the legacy update path.

### Client-side guards

- **Ownership gate** — caller must already be in `entity.owners`. Rejected with `AuthPermissionDenied` otherwise (the backend trusts callers for fast_release; we add this gate so you cannot accidentally hand ownership to someone else without being an owner yourself).
- **Empty diff** — both `add_owners` and `remove_owners` empty fails with `InputInvalidValue` rather than no-op'ing.
- **Orphan protection** — refusing to publish a change that would leave `owners` empty.
- **No-change short-circuit** — if every `add` is already present and every `remove` is already absent, the dispatcher returns `published=false`, `no_change=true`, and skips the fast_release call entirely.

### Response (preview, `confirm=false`)

```json
{
  "success": true,
  "action": "update_entity_owners",
  "data": {
    "uri": "tiktok/mysql__new_one_rds__new_table_1",
    "format_version": "V2",
    "current_user": "alice",
    "before_owners": ["alice", "bob"],
    "after_owners": ["alice", "carol"],
    "added": ["carol"],
    "removed": ["bob"],
    "skipped": [],
    "previous_hash_version": "10143624707",
    "published": false,
    "confirm_required": true,
    "next_steps": ["re-run with confirm=true to apply this owner change"]
  }
}
```

### Response (publish success, `confirm=true`)

```json
{
  "success": true,
  "action": "update_entity_owners",
  "data": {
    "uri": "tiktok/mysql__new_one_rds__new_table_1",
    "format_version": "V2",
    "current_user": "alice",
    "before_owners": ["alice", "bob"],
    "after_owners": ["alice", "bob", "carol"],
    "added": ["carol"],
    "removed": [],
    "skipped": [],
    "previous_hash_version": "10143624707",
    "published": true,
    "fast_release_code": 0,
    "fast_release_message": "success",
    "fast_release_data": null
  }
}
```

### Response (workflow conflict)

```json
{
  "success": false,
  "action": "update_entity_owners",
  "data": {
    "uri": "tiktok/mysql__new_one_rds__new_table_1",
    "before_owners": ["alice", "bob"],
    "after_owners": ["alice", "bob", "carol"],
    "published": false,
    "conflict": {
      "type": "workflow_conflict",
      "message": "ems api error (code=-703): workflow conflict, id: 190570023683 exists open workflow",
      "workflow_id": "190570023683",
      "workflow_url": "https://ent.tiktok-row.net/workflow/detail/190570023683",
      "blocking_reason": "Another open workflow on this entity is blocking further changes; this owner update cannot be applied until that workflow is approved or cancelled."
    },
    "next_steps": ["Open https://ent.tiktok-row.net/workflow/detail/190570023683 to approve or cancel the blocking workflow, then retry this entity owner change."]
  },
  "error": "update_entity_owners: cannot apply entity owner change to \"tiktok/mysql__new_one_rds__new_table_1\" — another open workflow (id=190570023683) is blocking it: …"
}
```

### Response (CAS conflict)

```json
{
  "success": false,
  "action": "update_entity_owners",
  "data": {
    "uri": "tiktok/mysql__new_one_rds__new_table_1",
    "published": false,
    "cas_conflict": {
      "type": "cas_conflict",
      "code": -128,
      "message": "ems api error (code=-128): save cas version conflict"
    },
    "next_steps": ["entity \"tiktok/mysql__new_one_rds__new_table_1\" has been modified since this preview was generated (CAS conflict); re-run get_entity (action=get_entity, uri=\"tiktok/mysql__new_one_rds__new_table_1\") to fetch the latest hash_version, then retry update_entity_owners."]
  },
  "error": "update_entity_owners: cannot apply entity owner change to \"tiktok/mysql__new_one_rds__new_table_1\" — the entity's hash_version moved before publish (CAS conflict). Re-fetch and retry."
}
```

### Examples

```bash
# Preview an owner change (no API write).
gdpa-cli run ems --input '{
  "action": "update_entity_owners",
  "uri": "tiktok/mysql__new_one_rds__new_table_1",
  "add_owners": ["carol"],
  "remove_owners": ["bob"]
}'

# Apply it.
gdpa-cli run ems --input '{
  "action": "update_entity_owners",
  "uri": "tiktok/mysql__new_one_rds__new_table_1",
  "add_owners": ["carol"],
  "remove_owners": ["bob"],
  "confirm": true
}'
```

### When talking to the user (agent guidance)

- Preview → 「准备给 entity `<uri>` 添加 `<added>` / 移除 `<removed>`，结果将变成 `<after_owners>`。确认后再执行（`confirm=true`）。」
- Publish 成功 → 「已更新 entity `<uri>` 的 owners 为 `<after_owners>`，立即生效。」
- Workflow conflict → 「该 entity 有未结束的 workflow（id=`<workflow_id>`），请先到 `<workflow_url>` 处理，再重试。」
- CAS conflict → 「entity 在 preview 与 confirm 之间发生了变更，请重新拉一次 `get_entity`，然后重新发起 owner 更新。」
- V1 拒绝 → 「`<uri>` 是 V1 legacy entity，本动作仅支持 V2/V3。请走 EMS UI 或等 V1 专用通路上线。」
