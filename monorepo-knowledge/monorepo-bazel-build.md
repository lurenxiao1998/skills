# Bazel 构建配置指南

本文档详细介绍了在TikTok Bazel Monorepo中进行Bazel构建适配的关键配置和常见问题解决方案。

## 指定Go版本

在Bazel Monorepo中构建Go项目时，需要明确指定使用的Go版本。

### 配置方式
在项目根目录的`WORKSPACE`文件最后一行添加：
```python
workspace_init("1.20")
```

### 版本类型说明
- **Tango版本**：如`"1.20"`，这是TikTok内部的Go发行版
- **开源版本**：如`"oss1.22.11"`，使用开源Go版本
- **系统版本**：`"host"`，使用系统安装的Go版本

### 验证当前版本
运行以下命令验证Bazel使用的Go版本：
```bash
bazel run @go_sdk//:bin/go -- version
```

## Tango Beast Mode优化

Tango Beast Mode是TikTok内部的Go编译器优化模式，可以显著提升构建性能。

### 启用方式

#### 单个Target启用
在`bazel build`命令后添加以下选项：
```bash
--@io_bazel_rules_go//go/config:gc_goopts=-beast=bce:gabinline:intrinsic:amdver=3:makeslicecopy:loglocation:inlbudget=240
--@io_bazel_rules_go//go/config:gc_linkopts=-enablebeast
```

#### 全局仓库启用
在`.bazelrc`文件中添加：
```python
build --@io_bazel_rules_go//go/config:gc_goopts=-beast=bce:gabinline:intrinsic:amdver=3:makeslicecopy:loglocation:inlbudget=240
build --@io_bazel_rules_go//go/config:gc_linkopts=-enablebeast
```

### 验证Beast Mode
在Linux环境下运行：
```bash
go tool buildid your_binary
```
- 如果结果为`redacted`：Beast Mode未启用
- 如果结果为`redacted/beastmode`：Beast Mode已成功启用

![Beast Mode验证示例](https://p-tika-sg.tiktok-row.net/tos-alisg-i-tika-sg/0cde2a8e76bf43608a1416d4fc055374~tplv-tika-image.image)

## 跨仓库IDL消费

Bazel支持跨仓库消费IDL（接口定义语言），简化外部依赖管理。

### 配置示例
在服务仓库中使用`go_repository`导入外部IDL仓库：
```python
go_repository(
    name = "service_rpc_idl",
    build_file_generation = "on",
    build_directives = [
        "gazelle:thrift_enable_all",
    ],
    build_extra_args = [
        "-thrift_import_prefix=code.byted.org/tiktok/tiktok",
    ],
    build_file_proto_mode = "disable_global",
    importpath = "code.byted.org/tiktok/service_rpc_idl",
    commit = "42b3727890bc27ca886bb589b6bbcb6f1eec340e",
)
```

### 代码引用
在Go代码中可以直接导入生成的代码：
```go
import (
    "code.byted.org/devinfra/monorepo/kitex_gen/a/b/c/tceimportservice"
)
```

### BUILD文件配置
```python
go_library(
    name = "go_lib",
    srcs = ["main.go"],
    importpath = "code.byted.org/devinfra/monorepo/examples/calc/go",
    visibility = ["//visibility:private"],
    deps = [
        "//examples/calc/idl:example_kitex",
        "@com_github_apache_thrift//lib/go/thrift",
        "@test_idl//:a_b_c_tceimportservice_kitex"
    ],
)
```

## 常见构建问题解决

### 1. 链接器错误：relocation overflow
**症状**：`error: relocation overflow: reference to local symbol`

**原因**：32位相对跳转/调用超出范围

**解决方案**：
- 在`.bazelrc`中添加：
  ```python
  test --linkopt='-pie'
  ```
- 或直接在命令中添加：`--linkopt=-pie`

### 2. 包冲突错误
**症状**：`package conflict error: XXX was compiled with ... But linked with ...`

**解决方案**：手动告诉gazelle冲突包的解析目标

**示例**（Cloudwego Kitex升级问题）：
在根目录`BUILD.bazel`中添加：
```python
# gazelle:resolve go github.com/cloudwego/kitex/pkg/protocol/bthrift @com_github_cloudwego_kitex//pkg/protocol/bthrift:bthrift
# gazelle:resolve go github.com/cloudwego/kitex/pkg/protocol/bthrift/apache @com_github_cloudwego_kitex//pkg/protocol/bthrift/apache:apache
```

### 3. MacOS本地编译错误
**症状**：`ld: B/BL out of range -152495120 (max +/-128MB)`

**解决方案**：
- 在命令中添加：`--@io_bazel_rules_go//go/config:gc_linkopts="-extldflags, -ld64"`
- 或在`BUILD.bazel`中配置：
  ```python
  go_binary(
      name = "devtask",
      basename = "main",
      embed = [":devtask_lib"],
      gc_linkopts = [
          "-extldflags",
          "-ld64",
      ],
      visibility = ["//visibility:public"],
  )
  ```

### 4. 第三方库不兼容
**症状**：go build能过，但bazel build失败

**常见案例**：
- **gorm.io插件**：需要同步更新相关插件库
- **protobuf编译**：本地安装的header文件冲突

**解决方案**：
1. 咨询团队文档：
   - [Monorepo Technical FAQ](https://bytedance.larkoffice.com/wiki/wikcnWyrxLUe2h13iZfQ9Izao0b)
   - [Bazel Monorepo Troubleshootings](https://bytedance.larkoffice.com/wiki/wikcn2z0ooQHB1DFFCabPbgc3Ay)
2. 联系[Bazel Oncall](http://go/bazeloncall)

## 调试相关配置

### 调试器兼容性问题
**症状**：`internal debugger error`

**原因**：Tango compiler与开源delve不兼容

**解决方案**：将`WORKSPACE`中的Go版本从Tango版本改为开源版本
```python
# 从
workspace_init("1.22")
# 改为
workspace_init("oss1.22")
```

## 最佳实践建议

1. **版本一致性**：确保开发、测试、生产环境使用相同的Go版本
2. **渐进式优化**：先确保基础构建通过，再逐步启用Beast Mode等优化
3. **依赖管理**：优先使用跨仓库IDL消费，避免代码重复
4. **问题排查**：遇到构建问题时，先运行`bazel clean --expunge`清理缓存
5. **工具链更新**：定期更新bazelisk和构建工具链

## 参考文档
- [Bazel Documentation (CN)](https://bytedance.larkoffice.com/wiki/IRufwLcU5ivxyGkg1DccQhDunyd)
- [Bazel Documentation (EN)](https://bytedance.larkoffice.com/wiki/QHghwxTMkizphgkD2CCcEEZQnJY)
- [Bazel Oncall](http://go/bazeloncall)
