# EMS · RDS deployment actions (Path 1 — DDL only, no entity update)

This file covers the three actions that drive a DDL change **without** touching the EMS entity catalog. They are the deliberate escape hatch from the standard `change_rds_table` lifecycle (Path 2) — use them when you have a working DDL on the live RDS but do **not** want EMS to register / update the entity metadata.

| action | role |
|---|---|
| `execute_rds_ddl` | (write, two-phase) push (vregion, sql) deployments straight through the RDS OpenAPI `execute_ddl_sql` endpoint. Returns a `global_deployment_id`. |
| `get_deployment_info` | (read-only) query per-vregion deployment status for a previously-issued `global_deployment_id`. |
| `cancel_deployment` | (write, two-phase) cancel an in-flight deployment. Preview 先 probe 每 vregion 状态，confirm 才提交。后端幂等；publish 阶段对 PPE 1s 超时有自动恢复。 |

先读 `SKILL.md` 拿全局 region / output envelope 约定，再回到这里。

## When to use Path 1 — 三类合法场景

EMS Entity 的两大下游消费方决定了它是否值得登记：

1. **DECC 平台打标**：DECC（数据合规与分类系统）通过 EMS 实体目录读字段元数据，做 PII / 敏感字段打标 / 风险审计。
2. **DES-MQ 跨 VGeo 数据同步**：DES-MQ 通过 EMS 的 Entity + Mapping + Sync Channel 把同一张逻辑表在多个 vregion 之间复制（Singapore-Central ↔ EU-TTP2 ↔ US-East）。

**只要这两条用户都不需要，就不需要 EMS Entity** —— 这种表直接走 Path 1 (`execute_rds_ddl`) 把 SQL 推到 RDS 即可，完全跳过 EMS 工作流（CREATE 与 ALTER 都适用）。Path 2 / 3 在这种情况下只是徒增 Owner 审批 + BPM 工单两道纯负担。

具体三类合法场景：

### 1. 表完全不需要 EMS（首选 Path 1）

判定标准 —— **必须由用户主动声明，两条都满足**：

1. 用户明确表示**无需在 DECC 平台打标**（不依赖 EMS 元数据做 PII / 敏感字段识别 / 合规审计）；
2. 用户明确表示**无需依赖 DES-MQ 做跨 VGeo 数据同步**（自己用 RDS 内置 binlog / MMR / 业务双写 / KSQL 等机制处理跨地域，或者本来就不打算跨地域）。

这两条是「**未来意图**」声明，不是当前部署状态：单 vregion 部署的表以后也可能扩展到多 vregion 并需要跨 VGeo 同步 —— 所以**不要根据"当前是否单 vregion"来判断**，否则后期扩展时所有数据都没有 EMS 实体记录，迁移成本会很高。

判断只能由用户/业务方做出。skill 不替用户做这个决定 —— 当用户既没说不要 DECC、也没说不要 DES-MQ 时，**默认走 Path 2/3** 把 entity 登记上，留好将来接入 DECC + DES-MQ 的口子。

满足两条声明后，CREATE 与 ALTER 全部走 `execute_rds_ddl`，**根本不会出现在 EMS 实体目录里**。

### 2. Entity-neutral ALTER（已经有 entity，但本次变更不影响 entity 元数据）

表已经在 EMS 里登记过，但本次 ALTER 只动 ENGINE / AUTO_INCREMENT / ROW_FORMAT 等表选项，不会改任何 EMS 跟踪的字段。详见下一节「entity-neutral ALTER 速查」。

### 3. EMS 紧急绕行（少见）

EMS workflow 出现卡死或环境异常，需要紧急把 RDS 部署推过去；事后再调 `import_online_table` (Path 5) / `change_rds_table` (Path 2) 把 EMS 元数据补回。

## ⚠️ When NOT to use Path 1

Path 1 **不会更新 EMS 实体目录**。所以以下场景必须走 Path 2 (`change_rds_table`) 或 Path 3 (`change_rds_table_with_entity_edits`)：

- 表要接入 DECC 平台做字段打标 / PII / 合规审计 —— DECC 读 EMS 实体目录拿字段元数据，跳过 Path 2 之后 DECC 看不到这张表；
- 表要依赖 DES-MQ 做跨 VGeo 数据同步 —— DES-MQ 通过 EMS 的 Entity + Mapping + Sync Channel 编排同步链路，没有 entity 就没有同步；
- 用户没明确表态「不要 DECC + 不要 DES-MQ」（哪怕只是没说），默认按需要 EMS 处理 —— 留好将来接入的口子；
- 表已在 EMS 注册并且本次变更涉及字段 / 索引 / 列注释 / 默认值 / 表选项 charset 等任何 entity-tracked 元数据 —— 用 Path 1 跑会让 EMS 视角和物理 schema 漂移。

每次 preview / publish 输出都会在 `risk_warnings` 数组里附上一条「跳过 EMS 实体更新」的提示；接受 `confirm=true` 之前请把第一条 risk warning 转述给用户。

## Entity-neutral ALTER 速查

> 适用前提：表**已经在 EMS 登记过 entity**，但本次 ALTER 只改物理表选项。如果表本身完全不需要 EMS（上一节场景 1），无论 CREATE 还是 ALTER 都可以直接走 Path 1，不必先看这张表。

Entity-neutral ALTER = 该 DDL 完全不会改动 EMS 实体目录里跟踪的任何字段。EMS 实体目录覆盖以下结构：

- `entity.fields[]`（字段名 / 类型 / codec / innerFields / description / tags / pii_labels）
- `entity.indices[]`（实体级索引）
- `mapping.<type>.columns[]`（列名 / 列类型 / 列注释 / 默认值 / 是否可空）
- `mapping.<type>.tableIndices[]`（物理索引）
- `mapping.<type>.tableOption`（charset / collate / 表注释）

只要 ALTER 涉及上面任何一项，就**不是**entity-neutral —— 必须走 Path 2/3。

### ✅ Entity-neutral（可直接走 Path 1）

| ALTER 子句 | 例子 | 为什么 entity-neutral |
|---|---|---|
| `ENGINE = X` | `ALTER TABLE t ENGINE = InnoDB` | 引擎不在 entity 元数据里。 |
| `AUTO_INCREMENT = N` | `ALTER TABLE t AUTO_INCREMENT = 10000` | 自增计数器，不影响 schema。 |
| `ROW_FORMAT = X` | `ALTER TABLE t ROW_FORMAT = DYNAMIC` | 物理存储选项，不在 entity 里。 |
| `KEY_BLOCK_SIZE = N` | `ALTER TABLE t KEY_BLOCK_SIZE = 8` | 物理存储选项，不在 entity 里。 |
| `STATS_*` 系列 | `ALTER TABLE t STATS_AUTO_RECALC = 1` | 统计信息选项，不在 entity 里。 |
| `DELAY_KEY_WRITE = X` | `ALTER TABLE t DELAY_KEY_WRITE = 1` | MyISAM 选项，不在 entity 里。 |

### ❌ NOT entity-neutral（必须走 Path 2/3）

| ALTER 子句 | 影响的 EMS 字段 |
|---|---|
| `ADD/DROP/MODIFY/CHANGE COLUMN`、`ALTER COLUMN SET/DROP DEFAULT` | `entity.fields[]` + `mapping.<type>.columns[]` |
| `ADD/DROP INDEX/KEY/UNIQUE/PRIMARY KEY/FULLTEXT/SPATIAL`、`RENAME INDEX` | `entity.indices[]` + `mapping.<type>.tableIndices[]` |
| `ADD/DROP CONSTRAINT`、`ADD/DROP FOREIGN KEY` | 同上索引/约束 |
| `RENAME COLUMN ... TO ...`、`CHANGE COLUMN old new ...` | 字段名 = entity 主键，必走 Path 2/3 |
| `MODIFY COLUMN x TYPE COMMENT '...'` | 列注释属于 mapping.columns，**也不是 neutral** |
| `CONVERT TO CHARACTER SET`、`DEFAULT CHARACTER SET`、`COLLATE` | 改 `mapping.<type>.tableOption.charset/collate` |
| `COMMENT = '...'`（表级注释） | 改 `mapping.<type>.tableOption.comment` |
| `RENAME TO new_table` | 表名 = entity URI 的一部分，需要 EMS 重新登记 |

### Skill 自动提示

`change_rds_table` 与 `change_rds_table_with_entity_edits` 在 preview 阶段会做一次合并校验（DDL 关键字白名单 + EMS validate 推断结果对比），如果整批 ALTER 都判定为 entity-neutral，就在 `next_steps` 数组里追加一条 `id: "use_path1"` 的建议；否则不出。该提示是「可选的捷径」，不是必须 —— 即使 entity-neutral，用户仍然可以走 Path 2 让 EMS 留个发布留痕。判断逻辑保守：但凡能走任何字段/索引/列变动，就**不**会建议 Path 1。

如果 skill 没主动给你 hint，但你判断这条 ALTER 真的只动 `ENGINE` / `AUTO_INCREMENT` 之类的表选项，可以直接选 `execute_rds_ddl` 跑 —— 不强制依赖 hint。

> ⚠️ 这条 hint 只面向「表已在 EMS 登记过 entity」的场景。对于「表完全不需要 EMS」的场景（上文场景 1），用户从一开始就该直接选 `execute_rds_ddl`；skill 不会做「这张表是否需要 EMS」的代决定 —— 这个判断只能由用户/业务方做出。

## RDS / MySQL only

`execute_rds_ddl` 与 `change_rds_table` 一样，仅支持 `tiktok/mysql/...` storage。其它 storage 类型一律拒绝。

## Inputs — `execute_rds_ddl`

`execute_rds_ddl` 的输入与 `change_rds_table` 几乎一致，复用同一个 `tables[]` parser；区别只是没有 entity 推断 + 多一个 `rds_psm` override。

### Top-level fields

| Field | Type | Notes |
|---|---|---|
| `rds_uri` / `storage_uri` | string | Required (one of three) — pin the shared RDS. |
| `rds_psm` | string | Optional. When set, used verbatim as the `psm` for every (vregion, sql) entry. **Wins over** the storage's `idcinfos` PSM. Useful when the storage owns multiple PSMs and you need to target a specific one. |
| `vregions` | []string or csv | Default vregion list. Each row may override. |
| `sync_alter_to_stress_table` | bool | Forwarded verbatim to `ExecuteRdsDdlVregionRequest.sync_alter_to_stress_table`. |
| `confirm` | bool | Preview by default; pass `true` to actually call RDS OpenAPI. |

### `tables[]` per-row fields

Same as `change_rds_table` minus entity-only fields (`entity_uri`, `operation`):

| Field | Type | Required | Notes |
|---|---|---|---|
| `table_name` | string | Yes | Physical RDS table name. (No `entity_uri` fallback — Path 1 does not need to resolve an entity.) |
| `ddl_sql` | string | One of `ddl_sql` / `regional_sql_list` | DDL applied to every vregion of this row. |
| `regional_sql_list` | []object | One of `ddl_sql` / `regional_sql_list` | `[{"vregion":"Singapore-Central","sql":"..."}]`. |
| `vregions` | []string | No | Per-row override of the shared default. |
| `is_sharding_table` | bool | No | Forwarded verbatim. |
| `sharding_key` / `sharding_key_type` | string | When `is_sharding_table=true` | Forwarded verbatim. |
| `sync_alter_to_stress_table` | bool | No | Per-row override of the shared default. |

### PSM resolution

`execute_rds_ddl` needs a PSM per (vregion, sql) entry. Resolution order:

1. Top-level `rds_psm` — when set, used for every vregion.
2. Storage `idcinfos[]` lookup: each `idcinfos[i]` entry maps `idc → vregion` via `gopkg/env`; the matching entry's `psm` is used.
3. Fallback: if no `idc → vregion` mapping resolves, the first `idcinfos[i].psm` is used as a single fallback PSM.

If neither path yields a PSM for a given vregion, the dispatcher errors out with `INPUT-002` naming the offending vregion so the user can pass `rds_psm` explicitly.

## Output — `execute_rds_ddl`

### Preview (`confirm=false`, default)

```jsonc
{
  "display_action": "Execute RDS DDL (no entity update)",
  "storage_uri":    "tiktok/mysql/new_one_rds",
  "psm":            "tiktok.mysql.new_one_rds",
  "shared_vregions": ["Singapore-Central"],
  "tables": [
    {
      "entity_uri":        "tiktok/mysql__new_one_rds__foo",   // best-effort echo
      "table_name":        "foo",
      "operation":         "CREATE",
      "regional_sql_list": [{"vregion":"Singapore-Central","psm":"toutiao.mysql.new_one_rds_sg","sql":"CREATE TABLE foo …"}]
    }
  ],
  "risk_warnings":    ["execute_rds_ddl 跳过 EMS 实体更新：DECC / DES-MQ / 数据血缘等依赖 EMS 元数据的下游工具不会感知到这次变更…"],
  "published":        false,
  "confirm_required": true,
  "next_steps":       ["确认后将通过 RDS OpenAPI 直接执行此 DDL（共 N 条 vregion 部署）"]
}
```

### Publish (`confirm=true`)

```jsonc
{
  "display_action":       "Execute RDS DDL (no entity update)",
  "storage_uri":          "tiktok/mysql/new_one_rds",
  "psm":                  "tiktok.mysql.new_one_rds",
  "published":            true,
  "tables":               [ … same per-row shape as preview … ],
  "global_deployment_id": "dep-abc-001",
  "data":                 { … raw ExecuteRdsDdl response … },
  "risk_warnings":        ["execute_rds_ddl 跳过 EMS 实体更新…"],
  "next_steps":           ["可使用 get_deployment_info global_deployment_id=\"dep-abc-001\" 查询每个 vregion 的部署状态；如需取消可调用 cancel_deployment。"]
}
```

If the backend response does not include a `global_deployment_id`, `next_steps[0]` switches to "已提交，但响应中未包含 global_deployment_id；请通过 RDS 平台直接查看部署状态。" — the request succeeded but you'll need to track status via the RDS console.

## Inputs / Output — `get_deployment_info`

Read-only.

| Field | Type | Required |
|---|---|---|
| `global_deployment_id` | string | Yes |

Output:

```jsonc
{
  "global_deployment_id": "dep-abc-001",
  "data":                 { … raw GetDeploymentInfo response … },
  "per_vregion": [
    {"vregion":"Singapore-Central","deployment_status":3,"deployment_status_name":"success","pipeline_url":"…"},
    {"vregion":"US-East","deployment_status":2,"deployment_status_name":"running","pipeline_url":"…"}
  ]
}
```

`per_vregion` is a flattened view of the backend's `data.vregion2_deployment_info` map so agent UIs can render a clean table without re-walking the map. Forward-compat passthrough — any extra keys on the per-vregion object are forwarded verbatim.

## Inputs / Output — `cancel_deployment`

Two-phase (mirrors `close_workflow`). Preview 阶段调一次 `GetDeploymentInfo` 把每 vregion 当前的状态展示给用户，`confirm=true` 才向后端发送 cancel 请求。后端幂等 —— 重复 confirm 是 no-op；已经处于 terminal (`Cancelled` / `Success` / `Failed`) 状态的 vregion 也是 no-op。

| Field | Type | Required | Notes |
|---|---|---|---|
| `global_deployment_id` | string | Yes | `execute_rds_ddl` 返回的 deployment id。 |
| `confirm` | bool | No | 默认 `false`（preview）；传 `true` 才真正取消。 |

### Preview (`confirm` unset / false)

```jsonc
{
  "display_action":       "Cancel RDS Deployment",
  "global_deployment_id": "dep-abc-001",
  "per_vregion": [
    {"vregion":"Singapore-Central","deployment_status":2,"deployment_status_name":"Running","pipeline_url":"…","first_build_url":"…?ppl_action=cancel"},
    {"vregion":"EU-TTP2","deployment_status":12,"deployment_status_name":"Cancelled","pipeline_url":"…","first_build_url":"…?ppl_action=cancel"}
  ],
  "expected_results": [
    "该 global_deployment_id 下所有处于 in-flight 状态（Pending / Running 等）的 vregion 部署都会被取消。",
    "已经处于 terminal 状态（Cancelled / Success / Failed）的 vregion 不受影响 —— 后端幂等。",
    "已经成功落地的 DDL 变更不会回滚；如需逆向，请新建反向 DDL。"
  ],
  "published":        false,
  "confirm_required": true,
  "next_steps":       ["确认后将通过 EMS OpenAPI 取消该 deployment（共 N 个 vregion，后端幂等）。"]
}
```

### Publish (`confirm=true`)

```jsonc
{
  "display_action":       "Cancel RDS Deployment",
  "global_deployment_id": "dep-abc-001",
  "published":            true,
  "cancelled":            true,
  "data":                 { … raw CancelDeployment response … },
  "next_steps":           ["已发送取消请求。该接口幂等，重复调用会得到同样结果；通过 get_deployment_info 确认最终状态。"]
}
```

> Publish 阶段不再额外打 `GetDeploymentInfo`（preview 阶段已展示一次），只在 RPC 超时触发自动恢复时才 probe。如果你想在 cancel 后再核对最终状态，请按 `next_steps` 指示再跑一次 `get_deployment_info`。

### Upstream RPC timeout auto-recovery (publish phase only)

EMS 平台 API → `tiktok.ems.openapi_v2` 这一跳的 `request_timeout` 默认 1s，PPE 上稳定地超过这个阈值（实测 1002ms 左右）。在原始实现里这会让客户端看到 `RPCError ErrType:[RPC_FAILED] reason=request timeout request_timeout=1000ms`，但**服务端实际已经接受 cancel 请求并把 deployment 切到 `Cancelled`**。

publish 阶段（`confirm=true`）对这种情况做自动恢复 —— preview 阶段不会触发，因为 preview 只读不下发：

1. 收到 `RPC_FAILED` / `request timeout` / `request_timeout=` 形态的错误时，自动调用一次 `GetDeploymentInfo` 二次确认。
2. 如果每个 vregion 的 `deployment_status_name` 都是 `Cancelled`，把响应降级成普通的成功，并附一条 `risk_warnings`：

   ```jsonc
   {
     "display_action":       "Cancel RDS Deployment",
     "global_deployment_id": "dep-abc-001",
     "published":            true,
     "cancelled":            true,
     "per_vregion":          [ … flattened deployment-info rows … ],
     "risk_warnings":        ["cancel_deployment 上游 RPC 超时…二次调用 get_deployment_info 显示所有 vregion 已 Cancelled，本 skill 自动按成功处理。"],
     "next_steps":           ["Cancel 已落地。如需再做一次核验可跑 get_deployment_info global_deployment_id=dep-abc-001。"]
   }
   ```

3. 如果 probe 显示部分 vregion 还在 in-flight，原始 RPC 错误透传给调用方，并在 wrap 里追加 `, 可手动 cancel: <vregion>=<bits_pipeline_url>` 让用户直接到 BITS pipeline 上手动取消（已经 Cancelled 的 vregion 不会出现在这个提示里）。
4. 如果 probe 自身也失败（例如同一个网关再次 502），返回组合错误同时点名两个失败动作 + 给出复核命令。

非 transient 错误（鉴权、validation、参数错误等）**不会**触发 probe，原样透传，避免无谓地打 audit log / 403。

## Typical workflows

### Cancel a stuck deployment

```bash
gdpa-cli run ems --session-id "$S" --input '{
  "action": "get_deployment_info",
  "global_deployment_id": "dep-abc-001"
}'

# Output shows one vregion stuck in deployment_status=2 / "running" for an hour;
# cancel_deployment is two-phase — first call previews per_vregion + expected_results.
gdpa-cli run ems --session-id "$S" --input '{
  "action": "cancel_deployment",
  "global_deployment_id": "dep-abc-001"
}'

# Re-run with confirm:true to actually fire the cancel.
gdpa-cli run ems --session-id "$S" --input '{
  "action": "cancel_deployment",
  "global_deployment_id": "dep-abc-001",
  "confirm": true
}'
```

### Re-import after Path 1 deploy

```bash
gdpa-cli run ems --session-id "$S" --input '{
  "action": "execute_rds_ddl",
  "rds_uri": "tiktok/mysql/new_one_rds",
  "tables": [{"table_name":"foo","ddl_sql":"CREATE TABLE foo …"}],
  "confirm": true
}'
# Wait for the deployment to succeed via get_deployment_info, then …
gdpa-cli run ems --session-id "$S" --input '{
  "action": "import_online_table",
  "rds_uri": "tiktok/mysql/new_one_rds",
  "table_name": "foo",
  "confirm": true
}'
```
