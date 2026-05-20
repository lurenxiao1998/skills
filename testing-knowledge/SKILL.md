---
name: testing-knowledge
description: 当编写 Golang 单元测试、使用 github.com/bytedance/mockey 进行 Mock、或需要 PatchConvey/MockGeneric/When/Sequence 等 Mock 功能时使用。
user-invocable: false
---

# 测试知识库

测试相关的工具库和最佳实践指南。

## Mockey Mock 框架

Mockey 是字节跳动开源的 Golang Mock 框架，用于单元测试中的函数和方法 Mock：

- **函数 Mock**：Mock 普通函数和包级函数
- **方法 Mock**：Mock 结构体方法
- **链式调用**：支持链式 API 配置 Mock 行为
- **自动清理**：测试结束后自动恢复原函数

**使用场景**：
- 单元测试中 Mock 外部依赖
- Mock RPC 调用
- Mock 数据库操作
- 测试边界条件

[mockey-usage.md](./mockey-usage.md) - Mockey 使用指南
