# Monorepo 单元测试指南

## 单元测试框架

在Bazel Monorepo中，我们统一了单元测试框架和代码指导规范，主要使用以下工具：

### Mockey（Mock库）
- **官方文档**：[Mockey (go mockito) 使用说明](https://bytedance.larkoffice.com/wiki/wikcn2apwF3H9HhQHQjWa5yLRtf)
- **实现机制**：[浅谈 Golang 中的猴子补丁 —— 以 mockey 为例](https://bytedance.sg.larkoffice.com/docx/WQlkd8sr5ozYvJxo9pDcacYefnnh)

### Convey（断言库）
- **最佳实践**：[单元测试 Convey + Mockey 全知全解](https://bytedance.larkoffice.com/wiki/WgNewv3u7iNyQHksjRvcU8Kjnme)

### 代码示例
```go
// 原始代码
func SendTextMsg(ctx context.Context, msg string, id string, t string) error {
    if msg == "" {
       return nil
    }
    textContent := model.TextContent{
       Text: msg,
    }
    text, err := jsoniter.MarshalToString(textContent)
    if err != nil {
       logs.CtxError(ctx, "marshal to string failed, err=", err)
       return err
    }

    err = larkProvider.SendMessage(ctx, t, id, text, "text")
    if err != nil {
       logs.CtxError(ctx, "send text msg failed, err=%s", err)
       return err
    }
    return nil
}

// 单元测试
import (
        "context"
        "fmt"
        "testing"

        "github.com/bytedance/mockey"
        jsoniter "github.com/json-iterator/go"
        "github.com/smartystreets/goconvey/convey"
)

func TestSendTextMsg(t *testing.T) {
        t.Run("Happy Case", func(t *testing.T) {
                mockey.PatchConvey("", t, func() {
                        // Arrange
                        mockey.Mock(jsoniter.MarshalToString).Return("", nil).Build()
                        mockey.Mock(lark.SendMessage).Return(nil).Build()

                        // Act
                        err := SendTextMsg(context.Background(), "", "", "")

                        // Assert
                        convey.So(err, convey.ShouldBeNil)
                })
        })
        t.Run("failed to send message", func(t *testing.T) {
                        // Arrange
                        mockey.Mock(jsoniter.MarshalToString).Return("", nil).Build()
                        mockey.Mock(lark.SendMessage).Return(errors.New("failed to send message")).Build()

                        // Act
                        err := SendTextMsg(context.Background(), "", "", "")

                        // Assert
                        convey.So(err, convey.ShouldNotBeNil)
        })
}
```

## 自动生成工具

### Bits单元测试（mocka）
- **用户指南**：[Bits单元测试Goland插件使用指南：Go语言](https://bytedance.feishu.cn/docx/Kc8ud6VMBoySD0x9f8Vc0FgLn2g?theme=LIGHT&contentTheme=DARK)

### LLM单元测试生成
通过LLM自动生成单元测试，支持Polyrepo和Monorepo两种模式。

#### 前置条件
1. 为仓库添加服务账号 `ci_qualityarchitecture_satcheck` 权限，用于提交UT用例的MR
2. 安装TT CLI：[TT CLI用户手册](https://bytedance.larkoffice.com/wiki/WieKwr8yKiNLvCkB4VlcJokVn9c)

#### Monorepo用户使用方式
1. 进入Monorepo目录，在源代码所在目录下运行：
   ```bash
   tt mn test generate --path={path to generate ut} --codebaseID={codebase_id}
   
   示例：
   tt mn test generate --path=arch/server/monorepo/remote --codebaseID=527953
   ```
2. 检查任务状态：
   ```bash
   tt mn test generate --taskID=152598
   ```

任务完成后会收到**Bits质量通知**发送的MR链接通知。

## 运行单元测试

### 本地运行（Mac）

#### CLI方式
使用 `tt mn test` 命令在本地运行单元测试。

**主要功能**：
- **选择并运行单元测试**：通过交互式界面选择要运行的测试模块
- **添加环境变量**：支持自定义环境变量，通过 `.monorepo_config.yaml` 配置文件管理不同路径的测试参数
- **远程测试**：使用 `tt mn test remote` 在bytesuite容器中运行测试，模拟CI环境
- **覆盖率测试**：使用 `tt mn test --coverage` 输出测试覆盖率可视化结果

**环境变量配置示例**：
在 `.monorepo_config.yaml` 中配置：
```yaml
testArgs:
  app/mention_api/:
    - GDP_MOCK_ROOT=app/mention_api
    - TCE_PSM=tiktok.mention.api
  app/mention_api/utils/:
    - IS_UNIT_TEST_ENV=1
    - TCE_PSM=tiktok.mention.rpc
```

#### Goland方式
- **文档**：[在Goland中运行单元测试](https://bytedance.larkoffice.com/wiki/UvkEwO6reik56Kkm1VucIdWgnsh)

### CI中运行单元测试
- **配置文档**：[CI中的单元测试配置](https://bytedance.larkoffice.com/wiki/XKUHwDsRIi0NOpkxoCYcRL20nUb)

## 测试生成功能

### `tt mn test generate` 命令
该命令用于为所有公共方法生成示例单元测试。

**使用流程**：
1. 运行 `tt mn test generate`
2. 选择目标模块
3. 系统会自动为该模块下所有没有单元测试的Go文件生成测试文件

**功能特点**：
- 自动识别需要测试的公共方法
- 生成符合框架规范的测试代码
- 支持批量生成多个测试文件

## 测试覆盖率

通过 `tt mn test --coverage` 命令可以获取测试覆盖率报告，该命令类似于 `go test --cover`，但提供了更直观的可视化结果展示。

**输出内容**：
- 各文件的测试覆盖率百分比
- 未覆盖的代码行
- 覆盖率趋势分析

## 最佳实践

1. **测试左移**：在开发早期编写单元测试，尽早发现问题
2. **Mock使用**：合理使用Mockey进行依赖模拟，确保测试隔离性
3. **断言清晰**：使用Convey提供清晰的断言描述
4. **覆盖率目标**：设定合理的测试覆盖率目标，通常建议不低于80%
5. **CI集成**：确保所有单元测试在CI流水线中自动运行

## 参考资料

1. [Unit Test Generation By LLM](https://bytedance.us.larkoffice.com/docx/RgxcdExY7oakF7xOOpCuFgZNsTb)
2. [TikTok CLI HowTos](https://bytedance.feishu.cn/wiki/wikcnvL6orQ5HMODAbwD8T2rTTh?theme=LIGHT&contentTheme=DARK)
3. [CI中的单元测试配置](https://bytedance.larkoffice.com/wiki/XKUHwDsRIi0NOpkxoCYcRL20nUb)

