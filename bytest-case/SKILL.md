---
name: bytest-case
description: Query BITS test cases (bytest/case platform) — get test case detail including full mind map tree structure with steps, expected results, and embedded images. Use whenever the user mentions BITS test cases, test case detail, bytest, case platform, wants to view test case content, get test steps, check test case mind map, QA signoff case details, or needs to retrieve test case data from BITS quality platform. Also trigger when the user provides a BITS quality/case/caseDetail URL, mentions querying test cases by case ID, or provides a case_id/test_case_id with product_id/projectId and optional space_id.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# BITS Test Case Query

查询 BITS 测试用例平台（bytest）的测试用例详情，包含完整的脑图结构（测试步骤、预期结果、图片等）。

> **session_id 当前必需**：这个 Agent 查询成功后会把结果文件写入 `.gdpa/{session-id}/`，因此当前版本仍然需要显式传入 `--session-id`。
> 建议先执行 `gdpa-cli create-session`，再在后续命令里复用同一个 Session ID。
> 执行顺序固定为：创建 session → 使用结构化 JSON 调用 `bytest_case` → 读取返回的 `file_path`；不要在成功调用前搜索历史缓存。

## Actions

| Action | 描述 | 必填参数 | 可选参数 |
|--------|------|----------|----------|
| `get_case_detail` | 获取测试用例详情 | `test_case_id`, `product_id` | `space_id`, `operator` |

## 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `action` | string | 操作类型（见上表） |
| `test_case_id` | int | 测试用例 ID（URL 中 caseDetail/ 后面的数字） |
| `product_id` | int | 产品/项目 ID（URL 中的 projectId 参数） |
| `space_id` | string | OnesSite 空间 ID（URL 中 devops/ 后面的数字，可选） |
| `operator` | string | 操作者用户名（可选；未传时 runtime 会在请求前默认填充为 `gdpa-agent`） |

## 使用示例

### 获取测试用例详情

```bash
SESSION_ID=$(gdpa-cli create-session)
gdpa-cli run bytest_case --session-id "$SESSION_ID" --input '{"action": "get_case_detail", "test_case_id": 3782343, "product_id": 66666866}'
```

已知 `test_case_id` 与 `product_id` 时，直接执行上面的一次结构化调用；URL 中有 `space_id` 时同步传入，无需先做参数枚举或文件扫描。

如果返回 `401 InvalidAuthorization`、JWT/authentication 相关错误或其他鉴权失败，保持同一个 `SESSION_ID`，优先检查登录态、JWT 与权限；当前实现即使未传 `operator` 也会在请求前默认填充 `gdpa-agent`，因此不要把“operator missing”当作主要排查分支。只有在用户明确要求指定操作者时，才把该 `operator` 作为请求上下文补传后重试一次；仍失败时停在鉴权阻塞并报告，不要切换到浏览器、仓库搜索或历史缓存。

### 从 URL 提取参数

BITS 测试用例 URL 格式：
```
https://bits.bytedance.net/devops/{space_id}/quality/case/caseDetail/{test_case_id}?projectId={product_id}
```

例如：`https://bits.bytedance.net/devops/1499051266/quality/case/caseDetail/3782343?projectId=66666866`
- `test_case_id` = 3782343
- `product_id` = 66666866
- `space_id` = 1499051266

## 输出文件

查询成功后，结果会自动保存到 session 工作目录：

```
.gdpa/{session-id}/bytest-case-{test_case_id}.json
```

返回结果中包含 `file_path` 字段，指向保存的文件绝对路径。
只读取本次成功调用返回的 `file_path`；没有返回 `file_path` 时，才使用当前 session 下的确定性路径 `.gdpa/{session-id}/bytest-case-{test_case_id}.json`。
排查文件时范围限定为这两个当前-session路径。

## 响应结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `success` | bool | 是否成功 |
| `action` | string | 操作类型 |
| `file_path` | string | 结果文件的绝对路径 |
| `data` | object | TestCaseDetail 详情 |

响应的 `data` 字段包含 `TestCaseDetail`，关键字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `TestCaseId` | int | 用例 ID |
| `ProductId` | int | API 返回的产品/项目 ID（与请求值不一致时以此为准） |
| `TestCaseTitle` | string | 用例标题 |
| `CaseNum` | int | 子用例数量 |
| `TestCaseStatus` | int | 用例状态（3=已完成） |
| `TestCaseMind` | string | 脑图 JSON 字符串 |

回答用户时优先使用 API 返回的 `TestCaseId` 与 `data.ProductId` 作为结果中的主元数据；请求里的 `product_id`、`space_id`、`operator` 只作为本次调用上下文回显。若请求 `product_id` 与返回的 `data.ProductId` 不一致，应明确说明“请求值 X，返回值 Y”，并以返回值为准；步骤、预期结果、备注和资源标签应从 `TestCaseMind` 节点中提取并对应到节点文本。

### 脑图节点结构

`TestCaseMind` 是一个嵌套的 JSON 树结构，每个节点包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `text` | string | 节点文本内容 |
| `image` | string | 图片 URL（如有） |
| `imageTitle` | string | 图片标题（如有） |
| `imageSize` | object | 图片尺寸 `{width, height}` |
| `note` | string | 备注 |
| `nodeType` | int | 节点类型 |
| `priority` | int | 优先级 |
| `resource` | array | 标签列表 |
| `children` | array | 子节点列表 |

节点类型（nodeType）：
- `0` = 分类/目录
- `3` = 用例集
- `6` = 测试步骤
- `13` = 预期结果

当节点包含 `image`、`imageTitle` 或 `imageSize` 时，在最终回答中列出这些图片证据；如果遍历后没有图片字段，明确说明未发现嵌入图片。
