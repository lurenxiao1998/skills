# EMS · Storage actions

`list_storages`、`get_storage`、`update_storage_owners`、`sync_rds_owner`。先读 `SKILL.md` 拿全局 region / output envelope 约定，再回到这里。

`update_storage_owners` 与 `sync_rds_owner` 是 storage 组里的两个写动作；schema-change / workflow 相关的写动作（`create_schema_change` / `approve_workflow_owner_gate` / `advance_workflow_bpm_ticket` / `close_workflow`）见 `references/schema_change.md`。

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
    "next_step": "re-run with confirm=true to apply this owner change"
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
    "next_step": "Open https://ent.tiktok-row.net/workflow/detail/190570023683 to approve or cancel the blocking workflow, then retry this owner change."
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
> Scope: this gate applies to `sync_rds_owner` only. Other EMS write actions (`update_storage_owners`, `create_schema_change`, `approve_workflow_owner_gate`, `advance_workflow_bpm_ticket`, `close_workflow`) keep the standard two-phase preview/apply convention without the per-call re-confirmation requirement.

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
    "next_step": "re-run with confirm=true to sync these RDS owners into the storage"
  }
}
```

### Response (confirm mode)

Same payload, plus `"published": true` and `next_step` confirming the sync. `fast_release_code` / `fast_release_message` / `fast_release_data` mirror the EMS response envelope for debugging but should not be surfaced verbatim to users.

### Response (workflow conflict)

Same shape as `update_storage_owners` — the `conflict` block carries the blocking workflow's id + URL and `next_step` points at the EMS workflow detail page. The error string carries `[API-004] sync_rds_owner: ...` so callers can recognise which write was rejected.

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
