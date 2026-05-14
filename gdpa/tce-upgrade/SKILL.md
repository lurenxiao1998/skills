---
name: tce-upgrade
description: This skill should be used when the user asks to "upgrade TCE service", "升级 TCE 服务", "更新服务版本", "deploy new version", "升级到新版本", "升级集群", "upgrade cluster", "上线", "发版", or needs to perform a TCE service upgrade in any environment (BOE, PPE, or production). Supports CN, BOE, and I18N control planes. This skill guides through the complete upgrade workflow including version selection, cluster selection, confirmation, and deployment monitoring.
allowed-tools: Bash(byte-cli:*)
version: 0.2.0
tags:
  - byte-skill
---

# ByteDance TCE Upgrade

> **版本**: 0.2.0 — 支持 BOE、CN (PPE)、I18N (Production) 三种控制面

## ⛔ 安全约束

### 环境限制

- ✅ 允许（无需额外确认）：
  - `BOE`（所有 env）
  - `CN` 且 env 名称以 `ppe_` 开头（例如 `ppe_xxx`）
- ✅ 允许（需用户明确要求时）：
  - 线上生产环境（I18N 控制面下的 US-East、Singapore-Central 等环境）
  - 前提：用户**明确、主动**要求操作线上环境
- ❌ 禁止：
  - 用户未明确要求时，自行发起线上生产环境变更

### 交互确认

- BOE / PPE 环境：建议在创建升级工单前要求确认
- 线上生产环境：**必须**在用户明确要求后才操作，且操作前需二次确认（包含 PSM、版本号、目标集群/区域）

### 禁止操作（本 skill 不执行）

- 不执行 Delete/Scale/Rollback/Cancel 等危险操作
- 只做：查询（Search/Get/List）→ 创建升级工单（CreateUpgradeTicket）→ 监控工单（GetDeploymentTicket）


## Prerequisites

1. **byte-cli installed**
   - `uv tool install --index https://bytedpypi.byted.org/simple --force "git+https://code.byted.org/bytedance/byte-skill.git#subdirectory=byte-cli"`
2. **Config path（本 skill 专用）**

   需要将本 skill 的 base directory 与相对路径 `assets/config.json` 拼接成完整路径传给 `--config` 参数：

   ```bash
   CONFIG="<base-dir>/assets/config.json"
   ```

3. **JWT 登录**

   根据目标控制面登录对应控制面：

   | 控制面 | 登录命令 | 适用环境 |
   |--------|---------|---------|
   | `BOE` | `byte-cli login --control-plane boe` | BOE 测试环境 |
   | `CN` | `byte-cli login --control-plane cn` | CN 线上 + PPE |
   | `I18N-TT` | `byte-cli login --control-plane i18n-tt` | I18N 线上生产环境 |

   JWT 自动从 Chrome cookies 获取，需确保已在对应平台的浏览器中登录。

## 控制面与区域说明

config.json 中定义了三个控制面，每个控制面对应不同的 API Gateway：

| 控制面 | config key | API Gateway | 适用区域 |
|--------|-----------|-------------|---------|
| BOE | `BOE` | `cloud-boe.bytedance.net` | BOE 测试 |
| CN | `CN` | `cloud.bytedance.net` | CN 线上 + PPE |
| I18N-TT | `I18N-TT` | `bc-sg-gw.tiktok-row.net` | US-East、Singapore-Central 等 I18N 生产环境 |

### CN vs I18N 的关键区别

| | CN 控制面 | I18N 控制面 |
|--|----------|------------|
| Gateway | `cloud.bytedance.net` | `bc-sg-gw.tiktok-row.net` |
| 平台入口 | cloud.bytedance.net | cloud.tiktok-row.net |
| 典型区域 | China-North | US-East, Singapore-Central |
| Zone 名称 | 如 `lf`, `sg1` | 如 `Aliyun_VA`, `Singapore-Central` |
| 登录 | `byte-cli login --control-plane cn` | `byte-cli login --control-plane i18n-tt` |

> **注意**：`Aliyun_VA` 是 I18N 控制面下 US-East VRegion 对应的 zone 名称。

## 最小升级流程（Happy Path）

下面以 `CONTROL_PLANE` 作为控制面占位符，实际使用时替换为 `BOE`、`CN` 或 `I18N-TT`。

### Step 1: SearchService → 获取 service_id

```bash
byte-cli --config "$CONFIG" TCE I18N-TT SearchService \
  --search "${PSM}" \
  --output-filter '.response_body.data'
```

从返回中提取：
- `service_id`（在 `data[].meta.id`）

### Step 2: GetService → 确认服务信息与 main repo

```bash
byte-cli --config "$CONFIG" TCE I18N-TT GetService \
  --service-id "${SERVICE_ID}" \
  --output-filter '.response_body.data'
```

建议关注：
- `meta.psm / meta.env / meta.status`
- `build.scm_repo_info[] | select(.main_repo == true)` 的 repo（用于主版本选择）

### Step 3: ListClusters → 获取可升级集群

```bash
byte-cli --config "$CONFIG" TCE I18N-TT ListClusters \
  --service-id "${SERVICE_ID}" \
  --output-filter '.response_body.data'
```

你需要从每个 cluster 提取：
- cluster id：`meta.id`
- name：`meta.name`
- zone / physical_cluster：`resource.zone` / `resource.physical_cluster`
- rollout_strategy

> **I18N 提示**：I18N 控制面下 zone 名称可能是 `Aliyun_VA`（对应 US-East）、`Singapore-Central` 等。

### Step 4: GetRepoInfoList → 获取可选版本

```bash
byte-cli --config "$CONFIG" TCE I18N-TT GetRepoInfoList \
  --service-id "${SERVICE_ID}" \
  --output-filter '.response_body.data'
```

建议处理策略：
- 主 repo：给用户展示最近 5 个版本，确认目标版本
- 非主 repo（如 `toutiao/load`、`toutiao/runtime`）：默认取各自最新版本（页面默认行为）

### Step 5: 组装 CreateUpgradeTicket payload

`CreateUpgradeTicket` 的关键字段：
- `--service`：service_id（integer）
- `--cluster-list`：JSON array 字符串，例如：`[{"id":598489,"rollout_strategy":"eager"}]`
- `--cluster-info`：JSON object 字符串，需包含 `runtime.repo_info`（即页面里的 repo_info 列表，包含主 repo 和非主 repo）

示例：

```bash
CLUSTER_LIST='[{"id":598489,"rollout_strategy":"eager"},{"id":598490,"rollout_strategy":"eager"}]'

CLUSTER_INFO='{"runtime":{"repo_info":[
  {"name":"des/mq/console","version":"1.0.0.5830","description":"feat: add proxy","scm_repo_id":"135127"},
  {"name":"toutiao/load","version":"1.0.2.619","description":"","scm_repo_id":"667"},
  {"name":"toutiao/runtime","version":"1.0.1.845","description":"","scm_repo_id":"631"}
]}}'

byte-cli --config "$CONFIG" TCE I18N-TT CreateUpgradeTicket \
  --service "${SERVICE_ID}" \
  --pipeline-template 1 \
  --cluster-list "$CLUSTER_LIST" \
  --cluster-info "$CLUSTER_INFO"
```

返回中提取：
- `ticket_id`（在 `data.id` 或 `data.pipeline_id`）

> **注意**：`cluster_info` 必须包含**所有** repo（主 repo + 非主 repo），否则 TCE 会报参数错误。非主 repo 的版本默认取最新即可。

### Step 6: 用户确认后创建升级工单

同 Step 5，执行 `CreateUpgradeTicket`。

### Step 7: 监控工单

```bash
byte-cli --config "$CONFIG" TCE I18N-TT GetDeploymentTicket \
  --ticket-id "${TICKET_ID}" \
  --output-filter '.response_body.data.meta'
```

- 轮询频率：60s
- 超时建议：10min
- 终态：`success/finished/failed/cancelled`（以实际字段为准）

完整轮询脚本与更友好的输出格式见：`references/monitoring.md`。

## 常见失败场景（精简版）

- `service not found`：PSM/控制面不对；回到 Step 1 校验
- `No valid cookie` / JWT 过期：重新执行 `byte-cli login --control-plane <control-plane>`
- `InvalidParameter`：多见于 `CreateUpgradeTicket` payload 字段缺失/格式不对；对照 `references/api.md` 的 payload 要求
- `Permission denied`：需要 service owner 授权
- I18N 控制面找不到 US-East：检查 zone 名称是否为 `Aliyun_VA`（不是 `US-East`）
