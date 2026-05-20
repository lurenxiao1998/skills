# EMS · Storage actions

`list_storages`、`get_storage`、`update_storage_owners`、`sync_rds_owner`、`subscribe_storage`、`unsubscribe_storage`。先读 `SKILL.md` 拿全局 region / output envelope 约定，再回到这里。

`update_storage_owners` 与 `sync_rds_owner` 是 storage 组里的两个传统二段式写动作；`subscribe_storage` / `unsubscribe_storage` 是单发幂等写动作（**不走** preview/confirm，见下面对应章节）；schema-change / workflow 相关的写动作（`change_rds_table` / `change_rds_table_with_entity_edits` / `execute_rds_ddl` / `approve_workflow_owner_gate` / `advance_workflow_bpm_ticket` / `close_workflow`）见 `references/schema_change.md`。

## `list_storages`

List V2 + V3 storages. Maps to `GET /api/platform/v3/storage`.

> ⚠️ To list storages **owned by a specific user**, use `mode=2` — the backend filters by the JWT user automatically. **Do NOT pass a free-form `owner` param.** Skill defaults to `mode=2` ("my storages") and echoes the resolved `query_user` in the response.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `mode` | int | Defaulted to `2` | `1`=all visible storages, `2`=only storages owned by the JWT user (= "my storages"), `3`=subscribed. **Backend requires this field.** |
| `storage_uri` | string | No | Fuzzy match on storage URI (use `exact=true` for exact match) |
| `psm` | string | No | Filter by PSM inside the storage's `idcinfos` |
| `type` | int | No | `ResourceType` enum. `1`=MYSQL, `2`=ABASE, `3`=BYTEDOC, ... |
| `exact` | bool | No | Whether `storage_uri` / `psm` must match exactly |
| `page_num` | int | No | Default `1` |
| `page_size` | int | No | Default `20` |

Examples:

```bash
# my storages — owner mode (default)
gdpa-cli run ems --session-id "$SESSION_ID" --input '{"action":"list_storages"}'

# fuzzy match on storage URI
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "list_storages",
  "mode": 1,
  "storage_uri": "new_one_rds"
}'
```

## `get_storage`

Get storage detail by URI. Maps to `GET /api/platform/v2/storage/:uri`.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | Storage URI, e.g. `tiktok/mysql/new_one_rds` |

Returned `data` includes the storage's `spec`, `topology`, `meta`, and owner info — there is no separate topology action.

```bash
gdpa-cli run ems --session-id "$SESSION_ID" --input '{
  "action": "get_storage",
  "uri": "tiktok/mysql/new_one_rds"
}'
```

## `update_storage_owners` (write)

Modify a storage's `owners` list (add / remove users). The change is applied immediately when confirmed; it does **not** require any separate owner/admin approval step (this is the only write action in the skill that auto-completes — schema-change writes always go through a workflow).

> **Two-phase safety posture** (matches `tcc-deploy`): the action **defaults to preview-only**. Pass `confirm=true` explicitly to apply the change.
>
> - `confirm` unset / `false` → return a diff (before / after / added / removed / skipped), do NOT touch the backend write API
> - `confirm=true` → re-issue the full storage wrapper with **only** the `owners` field mutated, everything else preserved byte-for-byte. Optimistic concurrency is enforced via a hash of the latest schema — if someone else publishes a schema change concurrently the call returns a CAS conflict and the skill surfaces it.

**Authorization** — the skill enforces ownership client-side before touching the API: the JWT-derived current user must already be in `owners`, otherwise the call is rejected with `AUTH-005 AuthPermissionDenied`. The EMS backend only checks JWT + CAS, not ownership, so this gate lives here.

**Safeguards**

- Empty resulting owners → refused (`INPUT-002`, "refuse to orphan the storage")
- `add_owners` / `remove_owners` both empty → refused (`INPUT-002`, at least one change required)
- Adding a user already in `owners` → reported in `skipped`, not `added`
- Removing a user not in `owners` → reported in `skipped`, not `removed`
- Resulting owners identical to current (e.g. only skips) → returns `no_change=true` and does NOT call the write API, even with `confirm=true`

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | Storage URI, e.g. `tiktok/mysql/new_one_rds` |
| `add_owners` | []string or csv | No | Users to add. Skipped if already present. |
| `remove_owners` | []string or csv | No | Users to remove. Skipped if not present. |
| `confirm` | bool | No | Default `false` (preview). Pass `true` to apply the change. |

### When talking to the user (agent guidance)

When an agent uses this action and needs to show the diff or ask the user to confirm, it MUST paraphrase in user-visible terms. Do **not** leak the backing API name (`StorageFastRelease` / `fast_release`) or the internal concurrency fields (`previous_hash_version`, `hash_version`) into confirmation prompts or success messages. Concretely:

- Preview → "Here is the owner change I will make. Apply it?"
- Confirmation result → "Owner change applied." (don't say "workflow submitted, waiting for approval" — the change auto-completes with no approval step.)
- Workflow conflict → "Another open workflow on this storage is blocking this change. Approve or cancel it at `<workflow_url>`, then retry."

The fields `previous_hash_version`, `fast_release_code`, `fast_release_message`, `fast_release_data` are kept in the structured response for programmatic consumers (and debugging) — they should not be surfaced verbatim to end users.

### Response (preview mode)

```json
{
  "success": true,
  "action": "update_storage_owners",
  "data": {
    "uri": "tiktok/mysql/new_one_rds",
    "storage_type": "mysql",
    "current_user": "alice",
    "before_owners": ["alice", "bob"],
    "after_owners":  ["alice", "carol"],
    "added":   ["carol"],
    "removed": ["bob"],
    "skipped": [],
    "previous_hash_version": "10143624707",
    "published": false,
    "confirm_required": true,
    "next_steps": ["re-run with confirm=true to apply this owner change"]
  }
}
```

### Response (confirm mode)

Same payload, plus `"published": true`. `fast_release_code` / `fast_release_message` / `fast_release_data` mirror the EMS response envelope for debugging but should not be surfaced verbatim to users.

### Response (workflow conflict)

The backend rejects the write with business code `-703` when another schema-change workflow for the same storage is still open (pending approval or execution). The skill surfaces this as a structured failure: `success=false` with a `conflict` block pointing at the blocking workflow, so the user can jump directly to the UI to approve or cancel it and then retry.

```json
{
  "success": false,
  "action": "update_storage_owners",
  "error": "[API-004] update_storage_owners: cannot apply owner change to \"tiktok/mysql/new_one_rds\" — another open workflow (id=190570023683) is blocking it: https://ent.tiktok-row.net/workflow/detail/190570023683",
  "data": {
    "uri": "tiktok/mysql/new_one_rds",
    "before_owners": ["alice", "bob"],
    "after_owners":  ["alice", "bob", "carol"],
    "added":   ["carol"],
    "removed": [],
    "skipped": [],
    "previous_hash_version": "10143624707",
    "published": false,
    "conflict": {
      "type": "workflow_conflict",
      "workflow_id": "190570023683",
      "workflow_url": "https://ent.tiktok-row.net/workflow/detail/190570023683",
      "message": "ems api error (code=-703): workflow conflict, id: 190570023683 exists open workflow",
      "blocking_reason": "Another open workflow on this storage is blocking further changes; this owner update cannot be applied until that workflow is approved or cancelled."
    },
    "next_steps": ["Open https://ent.tiktok-row.net/workflow/detail/190570023683 to approve or cancel the blocking workflow, then retry this owner change."]
  }
}
```

### Examples

```bash
# 1. Preview a change — diff-only, never publishes.
gdpa-cli run ems --input '{
  "action": "update_storage_owners",
  "uri": "tiktok/mysql/new_one_rds",
  "add_owners": ["carol"],
  "remove_owners": ["bob"]
}'

# 2. Actually publish after inspecting the preview above.
gdpa-cli run ems --input '{
  "action": "update_storage_owners",
  "uri": "tiktok/mysql/new_one_rds",
  "add_owners": ["carol"],
  "remove_owners": ["bob"],
  "confirm": true
}'
```

## `sync_rds_owner` (write)

Sync the RDS-side owners of a MySQL storage **into** the storage's `owners` list. Maps to `POST /api/platform/openapi/v1/storage/sync_rds_owner` on the EMS platform_api. Two-phase by default — preview returns the diff, `confirm=true` publishes the merged owners via the same `fast_release` path used by `update_storage_owners`.

> **Append-only**: this endpoint never removes owners from the storage. `removed` in the result envelope is always `[]`, even when the storage has owners that no longer exist on the RDS side. Owners that exist on the storage but are missing from RDS are kept as-is. If the user actually needs to **drop** an owner, route them to `update_storage_owners` with `remove_owners` instead.

> ### ⚠️ Strict re-confirmation gate (this action only)
>
> `sync_rds_owner` is the only EMS action that requires an **explicit, per-call** user re-confirmation between preview and apply. Even when the user's phrasing already sounds decisive — "帮我同步 RDS owner" / "sync the owner now" / "apply the sync to storage X" — the agent **MUST**:
>
> 1. Call `sync_rds_owner` with `confirm:false` (or omit `confirm`) to render the preview diff (`before_owners` / `after_owners` / `added` / `removed` / `skipped`).
> 2. Surface that diff to the user and **stop**, waiting for an explicit consent reply such as "同意 / 确认 / apply / yes / go ahead". A re-statement of the original intent does NOT count as consent.
> 3. Only after that explicit consent, re-issue the call with `confirm:true`.
>
> Hard rules:
>
> - Do **NOT** send `confirm:true` on the first call.
> - Do **NOT** chain preview → apply inside a single agent turn, even if `no_change=false` and there are no conflicts.
> - Do **NOT** treat earlier "sync the owner" phrasing, repeated retries ("重新尝试同步"), or "帮我同步" as standing consent. Each apply needs its own fresh consent immediately after a fresh preview.
> - If `no_change=true` in the preview (RDS owners already a subset of storage owners), do not ask for confirmation — just report "RDS owners are already in sync; no change needed."
>
> Scope: this gate applies to `sync_rds_owner` only. Other EMS write actions (`update_storage_owners`, `change_rds_table`, `approve_workflow_owner_gate`, `advance_workflow_bpm_ticket`, `close_workflow`) keep the standard two-phase preview/apply convention without the per-call re-confirmation requirement.

This is a thin wrapper around the server-side endpoint: the backend resolves the RDS owners (via `EMSStorageService.GetRDSOwnersByStorage`), merges them into the storage's existing `owners`, and (when confirmed) republishes the storage with `Owners = afterOwners`. The skill itself only validates inputs and reshapes the result envelope — there is no client-side owner computation.

> **When to pick this over `update_storage_owners`**
>
> - Use `sync_rds_owner` when the user wants to **pull in** the upstream RDS owners onto the storage (e.g. "把 RDS 的 owner 同步到 storage")。Single call, no need to enumerate names. Append-only — does NOT strip owners that already exist on the storage but are missing from RDS.
> - Use `update_storage_owners` when the user wants to add or **remove** specific named users (whether or not they are on the RDS side). `sync_rds_owner` cannot remove owners.

> **Server-side rules** (enforced by ent_mono, NOT by the skill):
>
> - Only `mysql` storages are supported. Non-MySQL URIs are rejected with an INPUT-002-style error.
> - Caller must already be **either** a storage owner **or** an existing rds owner. If neither, the call fails with `AUTH-005 AuthPermissionDenied`.
> - Blocked when an open schema-change workflow exists on the storage. The skill surfaces this as the same `conflict` block emitted by `update_storage_owners` (workflow URL + blocking reason).
> - When the RDS owners are already a subset of the storage owners (no diff), the action returns `no_change=true` and skips the write — even with `confirm=true`.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | Storage URI, e.g. `tiktok/mysql/new_one_rds`. Must be a MySQL storage. |
| `confirm` | bool | No | Default `false` (preview). Pass `true` to apply the merge. |

### When talking to the user (agent guidance)

Same paraphrasing rules as `update_storage_owners` — do not leak `fast_release` / `previous_hash_version` / `EMSStorageService.GetRDSOwnersByStorage` into prompts:

- Preview → "Here are the RDS owners I'll sync into this storage. Apply it?"
- Confirmation result → "RDS owners synced into the storage." (auto-completes; do not say "workflow submitted, waiting for approval".)
- No diff → "RDS owners are already in sync with this storage; no change needed."
- Workflow conflict → "Another open workflow on this storage is blocking this change. Approve or cancel it at `<workflow_url>`, then retry."

The fields `previous_hash_version`, `fast_release_code`, `fast_release_message`, `fast_release_data` are kept in the structured response for programmatic consumers (and debugging) — they should not be surfaced verbatim to end users.

### Response (preview mode)

```json
{
  "success": true,
  "action": "sync_rds_owner",
  "data": {
    "display_action": "Sync RDS Owners",
    "uri": "tiktok/mysql/new_one_rds",
    "storage_type": "mysql",
    "current_user": "alice",
    "before_owners": ["alice", "bob"],
    "after_owners":  ["alice", "bob", "carol"],
    "added":   ["carol"],
    "removed": [],
    "skipped": [],
    "previous_hash_version": "10143624707",
    "published": false,
    "confirm_required": true,
    "next_steps": ["re-run with confirm=true to sync these RDS owners into the storage"]
  }
}
```

### Response (confirm mode)

Same payload, plus `"published": true` and a `next_steps` array confirming the sync. `fast_release_code` / `fast_release_message` / `fast_release_data` mirror the EMS response envelope for debugging but should not be surfaced verbatim to users.

### Response (workflow conflict)

Same shape as `update_storage_owners` — the `conflict` block carries the blocking workflow's id + URL and `next_steps` points at the EMS workflow detail page. The error string carries `[API-004] sync_rds_owner: ...` so callers can recognise which write was rejected.

### Examples

```bash
# 1. Preview the RDS-owner sync — diff-only, never publishes.
gdpa-cli run ems --input '{
  "action": "sync_rds_owner",
  "uri": "tiktok/mysql/new_one_rds"
}'

# 2. Apply the sync after inspecting the preview above.
gdpa-cli run ems --input '{
  "action": "sync_rds_owner",
  "uri": "tiktok/mysql/new_one_rds",
  "confirm": true
}'
```

## `subscribe_storage` (write, single-shot) / `unsubscribe_storage` (write, single-shot)

Add or remove the current JWT user from a storage's subscriber list. Maps to:

- `PUT /api/platform/v1/storage/{uri}/subscribe`
- `PUT /api/platform/v1/storage/{uri}/unsubscribe`

After subscribing, the storage shows up in `list_storages mode=3` (subscribed). Unsubscribing reverses that. The pair is the API counterpart of the **Subscribe / Unsubscribe** button on the storage detail page in the EMS UI.

> **⚠️ Single-shot exception** — unlike `update_storage_owners` and `sync_rds_owner`, these two actions **do NOT** use the two-phase preview/confirm flow. They go straight to PUT. This is a deliberate divergence from the rest of the storage write actions because:
>
> - Both endpoints are **idempotent** on the backend. Subscribing twice is a no-op; unsubscribing twice is a no-op. Re-running cannot corrupt state.
> - The operation is **trivially reversible** by one call of the opposite action — a misfired `subscribe_storage` is undone by exactly one `unsubscribe_storage`.
> - There is **no CAS / hash-version**, **no workflow conflict** to surface, and **no permission coordination** — any user who can see the storage is allowed to (un)subscribe themselves.
>
> Forcing a preview gate here would add friction with no correctness benefit. If you find yourself wanting to add a confirm step, prefer a one-line user-visible "I'll subscribe you to <uri>" statement before the call instead of changing the action contract.

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `uri` | string | Yes | Storage URI, e.g. `tiktok/mysql/new_one_rds`. URL-escaping is handled by the client; pass it un-escaped. |

### Response (success)

```json
{
  "success": true,
  "action": "subscribe_storage",
  "data": {
    "uri": "tiktok/mysql/new_one_rds",
    "kind": "storage",
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

- `subscribed` reflects the **target state AFTER the call** (always `true` for `subscribe_storage`, always `false` for `unsubscribe_storage`). Because the backend is idempotent, this is the documented contract whether or not the user was already in (or out of) the subscriber list.
- `current_user` is the JWT-derived username (falls back to "unknown" rather than failing the call when it cannot be resolved). Use it when phrasing the user-facing reply: "已为 alice 订阅 tiktok/mysql/new_one_rds".
- `kind` / `operation` are constant per-action — agents that consume the four subscribe/unsubscribe actions through a single code path can branch on them without re-discovering field names per RPC.
- Inner `data` is the EMS envelope's `data` field forwarded verbatim. Currently `null` for both endpoints; preserved for forward compatibility.

### Examples

```bash
# Subscribe to a storage — single shot, no confirm step.
gdpa-cli run ems --input '{
  "action": "subscribe_storage",
  "uri": "tiktok/mysql/new_one_rds"
}'

# Verify it shows up in the subscribed list.
gdpa-cli run ems --input '{
  "action": "list_storages",
  "mode": 3
}'

# Unsubscribe.
gdpa-cli run ems --input '{
  "action": "unsubscribe_storage",
  "uri": "tiktok/mysql/new_one_rds"
}'
```

### When talking to the user (agent guidance)

- Subscribe → "已为 `<current_user>` 订阅 `<uri>`，可在 `list_storages mode=3` 看到。"
- Unsubscribe → "已为 `<current_user>` 取消订阅 `<uri>`。"
- Idempotent retry → No special phrasing needed; the operation is a no-op so it's safe to omit. If the user explicitly asks ("再订阅一次会怎样？"), confirm that the backend treats it as a no-op.

## `get_rds_online_spec`

Read-only. Query the **live runtime spec** of an RDS storage across one
or more vregions. Mirrors what the EMS UI shows on the storage detail
"DB Spec" tab, but pulls from the live RDS source-of-truth instead of
the EMS metadata catalog — so the result reflects the actual deployed
DB (engine, sharding state, capacity, slow-query kill thresholds, owners
& auth lists, importance / security level). Backed by
`POST /api/platform/openapi/v1/rds/online_spec` →
`tiktok_ems_openapi_v2.RdsLoadGlobalSot`.

> RDS / MySQL storages only — non-RDS storages are rejected outright.

### 参数

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `storage_uri` | string | One of these | Direct URI, fastest path. Mutually compatible with `rds_uri` (alias). |
| `rds_uri` | string | One of these | Same as `storage_uri`; provided for compatibility with the change_rds_table family. |
| `rds_psm` | string | One of these / override | Either resolves the storage by PSM (when `storage_uri` is unset) OR — when `storage_uri` IS set — overrides the per-vregion PSM derivation (every vregion is queried with this PSM). |
| `vregions` | []string or csv | No | Narrow the query to specific vregions. When omitted, defaults to **all production vregions** in the storage's `idcinfos[]`. |

### vregion → psm 解析规则

1. `rds_psm` (top-level) wins for every vregion when set — used to be a
   "best-effort PSM" escape hatch (see notes below).
2. Otherwise: per-vregion mapping derived from
   `GetStorage.idcinfos[]`, treating each entry's `idc` field as a VDC
   code that resolves to a single canonical vregion.
3. **No silent fallback.** If a requested vregion has no per-vregion
   PSM in `idcinfos` and no `rds_psm` override is provided, the action
   errors with `cannot resolve PSM for vregion(s) [...]`. RDS PSMs are
   region-specific (`...mysql.foo_sg` ≠ `...mysql.foo_us`), so guessing
   would produce confusing per-vregion backend errors — an explicit
   override is safer.

### 返回字段

```json
{
  "storage_uri": "tiktok/mysql/new_one_rds",
  "psm": "tiktok.mysql.new_one_rds",
  "requests": [
    {"vregion": "Singapore-Central", "psm": "toutiao.mysql.new_one_rds_sg"},
    {"vregion": "US-East",           "psm": "toutiao.mysql.new_one_rds_us"}
  ],
  "specs_by_vregion": {
    "Singapore-Central": {
      "vregion": "Singapore-Central",
      "psm": "toutiao.mysql.new_one_rds_sg",
      "engine": "InnoDB",
      "wqps": 1200,
      "rqps": 4500,
      "capacity_gb": 100,
      "is_sharding": false,
      "importance_level": "Normal",
      "security_level": "L3",
      "creator": "alice",
      "cooperators": ["bob","carol"],
      "biz_psm_read":  ["toutiao.foo.read"],
      "biz_psm_write": ["toutiao.foo.write"],
      "user_read":     ["alice"],
      "user_write":    ["bob"],
      "slow_query_kill_config": {"master": 60, "slave": 60}
    }
  },
  "data": { /* full backend envelope: {success, specs:[...]} */ }
}
```

`specs_by_vregion` is the flattened convenience view (one entry per
vregion, keyed for O(1) lookup). For any field not in the table above,
fall back to `data.specs[i]`.

### 用法示例

```bash
# All vregions of an RDS storage
gdpa-cli run ems --input '{
  "action": "get_rds_online_spec",
  "storage_uri": "tiktok/mysql/new_one_rds"
}'

# Narrow to two vregions
gdpa-cli run ems --input '{
  "action": "get_rds_online_spec",
  "storage_uri": "tiktok/mysql/new_one_rds",
  "vregions": ["Singapore-Central", "US-East"]
}'

# Resolve storage by PSM
gdpa-cli run ems --input '{
  "action": "get_rds_online_spec",
  "rds_psm": "toutiao.mysql.new_one_rds_sg"
}'

# Force a single PSM for every vregion (rare; used when idcinfos is
# stale or the user knows the canonical PSM directly)
gdpa-cli run ems --input '{
  "action": "get_rds_online_spec",
  "storage_uri": "tiktok/mysql/new_one_rds",
  "vregions": ["US-East"],
  "rds_psm": "toutiao.mysql.new_one_rds_us"
}'
```
