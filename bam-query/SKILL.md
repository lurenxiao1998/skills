---
name: bam-query
description: Execute BAM RPC/HTTP requests for interface testing and deployment verification. Use this skill when the request target and payload are known; use bam-api separately for API discovery or method/path metadata. Show red-line parameters (PSM, API, IDL Version, VRegion, Env, Cluster, Request Body, and for HTTP Method, Query Params, Headers, Cookies if provided) before non-BOE execution.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# BAM Query Agent

BAM (ByteDance API Management) interface testing agent — send RPC/HTTP requests to test APIs.

> **When to use**: When you need to test API interfaces through BAM, send RPC requests to services, debug HTTP endpoints, or verify that a deployed service responds correctly in BOE/PPE/production environments. Deployment status, repository evidence, or curl output is not a substitute when the user asks for a BAM request result.

## ⚠️ MANDATORY: Confirmation Required Before Every Request (BOE Exempted)

Due to auto-defaulting logic (e.g., using latest IDL version, defaulting to prod environment), you should display the following "red-line" parameters as a clear table and wait for explicit user confirmation before proceeding — **when the target VRegion is a BOE environment** (`China-BOE` / alias `boe`, or `US-BOE` / alias `boei18n`), you can skip the confirmation step and execute the request directly.

BOE environments are non-production testing environments; requests to BOE do not affect live services, so confirmation is not required.

| Parameter        | Current Value (including defaults) | Status |
|------------------|-----------------------------------|--------|
| **PSM**          | ... | Required |
| **API / Path**   | ... | Required |
| **IDL Version**  | ... (e.g. 1.0.64 master) | Auto-fetched if empty |
| **VRegion**      | ... | Required |
| **Env**          | ... | Defaults to `prod` |
| **Cluster**      | ... | Defaults to `default` |
| **Request Body** | `{...}` | Business payload |
| **HTTP Method**  | (HTTP only) e.g. `GET` | Defaults to `GET` |
| **Query Params** | (HTTP only) e.g. `[{"key":"k","value":"v"}]` | Optional |
| **Headers**      | (HTTP only) e.g. `[{"key":"X-Custom","value":"val"}]` | Optional |
| **Cookies**      | (HTTP only) e.g. `[{"key":"name","value":"val"}]` | Optional |


**Only proceed to call bam-query after the user explicitly confirms.** Sending requests touches live services and cannot be undone.

## Quick Start

### RPC Request (Minimal)

```bash
gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{
  "action": "rpc",
  "psm": "desrpc.stability.thrift_server",
  "func_name": "GetItem",
  "request": "{}",
  "vregion": "US-BOE"
}'
```

### HTTP Request (Minimal)

```bash
gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{
  "action": "http",
  "psm": "tiktok.llmgw.api",
  "http_path": "/api/v1/config/litellm",
  "vregion": "US-BOE"
}'
```

### Execute-now branch

When the PSM, action, vregion, request payload, and method/path or `func_name` are already known, create or reuse one session and run `bam-query` immediately after the required confirmation gate. A valid BAM result, or a concrete BAM parameter error that identifies the missing field, is decisive evidence: finalize from it or repair that field directly instead of rereading this skill, running CLI help, or probing unrelated diagnostics.

## Input Parameters

### Common Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `psm` | string | **Required.** Service PSM (e.g. `tiktok.llmgw.api`) |
| `vregion` | string | **Required.** Must specify VRegion for API routing. Supported: `Singapore-Central`, `US-East`, `Asia-SouthEastBD`, `China-North`, `ChinaSinf-North`, `China-BOE`, `US-BOE`. Aliases: `sg`, `us`, `asia-southeastbd`, `cn`, `chinasinf-north`/`sinf-north`, `boe`, `boei18n` |

### RPC Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `action` | string | Must be `rpc` |
| `func_name` | string | **Required for RPC.** RPC function name (e.g. `GetItem`) |

### HTTP Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `action` | string | Must be `http` |
| `http_path` | string | **Required for HTTP.** HTTP path as defined in the IDL (e.g. `/api/v1/config/litellm`). Must be the **pure path without query parameters** — use `http_query` for query strings |

### Optional Parameters (Both RPC & HTTP)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `request` | string | `{}` | Request body (JSON string) |
| `vdc` | string | auto | VDC (虚拟数据中心), 从 VRegion 自动推导默认值。可手动指定: `sg1`, `maliva`, `lf`, `hl`, `boe`, `boei18n` 等 |
| `zone` | string | auto | Control plane, 从 VRegion 自动推导。可手动覆盖 |
| `env` | string | `prod` | Environment. ⚠️ Required if `vdc` is set |
| `cluster` | string | `default` | Cluster name |
| `idl_version` | string | auto (latest published version) | IDL version to use (e.g. `1.0.5`). Auto-fetched from BAM's published version list (by psm+branch) when not specified. Falls back to `master` if no versions are published. |
| `branch` | string | - | Branch name, used together with `idl_version` auto-fetch to query the correct published version for the given branch. |
| `timeout` | int | RPC:`5000`, HTTP:`60000` | Request timeout (ms) |

> **Note**: `idl_source` is fixed to `2` (from BAM) and cannot be changed.

### HTTP-Only Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `http_method` | string | `GET` | HTTP method: GET, POST, PUT, DELETE, PATCH |
| `http_query` | array | - | Query parameters appended to the path. Each entry is `{"key": "k", "value": "v"}`. Example: `[{"key": "key", "value": "task_254/task_summary"}]` |
| `http_req_headers` | array | - | Custom HTTP request headers. Each entry is `{"key": "Header-Name", "value": "header-value"}`. Content-Type is auto-set for POST/PUT requests |
| `http_cookies` | array | - | Cookies to send with the request. Each entry is `{"key": "cookie_name", "value": "cookie_value"}`. Entries are joined as `cookie_name=cookie_value; ...` in the Cookie header |
| `func_name` | string | - | Function name (e.g. `GetLiteLLMConfig`). Optional for HTTP |
| `http_host` | string | - | Host override. ⚠️ May cause routing 404 |

### HTTP pre-dispatch checklist

Before every HTTP request or HTTP retry, confirm:

- `action` is `http`; do not send HTTP paths through RPC mode.
- `http_path` is only the IDL path; move all query string fields into `http_query`.
- `http_query` entries use `[{"key":"...","value":"..."}]` shape and include required business keys.
- `bam-api` has resolved the endpoint/method when the path, IDL version, or required query keys are uncertain.

## VRegion & VDC Mapping (统一区域映射)

| VRegion | Aliases | VDCs | Gateway URL | JWT | Default Zone (RPC/HTTP) |
|---------|---------|------|-------------|-----|-------------------------|
| `Singapore-Central` | `sg` | sg1, my, my2, my3 | bc-useastdt-gw.tiktok-row.net | i18n | SGALI |
| `US-East` | `us`, `i18n` | maliva | bc-useastdt-gw.tiktok-row.net | i18n | MVAALI |
| `Asia-SouthEastBD` | `asia-southeastbd` | mya, myb, myc, bdsgdt, my5a | bc-useastdt-gw.tiktok-row.net | i18n | Asia-SouthEastBD |
| `China-North` | `cn`, `china` | lf, hl, lq, yg | paas-gw.byted.org | CN | CN |
| `ChinaSinf-North` | `chinasinf-north`, `chinasinfnorth`, `sinf-north`, `sinfnorth` | sinfonline, sinfonlinea, sinfonlinec | paas-gw.byted.org | CN | Sinf |
| `China-BOE` | `boe` | boe | paas-gw-boe.byted.org | CN | BOE |
| `US-BOE` | `boei18n` | boei18n | paas-gw-boei18n.byted.org | CN | i18n-BOE / BOEI18N |

## MD3C 兼容的服务发现

**服务发现失败常见原因**：
- VRegion 选择错误（服务未在该区域部署）
- VDC 选择错误（服务未在该数据中心部署）
- `env` 参数不正确

**服务发现失败的错误类型**：
- `instance not found` - 找不到实例
- `no available instance` - 无可用实例
- `no healthy instance` - 无健康实例
- `service not found` - 找不到服务
- `cluster not found` - 找不到集群
- `discovery failed` - 服务发现失败
- `找不到服务地址` - 服务地址解析失败

**处理方式**：
- **绝对不要自动切换 VRegion**：用户指定的 VRegion 是明确意图，禁止在未经用户确认的情况下尝试其他 VRegion。
- 如果用户仅指定了 VRegion 而未指定 VDC，遇到服务发现失败时，**先向用户说明错误原因**，然后建议用户尝试该 VRegion 下的其他 VDC（可参考 `md3c-knowledge` skill 获取 VDC 列表），**等待用户确认后再重试**。
- 如果用户同时指定了 VRegion 和 VDC，**直接报错并说明原因**，不要自动重试。

### Same-family recovery ladder

When bam-query fails with validation, service-discovery, HTTP path, or parameter errors, stay on the BAM path before considering repo/search/curl/deploy alternatives:

1. Normalize the current arguments against this page (`action`, PSM, vregion/vdc/env/cluster, method/path/func, request/query/header fields).
2. Re-check endpoint or method metadata with `bam-api` when path/func/IDL shape is uncertain.
3. Retry `bam-query` once with the corrected BAM arguments.
4. If still blocked, report the blocked BAM evidence tuple and the exact unmet input instead of switching proof surfaces.

## Output Format

```json
{
  "success": true,
  "action": "rpc",
  "psm": "desrpc.stability.thrift_server",
  "data": {
    "error_code": 0,
    "error_message": "",
    "log_id": "202602052110451579BFEAEF724107A05E",
    "address": "[fdbd:dccd:cde2:2009:4cd0:35ee:a9a5:d93e]:11721",
    "latency": "6.517642ms",
    "response": "{...}"
  }
}
```

Final answers must summarize the BAM evidence tuple, not just a success/failure sentence:

- action, PSM, VRegion, env/cluster or VDC, and method/path or `func_name`
- `log_id`, status or `error_code`, and a short response/error excerpt
- for blocked runs, the unmet BAM criterion and the exact parameter or metadata still needed

## Complete Examples

### RPC Example

```bash
gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{"action":"rpc","psm":"desrpc.stability.thrift_server","func_name":"GetItem","request":"{}","vregion":"US-BOE","env":"ppe_desrpc_test","vdc":"boei18n"}'
```

### HTTP Example (full params)

```bash
gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{"action":"http","psm":"tiktok.llmgw.api","http_method":"GET","http_path":"/api/v1/config/litellm","func_name":"GetLiteLLMConfig","vregion":"US-BOE","env":"prod","vdc":"boei18n","cluster":"default","idl_version":"1.0.5"}'
```

### HTTP Example (minimal)

```bash
gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{"action":"http","psm":"tiktok.llmgw.api","http_path":"/api/v1/config/litellm","vregion":"US-BOE"}'
```

### Canonical HTTP template: GetAsset

```bash
gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{
  "action": "http",
  "psm": "tiktok.eval.asset_store",
  "http_method": "GET",
  "http_path": "/assets/",
  "http_query": [{"key": "key", "value": "task_254/task_summary"}],
  "http_req_headers": [{"key": "X-Custom-Header", "value": "my-value"}],
  "vregion": "China-North",
  "env": "ppe_test_skill_bam",
  "idl_version": "1.0.2"
}'
```

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `psm is required` | Missing PSM | Add `psm` parameter |
| `vregion is required` | Missing VRegion | Add `vregion` parameter — must specify target region |
| `func_name is required` | Missing function for RPC | Add `func_name` parameter |
| `http_path is required` | Missing path for HTTP | Add `http_path` parameter |
| `HTTP path "..." not found` | Path doesn't match IDL | Check path matches IDL definition. If you have query params, move them to `http_query` instead of appending to `http_path` |
| `instance not found` | Zone mismatch | Set correct `vregion` or override `zone` |
| `connect timeout` | `vdc` set without `env` | Add `env` parameter |
| `i/o timeout` | Wrong `vregion` | Use correct `vregion` matching the target |
| `authentication failed` | JWT expired | Run `gdp login` first |
| `找不到服务地址` | 服务可能未在该VRegion内的默认VDC部署，或未在该VDC部署 | Follow the same-family recovery ladder; report the VRegion/VDC/env mismatch, suggest an in-region VDC retry only after user confirmation, and never switch VRegion automatically |
| `no available instance` | 同上 | Follow the same-family recovery ladder; keep the retry inside the requested VRegion/VDC/env scope |

## Authentication

JWT token authentication via `gdp login`. Make sure you have logged in first.

## Debugging

Use debug mode only after one BAM attempt has produced an unexplained transport/runtime failure. After a valid BAM result or a known parameter error, skip debug/help probes and either finalize or apply the same-family recovery ladder.

```bash
DEBUG=1 gdpa-cli run bam-query --session-id "$SESSION_ID" --input '{...}'
```

Logs saved to `/tmp/gdpa-agents/logs/`.

## Notes

- For non-BOE targets, confirm with user before sending; for BOE environments (`China-BOE`/`boe` or `US-BOE`/`boei18n`), you can skip confirmation and execute directly — BOE is non-production and does not affect live services
- **`vregion` is required**: Must specify vregion for every request. Supported: Singapore-Central, US-East, China-North, ChinaSinf-North, China-BOE, US-BOE
- `vregion` determines API gateway, JWT type, default zone and VDC
- `zone` and `vdc` are auto-derived from `vregion` but can be overridden
- `idl_source` is fixed to `2` (from BAM) — not user-configurable
- `idl_version` is auto-fetched from BAM's published version list; falls back to `master` if no versions are published
- Response includes `log_id` for tracing in Argos
- Use `http_status_code` in HTTP response to check if the target service returned expected status
- **Query params belong in `http_query`, not in `http_path`** — mixing them into the path can cause IDL validation failures
