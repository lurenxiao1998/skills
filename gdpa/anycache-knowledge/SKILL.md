---
name: anycache-knowledge
description: Use when working with code.byted.org/webcast/libs_anycache caching library in Golang services, implementing function cache, batch cache, or configuring cache strategies (cache-first, source-first, expired-data-backup).
user-invocable: false
---

# AnyCache 缓存组件

AnyCache 是 ByteDance webcast 团队开发的缓存最佳实践库，帮助开发者安全、优雅地使用缓存。

## SDK 接入

```bash
go get -u code.byted.org/webcast/libs_anycache
```

## 核心功能

### 1. 函数缓存（Function Cache）

将任意函数的执行结果自动缓存，无需手动管理缓存的读写逻辑：

```go
// 定义数据加载函数
loader := func(ctx context.Context, userID int64) (*UserInfo, error) {
    return db.GetUserByID(ctx, userID)
}

// 构建带缓存的 Fetcher
fetcher, _ := libs_anycache.BuildFetcherByLoader(
    loader,
    cachecomponent.NewRedisCache(redisClient),
    serializer.NewJSONSerializer[*UserInfo](),
    libs_anycache.WithTTL(time.Minute*10),
    libs_anycache.WithNamespace("user_info"),
)

// 使用：自动处理缓存读写
userInfo, err := fetcher.Get(ctx, 12345)
```

### 2. 批量缓存（Batch Cache）

支持批量数据获取，自动识别缓存命中/未命中的 key：

```go
// 批量加载函数
batchLoader := func(ctx context.Context, userIDs []int64) (map[int64]*UserInfo, error) {
    return db.GetUsersByIDs(ctx, userIDs)
}

batchFetcher, _ := libs_anycache.BuildBatchFetcherByBatchLoader(
    batchLoader,
    cachecomponent.NewRedisCache(redisClient),
    serializer.NewJSONSerializer[*UserInfo](),
    libs_anycache.WithTTL(time.Minute*10),
    libs_anycache.WithMaxFetchItemsCount(100),
)

// 批量获取：缓存命中的直接返回，未命中的批量回源
userInfoMap, err := batchFetcher.MGet(ctx, []int64{1, 2, 3, 4, 5})
```

### 3. 多层缓存（Multi-Level Cache）

组合本地缓存和远程缓存，减少网络开销：

```go
// L1: 本地缓存（毫秒级响应）
localCache := cachecomponent.NewLocalBytesCache(
    cachecomponent.WithLocalCacheSize(1024 * 1024 * 50), // 50MB
)

// L2: Redis 缓存
redisCache := cachecomponent.NewRedisCache(redisClient)

// 多层缓存：先查 L1，未命中再查 L2
multiCache := cachecomponent.NewMultiLevelCache(localCache, redisCache)
```

### 4. 缓存策略（Source Strategy）

六种策略满足不同业务场景：

| 策略 | 说明 | 适用场景 |
|-----|------|---------|
| `SsCacheFirst` | 缓存优先（默认） | 大多数读多写少场景 |
| `SsSourceFirst` | 回源优先，更新缓存 | 数据一致性要求高 |
| `SsOnlyCache` | 只读缓存，不回源 | 预热数据、降级场景 |
| `SsOnlySource` | 只回源，不用缓存 | 调试、特殊业务逻辑 |
| `SsExpiredDataBackup` | 过期数据兜底 | 高可用场景，容忍旧数据 |
| `SsExpiredDataAndAsyncSource` | 过期数据 + 异步回源 | 低延迟 + 最终一致 |

```go
// 过期数据兜底：回源失败时返回过期数据
libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataBackup)

// 异步回源：立即返回过期数据，后台异步更新
libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataAndAsyncSource)
```

## 最佳实践

### 场景一：用户信息缓存（高可用）

使用多层缓存 + 过期数据兜底，确保服务稳定：

```go
func NewUserFetcher(redisClient *goredis.Client) (libs_anycache.Fetcher[int64, *UserInfo], error) {
    localCache := cachecomponent.NewLocalBytesCache(
        cachecomponent.WithLocalCacheSize(1024 * 1024 * 50),
    )
    redisCache := cachecomponent.NewRedisCache(redisClient)
    multiCache := cachecomponent.NewMultiLevelCache(localCache, redisCache)

    loader := func(ctx context.Context, userID int64) (*UserInfo, error) {
        return db.GetUserByID(ctx, userID)
    }

    return libs_anycache.BuildFetcherByLoader(
        loader,
        multiCache,
        serializer.NewJSONIterSerializer[*UserInfo](),
        libs_anycache.WithTTL(time.Minute*10),
        libs_anycache.WithNamespace("user_info"),
        libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataBackup),
        libs_anycache.WithCacheNil(true), // 防止缓存穿透
    )
}
```

### 场景二：批量商品查询（高性能）

源函数支持批量查询，使用 MsgPack 序列化提升性能：

```go
func NewProductBatchFetcher(redisClient *goredis.Client) (libs_anycache.BatchFetcher[string, *Product], error) {
    batchLoader := func(ctx context.Context, productIDs []string) (map[string]*Product, error) {
        return productService.BatchGetProducts(ctx, productIDs)
    }

    return libs_anycache.BuildBatchFetcherByBatchLoader(
        batchLoader,
        cachecomponent.NewRedisCache(redisClient),
        serializer.NewMsgPackSerializer[*Product](), // MsgPack 更高效
        libs_anycache.WithTTL(time.Minute*5),
        libs_anycache.WithNamespace("product"),
        libs_anycache.WithMaxFetchItemsCount(200),
        libs_anycache.WithAsyncSaveCache(true), // 异步写缓存，降低延迟
    )
}
```

### 场景三：配置数据缓存（低延迟）

使用异步回源策略，优先返回数据：

```go
func NewConfigFetcher(redisClient *goredis.Client) (libs_anycache.Fetcher[string, *AppConfig], error) {
    loader := func(ctx context.Context, configKey string) (*AppConfig, error) {
        return configService.GetConfig(ctx, configKey)
    }

    return libs_anycache.BuildFetcherByLoader(
        loader,
        cachecomponent.NewRedisCache(redisClient),
        serializer.NewJSONSerializer[*AppConfig](),
        libs_anycache.WithTTL(time.Minute*1),
        libs_anycache.WithNamespace("app_config"),
        // 立即返回过期数据，后台异步更新
        libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataAndAsyncSource),
    )
}
```

### 场景四：外部 API 调用缓存（防穿透）

缓存外部 API 结果，包括空值：

```go
func NewExternalAPIFetcher(redisClient *goredis.Client) (libs_anycache.Fetcher[string, *ExternalData], error) {
    loader := func(ctx context.Context, resourceID string) (*ExternalData, error) {
        return externalAPI.GetResource(ctx, resourceID)
    }

    return libs_anycache.BuildFetcherByLoader(
        loader,
        cachecomponent.NewRedisCache(redisClient),
        serializer.NewJSONSerializer[*ExternalData](),
        libs_anycache.WithTTL(time.Minute*30),
        libs_anycache.WithNamespace("external_api"),
        libs_anycache.WithCacheNil(true),              // 缓存空值防穿透
        libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataBackup),
    )
}
```

## 常用配置选项

```go
// 基础配置
libs_anycache.WithTTL(time.Minute * 10)           // 缓存过期时间
libs_anycache.WithNamespace("prefix")              // Key 前缀
libs_anycache.WithMaxFetchItemsCount(100)          // 批量操作最大数量

// 高级配置
libs_anycache.WithCacheNil(true)                   // 缓存空值（防穿透）
libs_anycache.WithAsyncSaveCache(true)             // 异步写缓存
libs_anycache.WithDelTTL(time.Second * 30)         // 软删除 TTL
libs_anycache.WithKeyFunc(func(k int64) string {   // 自定义 key 生成
    return fmt.Sprintf("user:%d", k)
})
```

## 注意事项

1. **选择合适的序列化**：JSON 通用性好，MsgPack 性能更优
2. **合理设置 TTL**：根据数据更新频率和一致性要求权衡
3. **防止缓存穿透**：对可能为空的数据启用 `WithCacheNil(true)`
4. **批量操作限制**：设置 `WithMaxFetchItemsCount` 避免单次请求过大
5. **多层缓存顺序**：本地缓存在前，远程缓存在后

[anycache-usage.md](./anycache-usage.md) - AnyCache 完整 API 参考
