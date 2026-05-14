# AnyCache 使用指南

## 安装

```bash
go get -u code.byted.org/webcast/libs_anycache
```

## 核心概念

### Fetcher 接口

用于单个数据获取的缓存封装：

```go
type Fetcher[K comparable, V any] interface {
    Get(ctx context.Context, key K) (V, error)
    Set(ctx context.Context, key K, value V) error
    Del(ctx context.Context, key K) error
    Refresh(ctx context.Context, key K) (V, error)
}
```

### BatchFetcher 接口

用于批量数据获取的缓存封装：

```go
type BatchFetcher[K comparable, V any] interface {
    MGet(ctx context.Context, keys []K) (map[K]V, error)
    MSet(ctx context.Context, data map[K]V) error
    MDel(ctx context.Context, keys []K) error
    MRefresh(ctx context.Context, keys []K) (map[K]V, error)
}
```

## 三种函数缓存模式

### 1. BuildFetcherByLoader - 简单函数缓存

适用于单个 key 获取单个 value 的场景：

```go
import (
    "code.byted.org/webcast/libs_anycache"
    "code.byted.org/webcast/libs_anycache/cachecomponent"
    "code.byted.org/webcast/libs_anycache/serializer"
)

// 定义数据加载函数
loader := func(ctx context.Context, userID int64) (*UserInfo, error) {
    return db.GetUserByID(ctx, userID)
}

// 构建 Fetcher
fetcher, err := libs_anycache.BuildFetcherByLoader(
    loader,
    cachecomponent.NewRedisCache(redisClient),
    serializer.NewJSONSerializer[*UserInfo](),
    libs_anycache.WithTTL(time.Minute*10),
    libs_anycache.WithNamespace("user_info"),
)

// 使用
userInfo, err := fetcher.Get(ctx, 12345)
```

### 2. BuildBatchFetcherByBatchLoader - 批量函数缓存

适用于源函数本身支持批量查询的场景：

```go
// 定义批量数据加载函数
batchLoader := func(ctx context.Context, userIDs []int64) (map[int64]*UserInfo, error) {
    return db.GetUsersByIDs(ctx, userIDs)
}

// 构建 BatchFetcher
batchFetcher, err := libs_anycache.BuildBatchFetcherByBatchLoader(
    batchLoader,
    cachecomponent.NewRedisCache(redisClient),
    serializer.NewJSONSerializer[*UserInfo](),
    libs_anycache.WithTTL(time.Minute*10),
    libs_anycache.WithNamespace("user_info"),
    libs_anycache.WithMaxFetchItemsCount(100),
)

// 使用
userInfoMap, err := batchFetcher.MGet(ctx, []int64{1, 2, 3, 4, 5})
```

### 3. BuildBatchFetcherByLoader - 批量请求单函数

适用于源函数不支持批量，但调用方需要批量获取的场景（内部会并发调用）：

```go
// 单个数据加载函数
loader := func(ctx context.Context, userID int64) (*UserInfo, error) {
    return db.GetUserByID(ctx, userID)
}

// 构建 BatchFetcher（内部会并发调用 loader）
batchFetcher, err := libs_anycache.BuildBatchFetcherByLoader(
    loader,
    cachecomponent.NewRedisCache(redisClient),
    serializer.NewJSONSerializer[*UserInfo](),
    libs_anycache.WithTTL(time.Minute*10),
    libs_anycache.WithNamespace("user_info"),
)

// 使用
userInfoMap, err := batchFetcher.MGet(ctx, []int64{1, 2, 3, 4, 5})
```

## 缓存组件

### LocalBytesCache - 本地缓存

基于 ies_bytescache 的本地内存缓存：

```go
import "code.byted.org/webcast/libs_anycache/cachecomponent"

localCache := cachecomponent.NewLocalBytesCache(
    cachecomponent.WithLocalCacheSize(1024 * 1024 * 100), // 100MB
)
```

### Redis 缓存

```go
import (
    "code.byted.org/kv/goredis/v8"
    "code.byted.org/webcast/libs_anycache/cachecomponent"
)

redisClient := goredis.NewClient(...)
redisCache := cachecomponent.NewRedisCache(redisClient)
```

### MultiLevel - 多层缓存

组合多个缓存层，先查本地再查 Redis：

```go
multiCache := cachecomponent.NewMultiLevelCache(
    localCache,  // L1: 本地缓存
    redisCache,  // L2: Redis 缓存
)
```

## 序列化组件

### JSON 序列化

```go
import "code.byted.org/webcast/libs_anycache/serializer"

// 标准库 JSON
jsonSerializer := serializer.NewJSONSerializer[*UserInfo]()

// json-iterator（性能更好）
jsonIterSerializer := serializer.NewJSONIterSerializer[*UserInfo]()
```

### MsgPack 序列化

```go
msgpackSerializer := serializer.NewMsgPackSerializer[*UserInfo]()
```

## 缓存策略 (SourceStrategy)

通过 `WithSourceStrategy` 选项配置缓存策略：

### SsCacheFirst - 缓存优先（默认）

先查缓存，缓存未命中或过期时回源：

```go
libs_anycache.WithSourceStrategy(libs_anycache.SsCacheFirst)
```

### SsSourceFirst - 回源优先

每次都回源，同时更新缓存：

```go
libs_anycache.WithSourceStrategy(libs_anycache.SsSourceFirst)
```

### SsOnlyCache - 只读缓存

只从缓存读取，不回源：

```go
libs_anycache.WithSourceStrategy(libs_anycache.SsOnlyCache)
```

### SsOnlySource - 只回源

只从源读取，不使用缓存：

```go
libs_anycache.WithSourceStrategy(libs_anycache.SsOnlySource)
```

### SsExpiredDataBackup - 过期数据兜底

缓存过期时先尝试回源，回源失败则返回过期数据：

```go
libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataBackup)
```

### SsExpiredDataAndAsyncSource - 过期数据+异步回源

缓存过期时立即返回过期数据，同时异步回源更新缓存：

```go
libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataAndAsyncSource)
```

## 配置选项

### 基础配置

```go
// 缓存 TTL
libs_anycache.WithTTL(time.Minute * 10)

// 删除操作的 TTL（软删除）
libs_anycache.WithDelTTL(time.Second * 30)

// 命名空间（key 前缀）
libs_anycache.WithNamespace("user_info")

// 批量操作最大数量
libs_anycache.WithMaxFetchItemsCount(100)
```

### 高级配置

```go
// 缓存 nil 值（防止缓存穿透）
libs_anycache.WithCacheNil(true)

// 异步保存缓存
libs_anycache.WithAsyncSaveCache(true)

// 自定义 key 生成函数
libs_anycache.WithKeyFunc(func(key int64) string {
    return fmt.Sprintf("user:%d", key)
})
```

## 最佳实践示例

### 高可用缓存配置

使用多层缓存 + 过期数据兜底，确保高可用：

```go
import (
    "code.byted.org/webcast/libs_anycache"
    "code.byted.org/webcast/libs_anycache/cachecomponent"
    "code.byted.org/webcast/libs_anycache/serializer"
)

func NewUserFetcher(redisClient *goredis.Client) (libs_anycache.Fetcher[int64, *UserInfo], error) {
    // 本地缓存
    localCache := cachecomponent.NewLocalBytesCache(
        cachecomponent.WithLocalCacheSize(1024 * 1024 * 50), // 50MB
    )

    // Redis 缓存
    redisCache := cachecomponent.NewRedisCache(redisClient)

    // 多层缓存
    multiCache := cachecomponent.NewMultiLevelCache(localCache, redisCache)

    // 数据加载函数
    loader := func(ctx context.Context, userID int64) (*UserInfo, error) {
        return db.GetUserByID(ctx, userID)
    }

    return libs_anycache.BuildFetcherByLoader(
        loader,
        multiCache,
        serializer.NewJSONIterSerializer[*UserInfo](),
        libs_anycache.WithTTL(time.Minute*10),
        libs_anycache.WithNamespace("user_info"),
        libs_anycache.WithSourceStrategy(libs_anycache.SsExpiredDataBackup), // 过期数据兜底
        libs_anycache.WithCacheNil(true), // 缓存空值防穿透
    )
}
```

### 批量查询优化

```go
func NewUserBatchFetcher(redisClient *goredis.Client) (libs_anycache.BatchFetcher[int64, *UserInfo], error) {
    batchLoader := func(ctx context.Context, userIDs []int64) (map[int64]*UserInfo, error) {
        return db.GetUsersByIDs(ctx, userIDs)
    }

    return libs_anycache.BuildBatchFetcherByBatchLoader(
        batchLoader,
        cachecomponent.NewRedisCache(redisClient),
        serializer.NewMsgPackSerializer[*UserInfo](), // MsgPack 序列化更高效
        libs_anycache.WithTTL(time.Minute*5),
        libs_anycache.WithNamespace("user_batch"),
        libs_anycache.WithMaxFetchItemsCount(200),
        libs_anycache.WithAsyncSaveCache(true), // 异步写缓存
    )
}
```

## 相关资源

- [libs_anycache 仓库](https://code.byted.org/webcast/libs_anycache)
