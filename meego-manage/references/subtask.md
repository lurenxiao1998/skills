# Meego Subtask Reference

> 用于 `action=subtask_list / subtask_search / subtask_create / subtask_update / subtask_operate`。
> 这五个 action 对应飞书项目（Meego）「子任务」OpenAPI；`SKILL.md` 已有 action dispatch 的入口，本文件只覆盖参数细节。

子任务是节点流（node-flow）工作项节点下的执行单元，常用于「需求」工作项里某个节点（如 `dev` / `test`）下细化分工或挂交付物。状态流（state-flow）的工作项不会有子任务，相关接口会直接返回错误。

## 0. 通用约束

- `project_key` / `work_item_type_key`：除 `subtask_search` 外都必传；同 `create/get/update` 一样支持 `./.gdpa/meego.yaml` 兜底。
  - **`subtask_search` 的 `project_keys` 仅接受 raw key（24 位 hash，如 `64e70ccaf56b8dff0331bc7e`），不接受 `simple_name`（如 `ttarch`）**；可以先用 `action=project` 列出当前账号所有可见项目并取里面的 `project_key`。
- `work_item_id`：除 `subtask_search` 外都必传，是子任务挂载的父工作项实例 ID。
- `node_id`：节点 `state_key`（不是中文名）。优先用 `query_workflow` + `flow_type=0` 拿；`subtask_list` 返回的 `nodes[*].state_key` 也是合法 `node_id`。
- `task_id`：子任务实例 ID。
  - 请求侧统一以**整数**传入（`subtask_update` / `subtask_operate` 都接受 `int64` 或可解析为 int 的 `string`）。
  - 响应侧 `subtask_list` / `subtask_search` 里的 `id` 是 **string** 类型（如 `"7282802855"`），但仍可以原样回填到 `task_id` 字段——agent 会自动转换。
  - `subtask_create` 返回 `data` 直接是整数 `task_id`。
- 鉴权：与其他 action 一样走 `gdpa-cli login cn` 后的身份；如需覆盖见 `SKILL.md` 鉴权小节。

### 0.1 schedule / schedules 公共字段（子任务专用）

子任务排期对象与节点流不同，多了 `actual_work_time` 与 `is_auto`：

| 字段 | 类型 | 说明 |
|------|------|------|
| `owners` | `[]string` | 排期所有者的 user_key 列表；与角色联动型节点请改用 `role_assignee` |
| `estimate_start_date` | `int64` 或日期字符串 | 预计开始日期；接受 `YYYY-MM-DD` / `YYYY/MM/DD` / 时间戳；按本地时区 0 点起算 |
| `estimate_end_date` | `int64` 或日期字符串 | 预计结束日期；同上规则；按本地时区 23:59:59.999 算结尾 |
| `points` | `float` | 工作量估分 |
| `actual_work_time` | `int64` | 实际工作时长（毫秒） |
| `is_auto` | `bool` | 是否自动排期；不传时由后端按节点策略默认计算 |

`subtask_create` / `subtask_update` 用的是单个 `schedule`（对象），`subtask_operate` 用的是 `schedules`（数组，差异化排期场景）。

### 0.2 field_value_pairs / deliverable

两者都是 `Field` 数组：

```json
[
  { "field_key": "due_date", "field_type_key": "date", "field_value": "2026-05-08" },
  { "field_key": "field_deliverable", "field_type_key": "text", "field_value": "评审记录" }
]
```

- `subtask_create`：可传 `field_value_pairs`（不能传 `deliverable`，节点交付物字段一般在 `update` / `operate` 阶段才填）。
- `subtask_update`：`field_value_pairs` 与 `deliverable` 同时支持；至少传一个非空字段，否则会被早返回为 `InputMissingParam`。
- `subtask_operate`：仅支持 `deliverable`（API 不接受 `field_value_pairs`）。

`field_alias` 与 `field_value` 详细定义沿用 `references/update.md` / `references/create.md`。

## 1. action=`subtask_list`：查询单工作项下子任务

`GET /open_api/{project_key}/work_item/{work_item_type_key}/{work_item_id}/workflow/task`

**输入**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `project_key` | 是 | 见上 |
| `work_item_type_key` | 是 | 节点流工作项类型 |
| `work_item_id` | 是 | 父工作项实例 ID |
| `node_id` | 否 | 限定到某个节点的 `state_key`；不传则返回该工作项下所有节点及其子任务 |

**返回**：

```json
{
  "project_key": "...",
  "work_item_id": 7187641160,
  "node_id": "state_2",
  "nodes": [
    {
      "id": "state_2", "state_key": "state_2", "node_name": "Server任务",
      "template_id": 255768, "version": 76,
      "sub_tasks": [
        {
          "id": "7282802855", "name": "Argos 使用问题 Fix", "status": 0, "passed": true,
          "actual_begin_time": "2026-04-30T07:46:20.089Z", "actual_finish_time": "2026-04-30T07:47:00.964Z",
          "owners": ["laihongquan"], "assignee": ["laihongquan"],
          "schedules": [{ "owners": ["laihongquan"], "estimate_start_date": 1776614400000, "estimate_end_date": 1776787199999, "points": 2 }],
          "fields": [{ "field_key": "field_42fec7", "field_type_key": "date", "field_value": 1776614400000 }]
        }
      ]
    }
  ],
  "total_subtasks": 3
}
```

注意 `id` 是字符串（如 `"7282802855"`）；`node_name` 是节点中文名，`id` / `state_key` 是 `node_id`。

仅适用 node-flow 工作项；如果工作项是状态流，会拿到 Meego 端的报错（一般是 20026/20027）。

## 2. action=`subtask_search`：跨空间搜索子任务

`POST /open_api/work_item/subtask/search`

**输入**（全部可选；不传则返回当前账号在所有空间下所有子任务，结果较大请配合分页）：

| 参数 | 类型 | 说明 |
|------|------|------|
| `project_keys` | `[]string` | 限定空间；推荐至少传一个，避免返回过多 |
| `name` | `string` | 子任务名称模糊匹配 |
| `user_keys` | `[]string` | 子任务负责人 user_key |
| `status` | `int`（`0` 进行中 / `1` 已完成）| 过滤完成状态 |
| `created_at` | `{ "start": ..., "end": ... }` | 创建时间区间；接受日期字符串或毫秒时间戳 |
| `updated_at` | `{ "start": ..., "end": ... }` | 更新时间区间；同上 |
| `page_num` | `int` | 页码，默认 1 |
| `page_size` | `int` | 每页数量，默认 50 |

> Meego 在 `status` 字段没有"无过滤"的语义（0 表示进行中），所以只在用户**显式**传 `status` 时才下发过滤；想看所有状态请直接不传该字段。

**返回**：

```json
{
  "items": [
    {
      "work_item_id": 7187641160,
      "work_item_name": "GDPA Skill 稳定性 & 使用体验优化",
      "node_id": "state_2",
      "sub_task": { "id": "7282802855", "name": "Argos 使用问题 Fix", "status": 0, "passed": true, ... }
    }
  ],
  "total": 120,
  "page_num": 1,
  "page_size": 50
}
```

> 与 `subtask_list` 不同：`subtask_search` 把工作项级字段（`work_item_id` / `work_item_name` / `node_id`）放在外层，子任务详情挂在 `sub_task` 子对象里——这是飞书项目原生 API 的形态，不要把这两个 schema 混淆。

## 3. action=`subtask_create`：创建子任务

`POST /open_api/{project_key}/work_item/{work_item_type_key}/{work_item_id}/workflow/task`

**输入**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `project_key` / `work_item_type_key` / `work_item_id` | 是 | 见 §0 |
| `node_id` | 是 | 目标节点 `state_key`，先用 `query_workflow`/`subtask_list` 确认 |
| `name`（或 `subtask_name`） | 是 | 子任务标题；`name` 与父工作项创建时复用，故同时支持 `subtask_name` 别名 |
| `assignee` | 否 | `[]string`，子任务负责人 user_key 列表（节点负责人非"与角色联动"时用） |
| `role_assignee` | 否 | `[]{ "role": "RD", "owners": ["user_key"] }`，节点为"与角色联动"时用 |
| `schedule` | 否 | 单条排期对象，结构见 §0.1 |
| `note` | 否 | 备注 |
| `alias_key` | 否 | 目标节点的对接标识（高级场景，不传即可） |
| `field_value_pairs` | 否 | 子任务自定义字段值，结构见 §0.2 |

`assignee` 与 `role_assignee` 二选一；同时传时由 Meego 后端决定优先级，建议按节点类型只传一个。

**返回**：

```json
{ "project_key": "...", "work_item_id": 6300034462, "node_id": "dev", "name": "...", "task_id": 6132974, "created": true }
```

## 4. action=`subtask_update`：更新子任务

`POST /open_api/{project_key}/work_item/{work_item_type_key}/{work_item_id}/workflow/{node_id}/task/{task_id}`

**输入**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `project_key` / `work_item_type_key` / `work_item_id` / `node_id` / `task_id` | 是 | 路由参数；`node_id` 与 `task_id` 都来自 `subtask_list` 的返回 |
| `name`（或 `subtask_name`） | 否 | 修改子任务标题 |
| `assignee` | 否 | 覆盖式更新负责人列表 |
| `role_assignee` | 否 | 覆盖式更新角色负责人 |
| `schedule` | 否 | 覆盖式更新排期，结构见 §0.1 |
| `note` | 否 | 备注 |
| `field_value_pairs` | 否 | 自定义字段，§0.2 |
| `deliverable` | 否 | 节点交付物字段，§0.2 |

**至少传一个可变字段**；全空时 agent 会直接返回 `InputMissingParam`，避免无意义的 API 请求。

> ⚠️ **`field_value_pairs` 的能力边界**：`subtask_update` 接口对部分自定义字段（实测如「迭代」`work_item_related_multi_select` 类字段 `field_76b468`）会**静默忽略**——HTTP 200、`err_code=0`，但实际不写入。这类字段需改用通用 `action=update` + `work_item_type_key=sub_task` + `work_item_id=<task_id>` + `update_fields` 走两阶段（`confirm_update=true`）流程更新。系统字段（`name` / `assignee` / `schedule` / `note` / `deliverable`）走 `subtask_update` 仍然有效。

**返回**：

```json
{ "project_key": "...", "work_item_id": 6300034462, "node_id": "dev", "task_id": 6132974, "updated": true }
```

## 5. action=`subtask_operate`：完成 / 回滚子任务

`POST /open_api/{project_key}/work_item/{work_item_type_key}/{work_item_id}/subtask/modify`

**输入**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `project_key` / `work_item_type_key` / `work_item_id` | 是 | 见 §0 |
| `node_id` | 是 | 目标节点 `state_key` |
| `task_id` | 是 | 子任务 ID |
| `subtask_action` | 是 | `confirm`（完成）或 `rollback`（回滚）；为兼容历史输入也接受 `action_type` / `operate_action` 字段名 |
| `assignee` | 否 | 同步更新负责人 |
| `role_assignee` | 否 | 同步更新角色负责人 |
| `schedules` | 否 | **数组**形式的排期（差异化排期场景）；单条对象会被自动包装成单元素数组 |
| `deliverable` | 否 | 同步交交付物字段，§0.2 |

> 与节点级 `operate_node` 不同，子任务的回滚接口**不需要** `rollback_reason`；如果 SDK 端用户传了，会被忽略。

**返回**：

```json
{ "project_key": "...", "work_item_id": 6300034462, "node_id": "dev", "task_id": 6132974, "subtask_action": "confirm", "operated": true }
```

## 6. 推荐链路

1. 想看一下当前工作项有哪些子任务 → `subtask_list`，先不带 `node_id` 看全貌。
2. 想跨多个空间筛选「我负责的进行中子任务」 → `subtask_search` + `user_keys` + `status=0` + 必要的 `project_keys`。
3. 新建子任务前 → 先 `query_workflow`（`flow_type=0`）拿到目标 `node_id`，再 `subtask_create`。
4. 更新已有子任务 → `subtask_list` 拿到 `task_id`，再 `subtask_update`；如果只是要把它「完成」就直接 `subtask_operate` + `subtask_action=confirm`。
5. 节点交付物缺失被驳回时 → `subtask_update` 先把 `deliverable` 补完，再 `subtask_operate confirm`。
