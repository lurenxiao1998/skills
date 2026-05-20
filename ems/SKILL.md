---
name: ems
description: "Query / operate EMS (Entity-Mapping-Storage / Entity Platform, ent.tiktok-row.net): storages, entities, sync channels, owner edits, schema-change workflows, RDS DDL (CREATE/ALTER) via validate → publish → Owner gate → BPM. Trigger on EMS / Entity Platform / ent.tiktok-row.net / storage_iac / DB Spec / RDS table create/alter / DDL validation / Owner gate / sync channel / sync RDS owner, or any ent.tiktok-row.net URL, storage URI (`tiktok/mysql/...`), entity URI, or EMS workflow ID. NOT for BITS / DevFlow / Meego / standalone BPM. i18n-line only — refuse BOE / BOE-I18N (also drop `BOE-I18N` from validate/create inputs)."
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# EMS Skill

Query the **EMS Platform** (a.k.a. **Entity Platform**) at `ent.tiktok-row.net` — storages, entities, sync channels, and schema-change workflows.

> **Naming**: EMS = **Entity-Mapping-Storage**. The platform is also referred to as the **Entity Platform** in product docs and team conversations. "Entity Management Service" is **NOT** the correct expansion — do not use it. All three names (`EMS` / `Entity-Mapping-Storage` / `Entity Platform`) refer to the same console at `ent.tiktok-row.net`.

> **When to Use**: Look up a storage's spec / topology / tables, inspect a storage's sync channels, check an entity's schema or online DDL across vregions, browse schema-change workflows, drive an RDS table create/alter through validate → publish → owner approve → BPM, or resolve an ent.tiktok-row.net URL.

## ⚠️ Region coverage — i18n line ONLY

EMS is deployed exclusively on the i18n production line (`https://ent.tiktok-row.net`). There is **no BOE, no BOE-I18N, no CN-line** counterpart of this platform.

Concretely:
- The skill always uses an I18N JWT (resolved from `region.GetJWT("Singapore-Central")`).
- Storages/entities can themselves be deployed to BOE / BOE-I18N vregions, but **the EMS metadata catalog that describes them lives on i18n only** — you still query it through `ent.tiktok-row.net`.
- If the user asks "查 BOE 的 EMS / EMS 的 BOE 环境 / 在 BOE-I18N 上看 storage_iac"，refuse and point them at the i18n console (`ent.tiktok-row.net`) instead of guessing or substituting another endpoint.
- The `target_addr` parameter is for **i18n staging hosts**, not for BOE — do not pass a BOE address there.

### ⚠️ Schema-change publishing on `BOE-I18N` is NOT supported (write side)

Even though EMS can _read_ the metadata of a BOE / BOE-I18N storage, the **publish path** (`validate_ddl_change` → `change_rds_table` / `change_rds_table_with_entity_edits` → `approve_workflow_owner_gate` → `advance_workflow_bpm_ticket`) cannot drive a CREATE / ALTER through to a `BOE-I18N` vregion today — the resource-deployment step has no working BPM ticket on that region. Concretely:

- Do **NOT** include `BOE-I18N` in `tables[i].vregions` or the top-level `vregions` for `validate_ddl_change` / `change_rds_table` / `change_rds_table_with_entity_edits`. Drop it from the list (or split that region out into a separate, manual change) before publishing.
- When a user asks "在 BOE-I18N 上发布 / 建表 / 改表 storage / table"，refuse the publish and surface this limitation; do not silently retry on a different region.
- Read-only inspection of a BOE-I18N-bearing storage / entity (`get_storage`, `get_entity`, `list_entities`, `get_entity_online_ddl`, sync-channel actions) is unaffected — those just query the i18n catalog.

## Actions

All actions use the caller's Singapore-Central JWT (obtained automatically). EMS only has an i18n deployment, so there is no BOE / BOE-I18N / CN target to switch to — `target_addr` is reserved for i18n staging / proxy hosts, NOT for BOE.

| action | role | reference |
|---|---|---|
| `list_storages` | List V2+V3 storages (default mode=2 = my storages) | `references/storages.md` |
| `get_storage` | Get storage detail (spec / topology / meta) by URI | `references/storages.md` |
| `update_storage_owners` | (write) Modify a storage's owners list (add/remove) | `references/storages.md` |
| `sync_rds_owner` | (write) Sync RDS owners into a MySQL storage's owners list | `references/storages.md` |
| `subscribe_storage` | (write, single-shot) Subscribe the JWT user to a storage | `references/storages.md` |
| `unsubscribe_storage` | (write, single-shot) Unsubscribe the JWT user from a storage | `references/storages.md` |
| `get_storage_sync_channel` | List sync edges of a storage (mermaid + ascii topology) | `references/sync_channels.md` |
| `get_storage_sync_channel_detail` | Detail for ONE edge (sub-task / lag / throughput / link) | `references/sync_channels.md` |
| `get_rds_online_spec` | Live RDS runtime spec (engine / qps / capacity / owners / auth) per vregion | `references/storages.md` |
| `list_entities` | List entities (auto: storage_uri ⇒ all-under-storage; else my-entities) | `references/entities.md` |
| `get_entity` | Get entity detail (schema / columns) by entity URI | `references/entities.md` |
| `get_entity_online_ddl` | Query an RDS table's online DDL across vregions | `references/entities.md` |
| `subscribe_entity` | (write, single-shot) Subscribe the JWT user to an entity | `references/entities.md` |
| `unsubscribe_entity` | (write, single-shot) Unsubscribe the JWT user from an entity | `references/entities.md` |
| `update_entity_owners` | (write) Modify a V2 entity's owners list (add/remove) via fast_release | `references/entities.md` |
| `list_workflows` | List schema-change workflows (my / by storage / by entity) | `references/workflows.md` |
| `list_pending_approval_workflows` | List workflows **waiting on my approval** (personal inbox) | `references/workflows.md` |
| `list_related_resource_workflows` | List workflows touching resources I **subscribed to / own** | `references/workflows.md` |
| `get_workflow` | Get workflow detail + bound BITS pipeline + BPM tickets | `references/workflows.md` |
| `validate_ddl_change` | Validate a batch of CREATE/ALTER DDL + infer entity_mapping (RDS only) | `references/schema_change.md` |
| `execute_rds_ddl` | (write, Path 1) Push DDL straight to RDS OpenAPI; no entity update | `references/rds_deployment.md` |
| `get_deployment_info` | Path 1 follow-up — query per-vregion deployment status | `references/rds_deployment.md` |
| `cancel_deployment` | (write, two-phase) Cancel an in-flight RDS deployment | `references/rds_deployment.md` |
| `change_rds_table` | (write, Path 2) Publish DDL + auto-infer entity (the most common flow) | `references/schema_change.md` |
| `change_rds_table_with_entity_edits` | (write, Path 3) Publish DDL + user-supplied entity overrides | `references/schema_change.md` |
| `update_rds_entity` | (write, Path 4) **RDS** entity-only metadata edit (no DDL, no IaC) | `references/entities.md` |
| `precheck_entity` | Dry-run EntityMappingWrapper through EMS pre-publish validation | `references/entities.md` |
| `list_online_tables` | (Path 5) Enumerate physical RDS tables; flags `already_imported` | `references/entities.md` |
| `import_online_table` | (write, Path 5) Promote a physical RDS table to an EMS entity | `references/entities.md` |
| `approve_workflow_owner_gate` | (write) Approve the workflow's Owner-approval gate | `references/schema_change.md` |
| `advance_workflow_bpm_ticket` | (write) List or drive BPM tickets bound to the resource-deployment step | `references/schema_change.md` |
| `close_workflow` | (write) Terminate the workflow (cascades to BPM tickets) | `references/schema_change.md` |

**Read-only**: `list_storages`, `get_storage`, `get_storage_sync_channel`, `get_storage_sync_channel_detail`, `get_rds_online_spec`, `list_entities`, `get_entity`, `get_entity_online_ddl`, `list_workflows`, `list_pending_approval_workflows`, `list_related_resource_workflows`, `get_workflow`, `validate_ddl_change`, `get_deployment_info`, `precheck_entity`, `list_online_tables`.

> **`list_workflows` vs `list_pending_approval_workflows` / `list_related_resource_workflows`**: All three list schema-change workflows but the role-relationship they encode is different. `list_workflows` (V1 endpoint) is keyed by author / storage / entity — `mode=2` returns workflows the JWT user **authored**. The two `list_*_workflows` actions hit the OpenAPI v1 inbox endpoint and key by approval / subscription / ownership instead — `pending_approval` returns workflows where I am a reviewer that hasn't approved yet, `related_resource` returns workflows touching resources I subscribed to or own. Use the right one based on whether you want "what I started" or "what I need to act on / care about".

**Validation payload contract (shared across `validate_ddl_change` / `change_rds_table` / `change_rds_table_with_entity_edits` / `update_rds_entity`)**: all four actions emit the same **fixed-schema batch validation payload** so the agent UI never has to special-case missing keys. The payload always includes (empty array / map when there is nothing to flag):

- `summary: {total, create_count, alter_count, vregion_count, errors_count, warnings_count, all_valid}` — the at-a-glance header.
- `risk_warnings: [string]` — batch-wide advisories (e.g. `skip_validate_single_rds_ddl_sql`).
- `tables[].operation` — `"CREATE"` / `"ALTER"` enum (uppercase) for the user-facing label; legacy lower-case `create_table` / `alter_table` is still under `table_operation`.
- `tables[].regional_sql_list: [{vregion, sql}]` — per-vregion DDL exactly as the workflow will receive it.
- `tables[].field_diff: {added, removed, modified, unchanged_count}` — net change vs the **live online entity** (for ALTER) or all-added (for CREATE). `modified[*].inner_field_diff` recurses into JSON / struct sub-fields so users see exactly which inner field changed — no opaque innerFields blob comparisons.
- `tables[].entity_schema.fields[]` — post-change entity field ↔ table column mapping (Entity Field / Type / Table Column / Column Type / Description).
- `tables[].validation: {errors: [{level, source, vregion?, code?, message}], warnings: [...], regional: [...]}` — SQL / heuristic / consistency / precheck / entity_rules issues split by severity (`ERROR` blocks publish, `WARNING` is advisory).

Write actions (`change_rds_table` / `change_rds_table_with_entity_edits` / `update_rds_entity`) **additionally** wrap the above with the two-phase preview/confirm gate:

- `preview: true` / `confirm_required: true` / `published: false` — gate flags on the preview phase; after `confirm=true` the publish-success response sets `published: true` (no `preview` / `confirm_required` keys) and embeds the same per-row validation block for reference.
- `next_steps: [string]` — preview-only, always two entries: re-run with `confirm=true` (publish), or further edit fields via `change_rds_table_with_entity_edits` / `entity_overrides`.

`validate_ddl_change` is **read-only** — it does NOT emit the gate flags or `next_steps` (there is no second-phase action to point to; call one of the write actions when ready to publish).

Errors are **not** short-circuited row-by-row — when any row fails, the dispatcher returns the full payload + an `ApiBizError` so the user can see every blocker in one call. See `references/schema_change.md` → `Response highlights` for the canonical shape.

**Write actions** (all are two-phase: preview by default, pass `confirm=true` to apply):

- `update_storage_owners` — modify a storage's `owners` list. Auto-completes; no separate approval step.
- `update_entity_owners` — modify a V2 entity's `owners` list (add/remove). Auto-completes via EntityFastRelease; no schema-change workflow, no Owner approval gate. Caller must already be in the entity's `owners`. V2/V3 entities only — `format_version=V1` is rejected. Two-phase: preview by default, pass `confirm=true` to apply.
- `sync_rds_owner` — sync RDS-side owners into a MySQL storage's `owners` list. MySQL only; auto-completes; no separate approval step. Server-side merges the RDS owner list (resolved via EMS `GetRDSOwnersByStorage`) into the storage's existing owners. **⚠️ Strict re-confirmation gate** — even when the user's phrasing sounds like an intent to apply (e.g. "帮我同步 owner" / "sync the owner"), the agent **MUST** preview first with `confirm:false`, show the diff, and wait for an explicit "同意 / 确认 / apply / yes" reply before re-calling with `confirm:true`. Do not chain preview→apply inside a single turn. (This re-confirmation gate applies to `sync_rds_owner` only; other write actions still follow the standard two-phase convention but do not require this per-call gate.) See `references/storages.md → sync_rds_owner`.
- `execute_rds_ddl` — Path 1 — push DDL straight through the RDS OpenAPI without touching the EMS entity catalog. Surfaces an entry under `risk_warnings` because downstream EMS readers (DECC / DES-MQ / lineage) will NOT see the change. Returns a `global_deployment_id` you can later inspect via `get_deployment_info` / cancel via `cancel_deployment`.
- `cancel_deployment` — two-phase cancel of an in-flight RDS deployment. Preview 调一次 `get_deployment_info` 把每 vregion 的状态展示给用户，`confirm=true` 才发送 cancel。后端幂等，重复 confirm 是 no-op；publish 阶段对 PPE 上的 1s upstream RPC 超时有自动恢复（详见 `references/rds_deployment.md`）。
- `change_rds_table` — Path 2 — publish CREATE/ALTER TABLE workflow with auto-inferred entity (the most common case; replaces the old `create_schema_change` action).
- `change_rds_table_with_entity_edits` — Path 3 — same as `change_rds_table` plus per-row `entity_overrides` (field descriptions / tags / PII labels). Runs `precheck_entity` per row before publishing.
- `update_rds_entity` — Path 4 — **RDS** entity-only metadata change (no DDL, no IaC deployment). Internally publishes via `CreateSchemaChangeV2(skip_iac=true)`. V1 `format_version` entities are rejected. Non-RDS storages (abase / redis / …) are rejected too — those entities have a different `EntityMappingWrapper` shape and will be covered by dedicated `update_<storage>_entity` actions when they land.
- `import_online_table` — Path 5 — register an already-existing physical RDS table as an EMS entity. Preview (`just_build=true`) by default; surfaces `no_change=true` short-circuit when the table is already mapped to an entity.
- `approve_workflow_owner_gate` — approve the Owner-approval gate of a schema-change workflow as the current JWT user.
- `advance_workflow_bpm_ticket` — drive a BPM ticket bound to a workflow's resource-deployment step (Approve / Reject / postpone).
- `close_workflow` — terminate the entire EMS schema-change workflow (cascades to all bound BPM tickets). Use this — not BPM `op_key=stop` — when you want to actually cancel a workflow.

> **🛑 Removed action — `create_schema_change`**: This action was renamed to `change_rds_table` in this release. The new action keeps the same input shape (`rds_uri` + `tables[]`); only the name changed. Callers that still pass `create_schema_change` will fail with `unknown action`. Migrate by replacing the action string. The other four paths (`execute_rds_ddl`, `change_rds_table_with_entity_edits`, `update_rds_entity`, `import_online_table`) cover the previously unsupported variants.
>
> **🛑 Removed action — `update_entity`**: Path 4 was renamed to `update_rds_entity` to make its RDS-only scope explicit. Input shape (`uri` + `entity_overrides` + `confirm`) is unchanged; only the action string changed. Callers that still pass `update_entity` will fail with `unsupported action: update_entity`. Migrate by replacing the action string. Abase / Redis / other-storage entities have a different `EntityMappingWrapper` and will be covered by dedicated `update_<storage>_entity` actions when those storages are supported — they will NOT be retrofitted onto the old `update_entity` name.

**Single-shot exception** — `subscribe_storage` / `unsubscribe_storage` / `subscribe_entity` / `unsubscribe_entity` are also write actions but **do NOT use the two-phase preview/confirm flow**. They go straight to PUT because:
- the backend endpoints are idempotent (re-subscribing or re-unsubscribing is a no-op);
- the operation is trivially reversible by one call of the opposite action;
- there is no CAS / hash-version, no workflow-conflict surface, and no permission coordination (any user who can see the resource can (un)subscribe themselves).
Forcing a preview gate here would add friction with no correctness benefit. This is a deliberate divergence from the "write actions are two-phase" convention above; documented here per-action so future maintainers don't accidentally "fix" it. See `references/storages.md → subscribe_storage / unsubscribe_storage` and `references/entities.md → subscribe_entity / unsubscribe_entity`.

## 路由：按用户意图决定加载哪个 reference

模型应根据用户意图先选定 `action`，再加载对应文档：

| 想做的事 | 必读文件 |
|---|---|
| 查 storage / 改 storage owner | `references/storages.md` |
| 看一条 storage 的同步链路 / 某条 edge 的延迟、吞吐、子任务 | `references/sync_channels.md` |
| 查 entity（表）/ entity 列表 / RDS 表的在线 DDL | `references/entities.md` |
| 浏览 / 查询 schema-change workflow（含 pipeline + BPM 状态） | `references/workflows.md` |
| 看待我审批的 workflow / 我相关资源的 workflow（个人收件箱视角） | `references/workflows.md` |
| 查 RDS storage 的运行时规格（QPS / 容量 / 鉴权列表 / 安全级别 ...） | `references/storages.md` |
| RDS 建表 / 改表 全流程：validate → publish → owner approve → BPM → close | `references/schema_change.md` |
| RDS DDL 直跑（不动 entity）/ 查部署状态 / 取消部署 | `references/rds_deployment.md` |
| 只改 entity 元数据 / 给字段加描述/PII / 把线上表导入成 entity / precheck dry-run | `references/entities.md` |

### 🚦 Entity / Table 变更路径决策树

RDS 建/改表的入口动作有 5 条，按 "DDL 是否要跑" + "Entity 要不要 EMS 帮你推断 / 让你改" 决定走哪条。RDS / MySQL 以外的 storage 都不支持。`format_version=V1` 的 entity 是只读 legacy，所有写动作都会拒绝。

```mermaid
flowchart TD
    Start[用户想改 RDS 表 / Entity] --> A{有 DDL 要执行?}
    A -- "No" --> B{是不是只改 RDS entity 元数据?<br/>例如 描述 / tags / PII labels"}
    B -- "Yes" --> P4["update_rds_entity (Path 4)<br/>skip_iac=true<br/>不触发 RDS 部署<br/>⚠️ 仅支持 RDS/MySQL entity"]
    B -- "No" --> Import{"表已经在线上但 EMS<br/>没注册成 entity?"}
    Import -- "Yes" --> P5["import_online_table (Path 5)<br/>+ 先 list_online_tables 发现"]
    Import -- "No" --> Read["其他场景<br/>用 get_entity / list_entities 等只读动作"]
    A -- "Yes" --> NeedEMS{用户主动声明:<br/>无需 DECC 打标 + 无需 DES-MQ 跨 VGeo 同步?}
    NeedEMS -- "都明确说不要" --> P1["execute_rds_ddl (Path 1)<br/>RDS OpenAPI 直跑<br/>EMS 不感知"]
    NeedEMS -- "其他 / 没说" --> D{用户要在推断的 entity<br/>之上手工改字段元数据?}
    D -- "No" --> P2["change_rds_table (Path 2)<br/>最常用 — DDL + 自动推 entity"]
    D -- "Yes" --> P3["change_rds_table_with_entity_edits (Path 3)<br/>tables[i].entity_overrides + precheck"]
```

> 备注: 任何路径都建议在 publish 之前先跑 `validate_ddl_change` 或 `precheck_entity` 做一遍 dry-run；`change_rds_table*` 内部已自动包了 validate，但单独跑 validate 可以让模型把变更预览给用户确认。
>
> **路径 1（`execute_rds_ddl`）适用三种场景**，按出现频率排序：
> 1. **表完全不需要 EMS**：用户必须主动声明 —— ① 无需在 DECC 平台打标，② 无需依赖 DES-MQ 做跨 VGeo 数据同步。两条都满足时 CREATE / ALTER 都直接走 Path 1。**不要根据"当前是否单 vregion 部署"做这个判断** —— 单 vregion 表以后也可能扩展到多 vregion 并需要 DES-MQ 同步，提前登记 entity 才能避免后期迁移成本。用户没明确表态时，默认按需要 EMS 处理（走 Path 2/3）；
> 2. **Entity-neutral ALTER**：表已在 EMS 登记，但本次 ALTER 只动 ENGINE / AUTO_INCREMENT / ROW_FORMAT 等表选项，不会动任何字段（详见 `references/rds_deployment.md`）；
> 3. **EMS 紧急绕行**：workflow 卡死 / 环境异常需要临时跳过工作流，事后再 `import_online_table` 把元数据补回。
>
> 第 1 类的判断只能由用户/业务方做出 —— skill 不会替用户决定「这张表是否需要 EMS」。一旦决定不要 EMS，CREATE 也走 Path 1（不像第 2 类只允许 ALTER）。

> reference 文件在 skill 安装时已一并复制到本目录。请直接 read（`./references/<name>.md`），不要再尝试重新拉取。

## Quick Start

```bash
# List MY storages (mode defaults to 2 = owner; skill reads JWT username automatically, no owner param needed)
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"list_storages"}'

# Get storage detail — URI contains slashes; pass it un-escaped
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "get_storage",
  "uri": "tiktok/mysql/new_one_rds"
}'

# List tables / entities under an RDS storage
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "list_entities",
  "storage_uri": "tiktok/mysql/new_one_rds"
}'

# Storage sync channel topology — by URI (fast path) or by PSM (skill resolves once)
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "get_storage_sync_channel",
  "storage_uri": "tiktok/mysql/new_one_rds"
}'

# Workflow detail by id
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "get_workflow",
  "id": "119090688003"
}'

# RDS table change — full lifecycle (validate ⇒ publish ⇒ owner approve ⇒ drive BPM ⇒ close)
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "validate_ddl_change",
  "rds_uri": "tiktok/mysql/new_one_rds",
  "tables": [
    {
      "table_name": "foo",
      "ddl_sql": "CREATE TABLE foo (id BIGINT(20) UNSIGNED NOT NULL COMMENT '\''ID'\'', PRIMARY KEY (id)) ENGINE=INNODB CHARSET=utf8mb4"
    }
  ]
}'

gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "change_rds_table",
  "rds_uri": "tiktok/mysql/new_one_rds",
  "tables": [
    {
      "table_name": "foo",
      "ddl_sql": "CREATE TABLE foo (id BIGINT(20) UNSIGNED NOT NULL, PRIMARY KEY (id)) ENGINE=INNODB CHARSET=utf8mb4"
    }
  ],
  "confirm": true
}'

# Path 1 — execute DDL straight on RDS (no entity update). Surfaces an entry under risk_warnings;
# returns a global_deployment_id usable with get_deployment_info / cancel_deployment.
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "execute_rds_ddl",
  "rds_uri": "tiktok/mysql/new_one_rds",
  "tables": [{"table_name":"foo","ddl_sql":"CREATE TABLE foo (id BIGINT NOT NULL PRIMARY KEY)"}],
  "confirm": true
}'

# Path 3 — DDL + entity overrides (e.g. add a field description / PII label).
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "change_rds_table_with_entity_edits",
  "rds_uri": "tiktok/mysql/new_one_rds",
  "tables": [
    {
      "entity_uri": "tiktok/mysql__new_one_rds__user",
      "ddl_sql":    "ALTER TABLE user ADD COLUMN nickname VARCHAR(64)",
      "entity_overrides": {
        "fields": [{"name":"nickname","description":"User nickname","pii_labels":["PII_USERNAME"]}]
      }
    }
  ],
  "confirm": true
}'

# Path 4 — RDS entity-only metadata edit (no DDL, no IaC).
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "update_rds_entity",
  "uri": "tiktok/mysql__new_one_rds__user",
  "entity_overrides": {
    "fields": [{"name":"nickname","description":"Updated description"}]
  },
  "confirm": true
}'

# Path 5 — discover then import an online RDS table as an EMS entity.
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"list_online_tables","rds_uri":"tiktok/mysql/new_one_rds","already_imported":false}'
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"import_online_table","rds_uri":"tiktok/mysql/new_one_rds","table_name":"foo","confirm":true}'

# After change_rds_table* returns workflow_id, drive the workflow:
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"approve_workflow_owner_gate","workflow_id":"<id>","confirm":true}'
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"advance_workflow_bpm_ticket","workflow_id":"<id>"}'

# Terminate the entire workflow (cancels all bound BPM tickets):
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"close_workflow","workflow_id":"<id>","confirm":true}'
```

完整参数与每个 action 的 preview / confirm 输出格式见对应 `references/<name>.md`。

## Parameters shared by all actions

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `action` | string | Yes | Action name (see the table above) |
| `target_addr` | string | No | Override the default `https://ent.tiktok-row.net` host (i18n staging only — never a BOE address) |

> ⚠️ 不同 workflow-相关 action 用了不同的参数名：`get_workflow` 收 `id`，而 `approve_workflow_owner_gate` / `advance_workflow_bpm_ticket` / `close_workflow` 收 `workflow_id`。这是按 "拿资源" vs "操作 workflow" 区分的；具体见 `references/workflows.md` 与 `references/schema_change.md`。

## URL Mapping Cheat-Sheet

| UI Page | Action to Use |
|--------|--------|
| `https://ent.tiktok-row.net/storage?mode=1` | `list_storages` |
| `https://ent.tiktok-row.net/storage_iac/detail?uri=...` | `get_storage` |
| `PUT /api/platform/v1/storage/<uri>/subscribe` (Subscribe button on storage detail) | `subscribe_storage` |
| `PUT /api/platform/v1/storage/<uri>/unsubscribe` (Unsubscribe button on storage detail) | `unsubscribe_storage` |
| `https://ent.tiktok-row.net/storage_iac/detail?activeTab=table&uri=...` | `list_entities` with `storage_uri=<uri>` |
| `https://ent.tiktok-row.net/storage_iac/detail?activeTab=dbSpec&uri=...` | `get_storage` (spec embedded in V3 storage detail) |
| `https://ent.tiktok-row.net/storage_iac/detail?syncNodeId=<src>->...&uri=<storage_uri>` | `get_storage_sync_channel_detail` (one edge) |
| `https://ent.tiktok-row.net/entity` | `list_entities` |
| `https://ent.tiktok-row.net/storage_schema/detail?uri=...` | `get_entity` |
| `PUT /api/platform/v1/entity/<uri>/subscribe` (Subscribe button on entity detail) | `subscribe_entity` |
| `PUT /api/platform/v1/entity/<uri>/unsubscribe` (Unsubscribe button on entity detail) | `unsubscribe_entity` |
| `https://ent.tiktok-row.net/workflow` | `list_workflows` |
| `POST /api/platform/openapi/v1/schema_change/list` (mode=1 PENDING_APPROVAL) | `list_pending_approval_workflows` |
| `POST /api/platform/openapi/v1/schema_change/list` (mode=2 RELATED_RESOURCE) | `list_related_resource_workflows` |
| `POST /api/platform/openapi/v1/rds/online_spec` | `get_rds_online_spec` |
| `https://ent.tiktok-row.net/storage_iac/detail?activeTab=workflow&uri=<storage_uri>` | `list_workflows` with `storage_uri=<uri>` |
| `https://ent.tiktok-row.net/entity/detail?uri=<entity_uri>` (Workflow tab) | `list_workflows` with `entity_uri=<uri>` |
| `https://ent.tiktok-row.net/workflow/detail/<id>` | `get_workflow` |
| `https://ent.tiktok-row.net/storage_schema/detail/edit_v3?uri=<entity_uri>` (DDL editor) | `validate_ddl_change` ⇒ `change_rds_table` (Path 2) |
| `https://ent.tiktok-row.net/storage_schema/detail/edit_v3?uri=<entity_uri>` (DDL editor + 手工改 entity 字段) | `change_rds_table_with_entity_edits` (Path 3) |
| `https://ent.tiktok-row.net/storage_schema/detail/edit_meta?uri=<entity_uri>` (RDS metadata-only edit) | `update_rds_entity` (Path 4) |
| `POST /api/platform/openapi/v1/rds/execute_ddl_sql` (RDS OpenAPI direct) | `execute_rds_ddl` (Path 1) |
| `POST /api/platform/openapi/v1/deployment/info` | `get_deployment_info` |
| `POST /api/platform/openapi/v1/deployment/cancel` | `cancel_deployment` |
| `POST /api/platform/v2/entity/precheck` | `precheck_entity` |
| `POST /api/platform/v2/entity/online_table/list` | `list_online_tables` (Path 5) |
| `POST /api/platform/v2/entity/online_table/import` | `import_online_table` (Path 5) |
| `https://ent.tiktok-row.net/workflow/detail/<id>` (Owner-approval gate) | `approve_workflow_owner_gate` |
| `https://ent.tiktok-row.net/workflow/detail/<id>` (Close Workflow button) | `close_workflow` |
| `https://bpm-i18n.tiktok-row.net/record/<ticket_id>` (BPM ticket bound to a workflow) | `advance_workflow_bpm_ticket` |

## Output Shape

Every call returns:

```json
{
  "success": true,
  "action": "<action>",
  "data": {
    "<echoed request params>": "...",
    "data": { "...": "real EMS payload" }
  }
}
```

On failure, `success` is `false`, `data` is `null`, and a human-readable `error` field is present.

### ⚠️ Important: EMS response envelope

All EMS APIs (including the `/sdp/v1/dts/*` proxied endpoints) return the HTTP body as a uniform envelope:

```json
{ "code": 0, "message": "", "data": { "...": "actual payload" } }
```

The skill forwards that entire `data` field to you **as-is (raw JSON)**. So to read the real returned object, always drill into `result.data.data` — not `result.data`. The outer `data` only echoes the request parameters for traceability, the real EMS payload is the inner `data`.

Typical fields inside the inner `data`:
- List APIs (`list_storages`, `list_entities`, `list_workflows`): `list` (array) + `page_info` (page_num / page_size / total). Some older endpoints use `items` / `total` at top-level of the inner data.
- Detail APIs (`get_storage`, `get_entity`, `get_workflow`): the resource object directly.
- `get_entity_online_ddl`: `ddl_list` keyed by vregion.
- `get_storage_sync_channel`: `edge_list` (array) + `intention_diff` + `config`.
- `get_storage_sync_channel_detail`: per-edge SDP detail — typically `lag` / `throughput` / `link` / `sub_tasks` (one entry per VDC inside src/dst VRegion). Forward-compat passthrough; do not rely on the exact shape.
