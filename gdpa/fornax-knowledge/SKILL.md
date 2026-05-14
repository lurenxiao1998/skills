---
name: fornax-knowledge
description: 当在服务端应用中接入 Fornax AI Agent Ops 平台、使用 code.byted.org/flowdevops/fornax_sdk（Golang）@next-ai/fornax-sdk（Node.js）或 bytedance.fornax（Python）SDK、调用 Prompt Hub、RAG 检索、Trace 观测或评测能力时使用。
user-invocable: false
---

# Fornax AI Agent Ops 平台

Fornax（For Next）是字节跳动内部的 AI Agent 运维平台，提供 Prompt 即服务（Prompt as a Service）、基于知识库的 RAG 检索、AI 能力调用、链路观测和自动化评测等核心能力，帮助开发者高效构建和运维 AI 应用。

## SDK 接入

Fornax SDK 提供了多语言支持（Node.js、Python、Golang），用于在服务端应用中集成 Fornax 平台的各项能力。SDK 的核心设计原则是**初始化一次，多次复用**，确保同一个 AKSK 只初始化一个客户端实例。

**主要使用场景**：
- **Prompt 管理**：从 Fornax 平台拉取已发布的 Prompt 模板，并在运行时替换变量
- **RAG 检索**：基于 Fornax 平台管理的知识库进行文档检索和召回
- **AI 能力调用**：通过统一的接口调用多种大模型（GPT OpenAPI、火山方舟豆包等）
- **链路观测**：自动上报 Trace 数据到 Fornax 观测平台，支持自定义 Span 和会话管理
- **评测集成**：与 Fornax 评测平台对接，支持自定义评估规则和结果上报

**初始化示例（Python）**：
```python
from bytedance.fornax.infra import initialize, FornaxClient

# 全局初始化（单空间推荐）
initialize('your_ak', 'your_sk')
# 或创建多个空间客户端
client1 = FornaxClient(ak1, sk1)
client2 = FornaxClient(ak2, sk2)
```

**本地调试配置**：
本地调试需要配置环境变量以确保 Trace 能正确上报到 BOE 环境。对于 Golang SDK v1.0+，需设置以下环境变量：
```bash
export RUNTIME_IDC_NAME=boe  # 海外环境可使用 boei18n
export TCE_PSM=<your-psm>    # 如不设置则上报 "-"
```

[fornax-sdk-usage.md](./fornax-sdk-usage.md) - Fornax SDK 详细使用指南和最佳实践
[fornax-openapi.md](./fornax-openapi.md) - Fornax OpenAPI 接口说明和认证方式
[fornax-observability.md](./fornax-observability.md) - Fornax 观测能力集成指南

