---
name: tea-query
description: Query TEA report information and data, including dashboards, reports, and report data. Use when the user mentions TEA, TEA dashboards, TEA reports, wants to list dashboards or query report data from TEA. Also trigger when the user provides a TEA URL or mentions querying DataFinder reports.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# TEA Query Skill

Query TEA-next dashboards / reports / data via two complementary auth modes:

| Mode | Auth | Surface | When to prefer |
|------|------|---------|----------------|
| `df_*` actions (default for new use) | Personal **JWT → Titan Passport cookie** (no setup beyond `gdpa-cli login`) | Datafinder web API (same one the browser hits) | Day-to-day analysis, multi-analysis-type charts (event / lifecycle / funnel / retention / ...), ad-hoc DSL, save chart |
| Legacy actions (`list_dashboards`, `query_report`, ...) | DataOpen `app_id` + `app_secret` (per-region, on-platform setup) | OpenAPI surface | Existing automations, server-to-server jobs |

> **When to Use**: Listing dashboards, inspecting reports, retrieving report data, running custom analyses, saving new charts. Both auth modes are supported in parallel — pick the one that matches your scenario.

## Recommended quick start (JWT mode — no extra setup)

```bash
# 1. Make sure you have a ByteCloud login (one-time per machine).
gdpa-cli login

# 2. List dashboards under a project
gdpa-cli run tea-query --session-id "$SESSION_ID" --input '{
  "action": "df_list_dashboards",
  "region": "sg",
  "project_id": 38036812,
  "simplified": true
}'

# 3. List the reports inside a specific dashboard (includes full DSL)
gdpa-cli run tea-query --session-id "$SESSION_ID" --input '{
  "action": "df_list_dashboard_reports",
  "region": "sg",
  "project_id": 38036812,
  "dashboard_id": "7605531897938051591"
}'

# 4. Query a report. Default = clone the report's stored DSL ("template mode")
gdpa-cli run tea-query --session-id "$SESSION_ID" --input '{
  "action": "df_query_report",
  "region": "sg",
  "project_id": 38036812,
  "dashboard_id": "7605531897938051591",
  "report_id": "7605875855121711624",
  "period": [{
    "granularity": "day",
    "type": "past_range",
    "spans": [
      {"type": "past", "past": {"amount": 7, "unit": "day"}},
      {"type": "past", "past": {"amount": 1, "unit": "day"}}
    ],
    "timezone": "UTC",
    "week_start": 1
  }],
  "filters": [],
  "groups": [],
  "timeout_seconds": 60
}'

# 5. Save a new chart (TWO-PHASE — first call returns preview, second call commits)
gdpa-cli run tea-query --session-id "$SESSION_ID" --input '{
  "action": "df_save_chart",
  "region": "sg",
  "project_id": 38036812,
  "dashboard_id": "7605531897938051591",
  "report_name": "新的事件分析",
  "report_type": "event_analysis",
  "report_id": "7605875855121711624"
}'
# After getting confirmation from the user, repeat with `confirm: true`.
```

## Supported actions

### JWT (Titan Passport) actions — recommended

#### `df_list_dashboards`
List dashboards under a project. Returns the same shape the TEA frontend uses.

- Required: `region`, `project_id`
- Optional: `dashboard_id` (focus list around this dashboard), `simplified` (boolean — return simplified rows)

#### `df_get_dashboard`
Get a single dashboard's detail (sheet layout, dashboard meta).

- Required: `region`, `project_id`, `dashboard_id`

#### `df_list_dashboard_reports`
List all reports inside a dashboard, including the **full `dsl_content`** for each report. Use this to discover what charts exist and to clone an existing DSL as a starting point.

- Required: `region`, `project_id`, `dashboard_id`
- Output: `summary` (per-report id/name/type/query_type) plus `reports_raw` (full server payload).

#### `df_get_report`
Fetch a single report's metadata + parsed DSL.

- Required: `region`, `project_id`, `report_id`
- Optional: `dashboard_id` (skip auto-discovery — significantly faster)

#### `df_query_report` ⭐ core query
Run an analysis. Two modes:

- **Template mode** (most common): pass `report_id` (and ideally `dashboard_id`). The skill clones the report's stored DSL and applies your overrides on top.
- **Raw DSL mode**: pass `dsl` directly (object or JSON string).

Required: `region`, `project_id` (+ one of `report_id` / `dsl`)

Optional overrides applied on top of the template DSL:

| Field | Effect |
|-------|--------|
| `period` | Overrides `dsl.periods` (object or array) |
| `global_filter` | Replaces `dsl.content.profile_filters[0]` |
| `profile_filters` | Replaces the entire `dsl.content.profile_filters` array |
| `query_type` | Switches `dsl.content.query_type` (e.g. `event` → `life_cycle`) |
| `queries` | Replaces `dsl.content.queries` wholesale (advanced) |
| `filters` | Overrides the **first query**'s `filters` (most common "narrow this chart" path) |
| `groups` | Overrides the **first query**'s `groups_v2` |
| `limit` / `chart_type` / `refresh_cache` | Patches `dsl.content.option.*` |
| `extra_overrides` | Top-level patch map (escape hatch) |
| `app_id` | Sets `dsl.app_ids` + `X-FINDER-APP-ID` header |
| `timeout_seconds` | Polling timeout for the async result (default 90s) |

The skill performs the asynchronous handshake automatically:

1. `POST /datafinder/api/v1/analysis` → `result_id`
2. Polls `GET /datafinder/api/v1/analysis/{result_id}/result` until `result_status` is no longer `RUNNING`
3. Returns the parsed payload + final `status`

#### `df_list_metadata_events` / `df_list_metadata_properties`
Quickly enumerate the events / properties available on a project so the LLM can suggest valid choices when a user wants to build a custom DSL.

- Required: `region`, `project_id`

#### `df_save_chart` ⚠ destructive — two-phase confirm
Persist a new report (chart) into a dashboard.

**Phase 1** — call without `confirm` (or `confirm: false`). The agent returns a `preview` block summarizing the request and `requires_confirm: true`. **The LLM/agent MUST relay this preview to the human and obtain explicit consent.**

**Phase 2** — call again with **identical params and `confirm: true`** to actually create the chart.

Required: `region`, `project_id`, `dashboard_id`, `report_name`, `report_type` (e.g. `event_analysis`, `lifecycle_analysis`)

Optional: `app_id`, `dsl` (raw mode) OR `report_id` (template mode), `extra` (additional fields merged into the body).

Common report_type / query_type pairs (observed):

| `report_type` | Inner `content.query_type` | Page path |
|---------------|----------------------------|-----------|
| `event_analysis` | `event` | `/event-analysis/<id>` |
| `lifecycle_analysis` | `life_cycle` | `/lifecycle-analysis/<id>` |
| `funnel_analysis` | `funnel` | `/funnel-analysis/<id>` |
| `retention_analysis` | `retention` | `/retention-analysis/<id>` |
| `distribution_analysis` | `distribution` | `/distribution-analysis/<id>` |

If unsure, list the dashboard's reports first (`df_list_dashboard_reports`) and copy the existing `report_type`.

### Legacy OpenAPI actions

These remain unchanged for back-compat. They require `app_id` + `app_secret` (set via `gdpa-cli tea credential set --region <region>`).

- `list_dashboards`
- `get_dashboard`
- `list_reports`
- `query_report` (with `global_filter`, `profile_filters`, `period`, `skip_period_indexes`, `param_filters`, `property_logic`, `replace_info`)
- `get_report_in_dashboard`

When the OpenAPI mode is missing credentials, the agent returns structured `setup_required` fields pointing to the DataOpen credential page for the region.

## Typical workflows

### Inspect & query an existing chart (JWT mode)

```text
1. df_list_dashboards (region, project_id)             → pick dashboard_id
2. df_list_dashboard_reports (… dashboard_id)          → pick report_id, observe report_type
3. df_query_report (… dashboard_id, report_id, period) → run with date / filter overrides
```

### Custom analysis on the fly

```text
1. df_list_metadata_events (region, project_id)        → discover event names
2. Build a minimal `dsl` object (or take an existing report as template)
3. df_query_report (… dsl: {...})                      → returns trace + data items
```

### Save a chart (with mandatory user confirmation)

```text
1. df_query_report (… preview your DSL)
2. df_save_chart (… preview only, no confirm)          → relay preview to user
3. df_save_chart (… confirm: true)                     → only after explicit user "go ahead"
```

## Region mapping

| Region | API base | Login site |
|--------|----------|------------|
| `cn` | `data.bytedance.net` | `login.CN` (`gdpa-cli login`) |
| `sg` | `tea-captain.tiktok-row.net` | `login.I18N` (`gdpa-cli login --site i18n`) |

JWT mode uses the same Titan Passport cookie flow as the Aeolus skill: a personal ByteCloud JWT is exchanged for a `titan_passport_id` cookie scoped to the TEA host. The cookie is cached in-process for ~30 minutes.

## Required authentication

### JWT mode (default for new actions)

Just run `gdpa-cli login` (and `gdpa-cli login --site i18n` if you query the SG region). No per-region credential file is needed.

### OpenAPI mode (legacy)

For `list_dashboards`, `query_report`, etc., set up DataOpen credentials per region:

```bash
gdpa-cli tea credential set --region sg
```

CN credentials page: <https://data.bytedance.net/dataopen/tea-next/app>
SG credentials page: <https://tea-captain.tiktok-row.net/dataopen/tea-next/app>

## Notes / gotchas

- `df_save_chart` ALWAYS requires explicit `confirm: true` to actually write. Treat the preview output as a contract you must show the user.
- `df_query_report` polls the async result endpoint; long-running queries should pass `timeout_seconds` ≥ the expected wait.
- `report_id` and `dashboard_id` accept either integer or string — both are normalized.
- Numeric ids in the JSON output may exceed JavaScript safe-integer range; downstream tooling should treat them as strings.
- The OpenAPI surface is throttled to 5 QPS. If you only need to read data, prefer `df_*` actions, which run on the higher-limit web surface.
