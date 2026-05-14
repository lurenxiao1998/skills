# 发布单工具

在 BITS 创建发布单，并查询发布单基本信息。本工具与 [SKILL_tcc_config.md](./SKILL_tcc_config.md) 配合使用：先 `create_release_ticket` 创建发布单，再用 TCC 配置变更类 action（传 `release_ticket_id`）在发布单上修改 TCC 配置。

> **当前能力范围**：本工具针对 TCC 类型发布单做了便捷入参；其他项目类型（TCE / Web / FaaS）尚未支持完整 `build_configs` 透传，请走 BITS 页面创建。

## 模板分类（必读）

BITS workspace 下的发布单模板分两类，对应 UI "创建发布单 → 选择模板"侧栏：

| 类别 | 典型名字 | `team_flow_id` | 适用场景 | AI 独立创建 |
|------|---------|:---:|---------|:---:|
| **standalone（推荐）** | "单发布单" / "GDP 发布模版" | `0` | 无需先建 dev_task，发布单内直接做 TCC 配置变更 / 测试 / 发布 | ✅ |
| team_flow-bound | "需求发布" / "火车发布" | 非 0 | 在已有 dev_task 内部点 "创建发布单" 派生出来，与 dev_task 联动 | ⚠️ 不推荐独立创建 |

**经验法则**：AI agent 直接调 `create_release_ticket` 时，**应该选 standalone 模板**（`team_flow_id=0`），匹配人在 BITS UI 上选择"单发布单"的语义；只有当上下文里已经有一个 dev_task 并要为它派生发布单时，才用 team_flow-bound 模板（且必须传对应的 `team_flow_id`）。

可调 `list_workspace_workflows`（默认 `kind=standalone`）查询当前 workspace 下可用的 standalone 模板。

## create_release_ticket — 创建发布单

在指定 workspace 下创建一个新发布单。鉴权使用当前登录用户的 JWT 自动换取，无需手动传 `access_token`。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `name` | string | 是 | 发布单名称 |
| `workspace_id` | number | 是 | BITS 空间 ID（可通过 `get_recent_spaces` / `get_workspace_info` 获取） |
| `workflow_id` | number | 是 | 发布单模板 ID（**release workflow id，不是 dev_task workflow id**）。建议先调 `list_workspace_workflows` 取一个 standalone 模板（如"单发布单"）；想沿用同 workspace 已有发布单的模板也可以参考它的 `workflow_id` |
| `description` | string | 是 | 发布单描述 |
| `control_planes` | string[] | 是 | 控制面列表，支持别名 `cn` / `i18n` / `eu-ttp` / `us-ttp` 或常量名 `CONTROL_PLANE_*` |
| `projects` | object[] | 是 | 发布单包含的项目，至少 1 项。结构见下方 |
| `creator` | string | 否 | 创建者 username，默认取当前登录用户 |
| `release_approvers` | string[] | 否 | 发布负责人列表，默认 `[creator]` |
| `test_approvers` | string[] | 否 | 测试负责人列表，默认 `[creator]` |
| `team_flow_id` | number | **条件必填** | standalone 模板填 `0`（默认）；team_flow-bound 模板必须提供，否则 BITS 报 `team flow ID invalid (code=130168)`。可调 `list_workspace_workflows kind=team_flow` 查询每个 team_flow 模板对应的 `team_flow_id` |
| `notice` | string | 否 | 发布公告，默认空 |
| `is_from_create_dev_task` | bool | 否 | 是否从创建开发任务路径过来，默认 `false` |

**`projects` 字段结构（每个元素是一个对象）**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `project_unique_id` | string | 是 | 项目唯一 ID。TCC 项目即 PSM（如 `tiktok.passport.authnbridge`） |
| `project_type` | string | 否 | 项目类型，支持别名 `tcc` / `tce` / `faas` / `web` 或常量名 `PROJECT_TYPE_*`，默认 `tce` |
| `project_name` | string | 否 | 项目展示名，默认等于 `project_unique_id` |
| `psm` | string | 否 | TCC/TCE 项目的 PSM，默认等于 `project_unique_id` |
| `project_owners` | string[] | 否 | 项目负责人列表，默认 `[creator]` |
| `build_configs` | object[] | 否 | 当前版本未支持透传：传入非空数组会报错；省略时系统按外层 `control_planes` 自动生成空 `BuildConfig`（TCC 场景适用） |

**前置：查询可用的 standalone 模板**：

```bash
gdpa-cli run bits-devops --input '{
  "action": "list_workspace_workflows",
  "space_id": 94017024770
}'
# kind 默认为 "standalone"，返回示例：
# {
#   "workflows": [
#     {"workflow_id": 425268053506, "team_flow_id": 0, "name": "单发布单",   "is_standalone": true, "num_of_associated_dev_task_type": 1},
#     {"workflow_id": 404470188034, "team_flow_id": 0, "name": "GDP发布模版", "is_standalone": true, "num_of_associated_dev_task_type": 1}
#   ]
# }
```

**推荐示例（standalone "单发布单" 模板，AI agent 默认走这条）**：

```bash
gdpa-cli run bits-devops --input '{
  "action": "create_release_ticket",
  "name": "AuthNBridge Policy Storage Optimization",
  "workspace_id": 94017024770,
  "workflow_id":  425268053506,
  "team_flow_id": 0,
  "description":  "TCC daily release for authnbridge",
  "control_planes": ["cn", "i18n", "eu-ttp", "us-ttp"],
  "projects": [
    {"project_type": "tcc", "project_unique_id": "tiktok.passport.authnbridge"}
  ]
}'
```

**仅在已有 dev_task 派生场景下使用：team_flow-bound 模板**：

```bash
# 1) 先查 team_flow workflows
gdpa-cli run bits-devops --input '{"action":"list_workspace_workflows","space_id":94017024770,"kind":"team_flow"}'

# 2) 用 team_flow workflow_id + 对应 team_flow_id
gdpa-cli run bits-devops --input '{
  "action": "create_release_ticket",
  "name": "Daily release 2026-05-09",
  "workspace_id": 94017024770,
  "workflow_id":  425268053250,
  "team_flow_id": 424660152834,
  "description":  "Feature release derived from dev_task xxx",
  "control_planes": ["i18n", "eu-ttp", "us-ttp"],
  "projects": [
    {"project_type": "tcc", "project_unique_id": "tiktok.passport.authnbridge"}
  ]
}'
```

**返回**：

```json
{
  "success": true,
  "action":  "create_release_ticket",
  "release_ticket_id": 1148990694658,
  "name":         "...",
  "workspace_id": 351190531074,
  "workflow_id":  663631427586,
  "url": "https://bits.bytedance.net/devops/351190531074/release/releaseTicket/detail/1148990694658"
}
```

---

## get_release_ticket_basic_info — 获取发布单基本信息

返回发布单状态、所属模板、控制面、负责人、关联项目等元数据。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `release_ticket_id` | number | 是 | 发布单 ID。也接受 `id` 别名 |

**示例**：

```bash
gdpa-cli run bits-devops --input '{
  "action": "get_release_ticket_basic_info",
  "release_ticket_id": 1148990694658
}'
```

**返回**：原样透传 BITS 的 `data` 对象（含 `name` / `status` / `workflow_name` / `control_planes` / `creator` / `release_approvers` / `test_approvers` / `change_items` 等）。

---

## 下一步：在发布单上修改 TCC 配置

拿到 `release_ticket_id` 后，前往 [SKILL_tcc_config.md](./SKILL_tcc_config.md)。所有 TCC 配置变更类 action（`import_tcc_configs` / `list_tcc_change_items` / `edit_tcc_config` / `discard_tcc_change` / ...）都接受 `release_ticket_id` 作为承载体（与 `dev_task_id` 二选一）。

**典型链路**：

```bash
# 1. 创建发布单 → 拿到 release_ticket_id
gdpa-cli run bits-devops --input '{"action":"create_release_ticket", ...}'

# 2. 在发布单上导入 TCC 配置
gdpa-cli run bits-devops --input '{
  "action": "import_tcc_configs",
  "release_ticket_id": 1148990694658,
  "psm": "tiktok.passport.authnbridge",
  "conf_name": "gateway.tt4b",
  "control_planes": ["i18n"]
}'

# 3. 在发布单上编辑 TCC 配置内容
gdpa-cli run bits-devops --input '{
  "action": "edit_tcc_config",
  "release_ticket_id": 1148990694658,
  "psm": "tiktok.passport.authnbridge",
  "conf_name": "gateway.tt4b",
  "content": "...",
  "note": "append a new node"
}'

# 4. 推流水线前预检（建议）：确认目标 namespace 没有正在跑的发布工单
gdpa-cli run bits-devops --input '{
  "action": "precheck_tcc_release",
  "psm": "tiktok.passport.authnbridge",
  "vregions": ["Singapore-Central", "US-East"]
}'

# 5. 推 TCC 发布 stage（默认 dry-run，校验后再加 confirmed=true 真正下发）
gdpa-cli run bits-devops --input '{
  "action": "run_release_stage",
  "release_ticket_id": 1148990694658,
  "control_plane": "i18n"
}'
gdpa-cli run bits-devops --input '{
  "action": "run_release_stage",
  "release_ticket_id": 1148990694658,
  "stage_id": 88888888,
  "confirmed": true
}'
```

---

## precheck_tcc_release — 发布前预检 TCC 正在跑的工单

检查指定 namespace 在目标 vregion 上是否还有未结束的 TCC 发布工单。常用于真正推 release pipeline 前的安全闸门 —— 同一 namespace 同时有人在 BCC 直接改配置时，会与 BITS 发布单冲突。

> 本 action **完全只读**，不依赖 BITS 发布单，可独立运行做日常巡检。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `psm` | string | 是 | TCC 命名空间（PSM）。也接受 `namespace` / `ns_name` 别名 |
| `vregions` | string[] | 是 | 至少一个 VRegion，如 `["Singapore-Central", "US-East"]`；支持 VRegion 别名（`sg` / `us-east` 等） |
| `vregion` | string | 否 | 单 vregion 快捷写法，与 `vregions` 互补 |
| `env` | string | 否 | TCC 环境名，默认 `prod` |
| `strict_precheck` | bool | 否 | 默认 `false`。`true` 时只要发现一个正在跑的工单就把 `success` 置为 `false` |
| `page_size` | number | 否 | 每个 vregion 拉取条数，默认 50（一般够用） |

**示例**：

```bash
# 巡检 (宽松模式)：成功返回，包括每个 vregion 的正在跑工单列表
gdpa-cli run bits-devops --input '{
  "action": "precheck_tcc_release",
  "psm": "tiktok.passport.authnbridge",
  "vregions": ["Singapore-Central", "US-East", "EU-TTP2"]
}'

# 严格模式：发现冲突即 success=false，可以直接当成 release pipeline 的卡口
gdpa-cli run bits-devops --input '{
  "action": "precheck_tcc_release",
  "psm": "tiktok.passport.authnbridge",
  "vregions": ["US-TTP", "US-TTP2"],
  "strict_precheck": true
}'
```

**返回**：

```json
{
  "success": true,
  "action": "precheck_tcc_release",
  "namespace": "tiktok.passport.authnbridge",
  "env": "prod",
  "vregions": ["Singapore-Central", "US-East"],
  "strict_precheck": false,
  "running_deployments": [
    {
      "vregion": "Singapore-Central",
      "namespace": "tiktok.passport.authnbridge",
      "env": "prod",
      "running_cnt": 0,
      "running": []
    },
    {
      "vregion": "US-East",
      "namespace": "tiktok.passport.authnbridge",
      "env": "prod",
      "running_cnt": 1,
      "running": [
        {"id": 12345, "status": "running", "created_by": "alice", "created_at": 1715450000, "deployment_type": "normal", "remark": "..."}
      ]
    }
  ],
  "total_running": 1,
  "conflict_regions": ["US-East"],
  "message": "found 1 running deployment(s) in regions: US-East"
}
```

`strict_precheck=true` 命中冲突时，响应里会额外带 `error` 字段且 `success=false`。

---

## run_release_stage — 推进发布单 pipeline stage（带 confirmed 安全闸门）

在已有发布单上推进单个 BITS pipeline stage。**默认 dry-run** —— 只调 `GetStages` 列出可见 stage 并按 `(stage_id / stage_name / control_plane)` 选出目标，不真的下发流水线；用户复核后追加 `confirmed=true` 才真正调 `RunPipelineStage`。

> 本 action 不会绕过任何 BITS 侧审批闸门。建议只对 `stage_status=READY` 或 `pending` 的 stage 执行。

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `release_ticket_id` | number | 是 | 发布单 ID |
| `stage_id` | number | 否 | 显式指定 stage ID（最高优先级，命中即用） |
| `stage_name` | string | 否 | 按 `NodeInfo.Name` / `NameI18N` 子串匹配（不区分大小写） |
| `control_plane` | string\|number | 否 | 兜底挑选：当 `stage_name` / `stage_id` 都不命中时，按控制面 + 名字含 "tcc" 的启用 stage 选取。也会作为 `RunPipelineStage` 的 `selected_control_plane` 透传。支持别名 `cn` / `i18n` / `eu-ttp` / `us-ttp` 或常量名 `CONTROL_PLANE_*` |
| `confirmed` | bool | 否 | 默认 `false`。`true` 才真正下发 pipeline |

**示例（dry-run，先看选中的 stage 与全量列表）**：

```bash
gdpa-cli run bits-devops --input '{
  "action": "run_release_stage",
  "release_ticket_id": 1148990694658,
  "control_plane": "i18n"
}'
```

**示例（确认后真正下发）**：

```bash
gdpa-cli run bits-devops --input '{
  "action": "run_release_stage",
  "release_ticket_id": 1148990694658,
  "stage_id": 88888888,
  "confirmed": true
}'
```

**返回（dry-run）**：

```json
{
  "success": true,
  "action": "run_release_stage",
  "needs_confirmation": true,
  "release_ticket_id": 1148990694658,
  "control_plane": "i18n",
  "selected_stage": {
    "stage_id": 88888888,
    "stage_status": "READY",
    "node_info": {"id": 999, "name": "TCC I18N 发布", "name_i18n": "TCC I18N Release", "node_type": "tcc_release", "enabled": true, "version": 1}
  },
  "available_stages": [ {"stage_id": ..., "stage_status": "...", "node_info": {...}}, ... ],
  "username": "jiangbeili",
  "message": "Dry-run for run_release_stage. ..."
}
```

**返回（confirmed=true）**：

```json
{
  "success": true,
  "action": "run_release_stage",
  "needs_confirmation": false,
  "release_ticket_id": 1148990694658,
  "stage_id": 88888888,
  "control_plane": "i18n",
  "username": "jiangbeili",
  "upstream_message": "ok",
  "upstream_data": "...",
  "message": "Pipeline stage 88888888 started for release_ticket_id=1148990694658; track status via BITS UI."
}
```
