# Monorepo CLI 工具使用指南

## 概述

Monorepo CLI 是 TT CLI 的子命令集，通用表达式为 `tt mn {command}`。该工具旨在简化和优化在 Monorepo 设置中的开发工作流程，提供一系列命令使日常开发任务更加高效。目前已有超过 20+ 团队使用 Monorepo CLI 来提升开发体验。

## 安装与配置

### 安装 CLI

请参考安装指南进行安装：[TikTok CLI HowTos](https://bytedance.larkoffice.com/wiki/wikcnvL6orQ5HMODAbwD8T2rTTh)。

**不同环境的安装方式：**

- **Mac 用户**：运行 `./script/setup_mac.sh`
- **DevBox 用户**：运行 `./script/setup_devbox.sh`
- **CloudIDE 用户**：运行 `./script/setup_cloud_ide.sh`

### CloudIDE 配置

#### 自动配置
使用 boei18n 集群和 .cloudide/bytediderc.json 配置来构建 CloudIDE 工作空间。

![CloudIDE 配置](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/3fcc6650753a45e89473e588ff3a5833~tplv-tika-image.image)

## 核心命令详解

### 帮助命令

获取所有可用命令的概览：

```bash
tt monorepo --help
```

或使用别名：

```bash
tt mn --help
```

### `tt mn init` - 初始化项目

初始化一个新的 Bazel Monorepo 项目。该命令会提取 Bazel 文件并生成 Monorepo 相关文件和脚本。

**使用示例：**
```bash
# 初始化并自动提交到新分支
tt monorepo init

# 初始化但不自动推送
tt monorepo init --no-push
```

### `tt mn build` - 构建命令

构建 Bazel Monorepo 项目中的目标或服务，支持构建整个项目或特定目标。

**使用示例：**
```bash
# 构建选中的模块
tt monorepo build

# 构建特定目标
tt monorepo build //app/upvote_rpc/...

# 构建具体目标
tt monorepo build //app/upvote_rpc/service:service_test
```

![构建命令界面](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/5e430a72c4c6419e91f0c5583998ee92~tplv-tika-image.image)

**可用标志：**
- `--all`：构建所有模块
- `--boe`：使用 BOE 归档缓存服务器进行同步
- `--clean`：执行干净构建

### `tt mn test` - 测试命令

构建并测试指定目标，支持单元测试、集成测试和远程测试。

**使用示例：**
```bash
# 运行单元测试（交互式选择目标）
tt monorepo test

# 运行特定目录下的所有测试
tt monorepo test //app/upvote_rpc/...

# 运行具体目标的测试
tt monorepo test //app/upvote_rpc/service:service_test
```

![测试命令界面](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/4fe8f16eb3314a46b2b70a1e83b1ef21~tplv-tika-image.image)

**子命令：**
- `setup`：设置预合并测试
- `update`：更新预合并回归测试流水线
- `integration`：运行集成测试
- `remote`：运行远程测试
- `generate`：生成空测试文件

#### 测试环境变量配置

在 `.monorepo_config.yaml` 中配置测试参数，支持基于不同路径的独立参数配置：

![测试参数配置](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/b751c47bc4c34758afb921ec92270f85~tplv-tika-image.image)

#### `tt mn test generate` - 生成测试

为所有公共方法生成示例单元测试：

![生成测试界面](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/5708ce3092ba4983a3c0b3fb8121546d~tplv-tika-image.image)

#### `tt mn test --coverage` - 测试覆盖率

类似于 `go test --cover`，运行单元测试后输出测试覆盖率结果的可视化。

### `tt mn validate` - 验证命令

在创建新的合并请求之前验证 Bazel Monorepo 项目。

**使用示例：**
```bash
# 验证项目
tt monorepo validate
```

### `tt mn update` - 更新命令

更新选定目标的构建和 CI 流水线脚本。

**使用示例：**
```bash
# 更新选中的目标
tt monorepo update

# 更新特定包
tt monorepo update app/story_api

# 更新所有 PSM 包
tt monorepo update --all
```

**子命令：**
- `iac`：更新 IAC 配置
- `mnConfig`：更新 Monorepo 配置
- `readme`：更新旧仓库的 README
- `scm`：更新 Monorepo 迁移后的 SCM 名称
- `imports`：更新 Monorepo 中的导入路径

### `tt mn local` - 本地管理（稀疏检出）

管理本地磁盘上的 Monorepo 项目目标，支持稀疏检出功能。

**使用示例：**
```bash
# 列出本地磁盘上的所有目标
tt monorepo local ls

# 为 Monorepo 启用稀疏检出做准备
tt monorepo local enable-sparse

# 稀疏克隆 Monorepo
tt monorepo local clone git@code.byted.org:tiktok/tiktok.git tiktok

# 添加模块及其依赖到本地磁盘
tt monorepo local add arch/server/monorepo/gateway

# 从磁盘移除目标但保留在 git 历史中
tt monorepo local remove
```

### `tt mn idl` - IDL 管理

为新服务接入 Bazel Monorepo IDL 并生成相关脚本。

**使用示例：**
```bash
# 为所有启用的服务生成代码
tt monorepo idl generate

# 将仓库中的所有 IDL 文件接入 Bazel IDL
tt monorepo idl onboard
```

### `tt mn gen-idl` - IDL 代码生成

修改 IDL 文件后，运行此命令可在本地生成 IDL 代码。

**使用示例：**
```bash
# 为所有启用的服务生成 IDL 代码
tt monorepo gen-idl-code

# 为指定服务生成 IDL 代码
tt monorepo gen-idl-code app/service_api app/service_rpc
```

### `tt mn upgrade-go-version` - Go 版本升级

升级 Monorepo 中的 Go 版本，会更新 **go.mod、WORKSPACE、CI 文件和 atum 文件**。

![Go 版本升级界面](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/2e8beb17711745839f1aeefc8fe404ba~tplv-tika-image.image)

## 开发工作流

### 本地开发建议流程

1. **代码检出**：使用 `tt mn local` 命令管理本地磁盘上的 Monorepo 项目目标
2. **代码验证**：修改代码后运行 `tt mn validate` 进行验证
3. **本地构建**：使用 `tt mn build` 在本地构建变更
4. **单元测试**：运行 `tt mn test` 执行本地单元测试

### 稀疏检出（推荐）

建议启用稀疏检出功能，仅检出当前工作模块的代码，提高开发效率。

## 故障排除与支持

### 常见问题

- **CI 失败**：如果 CI 在第一个或最后一个阶段失败，很可能是网络问题或 CI 设置不正确导致的
- **构建/测试失败**：请详细检查日志以找出错误信息

### 获取帮助

- **团队成员**：如有任何问题，可联系 Monorepo 团队成员
- **FAQ 文档**：[Monorepo FAQ](https://bytedance.larkoffice.com/wiki/G6m0w1u6oijVQxksmrMctXAQnBd)
- **Oncall**：[Oncall 入口](https://oncall.bytedance.net/chats/user/index?tenantId=7026)

## 最佳实践

1. **使用 CLI 工具**：充分利用 `tt mn` 命令集来简化和优化开发流程
2. **稀疏检出**：对于大型 Monorepo，建议使用稀疏检出功能
3. **自动化验证**：安装 CloudDev 插件和 auto-gazelle 功能来自动验证变更
4. **定期更新**：使用 `tt mn update` 命令保持构建和 CI 流水线脚本的最新状态

