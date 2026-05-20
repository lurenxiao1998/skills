# TCC Golang SDK 使用说明

TCC（动态配置中心）是字节跳动内部的配置管理服务，提供配置的动态下发和实时更新能力。

## SDK 选型指南

TCC 有两个主要的 Golang SDK：

| SDK | 适用范围 | go mod path | 推荐版本 |
|-----|----------|-------------|----------|
| TCC V2 正式版 SDK | 访问 TCC V2/V3 配置 | `code.byted.org/gopkg/tccclient` | >= v1.6.2 |
| TCC V3 正式版 SDK | 访问 TCC V3 配置 | `code.byted.org/gopkg/tccclient/v3` | >= v3.0.0 |

## TCC V2 SDK 使用

### 安装

```shell
go get code.byted.org/gopkg/tccclient
```

> `code.byted.org/gopkg/tccclient` 正式版本（≤ 1.4.19 或 ≥ 1.6.2）的 ClientV2 同时支持读取 TCC V2、TCC V3 配置，是当前读取 TCC V3 配置时最稳定、适用性最佳的版本。

### 基础用法

```go
import (
    "context"
    "code.byted.org/gopkg/tccclient"
)

func main() {
    ctx := context.Background()

    // 创建配置
    config := tccclient.NewConfigV2()
    config.Confspace = "default"

    // 创建客户端
    clientV2, err := tccclient.NewClientV2("your.service.name", config)
    if err != nil {
        panic(err)
    }

    // 读取配置
    value, err := clientV2.GetConfig(ctx, "config_key")
    if err != nil {
        // 处理错误
    }
}
```

### 日志控制

TCC SDK 可能会输出 `context deadline exceeded` 日志，这属于正常行为。如需减少日志数量，请升级到 `>= v1.2.32` 版本，并使用以下方法：

#### 方法一：SetLogMode

```go
config := tccclient.NewConfigV2()
config.Confspace = "default"
config.SetLogMode(tccclient.HighMode)  // 设置日志模式

clientV2, err := tccclient.NewClientV2("your.service.name", config)
```

日志模式说明：

| 参数 | 效果 |
|------|------|
| `tccclient.LowMode` | 60s 时间窗口，前 4 次不打印，后续打印 |
| `tccclient.MediumMode` | 300s 时间窗口，前 4 次不打印，后续打印 |
| `tccclient.HighMode` | 300s 时间窗口，前 2 次不打印，后续打印 |
| `tccclient.AlwaysMode` | 所有错误日志都打印 |
| `tccclient.ForbiddenMode` | 不打印错误日志 |

#### 方法二：SetLogCounter

```go
import "time"

config := tccclient.NewConfigV2()
config.Confspace = "default"
// 在 200s 时间窗口内，前 2 次错误不打印，后续打印
config.SetLogCounter(3, 200*time.Second)

clientV2, err := tccclient.NewClientV2("your.service.name", config)
```

参数说明：

| 参数 | 说明 |
|------|------|
| `triggerLogCount int` | 时间窗口内前 n-1 次错误不打印，后续打印 |
| `triggerLogDuration time.Duration` | 时间窗口大小 |

## TCC V3 SDK 使用

### 安装

```shell
go get code.byted.org/gopkg/tccclient/v3
```

### 基础用法

```go
import (
    "context"
    tccclientv3 "code.byted.org/gopkg/tccclient/v3"
)

func main() {
    ctx := context.Background()

    // 创建 V3 客户端
    clientV3, err := tccclientv3.NewClientV3("your.service.name", nil)
    if err != nil {
        panic(err)
    }

    // 读取配置（需要指定目录和配置名）
    value, err := clientV3.GetConfig(ctx, "dir_name", "config_name")
    if err != nil {
        // 处理错误
    }
}
```

## 升级指南

### 从 alpha/beta 版本升级

如果你使用了以下 alpha/beta 版本，需要升级到正式版：

- `v1.5.0-beta.*`
- `v1.5.0-alpha.*`
- `v1.4.13`（意外泄露版本）

#### 升级方案

根据使用情况选择升级方案：

1. **仅使用 ClientV2**：升级到 TCC V2 正式版 SDK
   ```shell
   go get code.byted.org/gopkg/tccclient
   ```

2. **仅使用 ClientV3**：升级到 TCC V3 正式版 SDK
   ```shell
   go get code.byted.org/gopkg/tccclient/v3
   ```

3. **同时使用 ClientV2 和 ClientV3**：需要同时引入两个 SDK
   ```shell
   go get code.byted.org/gopkg/tccclient
   go get code.byted.org/gopkg/tccclient/v3
   ```

### 破坏性变更说明

#### V3 方法签名变更

从 `1.5.0-beta.xx` 升级到 `v3.0.0` 时，涉及 Key 的方法签名有变化：

```go
// 旧版本（beta）：Key 手动拼接
value, err := clientV3.GetConfig(ctx, "/some/dir/config_name")

// 新版本（v3.0.0）：Dir 和 ConfigName 分开
value, err := clientV3.GetConfig(ctx, "some/dir", "config_name")
```

这个变更是为了支持配置名称中包含 `/` 的场景。

## 缓存机制

TCC SDK 自带缓存功能，默认无过期设置以提升可用性。这可能导致在某些极端情形下缓存长时间未刷新。

如果业务对此敏感，建议主动进行监控配置。

## 已封禁版本

以下版本存在已知 bug，已通过血缘平台封禁，**严禁在生产环境中使用**：

| SDK | 封禁版本 |
|-----|----------|
| `code.byted.org/gopkg/tccclient` | v1.4.18, v1.4.13, v1.5.0-beta.10, v1.5.0-beta.9, v1.5.0-beta.8, v1.5.0-alpha.1 ~ v1.5.0-alpha.19 |

## 参考资料

- [TCC V2 SDK CHANGELOG](https://code.byted.org/gopkg/tccclient/blob/master/CHANGELOG.md)
- [TCC V2 SDK README](https://code.byted.org/gopkg/tccclient/blob/master/README.md)
- [TCC V3 SDK CHANGELOG](https://code.byted.org/gopkg/tccclient/blob/v3/CHANGELOG.md)
- [TCC V3 SDK README](https://code.byted.org/gopkg/tccclient/blob/v3/README.md)
- [TCC V3 服务控制台](https://cloud.bytedance.net/tcc/namespace)
