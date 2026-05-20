# Monorepo CI/CD 配置指南

## 概述

Monorepo的CI/CD流程由ServerArch - Monorepo团队统一配置和管理，通过分析每个项目的Bazel构建目标，CI流水线被单独配置和触发，不会影响跨服务。这种设计确保了各服务的独立性和构建效率。

## CI（持续集成）流程

### 标准CI流水线结构

所有Monorepo都有标准的CI流水线配置，每个服务的CI作业通常包含4个阶段：

1. **环境设置**（go, bazel） - 设置构建环境
2. **构建** - 执行Bazel构建
3. **测试** - 运行单元测试和集成测试
4. **测试覆盖率上传** - 上传测试覆盖率数据

### CI故障排查

当CI出现故障时，需要根据故障阶段进行排查：

- **第一阶段或最后阶段失败**：很可能是网络问题或CI设置不正确导致的，而不是代码变更引起的。建议首先重新运行作业，如果仍然失败，请联系Monorepo团队。

- **构建或测试阶段失败**：请详细检查日志以找出错误信息。

### CI配置最佳实践

#### 1. 创建yaml配置文件
在`.codebase/pipeline`目录中创建yaml配置文件。

#### 2. 使用标准模板和镜像
```yaml
template: bazel
name: Bazel ci
job_name: Bazel ci
image: hub.byted.org/base/bazel.codebase_ci_base:latest
env: boe
enable_proxy: true
enable_byteview: true
enable_codecov: true
enable_consul: true
```

#### 3. 网络代理配置
- 为了提升拉包速度和防止网络拉包错误，如果是BOE环境（online有时也需要），需要加上`enable_proxy = true`
- 添加代理后如果会破坏一些涉及HTTP的测试，可以在执行测试时取消代理设置：
  ```bash
  --test_env=http_proxy= --test_env=https_proxy= --test_env=no_proxy=
  ```

#### 4. Go配置迁移
Go的其他配置如`enable_consul: true`、`enable_mysql:true`可以原封不动地复制到Bazel CI中。

## CD（持续部署）流程

### 部署方式选择

在Monorepo中，您仍然可以保持原有的部署方式。我们推荐使用[Monorepo TBD（Trunk Based Development）](https://bytedance.larkoffice.com/wiki/wikcnOxFMOw4ikrSPTkSUbUl5Wd)作为Monorepo中的通用部署方法。

### ByteCycle工作空间配置

为新的Monorepo配置新的ByteCycle工作空间和相关子项目。每个服务可以根据相关性单独发布或同时发布多个服务。

### 部署指南文档

详细的部署配置和操作指南请参考：
- [Monorepo Development Runbook / Monorepo 开发指南](https://bytedance.larkoffice.com/docx/GyRjd6rBSoH9WLx0z6scKVppnwc)
- [Monorepo Deployment Runbook / Monorepo 部署指南](https://bytedance.feishu.cn/wiki/wikcnOxFMOw4ikrSPTkSUbUl5Wd)

## 测试左移策略

### 集成测试和回归测试

为了支持每个团队提高集成测试和回归测试覆盖率以符合测试左移策略，我们在CI上设置了集成测试和回归测试，以确保代码质量。

### 测试配置指南

如何设置和集成CI测试，以及如何实现集成测试的明确指南：
- [Shift Left Testing - Integration Test](https://bytedance.feishu.cn/wiki/G3Z6wsRNriwhxxk6igNcUwsnnge)

## 常见问题与解决方案

### 1. Bazel diff CI作业失败
当Bazel diff CI作业失败时，首先确定问题，然后评估是否需要升级Go依赖项。如果不需要，只需恢复到原始版本。如果需要升级，请找到一个兼容的版本来解决升级依赖项中的破坏性更改。运行`go get xxx@latest`通常可以解决此类问题。

### 2. SCM配置
创建用于测试的新SCM仓库，类似于：https://cloud-us.bytedance.net/scm/detail/297338/versions，并在适用时将该仓库同步到TTP。

### 3. CI作业触发
新创建的SCM仓库将用于运行SCM作业，并确保在每个PSM的ci.yaml文件中，在SCM和SCM TTP作业下使用测试仓库。

## 参考文档

- [Bazel Monorepo Continuous Integration](https://bytedance.larkoffice.com/wiki/SM4mwCVfDi9PlBkF6JkcGVBznJh) - 详细的CI作业配置说明
- [Monorepo Continuous Integration](https://bytedance.us.feishu.cn/docx/PPmAdVKzYoeuMexHp3XualPZsIe?from=from_copylink) - Monorepo持续集成详细文档
- [Monorepo Development Runbook](https://bytedance.larkoffice.com/docx/GyRjd6rBSoH9WLx0z6scKVppnwc) - Monorepo开发运行手册
- [Monorepo Deployment Runbook](https://bytedance.feishu.cn/wiki/wikcnOxFMOw4ikrSPTkSUbUl5Wd) - Monorepo部署运行手册

## 最佳实践

1. **保持CI配置一致性**：所有服务使用相同的CI模板和配置标准
2. **及时处理CI故障**：定期监控CI状态，及时处理构建失败
3. **优化构建时间**：利用Bazel的增量构建特性减少构建时间
4. **测试覆盖率监控**：确保测试覆盖率数据准确上传和分析
5. **部署策略规划**：根据服务相关性制定合理的部署计划