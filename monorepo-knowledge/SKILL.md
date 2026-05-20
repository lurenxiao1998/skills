---
name: monorepo-knowledge
description: 当在TikTok Bazel Monorepo中进行代码开发、使用tt mn命令集、编写单元测试、配置CI/CD流程或进行Bazel构建时使用。
user-invocable: false
---

# Bazel Monorepo 使用知识

## Bazel Monorepo

Bazel Monorepo是TikTok内部采用的大仓开发模式，通过统一的代码库管理多个项目或组件，结合Bazel构建系统和Trunk-Based开发策略，提升代码维护效率、促进跨团队协作，并实现真正的CI/CD流程。该平台提供集中式代码管理、统一的工具链构建、简化的依赖管理以及代码质量和合规管控能力。

## 使用方式

Bazel Monorepo的日常开发遵循Trunk-Based Development原则，开发任务应设计为粒度合理的变更，确保能在几天内合并到主分支。主要使用场景包括本地开发、代码验证、构建测试和CI/CD流程管理。

### 本地开发

本地开发时建议使用稀疏检出（Sparse Checkout）功能，仅检出当前工作模块的代码。主要开发流程包括：

1. **代码检出**：使用`tt mn local`命令管理本地磁盘上的Monorepo项目目标
2. **代码验证**：修改代码后运行`tt mn validate`进行验证
3. **本地构建**：使用`tt mn build`在本地构建变更
4. **单元测试**：运行`tt mn test`执行本地单元测试

[monorepo-local-dev.md](./monorepo-local-dev.md) - Monorepo本地开发指南

### 单元测试

Monorepo统一了单元测试框架和代码指导，支持通过LLM自动生成单元测试。测试左移（Shift-Left Testing）是Monorepo的关键策略，旨在在软件开发生命周期的早期阶段识别和解决问题。

**主要特性**：
- 统一的单元测试框架
- 支持对象模拟（mocking）
- 自动生成单元测试文件
- 准确的单元测试覆盖率计算

[monorepo-unit-test.md](./monorepo-unit-test.md) - Monorepo单元测试指南

### CI/CD流程

所有Monorepo都有由ServerArch - Monorepo团队配置的标准CI流水线，通过分析每个项目的Bazel构建目标，CI流水线被单独配置和触发，不会影响跨服务。

**CI阶段**：
1. 环境设置（go, bazel）
2. 构建
3. 测试
4. 测试覆盖率上传

**CD部署**：通过ByteCycle工作空间和相关子项目进行服务发布，可根据相关性单独或同时发布多个服务。

[monorepo-ci-cd.md](./monorepo-ci-cd.md) - Monorepo CI/CD配置指南

### Bazel构建适配

Bazel构建需要适配特定的Go版本和构建模式，包括Tango Beast Mode优化。

**关键配置**：
- 指定Go版本：在WORKSPACE文件中使用`workspace_init("1.20")`
- Beast Mode优化：添加特定的编译和链接选项
- 外部依赖管理：跨仓库消费IDL

[monorepo-bazel-build.md](./monorepo-bazel-build.md) - Bazel构建配置指南

### Monorepo CLI工具

Monorepo CLI是TT CLI的子命令集，通用表达式为`tt mn {command}`，旨在简化和优化在Monorepo设置中的开发工作流程。

**主要命令**：
- `tt mn validate`：在创建新合并请求前验证Bazel Monorepo项目
- `tt mn update`：更新选定目标的构建和CI流水线脚本
- `tt mn local`：管理本地磁盘上的Monorepo项目目标（稀疏检出）
- `tt mn test`：运行所有测试相关命令

[monorepo-cli.md](./monorepo-cli.md) - Monorepo CLI使用指南

