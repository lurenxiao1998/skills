# Mockey (Go Mockito) 使用指南

## 概述

Mockey 是一个简单易用的 Golang 打桩库，可以快速方便地进行函数和变量的 mock。目前已广泛应用于字节跳动服务的单元测试编写中（7k+ Repo）。

**重要提示**:
1. 要求在编译时**禁用内联和编译优化**，否则无法工作
2. 强烈建议与 [goconvey](https://github.com/smartystreets/goconvey) 库一起使用

## 安装

```bash
go get github.com/bytedance/mockey@latest
```

## 快速上手

### 最简单的例子

```go
package main

import (
    "fmt"
    "math/rand"

    . "github.com/bytedance/mockey"
)

func main() {
    Mock(rand.Int).Return(1).Build() // mock `rand.Int` 总是返回 1
    fmt.Printf("rand.Int() 总是返回: %v\n", rand.Int())
}
```

### 单元测试示例

```go
package main_test

import (
    "math/rand"
    "testing"

    . "github.com/bytedance/mockey"
    . "github.com/smartystreets/goconvey/convey"
)

func Win(in int) bool {
    return in > rand.Int()
}

func TestWin(t *testing.T) {
    PatchConvey("TestWin", t, func() {
        Mock(rand.Int).Return(100).Build() // mock

        res1 := Win(101)
        So(res1, ShouldBeTrue)

        res2 := Win(99)
        So(res2, ShouldBeFalse)
    })
}
```

## 基础特性

### Mock 函数/方法

```go
// mock 函数
Mock(Foo).Return("MOCKED!").Build()

// mock 方法（值接收器）
Mock(A.Foo).Return("MOCKED!").Build()

// mock 方法（指针接收器）
Mock((*B).Foo).Return("MOCKED!").Build()
```

### Mock 泛型函数/方法

```go
// mock 泛型函数
MockGeneric(FooGeneric[string]).Return("MOCKED!").Build()

// mock 泛型方法
MockGeneric((*GenericClass[string]).Foo).Return("MOCKED!").Build()
```

### 钩子函数

```go
// 使用 To 指定钩子函数
Mock(Foo).To(func(in string) string { return "MOCKED!" }).Build()

// 方法 mock 可以包含接收器
Mock(A.Foo).To(func(a A, in string) string {
    return a.prefix + ":inner:" + "MOCKED!"
}).Build()
```

### PatchConvey 作用域管理

推荐使用 `PatchConvey` 组织测试用例，mock 作用域只在 `PatchConvey` 内部：

```go
func TestXXX(t *testing.T) {
    PatchConvey("mock 1", t, func() {
        Mock(Foo).Return("MOCKED-1!").Build()
        res := Foo("anything")
        So(res, ShouldEqual, "MOCKED-1!")
    })

    // mock 已释放
    PatchConvey("mock released", t, func() {
        res := Foo("anything")
        So(res, ShouldEqual, "ori:anything")
    })
}
```

### GetMethod 处理特殊情况

```go
// 通过实例 mock 方法
a := new(A)
Mock(GetMethod(a, "Foo")).Return("MOCKED!").Build()

// mock 未导出类型的导出方法
Mock(GetMethod(sha256.New(), "Sum")).Return([]byte{0}).Build()

// mock 未导出方法
Mock(GetMethod(new(bytes.Buffer), "empty")).Return(true).Build()

// mock 嵌套结构体中的方法
Mock(GetMethod(Wrapper{}, "Foo")).Return("MOCKED!").Build()
```

## 高级特性

### 条件 Mock

```go
Mock(Foo).
    When(func(in string) bool { return len(in) == 0 }).Return("EMPTY").
    When(func(in string) bool { return len(in) <= 2 }).Return("SHORT").
    When(func(in string) bool { return len(in) <= 5 }).Return("MEDIUM").
    Build()
```

### 序列返回

```go
Mock(Foo).Return(Sequence("Alice").Then("Bob").Times(2).Then("Tom")).Build()
fmt.Println(Foo("anything")) // Alice
fmt.Println(Foo("anything")) // Bob
fmt.Println(Foo("anything")) // Bob
fmt.Println(Foo("anything")) // Tom
```

### 装饰器模式

```go
origin := Foo
decorator := func(in string) string {
    fmt.Println("arg is", in)
    out := origin(in)
    fmt.Println("res is", out)
    return out
}
Mock(Foo).Origin(&origin).To(decorator).Build()
```

### Goroutine 过滤

```go
// 只在当前 goroutine 生效
Mock(Foo).IncludeCurrentGoRoutine().Return("MOCKED!").Build()

// 排除当前 goroutine
Mock(Foo).ExcludeCurrentGoRoutine().Return("MOCKED!").Build()
```

### 获取 Mocker

```go
mocker := Mock(Foo).Return("MOCKED!").Build()

// 跟踪调用次数
fmt.Println(mocker.MockTimes()) // mock 生效次数
fmt.Println(mocker.Times())     // 函数调用总次数

// 重新 mock
mocker.Return("MOCKED2!")

// 释放 mock
mocker.Release()
```

## 禁用内联和编译优化

### 命令行

```bash
go test -gcflags="all=-l -N" -v ./...
```

### GoLand

使用「Debug 模式」或在 **Run/Debug Configurations > Go tool arguments** 中填写：
```
-gcflags="all=-l -N"
```

### VSCode

使用「Debug 模式」或在 `settings.json` 中添加：
```json
"go.buildFlags": ["-gcflags='all=-N -l'"]
```

## 常见问题

### Mock 不生效

1. **未禁用内联优化** - 检查编译参数
2. **未调用 Build()** - 确保调用了 `.Build()`
3. **Mock 目标不匹配** - 检查是指针还是值接收器
4. **泛型函数** - 需使用 `MockGeneric`

### 错误 "function is too short to patch"

- 未禁用内联优化
- 函数太短，可使用 `MockUnsafe`
- 函数已被其他工具 mock

### 错误 "re-mock"

同一 PatchConvey 中重复 mock 同一函数，使用 `mocker.Return()` 重新 mock。

## 兼容性

- 操作系统：Mac OS / Linux / Windows
- 架构：AMD64 / ARM64
- Go 版本：1.13+

## 相关文档

- [Mockey 官方文档](https://bytedance.larkoffice.com/wiki/wikcn2apwF3H9HhQHQjWa5yLRtf)
- [GitHub 仓库](https://github.com/bytedance/mockey)
