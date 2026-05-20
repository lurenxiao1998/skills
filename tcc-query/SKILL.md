---
name: tcc-query
description: Read TCC (TCE Configuration Center) configuration values and list namespace configs across CN, BOE, I18N, and TTP regions. Use when the user mentions TCC/TCE configuration, wants to check a config value, inspect namespace configs, verify config content, or compare configs across regions. Read-only; refuse write, publish, deploy, mutate, create, update, or delete requests.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# TCC Query Agent

Query TCC (TCE Configuration Center) configurations from BOE and international environments.

> **When to Use**: Query TCC configuration values, list configs in a namespace, or check TCC settings across regions.

## Routing & Recovery Contract

- Use this skill as the first and only TCC data source once the user asks to read, verify, list, or compare TCC/TCE configuration.
- Refuse write-like requests before building input: create, update, delete, publish, deploy, rollback, mutate, or any prompt that explicitly forbids TCC querying.
- After a failed call, recover in this order only: fix missing/invalid input from the user prompt, retry the same namespace/key/region once when the failure is transient, then report the failure with the evidence returned.
- Do not switch `vregion`, broaden namespace/key, run repo/code search, or use another tool family unless the user explicitly asks for that separate investigation.
- Keep one session for related calls; read the returned evidence before issuing any follow-up call.

## Quick Start

```bash
# Action: query - Get a single config item (default: Singapore-Central)
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{
  "command": "query",
  "namespace": "ttarch.gdp.gdpa",
  "key": "generic_agent_config"
}'

# Action: list - List all configs in a namespace with filters (New!)
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{
  "command": "list",
  "namespace": "tiktok.llmgw.api",
  "dir_path": "/default",
  "pn": 1,
  "rn": 20
}'
```

## Actions

### `query` (Default)
Used to fetch a single configuration item by its key.

Use `query` only when an exact config key is known. If `key` is present, set `command: "query"`; do not use `list` to retrieve that exact key.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `namespace` | string | Yes | TCC namespace (e.g. `tiktok.llmgw.api`) |
| `key` | string | Yes | Configuration key name (case-sensitive) |
| `vregion` | string | No | VRegion (default: `Singapore-Central`) |
| `env` | string | No | Environment filter (e.g. `prod`, `default`) |
| `dir_path` | string | No | Optional directory path filter |

### `list`
Used to list and search for multiple configuration items with advanced filtering.

Use `list` only for namespace browsing or filtered search. Do not send positional arguments; build a JSON object with the allowed fields below.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `namespace` | string | Yes | TCC namespace |
| `vregion` | string | No | VRegion (default: `Singapore-Central`) |
| `env` | string | No | Environment filter |
| `dir_path` | string | No | Filter by directory path (server-side) |
| `tags` | string/array | No | Filter by tags (comma-separated or JSON array) |
| `pn` | int | No | Page number (default: 1) |
| `rn` | int | No | Page size (default: 20) |
| `condition` | string | No | Search condition (e.g. `name`, `fuzzy`) |
| `no_return_value` | bool | No | Skip returning values to save bandwidth (default: false) |
| `scope` | string | No | Query scope (default: `all`) |

Accepted guardrails: `command` is `query` or `list`; `condition` is `name` for exact-name filtering or `fuzzy` only when the user asks for fuzzy search; `scope` defaults to `all`; `pn` starts at 1; `rn` defaults to 20. Ask for clarification instead of trying multiple parameter permutations.

## VRegion & VDC Mapping (统一区域映射)

| VRegion | Aliases | TCC API Region | Gateway (TCCRegion) | JWT   |
|---------|---------|----------------|---------------------|-------|
| `China-North` | `cn`, `china` | CN | CN | CN    |
| `China-East` | `chinaeast` | China-East | CN | CN    |
| `China-North6` | `chinanorth6`, `cn6` | China-North6 | CN | CN    |
| `China-Pay` | `chinapay` | China-Pay | CN | CN    |
| `China-Pay2` | `chinapay2` | China-Pay2 | CN | CN    |
| `Aliyun_NC2` | `aliyunnc2` | Aliyun_NC2 | CN | CN    |
| `China-Enterprise` | `chinaenterprise` | China-Enterprise | CN | CN    |
| `China-HKPay` | `chinahkpay`, `hkpay` | China-HKPay | CN | CN    |
| `ChinaSinf-North` | `sinfnorth`, `sinf-north` | ChinaSinf-North | CN | CN    |
| `China-BOE` | `boe`, `cn-boe`, `china-boe` | China-BOE | BOE | CN    |
| `Singapore-Central` | `sg`, `singapore` | Singapore-Central | Singapore-Central | i18n  |
| `US-East` | `us`, `us-east`, `useast` | US-East | US-East | i18n  |
| `US-BOE` | `boei18n`, `boe-i18n`, `us-boe` | US-BOE | BOE-I18N | i18n  |
| `EU-TTP` | `euttp`, `eu-ttp` | EU-TTP | EUTTP | i18n  |
| `EU-TTP2` | `euttp2`, `eu-ttp2` | EU-TTP2 | EUTTP2 | i18n  |
| `US-EastRed` | `useastred`, `us-eastred` | US-EastRed | US-EastRed | i18n  |
| `US-TTP` | `usttp`, `us-ttp`, `ttp` | US-TTP | USTTP | usttp |
| `US-TTP2` | `usttp2`, `us-ttp2`, `ttp2` | US-TTP2 | USTTP | usttp |
| `i18n` ⚠️ | `international` | *(聚合，无 Region 过滤)* | US-East | i18n  |

### ⚠️ 关于 `i18n` / `international` 的特殊语义

传 `vregion: "i18n"`（或 `"international"`）时，本 skill 进入**聚合查询模式**：返回跨 i18n 区域的配置列表，覆盖 `Singapore-Central`、`US-East`、`US-BOE`、`EU-TTP`、`EU-TTP2`、`US-EastRed`。

要查询具体某个 i18n 机房的配置，请传明确的 `Singapore-Central` / `US-East` 等，不要用 `i18n`。

## Output Format

传入 `dir_path` 时，只会影响结果过滤，不改变原有 response 结构。

Final answers must include: namespace, key or list filter, vregion, success/error status, and the relevant source evidence from `_final_result`. For not-found results, state whether a `dir_path` filter was applied and do not infer a different region. If nearby keys or fallback context are present in the returned data, summarize them; otherwise say they were not returned.

### Single Config Query

```json
{
  "success": true,
  "namespace": "ttarch.gdp.gdpa",
  "key": "generic_agent_config",
  "data": {
    "conf_name": "generic_agent_config",
    "config_type": "static",
    "data_type": "json",
    "description": "generic_agent_config",
    "env": "prod",
    "region": "China-BOE",
    "status": "active",
    "value": "{...JSON content...}",
    "version": 16
  }
}
```

### Namespace Listing

```json
{
  "success": true,
  "namespace": "ttarch.gdp.gdpa",
  "data": {
    "items": [
      { "key": "generic_agent_config", "value": "...", "type": "json" },
      { "key": "other_config", "value": "...", "type": "string" }
    ],
    "total_count": 23
  }
}
```

## Examples (Tested)

### Query China BOE Config

```bash
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{"namespace": "ttarch.gdp.gdpa", "key": "generic_agent_config", "vregion": "China-BOE"}'
```

### Query Singapore Config

```bash
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{"namespace": "tiktok.llmgw.api", "key": "allow_list", "vregion": "Singapore-Central"}'
```

### Query Config Under Specific Directory

```bash
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{"namespace": "desrpc.test.client", "key": "test_client_config", "vregion": "Singapore-Central", "dir_path": "/wzz"}'
```

### Exact Key vs Namespace Search

```bash
# Exact key: query mode, no fuzzy search
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{"command":"query","namespace":"desrpc.test.client","key":"test_client_config","vregion":"Singapore-Central"}'

# Namespace search: list mode with an explicit keyword/condition
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{"command":"list","namespace":"desrpc.test.client","keyword":"test_client","condition":"fuzzy","vregion":"Singapore-Central"}'
```

### List Configs Under Specific Directory

```bash
gdpa-cli run tcc-query --session-id "$SESSION_ID" --input '{"namespace": "desrpc.test.client", "vregion": "Singapore-Central", "dir_path": "/wzz"}'
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `namespace parameter is required` | Missing namespace | Add `namespace` parameter |
| `config 'xxx' not found in namespace` | Key doesn't exist in this vregion | Check key name. Report to user and suggest possible vregions, **never auto-switch vregion** |
| `config 'xxx' found in namespace 'yyy' but not under dir_path '/zzz'` | Key exists but directory filter does not match | Check `dir_path` or remove it |
| `namespace not found` | Namespace doesn't exist | Verify namespace spelling |
| `authentication failed` or empty JWT | Missing/expired TCC auth for the selected vregion | Report the auth/session failure; do not switch tools or regions automatically |
| `connection timeout` | Network or MCP issue | Retry the same call once, then report timeout evidence |
| `invalid vregion` or invalid parameter | Unsupported region or malformed input | Correct from the prompt or ask the user; do not fan out guesses |

## Notes

- **Default VRegion**: Singapore-Central. Use `vregion` to query different regions
- **Read-Only**: Configuration values can only be read, not modified
- **Namespace Format**: Use dot notation (e.g. `ttarch.gdp.gdpa`)
- **Case Sensitive**: Configuration keys are case-sensitive
- **Sensitive Data**: Config values may contain secrets - handle with care
- `dir_path` is sent to the TCC API for server-side filtering.
- Supports pagination with `pn` and `rn`.
- Different configs may exist in different vregions (e.g. `China-BOE` for China BOE, `Singapore-Central` for Singapore). **Always ask user before switching vregion**
