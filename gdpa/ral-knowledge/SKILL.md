---
name: ral-knowledge
description: RAL (Resource Access Layer) 初始化与使用指南。Use when initializing RAL in GDP/Non-GDP services, configuring traffic scheduling strategies (Topology/StoreRegion/VideoRegion/Custom), or making RPC calls with RAL routing.
user-invocable: false
---

# RAL 初始化指南

## 概述

所有使用 RAL 组件的服务，必须在服务启动时进行初始化。初始化方式根据服务是否接入 GDP 框架而有所不同。

### 整体初始化流程

1. **判断服务类型**
   - 检查 `main.go` 是否使用 GDP 引导库。

2. **执行初始化**
   - **GDP 服务**：直接启用 RAL 插件 (`regionrouter.UseRalPlugin()`)。
   - **非 GDP 服务**：
     1. **代码初始化**：调用 `bridge.Init` 并加载 `WithRal`。
     2. **框架适配**：根据 Kitex/Hertz 等框架注入 Middleware 或 Context。
     3. **编译脚本**：修改 `build.sh` 确保 RAL 配置被递归拷贝。

> **如何判断是否接入 GDP 框架？**
> 查看 `main.go` 函数，检查是否使用 `code.byted.org/gdp/gdp` 作为引导库启动。

## GDP 服务初始化

对于标准的 GDP 服务，只需在 `main.go` 或 `init.go` 中启用 RAL 插件即可。

```go
import "code.byted.org/gdp/regionrouter"

func Init() {
    // 启用 RAL 插件
    regionrouter.UseRalPlugin()
}
```

## 非 GDP 服务初始化 (使用 Bridge)

非 GDP 服务需使用 `bridge` 包初始化，并根据使用的服务框架（Kitex, Hertz 等）进行适配。

### Step 1: 初始化组件

```go
import "code.byted.org/gdp/dam/bridge"

func Init() {
    bridge.Init(
        bridge.WithRal(),
        bridge.WithRegionrouter(),
    )
}
```

### Step 2: 框架适配

根据使用的具体框架，需要进行额外的初始化（如添加 Middleware）。

**Kitex**:
```go
import bridgeKitex "code.byted.org/gdp/dam/bridge/kitex"

mw := bridgeKitex.NewMiddleware()
svr := itemservice.NewServer(new(ItemServiceImpl), server.WithMiddleware(mw))
```

**Hertz**:
```go
import bridgeHertz "code.byted.org/gdp/dam/bridge/hertz"

mw := bridgeHertz.NewMiddleware()
r.Use(mw)
```

**Ginex**:
```go
import bridgeGinex "code.byted.org/gdp/dam/bridge/ginex"

r := ginex.Default()
bridgeGinex.Use(r)
```

**Consumer**:
```go
import "code.byted.org/gdp/dam/bridge"

func Handler(ctx context.Context) {
    ctx = bridge.InitContext(ctx) // Add InitContext

    // Biz Logic...
}
```

**FaaS**:
```go
import (
    "code.byted.org/gdp/dam/bridge"
    "code.byted.org/gdp/dam/bridge/faas"
)

func main() {
    bytefaas.Start(faas.Wrap(handler))
}
```

### Step 3: 修改编译脚本 (build.sh)

非 GDP 服务需要确保 RAL 配置文件正确拷贝。

根据服务类型，修改 `build.sh` 中的配置文件拷贝逻辑。

**Kitex / Hertz / Faas / Consumer 服务**:
找到拷贝配置的命令（通常是 `cp conf/* output/conf/`），添加 `-r` 参数以支持递归拷贝。
```bash
cp -r conf/* output/conf/
```

**Kite / Ginex 服务**:
找到原有的拷贝配置命令，在下方添加以下命令：
```bash
find conf/ -type f ! -name "*_local.*" | xargs -I{} cp {} output/conf/
mkdir -p output/conf/ral
cp -r conf/ral/* output/conf/ral
```

---

# RAL 使用指南

## 概述
完成 RAL 初始化后，可以通过配置流量调度策略来实现跨机房路由、数据户口路由等高级功能。

## 1. 配置调度策略 (Configuration)

RAL 通过 `conf/ral/services/rpc.yaml` 配置流量调度策略。

### 基础配置结构
```yaml
ugc_center:               # 服务引用名
  PSM: tiktok.ugc.center  # 目标服务 PSM
  Protocol: rpc           # 协议 (仅支持 rpc)
  AdditionalCfg:
    RegionRouter:         # 流量调度配置
      Methods:
        MethodFoo:        # 方法级配置 (* 代表所有方法)
          TargetVRegion: ~ # ~ 代表默认本机房调度
```

### 调度策略详解

| 策略 | 说明 | 配置示例 |
|------|------|----------|
| **Topology** | **(默认)** Follow 下游部署架构调度。 | `TargetVRegion: ~` |
| **StoreRegion** | **数据户口**。基于实体 ID (如 UID) 归属地路由。 | `Strategy: storeregion` |
| **VideoRegion** | **视频位置**。基于 VID 所在机房路由。 | `Strategy: videoregion` |
| **Custom** | **自定义**。强制指定路由到某机房。 | `Strategy: custom`, `TargetVRegion: US-East` |

### StoreRegion 配置示例
```yaml
MethodFoo:
  Strategy: storeregion
  EntType: user        # 可选: user (默认), video
  EntIDGetter: fromreq # 必选: fromreq (需配置IDField), fromctx
  IDField: UserID      # fromreq 时必选
```

### VideoRegion 配置示例
```yaml
MethodFoo:
  Strategy: videoregion
  EntType: video
  EntIDGetter: fromreq
  IDField: Vid
  RoutingByMesh: true  # 必选
  FallbackToLocal: true
```

## 2. RPC 调用 (Usage)

使用 RAL 进行 RPC 调用时，会自动根据配置策略进行流量调度。

**版本要求**: `code.byted.org/kite/kitex` 版本必须为 `v1.15.5` 或 `>=v1.18.0`。

```go
import (
    // 方式一：使用 Overpass CLI (注意路径包含 /gdp/)
    "code.byted.org/tiktok/overpass/tiktok_ugc_center/gdp/rpc/tiktok_ugc_center"

    // 方式二：使用 RPCModels CLI
    tiktok_ugc_center "code.byted.org/tiktok/rpcmodels/tiktok_ugc_center/cli"
)

func Invoke(ctx context.Context) {
    req := &dto.PostRequest{}

    // 自动完成流量调度
    resp, err := tiktok_ugc_center.MethodFoo(ctx, req)
    if err != nil {
        // handle error
    }
}
```

### 注入上下文 (StoreRegion)
如果使用 `storeregion` 策略且需要手动注入国家码：
```go
import "code.byted.org/gdp/regionrouter"

func Invoker(ctx context.Context) {
    // 注入 countryCode 到 ctx 中
    ctx = regionrouter.WithStoreCountry(ctx, "US")
    resp, err := client.MethodFoo(ctx, req)
}
```

## 3. 发布与验证

### IaC 发布
推荐使用 IaC 管理 RAL 配置：
```bash
# 预览变更
gdp iac preview ral

# 应用变更
gdp iac apply ral
```

### 验证
查看日志中的 `Notice`，检查 `target_vregion` 是否符合预期：
```text
Notice ... psm=[tiktok.ugc.center] ... target_vregion=[US-TTP] ...
```
