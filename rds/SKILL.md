---
name: rds
description: Execute SQL queries on RDS databases via RDS-OG Cloud gateway or DataQ across multiple regions. Use first for direct database checks, table inventory, SQL verification, row inspection, backend/region diagnosis, or any request mentioning RDS/RDS-OG/DataQ. Supports standard, TTP, BOE, and NonTT environments, including direct VDC names as vregion input.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# RDS Agent

Execute SQL queries on RDS databases via RDS-OG Cloud gateway or DataQ. For database facts, schema/table inventory, backend checks, or SQL verification, run `rds` as the canonical evidence path before drawing conclusions.

> **When to Use**: Run SQL queries against RDS databases across Singapore, US, China, BOE, TTP, and NonTT environments. Repository search, shell commands, substitute skills, or delegation can provide context, but they are not replacements for canonical `rds` execution when the user asks for live DB evidence.

## Quick Start

```bash
# Execute a SELECT query (default: Singapore-Central, uses RDS-OG)
gdpa-cli run rds --session-id "$SESSION_ID" --input '{
  "db_name": "my_database",
  "dql": "SELECT * FROM users LIMIT 10"
}'

# Query with specific VRegion
gdpa-cli run rds --session-id "$SESSION_ID" --input '{
  "db_name": "my_database",
  "dql": "SELECT COUNT(*) FROM orders WHERE created_at > \"2025-01-01\"",
  "vregion": "China-North"
}'

# Query TTP environment (uses DataQ, dbpsm not needed)
gdpa-cli run rds --session-id "$SESSION_ID" --input '{
  "db_name": "my_ttp_database",
  "dql": "SELECT * FROM tasks LIMIT 10",
  "vregion": "us-ttp"
}'

# Query NonTT environment (uses cloud.byteintl.net)
gdpa-cli run rds --session-id "$SESSION_ID" --input '{
  "db_name": "my_database",
  "dql": "SELECT * FROM configs LIMIT 10",
  "vregion": "Asia-SouthEastBD"
}'

# Query NonTT with direct VDC name
gdpa-cli run rds --session-id "$SESSION_ID" --input '{
  "db_name": "my_database",
  "dql": "SELECT * FROM configs LIMIT 10",
  "vregion": "be2a"
}'
```

## Input Parameters

### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `db_name` | string | Database name in RDS |
| `dql` | string | SQL query to execute (SELECT, SHOW, etc.) |

### Optional

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `vregion` | string | `Singapore-Central` | VRegion 或 VDC 名。详见下方路由表。支持 VRegion 别名（如 `sg`）和 VDC 直接输入（如 `bdsgdt`、`be2a`） |
| `dbpsm` | string | auto-generated | Database PSM (RDS-OG only, ignored for TTP/DataQ). Auto-generated as `toutiao.mysql.<db_name>_read` when not provided |
| `action` | string | `run_sql` | Action type (currently only `run_sql` supported) |

### Invocation Contract

- Always call `gdpa-cli run rds` with JSON input; do not invent alternate action names or wrapper commands.
- Omit `action` or set exactly `"action":"run_sql"`; values such as `query`, `execute_sql`, or `run_query` are invalid.
- Required keys for every SQL execution are `db_name` and `dql`; add `vregion` only when the user names a region, TTP branch, BOE branch, or VDC.
- Valid minimal input: `{"db_name":"orders","dql":"SHOW TABLES","action":"run_sql"}`. Invalid input: `{"database":"orders","sql":"SHOW TABLES","action":"query"}`.

## Backend Routing

Agent 根据 VRegion/VDC 自动选择后端：

| Backend | VRegions | Description |
|---------|----------|-------------|
| **RDS-OG** (cloud.tiktok-row.net) | Singapore-Central, US-East, sg_sensitive, maliva_sensitive | I18N Cloud 网关 |
| **RDS-OG** (cloud.bytedance.net) | China-North | CN Cloud 网关 |
| **RDS-OG / Volc DBW** (cloud-boe.bytedance.net) | China-BOE | BOE 网关（自动检测火山 RDS，异步执行） |
| **RDS-OG / Volc DBW** (cloud-boe.bytedance.net) | US-BOE | BOEI18N（自动检测火山 RDS，异步执行） |
| **RDS-OG** (cloud.byteintl.net) | NonTT VRegion/VDC（见下表） | NonTT 机房网关 |
| **DataQ** | US-TTP, US-TTP2, EU-TTP2, US-EastRed | TTP 环境专用 |

### RDS-OG VRegion 映射（标准）

| VRegion | Aliases | RDS Region | SQL Mode | JWT |
|---------|---------|------------|----------|-----|
| `Singapore-Central` (default) | `sg` | alisg | RunSQL | i18n |
| `US-East` | `us`, `i18n` | maliva | RunSQL | i18n |
| `China-North` | `cn`, `china` | cn | RunSQL | CN |
| `China-BOE` | `boe` | boe | RunSQL | CN |
| `US-BOE` | `boei18n` | boei18n | RunSQLDirect | i18n |
| `sg_sensitive` | `sg-sensitive` | sg_sensitive | RunSQL | i18n |
| `maliva_sensitive` | `maliva-sensitive` | maliva_sensitive | RunSQL | i18n |

### NonTT VRegion 映射（cloud.byteintl.net）

| VRegion | Aliases | RDS Region | 默认 VDC | JWT |
|---------|---------|------------|----------|-----|
| `Singapore-SaaS` | `sg-saas`, `sgsaas` | Singapore-SaaS | sgsaas1larkidc1 | i18n |
| `Asia-SouthEastBD` | `asia-southeastbd` | bdsgdt | bdsgdt | i18n |
| `Asia-SaaS` | `asia-saas`, `asiasaas` | Asia-SaaS | jpsaas | i18n |
| `US-EE` | `us-ee`, `usee` | US-EE | va | i18n |
| `US-EastBD` | `us-eastbd`, `useastbd` | useast14a | useast14a | i18n |
| `Singapore-Common` | `sg-common`, `sgcommon` | sgcomm1 | sgcomm1 | i18n |
| `Europe-WestBD` | `eu-westbd`, `europewestbd` | bddedt | bddedt | i18n |
| `Australia-SouthEastBD` | `au-southeastbd` | syd2a | syd2a | i18n |
| `US-TTP3` | `ttp3`, `us-ttp3` | useast15a | useast15a | i18n |

### NonTT VDC 直接输入

同一 VRegion 下有多个 VDC 时（如 Europe-WestBD 有 bddedt 和 be2a），可直接输入 VDC 名：

| VDC 输入 | RDS Region | 所属 VRegion |
|----------|------------|-------------|
| `bdsgdt` | bdsgdt | Asia-SouthEastBD |
| `useast14a` | useast14a | US-EastBD |
| `sgcomm1` | sgcomm1 | Singapore-Common |
| `bddedt` | bddedt | Europe-WestBD |
| `be2a` | be2a | Europe-WestBD |
| `syd2a` | syd2a | Australia-SouthEastBD |
| `useast15a` | useast15a | US-TTP3 |
| `va` | US-EE | US-EE |
| `jpsaas` | Asia-SaaS | Asia-SaaS |
| `sgsaas1larkidc1` | Singapore-SaaS | Singapore-SaaS |

### DataQ VRegion 映射 (TTP)

| VRegion | Aliases | Geo | Region | JWT |
|---------|---------|-----|--------|-----|
| `US-TTP` | `ttp`, `us-ttp` | US | ova | ttp-us |
| `US-TTP2` | `ttp2`, `us-ttp2` | US | useast8 | ttp-us |
| `EU-TTP2` | `eu-ttp2`, `euttp2` | EU | no1a | i18n |
| `US-EastRed` | `us-eastred`, `useastred` | EU | us_east_gcp | i18n |

TTP routing is selected only by `vregion`; keep `db_name` as the database name and leave `dbpsm` unset because DataQ ignores it. If the user's wording mixes a TTP branch with a standard RDS region, perform one bounded correction by choosing the explicit `vregion` alias from this table, then retry `run_sql` once with the same `db_name` and `dql`.

## Output Format

```json
{
  "success": true,
  "action": "run_sql",
  "vregion": "US-TTP",
  "db_name": "my_database",
  "data": {
    "row_count": 10,
    "columns": ["id", "name", "status"],
    "rows": [
      {"id": "1", "name": "foo", "status": "active"},
      {"id": "2", "name": "bar", "status": "inactive"}
    ]
  }
}
```

> RDS-OG 返回还包含 `cost_time_ms` 和 `has_permission` 字段。DataQ 返回的 rows 为 `map[string]string` 格式。

### Final Answer Checklist

- State the executed `rds` evidence: `db_name`, effective `vregion`/VDC, backend when visible, and the SQL shape used.
- Include the returned row payload or structured failure payload; distinguish empty rows from execution/parsing failure.
- Close every user-requested dimension such as table existence, row count, stage/backend, region, or permission status before finalizing.
- If canonical execution fails after the bounded recovery ladder, final answer should name the failure, whether retry is safe, and the exact missing evidence.

## Examples

### Query Singapore RDS (RDS-OG)

```bash
gdpa-cli run rds --session-id "$SESSION_ID" --input '{"db_name": "user_db", "dql": "SELECT * FROM users LIMIT 5", "vregion": "sg"}'
```

### Query NonTT VRegion (cloud.byteintl.net)

```bash
gdpa-cli run rds --session-id "$SESSION_ID" --input '{"db_name": "cp_govern", "dql": "SELECT * FROM timeouts LIMIT 1", "vregion": "Asia-SouthEastBD"}'
```

### Query NonTT with VDC name (Europe-WestBD be2a)

```bash
gdpa-cli run rds --session-id "$SESSION_ID" --input '{"db_name": "cp_govern", "dql": "SELECT * FROM timeouts LIMIT 1", "vregion": "be2a"}'
```

### Query TTP US Database (DataQ)

```bash
gdpa-cli run rds --session-id "$SESSION_ID" --input '{"db_name": "my_ttp_db", "dql": "SELECT id, name FROM configs LIMIT 10", "vregion": "ttp"}'
```

### Query China BOE (auto-detects Volcano RDS)

```bash
gdpa-cli run rds --session-id "$SESSION_ID" --input '{"db_name": "gdp_auto_test", "dql": "SHOW TABLES", "vregion": "boe"}'
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `db_name parameter is required` | Missing database name | Add `db_name` parameter |
| `dql parameter is required` | Missing SQL query | Add `dql` parameter |
| `invalid vregion/vdc` | Unknown VRegion or VDC name | Check supported VRegion/VDC list above |
| `authentication failed` | JWT token issue | Check network and login status (`gdpa-cli login`) |
| `RDS error (code=xxx)` | RDS-OG backend error | Check SQL syntax, permissions, or database name |
| `DataQ error (code=xxx)` | DataQ backend error | Check SQL syntax, database name, or DataQ permissions |
| `unknown action` / missing `db_name` / missing `dql` | Invocation shape error | Correct the JSON to the Invocation Contract and retry `run_sql` once with the same user goal |
| Backend 500, HTML body, gateway timeout | Transient RDS-OG/backend failure | Retry once in the same `vregion` with the same SQL; if it fails again, return the error payload and retry hint instead of switching tools |
| Large query timeout | Query too broad | Narrow with `WHERE`/`LIMIT` and retry once in the same backend before finalizing |

Recovery ladder: first repair authentication, action, required-parameter, region, or transient-backend failures inside the canonical `rds` path. Use repository search, delegation, or substitute tools only after the bounded `rds` correction/retry has either succeeded or produced a final structured failure.

Stop after one same-region retry for transient backend failures. Switch regions only when the user provided an alternate region/VDC or the error explicitly says the selected region/VDC is unsupported for that database.

## Notes

- **Auto backend selection**: TTP VRegions use DataQ; NonTT VDC inputs use cloud.byteintl.net; all others use standard RDS-OG
- **BOE 火山 RDS**: China-BOE/US-BOE 环境会自动检测火山引擎 RDS 数据库，检测到后自动走 DBW 异步接口（CreateSession → ExecuteCommandSet → DescribeCommand 渐进轮询 5s→10s→15s→20s）。如果数据库不是火山 RDS，则回退到标准 RDS-OG 流程
- **VDC 直接输入**: 可跳过 VRegion，直接用 VDC 名（如 `be2a`）查询特定机房
- **DBPSM**: Only used by RDS-OG; for TTP/DataQ queries, `dbpsm` is ignored
- **SQL Safety**: Always use LIMIT in SELECT queries to avoid returning excessive data
- **Timeout**: Large queries may timeout; keep SQL simple and add appropriate WHERE/LIMIT clauses
