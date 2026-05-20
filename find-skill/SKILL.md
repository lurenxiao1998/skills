---
name: find-skill
description: Find and install missing GDPA skills — capabilities supported by GDPA but not yet installed in this session. Use whenever the user needs an ability and no matching skill is currently visible.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# Find Skill

> 当你想做某件事但当前会话里没有匹配的 GDPA skill 时，调用本 skill 拿到**全部**可装 skill 的索引（name + description + install_cmd），**由你自己**按语义挑出最合适的 1-3 个，再引导用户安装。

## 为什么不传 query

本 skill 不做关键词评分 —— LLM 比关键词强百倍。直接返回**全量 catalog**让你看完自己选：

- ✅ 同义词、模糊意图、中英混合、typo 全部由你处理
- ✅ 多意图组合（"既要监控又要日志"）你可以同时选 2 个
- ✅ 一次调用 ~10K tokens 覆盖全部 100 个 skill，Claude 5min 缓存窗口内后续相关问题免费复用

## Quick Start

```bash
gdpa-cli run find-skill --session-id "$SESSION_ID" --input '{}'
```

无任何参数。返回当前用户所有可装的 GDPA skill。

## Output Format

```json
{
  "success": true,
  "count": 100,
  "catalog": [
    {
      "name": "abase",
      "description": "Query Abase NoSQL data via ByteCloud gateway across multiple regions...",
      "install_cmd": "gdpa-cli install-skill --add abase"
    },
    {
      "name": "hertz-knowledge",
      "description": "Hertz HTTP framework guide.",
      "plugin": "backend",
      "is_external": true,
      "install_cmd": "gdpa-cli install-skill --add hertz-knowledge"
    }
  ],
  "hint": "已返回 100 个可安装 skill 的 catalog。请根据用户原始意图，从中挑选最匹配的 1-3 个..."
}
```

## Output Fields

| Field | Description |
|-------|-------------|
| `count` | catalog 总条目数 |
| `catalog[].name` | skill 名（用作 `--add` 的值） |
| `catalog[].description` | SKILL.md frontmatter 的 description（一行/多行合并） |
| `catalog[].plugin` | 来源 plugin 名（external skill 才有） |
| `catalog[].is_external` | 是否来自外部 plugin |
| `catalog[].install_cmd` | 永远是 `gdpa-cli install-skill --add <name>` 形式；CLI 端按现有 selection 做"安全合并"（blacklist 移除该项 / whitelist 追加该项 / 无 selection 时 noop） |
| `hint` | 给你的下一步动作建议 |

## How to Apply

1. **读完整个 catalog**（按字典序排序，便于扫读）。
2. **结合用户原始意图**，从中挑出最匹配的 1-3 个 skill：
   - 直接命中：用 `AskUserQuestion` 工具询问是否安装（见下面 §AskUserQuestion 流程）。
   - 多个候选：用 `AskUserQuestion` 列出 2-3 个 + 一句话简介让用户选。
   - 完全没有匹配：诚实告诉用户没找到，不要硬凑。
3. **用户在 AskUserQuestion 中确认后**，通过 Bash 工具执行对应 entry 的 `install_cmd`。
4. **安装完成后**继续原任务，新 skill 下一次 Skill 工具调用就能用。

> 📌 `install_cmd` 永远是 `gdpa-cli install-skill --add <name>` 形式。cli 端会读取
> 现有 `_selection.json` 自动计算"安全合并"（blacklist 移除该项 / whitelist 追加
> 该项 / 无 selection 时 noop），**不会**误删其它已装 skill。LLM 不需要关心
> selection 模式，照命令跑就行。
>
> ⚠️ 不要为了"省事"自己拼 `--skill-list <name>`，那是白名单**强覆盖**模式，会
> 清空白名单外的所有 skill。

## AskUserQuestion 流程（强制）

**找到候选后必须用 `AskUserQuestion` 工具收集用户确认**，不要单纯输出文字让用户回复"装" —— 显式选项更清晰、可审计、避免误解。

> **注意**：下面给的是 `AskUserQuestion` 工具的**参数结构**（JSON），不是要你跑某种代码。直接把这个结构作为参数调用 `AskUserQuestion` 工具即可。

### 单候选场景

调用 `AskUserQuestion` 传入：

```json
{
  "questions": [{
    "question": "找到 `abase` skill — Query Abase NoSQL data via ByteCloud gateway. 要安装吗？",
    "header": "Install abase",
    "multiSelect": false,
    "options": [
      {"label": "安装", "description": "运行 gdpa-cli install-skill ... 后继续原任务"},
      {"label": "不装，先看看", "description": "我只告诉你怎么手动装"}
    ]
  }]
}
```

### 多候选场景

调用 `AskUserQuestion` 传入：

```json
{
  "questions": [{
    "question": "GDPA 里有几个跟 Redis 相关的 skill，你想装哪个？",
    "header": "Pick skill",
    "multiSelect": false,
    "options": [
      {"label": "redis", "description": "Query Redis (ByteCache) via ByteCloud gateway"},
      {"label": "storage-knowledge", "description": "Go SDK 接入 Redis/Abase/RDS 等存储的知识库"},
      {"label": "都装", "description": "两个一起加进来"}
    ]
  }]
}
```

### 用户选择后

- 选了"安装"或具体某个 skill → Bash 执行对应 `install_cmd` → 告知用户已装 → 继续原任务（重新触发新 skill）
- 选了"不装" → 把 `install_cmd` 文字给用户作为参考，结束本轮
- 选了"Other" → 看用户写了什么，照办

## 怎么跟用户说（话术模板）

| ✅ Good | ❌ Bad |
|---|---|
| "找到了 `abase` — Query Abase NoSQL data via ByteCloud gateway. 要装吗？"（**配 AskUserQuestion**） | "运行 `gdpa-cli install-skill ...`"（**没说明装的是什么**） |
| "GDPA 里没找到 DES-HDFS 相关 skill，可能：1) 还没接入，2) 走 bytecloud-doc 文档兜底，3) 你想的是别的名字？" | "GDPA 不支持。"（**没给替代路径**） |
| 在 AskUserQuestion 描述里展示 catalog 的 description 让用户判断 | 只展示 skill 名字不展示能力 |

## 安装出错怎么办

| 错误现象 | 可能原因 | 排查建议 |
|---|---|---|
| `Permission denied` / `unauthorized` / `JWT` 相关 | GDPA 登录态过期 | 让用户运行 `gdpa-cli login` 后重试 |
| `agent not found: <name>` | 本地 cli 版本过旧不含该 agent | 让 cli 自动更新（不要设 `GDPA_NO_UPDATE`），或重新登录触发 update |
| `network timeout` / 连接拒绝 | VPN / 内网不通 | 让用户检查 VPN，TTP 环境要走 TTP build |
| 命令返回成功但 Claude Code 看不到新 skill | 安装是即时硬链接，但 Claude Code 系统提示需要新会话刷新 | 让用户开新会话；同一会话内可用 Bash 跑 `gdpa-cli run <name>` 直接调用 |
| `--skill-list` 把其他 skill 清掉了 | 用了 `--skill-list` 强覆盖而不是 `--add` | 永远用 catalog 给的 `install_cmd`（`--add` 增量）；如已发生，再跑一次 `gdpa-cli install-skill`（默认重跑）把丢失的加回 |

## When to Use

| 场景 | 是否使用 |
|---|---|
| 用户提到平台名/能力，但你没看到对应 skill (e.g. "查 abase" / "Redis 数据" / "lark 文档") | ✅ 用 |
| 当前 skill 列表里已经有匹配的，比如用户问 codebase 你已经有 codebase skill | ❌ 直接调用现有 skill |
| 用户明确说"装一个 X" | ✅ 用，从 catalog 找 X 后引导 install |
| 用户问"GDPA 还有什么 skill" | ✅ 用，把 catalog 整理后展示 |

## Do Not Use

- ❌ 不要为已经在系统提示里出现的 skill 调本 skill（直接用即可）
- ❌ 不要把 catalog 直接 dump 给用户（要先按用户意图过滤再展示）
- ❌ 不要在用户没明确表示需要某能力时主动调用（会显得多余）

## 安装是否会破坏当前会话

不会。`install_cmd` 字段返回的命令是增量追加（写入中央存储 + 硬链接同步），**不会**卸载已装的其他 skill；新 skill 立即对下一次调用可见。

## Examples

```bash
# 拉取 catalog（无参数）
gdpa-cli run find-skill --input '{}'
```

## Related

- `gdpa-cli list-skill` — CLI 直接列出可装 skill（人类视角）
- `gdpa-cli install-skill --add <name>` — **增量加入**（catalog 用的命令）
- `gdpa-cli install-skill --remove <name>` — **增量移出**（与 --add 对称，可一次多个）
- `gdpa-cli install-skill --skill-list <name>` — 白名单**强覆盖**模式（**有清空风险**，不推荐）

## Debugging

```bash
DEBUG=1 gdpa-cli run find-skill --input '{}'
```
