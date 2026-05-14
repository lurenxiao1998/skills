# Monorepo 本地开发指南

## 概述

本地开发是Bazel Monorepo日常开发的核心环节，遵循Trunk-Based Development原则，确保开发任务能在几天内合并到主分支。本地开发流程主要包括代码检出、验证、构建和测试四个关键步骤。

## 环境准备

### 安装TT CLI

在开始本地开发前，需要安装TT CLI工具：

**Mac & DevBox用户**：
```shell
$ ./script/setup_mac.sh        // for mac user 
$ ./script/setup_devbox.sh     // for devbox user
```

**CloudIDE用户**：
- **自动配置**：使用boei18n集群和.cloudide/bytediderc.json配置构建CloudIDE工作空间
- **手动配置**：从CloudIDE终端运行设置脚本：
```shell
$ ./script/setup_cloud_ide.sh     // for cloud ide user, manual setup
```

![CloudIDE配置界面](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/3fcc6650753a45e89473e588ff3a5833~tplv-tika-image.image)

## 本地开发流程

### 1. 代码检出

**稀疏检出（Sparse Checkout）**：
- **可选功能**：仅检出当前工作模块的代码，减少本地磁盘占用
- **使用方法**：按照[TT CLI Local Commands Usage(Sparse-Checkout)](https://bytedance.feishu.cn/wiki/Ldr3w2qttiaqzdkF6C7cAYb7nNd)指南启用稀疏检出功能
- **命令**：使用`tt mn local`命令管理本地磁盘上的Monorepo项目目标

### 2. 代码验证

**验证命令**：
```shell
$ tt mn validate
```

**推荐工具**：
- **CloudDev插件**：安装CloudDev插件和auto-gazelle功能，帮助自动验证代码变更
- **安装指南**：参考[Auto-Gazelle文档](https://bytedance.larkoffice.com/wiki/B8qKwIe1FizpOPk8Ztzc58pnngc)

### 3. 本地构建

**构建命令**：
```shell
$ tt mn build
```

**功能说明**：
- 在本地构建代码变更
- 验证Bazel构建配置的正确性
- 检查依赖关系是否完整

### 4. 单元测试

**测试命令**：
```shell
$ tt mn test
```

**详细指南**：
- 参考[Monorepo Unit Test Guide](https://bytedance.larkoffice.com/wiki/Gb2rwisT9ihtzOkL7Drc971Qnti)获取更多信息
- 支持本地运行所有测试相关命令

## 最佳实践

### 代码风格维护

**建议**：
- 保持一致的编码风格
- 遵循团队代码规范
- 定期运行代码格式化工具

### 开发效率提升

**工具推荐**：
1. **TT CLI工具**：使用`tt mn`命令集简化开发流程
2. **稀疏检出**：对于大型项目，启用稀疏检出减少本地资源占用
3. **自动验证**：配置CloudDev插件实现代码变更自动验证

### 问题排查

**常见问题**：
1. **构建失败**：检查Bazel构建配置和依赖关系
2. **验证错误**：运行`tt mn validate`查看详细错误信息
3. **测试失败**：参考单元测试指南排查测试用例问题

## 相关资源

- [TT CLI Local Commands Usage(Sparse-Checkout)](https://bytedance.feishu.cn/wiki/Ldr3w2qttiaqzdkF6C7cAYb7nNd)
- [Auto-Gazelle文档](https://bytedance.larkoffice.com/wiki/B8qKwIe1FizpOPk8Ztzc58pnngc)
- [Monorepo Unit Test Guide](https://bytedance.larkoffice.com/wiki/Gb2rwisT9ihtzOkL7Drc971Qnti)
- [TikTok Bazel Monorepo User Manual](https://bytedance.larkoffice.com/wiki/OYwbwD9ZjiZAtPkGVqScB7a9nHf)

## 技术支持

如有问题，请联系Monorepo团队：
- **美国团队（SJC & SEA）**：bartosz.narkiewicz@bytedance.com, jerry.jiang@bytedance.com
- **中国团队（深圳）**：tongjue.wang@bytedance.com, alex.he@bytedance.com, yipengwei@bytedance.com

**Oncall入口**：[Oncall](https://oncall.bytedance.net/chats/user/index?tenantId=7026)
