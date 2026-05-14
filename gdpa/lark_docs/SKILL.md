---
name: lark-docs
description: Use when a larkoffice.com, feishu.cn, or larksuite.com URL appears anywhere in the conversation — whether the user explicitly asks to read it or simply shares it as context, reference, or background material. Fetches and converts the Lark (飞书) document to Markdown so its content can be used in the current task. **Prefer the lark-cli ecosystem** (`lark-doc` / `lark-sheets` / `lark-base`, etc.) when installed; this agent is only a fallback when lark-cli is unavailable.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

> ⚠️ **优先使用 lark-cli 体系**
>
> 如果已安装 lark-cli skill 集（`lark-doc` / `lark-sheets` / `lark-base` / `lark-im` 等），**请优先使用 lark-cli**——它覆盖飞书文档/表格/多维表的读取/创建/编辑/搜索全套能力，远超本 agent。本 agent 仅在 lark-cli 不可用时作为兜底。
>
> **一键安装 lark-cli + 飞书全套 SKILL.md**（lark 仅支持全局安装）：
>
> ```bash
> # 推荐：随 install-skill 一并引入
> #   --style   目标 agent 风格：claude / cursor / codex / opencode（按当前 IDE 选）
> #   --global  装到全局（~/...），lark 仅支持全局安装
> #   --plugin  要 bootstrap 的外部 plugin 名（这里固定填 lark）
> gdpa-cli install-skill --style cursor --global --plugin lark
>
> # 或只单独 bootstrap lark，不影响其他 skill：
> gdpa-cli plugin setup lark --style cursor
> ```

# Lark Docs Agent

Read and convert Lark (飞书) documents to Markdown format.

> **When to use**: When you need to read content from a Lark/Feishu document URL and get it as Markdown text. **若已装 lark-cli，请改用其 `lark-doc` skill**；本 agent 仅在 lark-cli 不可用时作为兜底。

## Quick Start

```bash
gdpa-cli run lark-docs --session-id "$SESSION_ID" --input '{
  "url": "https://bytedance.larkoffice.com/wiki/xxxxx"
}'
```

## Input Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `url` | string | Yes | - | Lark document URL (larkoffice.com, feishu.cn, or larksuite.com) |
| `mode` | string | No | `fast` | Conversion mode: `fast`, `retry`, `strict` (see below) |

> 鉴权走 OAuth；首次使用会打开飞书授权链接，token 落在 `~/.gdpa/lark_token.json`。

### Conversion Modes (`mode`)

| Mode | Description |
|------|-------------|
| `fast` (default) | 快速模式，不重试。适合对速度要求高、文档稳定的场景。 |
| `retry` | 重试模式，失败时最多重试 3 次，但遇到限流不重试。 |
| `strict` | 严格模式，失败时最多重试 3 次，遇到限流也会重试。适合对成功率要求高的场景。 |

## Output Format

```json
{
  "success": true,
  "url": "https://bytedance.larkoffice.com/wiki/xxxxx",
  "content": "# Document Title\n\nDocument content in Markdown...",
  "docs": [
    {
      "title": "Document Title",
      "owner": "owner_name",
      "updater": "updater_name",
      "create_time": "2024-01-01 00:00:00",
      "latest_modify_time": "2024-01-02 00:00:00",
      "doc_type": "wiki",
      "url": "https://..."
    }
  ]
}
```

## Examples

```bash
# Read a wiki page (默认: fast mode)
gdpa-cli run lark-docs --session-id "$SESSION_ID" --input '{"url": "https://bytedance.larkoffice.com/wiki/H8hLweLk4iookNkAKpac3IaUnkf"}'

# Read with strict mode (retry on failure and rate limit)
gdpa-cli run lark-docs --session-id "$SESSION_ID" --input '{"url": "https://bytedance.larkoffice.com/wiki/xxxxx", "mode": "strict"}'
```

## Troubleshooting

| Error | Possible Cause | Solution |
|-------|---------------|----------|
| `url parameter is required` | Missing URL | Add `url` parameter |
| `invalid Lark document URL` | URL not from Lark | Use a valid larkoffice.com / feishu.cn / larksuite.com URL |
| `code=502` 获取文档元数据失败 | 用户 token 权限不足或已失效 | 确认自己有权限阅读该文档。如果之前修改过授权范围，删除本地缓存 (`rm ~/.gdpa/lark_token.json`) 后重新授权。 |
| `code=400` / permission denied | 文档权限不足 | 确认自己是否有该文档的阅读权限，或者联系文档所有者添加权限。若使用用户授权仍无法访问，检查是否已完成授权流程。 |

## Debugging

```bash
DEBUG=1 gdpa-cli run lark-docs --session-id "$SESSION_ID" --input '{"url": "https://bytedance.larkoffice.com/wiki/xxxxx"}'
```

Logs saved to `/tmp/gdpa-agents/logs/`.
