# Aeolus — Dashboard Chart Queries

This module is for **Aeolus dashboards**: list a dashboard's charts and
filters, fetch the data of a single chart, or on-demand look up the candidate
values for a multi-select filter. It does NOT run ad-hoc SQL — see
[query_editor.md](./query_editor.md) for that.

Authentication: Titan Passport via the user's ByteCloud JWT. Run `gdpa-cli login`
once; no extra credential setup needed.

## How a dashboard sheet is actually queried

Important mental model — there is **no single combined SQL** for a sheet, even
though the URL looks like one resource:

- The browser opens the sheet → fires **N independent POSTs**, one per chart,
  to `/aeolus/vqs/api/v2/vizQuery/query?reportId=<chart_id>`. Each request
  carries that chart's own `dataSetId`, `dimMetList`, `groupByIdList`,
  `whereList`, and a copy of the dashboard chip filters that target this
  chart. The server compiles **one ClickHouse SQL per request**.
- Different charts on the same sheet routinely use different datasets,
  different dimensions, and different aggregations — they cannot be merged.
- The dashboard "page-level" filter chips (sticky header) are **not** stored
  in any chart's saved schema. The frontend takes the chip's current value
  and **inlines it into every chart's `whereList`** whose `reportId` appears
  in the chip's `chartIDs` list, then sends that per-chart request.

Consequences for this skill:

- `query_report` is the unit of execution — there is no "query whole sheet"
  call. To summarize a dashboard, the model loops `query_report` over every
  reportId from `get_dashboard`.
- A bug in how we encode one chart's `whereList` only breaks **that chart**;
  sibling charts on the same sheet can still succeed with the same chip
  filter. The [measure-as-filter pitfall](#measure-as-filter-pitfall) below
  is one example of this kind of single-chart breakage.
- Latency adds up linearly. If you only need 2 charts out of 12, query just
  those 2; do not pre-fetch the whole sheet.

## Actions

All dashboard actions accept optional `http_timeout_ms` to override the
underlying HTTP timeout. Use it for slow networks or large chart queries, for
example `120000` for 120 seconds.

### `get_dashboard` — list charts and filters

Use this **first** when the user gives you a dashboard URL and wants to know
what's available before drilling in. This call is cheap — it returns schemas
only and does NOT fan out to fetch candidate values.

| Param | Required | Notes |
|-------|---------|-------|
| `dashboard_url` | one of url/(id+sheet) | Will auto-extract `dashboard_id`, `app_id`, `sheet_id`, `region` |
| `dashboard_id` | one of url/(id+sheet) | Numeric dashboard ID |
| `sheet_id` | required if no url | Numeric sheet ID |
| `app_id` | optional | Will fall back to dashboard metadata |
| `region` | optional | `cn` (default), `sg`, `va`, `ttp` — auto-set from URL host |

```bash
gdpa-cli run aeolus --input '{
  "action": "get_dashboard",
  "dashboard_url": "https://data.bytedance.net/aeolus/pages/dashboard/1421544?appId=1008589&sheetId=1960002"
}'
```

Output highlights:

- `sheets[]`: every tab on the same dashboard — `{sheet_id, name, sheet_order, current, url}`.
  The `dashboardAndSheet` API returns the full list with one round trip, so you
  can switch tabs by re-issuing `get_dashboard` with another `sheet_id` instead
  of asking the user for the URL of every tab.
- `reports[]`: `{#, reportId, name, displayType}` — show this list to the user.
- `filters[]`: each filter's `name`, `filter_type`, `default_value`, `scope`,
  `report_count`, and `has_candidates` (true for `multi_select` with a known
  field expression). Candidate values are NOT included — fetch them lazily with
  `get_filter_candidates`.

  `scope` distinguishes filter shapes:
  - `global` — chart-level filter present on every report on this sheet.
  - `report` — chart-level filter present on a subset of reports.
  - `dashboard` — dashboard-page-level filter chip (sticky header). Carries an
    extra `chart_ids` listing which reports the dashboard runtime applies it
    to. `query_report` auto-injects this chip's value into the whereList for
    any matching report — overriding works the same way as a chart filter.

- `task_id`: opaque, reused internally — no need to surface it.
- `hint`: short next-step instruction.

### `get_filter_candidates` — fetch candidate values on demand

Call only for a specific filter the user cares about, not preemptively for all
filters. Results are scoped to the dashboard's current filter context (defaults
plus anything you pass via `filters`), so you get options that are actually
selectable, not the global set.

| Param | Required | Notes |
|-------|---------|-------|
| `dashboard_url` or `dashboard_id`+`sheet_id` | yes | Same as `get_dashboard` |
| `filter_name` | yes | Must match a filter from `get_dashboard`'s `filters[].name` |
| `filters` | optional | Current context for other filters (e.g. `{"p_date": "2026-04-12"}`). The target filter's own value is intentionally ignored so it doesn't constrain its own candidates. |

```bash
gdpa-cli run aeolus --input '{
  "action": "get_filter_candidates",
  "dashboard_url": "https://data.bytedance.net/aeolus/pages/dashboard/1421544?appId=1008589&sheetId=1960002",
  "filter_name": "project",
  "filters": {"p_date": "2026-04-12"}
}'
```

Output: `{filter_name, filter_type, candidates[], context_used, ...}`.
`context_used=true` means the returned set was scoped by the dashboard's
filter context; `false` means the API fell back to the global dimension set
(e.g. because no owning report could be resolved).

### `query_report` — fetch one chart's data

Call this after `get_dashboard` (or when the user already knows which chart).

| Param | Required | Notes |
|-------|---------|-------|
| `dashboard_url` or `dashboard_id`+`sheet_id` | yes | Same as `get_dashboard` |
| `report_id` **or** `report_name` | yes | `report_name` accepts fuzzy substring; an exact match wins |
| `filters` | optional | `map<filter_name, value>` to override the chart's where clauses or any matching dashboard-level chip filter (the runtime injects them automatically — see [Dashboard-level chip filters](#dashboard-level-chip-filters) below). Names are case-sensitive for chart filters; dashboard chip names accept either the chip display name (e.g. `"Skills 批量标记"`) or the dim_met name shown in the injected whereList (e.g. `"批量标记"`). Use `get_dashboard` / `get_filter_candidates` to discover names. See [Filter override shapes](#filter-override-shapes) for value formats. |
| `params` | optional | `map<param_name, value>` to override **dashboard-level parameters** (the top parameter panel of the dashboard, distinct from per-chart where filters). |
| `dynamic_fields` | optional | `map<dynamicPillId, fieldId or [fieldId...]>` to pick which concrete dimension a dynamic-pill placeholder resolves to (the UI switcher like "按 OS 拆 / 按机房拆"). Pill ids are exposed as `dynamic...` placeholders in the chart schema. |
| `date` | optional | Backward-compat shortcut. **Scoped to the target report only** — overrides the first date filter defined on that chart; no effect on sibling charts. Prefer explicit `filters` when the dashboard has multiple date filters. |
| `dry_run` | optional (bool) | When `true`, build the query body and return it as `request_preview` **without sending any network request**. Use to verify your overrides (whereList / paramList / groupByIdList) before paying for a real query. |

#### Filter override shapes

The `filters` map accepts three shapes per key — pick the one that matches
what the chart's filter expects:

| Shape | Example | Effect |
|-------|---------|--------|
| plain string | `{"p_date": "2026-04-12"}` | single value; for `date` filters acts as `between [day, day]` |
| range string | `{"p_date": "2026-04-01,2026-04-12"}` | for `date` filters → `between` |
| array | `{"os": ["android", "ios"]}` | for `multi_select` filters → `in` |
| structured | `{"date": {"op":"lastSync","val":[7]}}` | advanced — explicit `op` / `val[ / valOption]`. Supports `lastSync` (relative windows), `between`, `in`, `not in`, `!=`, etc. |

```bash
gdpa-cli run aeolus --input '{
  "action": "query_report",
  "dashboard_url": "https://aeolus-va.tiktok-row.net/pages/dashboard/404168?appId=1002298&sheetId=453043",
  "report_name": "首帧时长-PCT50 (ms)",
  "filters": {"date": {"op":"lastSync","val":[7]}}
}'
```

#### Dashboard-level chip filters

Some dashboards expose filter chips in a sticky header above the charts (e.g.
"Skills 批量标记", "OS 选择"). These are **not** part of any chart's saved
schema — the dashboard runtime injects them into every chart whose `reportId`
appears in the chip's `chartIDs` list. `get_dashboard` surfaces them in
`filters[]` with `scope: "dashboard"` and the `chart_ids` they target.

For `query_report`, the agent does the same injection automatically:

- For any chip whose `chart_ids` include the target report, an entry is added
  to the constructed whereList using the chip's default value (`val`/`op` from
  the dashboard payload), so the result matches what the dashboard renders out
  of the box.
- Override the chip exactly like a chart filter — pass either the chip name
  (`"Skills 批量标记"`) or the underlying dim_met name (`"批量标记"`) as the
  key in `filters`. Both case-insensitive.
- Charts whose `reportId` is **not** in the chip's `chart_ids` are not affected
  — the chip is silently skipped, matching dashboard UI behavior.

```bash
# Inspect: dashboard 575500 / sheet 周大盘数据 has a "Skills 批量标记" chip
gdpa-cli run aeolus --input '{
  "action": "get_dashboard",
  "dashboard_url": "https://aeolus-sg.tiktok-row.net/aeolus/pages/dashboard/575500?appId=801869&sheetId=673674"
}'
# → filters[] contains {name: "Skills 批量标记", scope: "dashboard", chart_ids: [...]}

# Apply chip = false (exclude batch calls); auto-injected, no chart-level filter needed
gdpa-cli run aeolus --input '{
  "action": "query_report",
  "dashboard_url": "https://aeolus-sg.tiktok-row.net/aeolus/pages/dashboard/575500?appId=801869&sheetId=673674",
  "report_id": 2127002,
  "filters": {"批量标记": "false"}
}'
```

`get_filter_candidates` works on dashboard chips too: `filter_name` accepts
the chip display name and returns the chip's distinct values via dimSuggest.

#### `dry_run` — preview the request body without querying

Highly recommended whenever you're building a complex override (new `params`,
multiple `filters`, `dynamic_fields`) and want to double-check before firing
the real query. Returns `request_preview` with the exact `whereList` /
`paramList` / `groupByIdList` / `dimMetList` the client would send, and
`unmatched_filters` / `warning` if any override key didn't match anything on
the chart.

```bash
gdpa-cli run aeolus --input '{
  "action": "query_report",
  "dashboard_url": "https://aeolus-va.tiktok-row.net/pages/dashboard/404168?appId=1002298&sheetId=453043",
  "report_name": "首帧时长-PCT50 (ms)",
  "filters": {"date": {"op":"lastSync","val":[7]}, "OS": ["android"]},
  "dry_run": true
}'
```

Typical dry-run output:

```json
{
  "queried_report": {"reportId": 3077167, "name": "首帧时长-PCT50 (ms)", ...},
  "effective_filters": [
    {"name": "date",     "op": "lastSync", "value": [7],     "source": "override"},
    {"name": "dim_name", "op": "in",       "value": ["os"], "source": "default"}
  ],
  "unmatched_filters": ["OS"],
  "warning": "filters [OS] not found on chart \"首帧时长-PCT50 (ms)\"; valid filter names: [date dim_name]. Names are case-sensitive; call get_filter_candidates for candidate values.",
  "dry_run": true,
  "request_preview": {
    "api_path": "/aeolus/vqs/api/v2/vizQuery/query (primary) — falls back to /aeolus/glue/api/v1/dashboard/query on routing errors",
    "reportId": 3077167,
    "dataSourceId": 577,
    "query": {
      "whereList":     [...],
      "paramList":     [],
      "groupByIdList": ["1700037135281", "1700037246790"],
      "dimMetList":    [],
      "hasDynamicField": false,
      "limit": 10000,
      "sort":  {"type": "sort", "orderByList": []}
    },
    "body_json_size": 8724
  }
}
```

Use `dry_run` as a zero-cost sanity check: confirm `effective_filters[*].source`
are what you expect, confirm `unmatched_filters` is empty, then drop `dry_run`
to run for real.

#### Output (normal, non-dry-run mode)

- `queried_report`: `{reportId, name, dataSetId, displayType}`
- `effective_filters[]`: every filter actually applied, with `source` — either
  `override` (came from the caller's `filters`/`date` param) or `default` (the
  dashboard's configured default). Use this to confirm the effective date /
  dimensions before showing the user.
- `unmatched_filters[]` + `warning` (only when something was ignored): names
  in your `filters` map that did **not** match any filter on the chart. The
  query still ran, just without those overrides — typically a typo (`OS` vs
  `os`) or a filter that lives on a different chart.
- `query_route`: `vqs` or `glue` — which backend served the request (VQS is
  the primary path; glue is the fallback for a small set of legacy chart types).
- `query_data`:
  - `columns[]` and `rows[]`: human-readable table view (already alias-translated).
  - `costMs`, `sqlList`: timing / debug info.

## Driving-model tips

1. If the user provides only a URL and nothing else, **do not** jump straight
   to `query_report`. Either call `get_dashboard` first and present the
   chart/filter list, or use `AskUserQuestion` to ask whether they want
   overview, specific chart, or just the underlying dataset.
2. For `multi_select` filters, only call `get_filter_candidates` for the
   one(s) the user is actively choosing — not for every filter up-front. A
   large dashboard can have many filters and each call is a round trip.
3. When matching a chart by name, prefer surfacing the matched report's `name`
   and `reportId` back to the user before showing data.
4. To compare across dates, call `query_report` repeatedly with different
   `filters.p_date` values rather than asking the user to construct multiple
   URLs.
5. Prefer `filters` over `date`. The `date` shortcut rewrites only the first
   date filter of the **target chart**, and does nothing on sibling charts —
   if the user's intent is "change the whole dashboard's date", pass
   `filters` explicitly on each chart you query.
6. When building a non-trivial override (multiple `filters`, `params`, or
   `dynamic_fields`), run once with `dry_run: true` first. Inspect
   `effective_filters[*].source` and `unmatched_filters` — fix any typos —
   then re-run without `dry_run`. This avoids silent "why isn't my filter
   working?" loops.

## Errors you may see

### Caller-side (skill rejects the call)

- `query_report requires report_id or report_name` — caller forgot to pass the
  chart selector.
- `report_name "X" matched N reports` — the fuzzy match was ambiguous; ask the
  user to pick from the listed candidates.
- `filter_name "X" not found` / `filter ... does not support candidate lookup`
  — the filter either doesn't exist on this dashboard or isn't a `multi_select`
  with a resolvable field.
- `unmatched_filters` non-empty in `query_report` output — your `filters` /
  `params` / `dynamic_fields` map contained keys the chart doesn't have. The
  query still ran with the remaining (matched) overrides; fix the typos and
  re-run. Common cause: case mismatch (`OS` vs `os`), or the filter belongs
  to a sibling chart.

### Server-side (Aeolus / ClickHouse pushes back)

These come back as the chart's `code` field; the skill surfaces them
verbatim so the model can decide whether to retry, change inputs, or escalate.

- `aeolus/clickhouse/unknownIdentiferExplict` with `Missing columns: 'X' 'Y' …`
  — **dataset schema drift**: the dataset's metric / dimension definitions
  reference ClickHouse columns that no longer exist in the underlying table.
  This is **not fixable from the client** — opening the dashboard in the
  browser fails on the same chart with the same error. Action: tell the user
  which chart fails and which columns are missing, and suggest contacting the
  dataset / dashboard owner. Do NOT keep retrying with different overrides.
- `aeolus/clickhouse/readFailed` / `aeolus/clickhouse/sqlParseFailed` /
  `aeolus/clickhouse/illegalARgType` — the server-rendered SQL was rejected by
  ClickHouse (data missing for the requested partition, type mismatch, etc.).
  First sanity check: try a different `filters.p_date` (often the underlying
  table just doesn't have data for the requested day). If a partition with
  data still errors, treat it like `unknownIdentiferExplict` above —
  server-side dataset issue.
- `aeolus/clickhouse/syntaxError` with `Aggregate function ... is not supported
  in WHERE expression` — historically this was a client-side bug
  ([measure-as-filter pitfall](#measure-as-filter-pitfall) below) that was
  fixed; if you see it again, it likely means the chart introduced a new
  aggregation prefix (e.g. some compound `avgday_<id>_sum_<id>`) that the
  prefix-stripping logic in `applyWhereList` doesn't recognize. Capture the
  failing reportId and the request body via `dry_run` and add the new prefix
  to `knownAggrPrefixes`.
- `aeolus/user/forbidden` / `aeolus/user/unauthorized` — the user's Titan
  Passport session does not have permission for that `appId` / dashboard /
  dataset. The skill cannot bypass this. Tell the user to apply for access on
  the dashboard's `?appId=…` page (or `gdpa-cli login` again if the session
  expired).
- `aeolus/unknown` with `extra_msg` containing a measure / dimension id (e.g.
  `avgday_<dayId>_sum_<fieldId>`, `ratio_<id>_<id>`) — a derived measure shape
  the client doesn't recognize. The current skill already passes through
  unknown derived measures from the schema; if you still see this, the chart
  is using an even more exotic shape — surface the id and escalate to the
  dashboard owner.
- `147999` from Aeolus — a small number of charts (e.g. raw-data preview) are
  not stably queryable via this API; report the failure and suggest opening
  the dashboard directly.

### Measure-as-filter pitfall

When a chart's filter is built off an aggregated metric (e.g. the user dragged
`求和(has_error_field)` onto the filter shelf and set `> 0`), the **saved
schema** stores the filter id with an aggregation prefix:

```json
{ "name": "has_error_field", "id": "sum_10000008613142", "op": ">", "val": [0] }
```

The browser's runtime strips that `sum_` prefix before sending the request, so
the actual on-the-wire `whereList` is:

```json
{ "name": "has_error_field", "id": "10000008613142", "op": ">", "val": [0] }
```

If we forward the prefixed id verbatim, the server compiles
`WHERE sum(has_error_field) > 0`, which ClickHouse rejects (aggregates are
only valid in `HAVING`). The chart loads in the browser but errors out via
this client. `applyWhereList` now mirrors browser behavior: any `whereList`
entry whose `id` matches a known aggregation prefix
(`sum_/avg_/min_/max_/count_/countDistinct_/distinct_count_/approxDistinct_/median_/stddev_/variance_`)
gets the prefix trimmed before the body is serialized. Compound prefixes like
`avgday_<id>_sum_<id>` are not stripped — extend `knownAggrPrefixes` if a new
chart type breaks for this reason.

Cross-checking with HAR dumps: capture the same chart in the browser via
DevTools, compare the on-the-wire `whereList` with the agent's `dry_run`
output. Any divergence in `id`, `name`, `op`, or `option.isWhereInAggr` is a
candidate root cause for "browser works, agent fails" reports.

### Partial dashboard failures

A dashboard often has a mix of working and broken charts. `get_dashboard`
always lists the full set, but `query_report` is per-chart. When asked to
"summarize this dashboard", the right shape is: query each chart, and for
each one report either the data or the chart-level `code`/`msg`. **Do not**
hide chart-level failures behind a top-level "everything failed"; surface
each one with its `reportId` and `name` so the user can decide what to do.

## Maintaining calculated fields (`update_field`)

`update_field` updates a dataset's派生字段 (calculated `dim_met`) — what the
dashboard UI does when you edit a calculated field and click "保存". Hits
`PUT /aeolus/api/v3/dataSet/dimMet` with the same Titan Passport auth as
`get_dashboard`, plus three extra headers required by the server's CSRF
check on writes (`Origin`, `Referer`, `x-titan-token`); the client sets
those automatically.

### Scope

- **Update only.** `field_id` is required.
- **No create.** The create path uses a different verb/route that hasn't
  been HAR-captured yet (POST to the same path returns HTTP 405). If you
  need to add a brand-new field, do it once in the UI, then maintain it
  from this skill afterwards.
- **No delete.** Same reason as create.

### Two-phase confirmation (mandatory for the model)

`update_field` is a destructive write — it overwrites a calculated field
that may be referenced by many dashboards. To match
`/.agents/doc/skill_development.md` §4 ("写操作必须有显式用户确认")
the action is **preview-by-default**, and `confirm:true` is the **only**
switch that can enable a real write:

1. **Preview phase** — call `update_field` without `confirm` (or with
   `confirm:false`). The skill returns `preview:true` and a snapshot of
   the request body (resolved `expr`, `data_type`, scope, etc.) without
   touching the server. **Show this snapshot to the user verbatim.**
2. **Confirm phase** — only after the user explicitly approves, re-issue
   the exact same input plus `"confirm": true`. The skill performs the
   PUT and returns `confirmed:true` plus the server-parsed `full_expr`.

Flag interaction (kept narrow on purpose, no foot-guns):

- No flags / `confirm:false` / `dry_run:true` → preview only.
- `confirm:true` → write.
- `confirm:true` + `dry_run:true` → preview only (`dry_run:true` is a
  hard kill switch — useful when chaining inputs that already carry
  `confirm:true` but you want to take one more look).
- `dry_run:false` **without** `confirm:true` → still preview only.
  `dry_run` cannot enable a write on its own; only `confirm:true` can.

**Never fabricate `confirm:true` automatically — it must be a
human-in-the-loop decision.**

### Inputs

| key | required | default | meaning |
|-----|---------|---------|---------|
| `region` | yes | — | `cn` / `sg` / `va` / `ttp` |
| `dataset_id` | yes | — | the dataset that owns this field |
| `field_id` | yes | — | the existing dim_met id (find via `dataset_fields`) |
| `name` | yes | — | display name shown in the field picker, e.g. "批量标记" |
| `expr` | yes | — | the calculated expression — see [expression_functions.md](./expression_functions.md) |
| `app_id` | no | 0 | sets the `app-id` header — needed when the dataset enforces app scoping |
| `descr` | no | "" | tooltip text |
| `data_type` | no | `string` | `string` / `int` / `float` / `double` / `date` / `datetime` / `bool` |
| `role_type` | no | 0 | 0 = dimension, 1 = measure |
| `scope` | no | 2 | 2 = private to dataset (UI default); 0 = global; 1 = app-shared. **Pointer-tracked: pass 0 explicitly to opt into global** |
| `is_private` | no | 1 | 1 keeps the field hidden from non-owners (UI default); 0 = visible. **Pass 0 explicitly to flip** |
| `dim_met_variety` | no | 2 | 2 = calculated/derived (UI default); 0 = raw column. **Pass 0 explicitly to opt in** |
| `confirm` | no | false | `true` to actually write — the only switch that enables a write |
| `dry_run` | no | — | `dry_run:true` is a hard kill switch (forces preview even with `confirm:true`); `dry_run:false` alone never enables a write |

The 3 marked rows above (`scope` / `is_private` / `dim_met_variety`) are
tri-state: the underlying client uses `*int`, so a caller-supplied 0 is
preserved instead of being silently replaced by the UI default. This
matters when the user wants `scope=0` (global) or `is_private=0` (visible
to everyone) — passing the literal 0 actually changes the server-side
field instead of being mistaken for "not provided".

### Reading the response

- **Preview reply** — `preview:true`, plus an echo of `dataset_id`, `field_id`,
  `name`, `expr`, `data_type`, `role_type`, and either the explicit
  `scope` / `is_private` / `dim_met_variety` (if you passed them) or
  their `<key>_default` counterparts (so you can show the user "we'll
  fall back to UI default 2"). Nothing has been written.
- **Confirm reply** — `confirmed:true`, plus the canonicalized `field`
  block. `field.full_expr` is what the engine actually parsed (e.g.
  `[action]` rewrites to `` (`action`) ``); compare it to your `expr` to
  spot well-formedness issues. If the expression is malformed the engine
  returns an Aeolus error with a Chinese hint inside `msg` (e.g.
  "未识别的函数 / 字段不存在"), which the skill surfaces verbatim.

### Examples

```bash
# Step 1: preview (no confirm flag)
gdpa-cli run aeolus --input '{
  "action": "update_field",
  "region": "sg",
  "dataset_id": 1540320,
  "app_id": 801869,
  "field_id": 10000009126884,
  "name": "批量标记",
  "expr": "if(equals([action], '\''list_repo_merge_requests'\''), '\''true'\'', '\''false'\'')",
  "descr": "判断是否为批量调用",
  "data_type": "string",
  "role_type": 0
}'
# → returns {"preview": true, ...}; show the snapshot to the user.

# Step 2: only after user confirms — re-send the same input with confirm:true
gdpa-cli run aeolus --input '{
  ...same input as above...,
  "confirm": true
}'
# → returns {"confirmed": true, "field": {...}}.
```

### Common pitfalls

1. **Field reference syntax** — both `[中文名]` and `` `english_name` `` are
   accepted at write time, but the canonical form (returned in `full_expr`)
   is `` (`column_name`) ``. If you reference a field that doesn't exist on
   the dataset, the server rejects with "字段不存在".
2. **String literals must use single quotes** — double quotes are treated as
   identifier quoting in ClickHouse, which silently corrupts the expression.
3. **Updating a referenced field invalidates downstream caches** — the
   dashboard's chart-data cache flushes within a few seconds, but freshly
   built dashboards may still show stale data for ~30s. Tell the user to
   refresh.
4. **No bulk API** — to update many fields, call `update_field` per field;
   there is no batch endpoint exposed by the dashboard UI.
5. **`aeolus/user/forbidden`** — the current `gdpa-cli` session user is not
   the field's `ownerEmailPrefix` and not a dataset admin. Aeolus enforces
   per-field ACL on writes; the skill cannot bypass it. Tell the user to
   either (a) `gdpa-cli login` as the field owner, or (b) ask the field
   owner to update the field, or (c) ask the dataset admin to transfer
   ownership.
6. **HTTP 500 with HTML body** — usually means the CSRF check rejected the
   request because `Origin`/`Referer`/`x-titan-token` were missing. The
   skill sets all three; if you still see this in the wild, the Titan
   Passport session probably expired — `gdpa-cli login` again.

## Looking up expression functions (`list_functions`)

`list_functions` calls `/aeolus/api/v3/misc/funcsHelp`, the same endpoint
that powers the "fx" popup in the dashboard UI. It returns the full
expression-language catalog (~166 entries / 21 categories for
ClickHouse / zh_CN / dataSetType=34).

### Read-the-snapshot-first rule

For day-to-day expression authoring, **read
[expression_functions.md](./expression_functions.md) instead** — it's an
offline snapshot of the same data, indexed by category, with a "常用模板"
section that mirrors the UI's "常用函数" panel. Only call `list_functions`
when you need to:

- confirm the snapshot is still current (e.g. a function the user mentions
  isn't in the file),
- check a different `engineType` (Hive / Presto / Spark) — defaults are
  ClickHouse, and signatures sometimes differ across engines,
- verify a function is available in your specific dataset
  (`dataset_type` matters for fabric vs raw).

### Inputs

All parameters are optional except `region`. Defaults reproduce the UI's "fx" popup.

| key | default | meaning |
|-----|---------|---------|
| `region` | — (required) | `cn` / `sg` / `va` / `ttp` |
| `engine_type` | `ClickHouse` | also accepts `Hive`, `Presto`, `Spark` |
| `language` | `zh_CN` | `en_US` returns English `usage` / `example` |
| `category` | `normal` | `common` returns the curated subset shown in the UI's "常用函数" tab |
| `dataset_type` | 34 | matches fabric (virtual) datasets; pass 0 to omit |
| `data_source_types` | `click_house` | comma-separated; matches the engine |
| `search` | — | client-side substring filter on name / format / usage / type |

### Examples

```bash
# fetch ClickHouse / zh_CN catalog and grep client-side for "json"
gdpa-cli run aeolus --input '{
  "action": "list_functions",
  "region": "sg",
  "search": "json"
}'

# check Hive variant of a function
gdpa-cli run aeolus --input '{
  "action": "list_functions",
  "region": "sg",
  "engine_type": "Hive",
  "search": "to_date"
}'
```
