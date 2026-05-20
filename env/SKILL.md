---
name: env
description: "Query and manage Env Platform BOE/PPE environments: details, services, clusters, permissions, fallback config, DSL deploy/upgrade/delete for TCE/TCC, environment create/delete, deployment status, and SCM dependencies. Use when the user mentions Env Platform, BOE/PPE environments, DSL deploy, TCE/TCC deployment, environment management, service deployment, or environment creation."
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# Env Platform 查询与部署

> **何时使用**: 查询或管理 BOE/PPE 环境信息，包括环境详情、服务列表、集群信息、权限检查、Fallback 配置、服务部署（创建/升级/删除）、环境创建、部署状态查询、SCM 依赖等。

## 快速路径决策表

执行任何操作前，根据意图直接选择对应 action，无需重复读取本文件：

| 意图 | Action | 必填参数 |
|------|--------|----------|
| 查询环境详情 | detail | name, vregion |
| 查询服务列表 | service_info | name, vregion |
| 查询 PSM 集群信息 | cluster_info | psm, scope, vregion |
| 检查操作权限 | check_permission | psm, scope, env, vregion |
| 查询 Fallback 配置 | fallback_conf | env_name, env_type, vregion |
| 查询实例元信息 | instance_meta | name, vregion |
| 获取部署建议 | create_suggest | psm, vregion |
| 查询 SCM 依赖 | scm_dependencies | psm, vregion |
| 部署/升级/删除服务（已有环境） | dsl_deploy | name, psm, vregion |
| 创建新环境+部署服务 | dsl_create | name, psm, version/branch, vregion |
| 部署 ByteFaaS（已有环境） | faas_deploy | name, psm, vregion |
| 创建新环境+部署 ByteFaaS | faas_create | name, psm, vregion |
| 查询部署状态 | dsl_status | deployment_id, vregion |
| 重试失败部署 | dsl_retry | deployment_id, vregion |
| 删除环境 | delete_env | name, vregion |

> 参数详情见 [action-reference.md](references/action-reference.md)

## Action 选择流程

```
1. 需要创建新环境？→ TCE/TCC: dsl_create | ByteFaaS: faas_create
2. 已有环境中操作？→ 部署: dsl_deploy / faas_deploy | 状态: dsl_status | 重试: dsl_retry
3. 仅查询？→ 按意图选择 detail/service_info/cluster_info/check_permission/...
```

## 部署完成门禁

**给出最终答案前必须验证：**

1. **deployment_id** — 部署请求返回的 ID；缺失 = 部署未发起
2. **终态确认** — `dsl_status` 必须为 `success` 或 `failure`，非 `Pending`/`running`；若运行中则轮询至终态
3. **集群/服务对账** — 结果须包含目标 PSM 对应的集群或服务信息
4. **失败证据** — 部署失败时必须包含原因，不得以"成功"措辞结尾
5. **环境标识** — 答案须包含 env name 和 vregion

**禁止**：`dsl_status` 返回非终态时不得声称部署成功。

## 跟进调用校验

`dsl_status`/`dsl_retry`/后续 `dsl_deploy` 必须从上一步携带：

- **deployment_id** — 不接受空值/占位符（`0`/`""`/`null`）
- **vregion** — 须与首次部署一致
- **env/name/env_name** — 如果上一步返回里带了环境名，建议一并保留到后续命令里，方便人工核对，但当前 API 不把它当作必填路由参数

缺失 `deployment_id` 或 `vregion` 时须先查询补全后再发起跟进调用。

## 轮询策略

- 短间隔重试（10–15 秒），最多 6 次
- **禁止**长阻塞包装命令（如 `sleep 45 && dsl_status`）
- 超过上限未终态时报告当前状态

## 使用方法

```bash
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "<action>", ...}'
```

## 通用参数

| 参数 | 类型 | 描述 |
|------|------|------|
| action | string | 必填，要执行的操作 |
| name | string | 环境名称（如 `boe_xxx` 或 `ppe_xxx`） |
| psm | string | 服务 PSM |
| vregion | string | **必填**，VRegion 常量，未指定时须先询问用户 |

## Action 一览

### 查询类

| Action | 描述 | 必填参数 |
|--------|------|----------|
| detail | 获取环境详情 | name |
| service_info | 获取服务列表 | name |
| cluster_info | 获取集群信息 | psm, scope |
| check_permission | 检查操作权限 | psm, scope, env |
| fallback_conf | 获取 Fallback 配置 | env_name |
| instance_meta | 获取实例元信息 | name |
| create_suggest | 获取部署建议 | psm |
| scm_dependencies | 获取 SCM 依赖 | psm |

### 部署类

| Action | 描述 | 必填参数 |
|--------|------|----------|
| dsl_deploy | 部署/升级/删除 TCE/TCC 服务 | name, psm |
| dsl_create | 创建新环境+部署 TCE/TCC | name, psm, version/branch |
| faas_deploy | 部署 ByteFaaS（已有环境） | name, psm |
| faas_create | 创建新环境+部署 ByteFaaS | name, psm |
| delete_env | 删除整个环境 | name |
| dsl_status | 查询部署状态 | deployment_id |
| dsl_retry | 重试失败部署 | deployment_id |

> 各 action 可选参数、自动补全规则、TCC/ByteFaaS 注意事项见 [action-reference.md](references/action-reference.md)

## 错误处理

| 错误 | 解决方案 |
|------|----------|
| `action parameter is required` | 添加 action |
| `name parameter is required` | 添加 name |
| `deployment_id parameter is required` | 添加 deployment_id |
| `TCC deployment requires 'region'` | 添加 region |
| `authentication failed` | 运行 `gdpa-cli login` |
| `NOT_EXIST env not exists` | 检查名称或用 dsl_create |
| `Quota checking failed` | 减少配额需求或申请更多 |
| `unfinished tickets` | 等待前一个部署完成 |

## 注意事项

- **vregion 为必填参数**，未指定时须先询问用户目标区域
- TCC 部署 `region` 为必填（如 `EU-TTP`、`US-EastRed`）
- `dsl_status`/`dsl_retry` 只强制要求 `deployment_id + vregion`；若上一步输出里已有 `env/name/env_name`，建议一并保留，便于人工核对
- 部署后轮询：`Pending` → `running` → `success`/`failure`
- 需先 `gdpa-cli login` 获取认证凭据
- `faas_deploy` upgrade 须提供 `cluster`
- 环境名称通常以 `boe_` 或 `ppe_` 为前缀

> VRegion 列表见 [vregion-reference.md](references/vregion-reference.md)
> 输出格式见 [output-format.md](references/output-format.md)
> 完整示例见 [deploy-examples.md](references/deploy-examples.md)
