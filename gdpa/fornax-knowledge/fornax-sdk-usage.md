# Fornax SDK 使用指南

本文档详细介绍了Fornax SDK的安装、初始化、核心功能使用以及最佳实践，帮助开发者快速集成Fornax平台的各项AI能力。

## 环境准备

### 大模型Key获取
Fornax SDK支持多种大模型接入，需要提前获取相应的API Key：
- **MaaS（火山方舟）**：通过[cloud.bytedance.net](https://cloud.bytedance.net/docs/ark/docs/664afad9e16ff302cb5c0706/664afadc3c82fe026aad1aad)申请
- **GPT-OpenAPI**：通过[GPT-OpenAPI接入手册](https://bytedance.larkoffice.com/wiki/wikcnUPXCY2idGyg2AXKPvay4pd)申请

### 平台侧准备
1. **访问控制面**：
   - BOE/CN：https://fornax.bytedance.net/space
   - BOEI18N/I18N：https://fornax.byteintl.net/
2. **创建空间**：申请一个属于团队的空间
3. **生成AK/SK**：在空间管理中生成属于自己空间的Access Key和Secret Key，妥善保管

## SDK安装

### Golang
```go
go get code.byted.org/flowdevops/fornax_sdk@latest
```

### Python
确保Python版本≥3.8，并设置私有源：
```bash
pip install bytedance.fornax --upgrade
```

关键依赖包：
```python
langchain==0.2.0
langchain-community==0.2.0
langchain-core==0.2.0
langchain-openai==0.1.7
langchain_experimental==0.0.60
```

### Node.js
```shell
npm i @next-ai/fornax-sdk
```

## 配置与初始化

### 本地调试配置
本地调试需要配置环境变量以确保Trace能正确上报到对应环境：

**Golang SDK v1.0+**：
```bash
export RUNTIME_IDC_NAME=boe  # 海外环境可使用boei18n
export TCE_PSM=<your-psm>    # 如不设置则上报"-"
```

**Python SDK**：
需要在`import bytedance.infra`前全局注入环境变量

### 客户端初始化

**Golang**：
```go
import (
    "code.byted.org/flowdevops/fornax_sdk"
    "code.byted.org/flowdevops/fornax_sdk/domain"
)

func InitFornaxClient() (*fornax_sdk.Client, error) {
    client, err := fornax_sdk.NewClient(&domain.Config{
        Identity: &domain.Identity{
            AK: "your_ak",
            SK: "your_sk",
        },
    })
    return client, err
}
```

**Python**：
```python
from bytedance.fornax.infra import initialize, FornaxClient

# 方式1：全局初始化（单空间推荐）
initialize('your_ak', 'your_sk')

# 方式2：创建多个空间客户端
client1 = FornaxClient(ak1, sk1)
client2 = FornaxClient(ak2, sk2)
```

**重要原则**：请保证同一个AKSK只初始化一个fornaxClient，在多次请求时复用

## 核心功能使用

### 1. Prompt管理

#### 从Fornax平台拉取Prompt
**Golang**：
```go
func GetPrompt(ctx context.Context, client *fornax_sdk.Client) error {
    getPromptResult, err := client.GetPrompt(ctx, &prompt.GetPromptParam{
        Key: "fornax.example.trip_assistant",
    })
    if err != nil {
        return err
    }
    
    // 替换Prompt中的变量
    messageList, err := client.FormatPrompt(ctx, getPromptResult.Prompt, map[string]any{
        "role":         "旅游",
        "holiday_name": "五一",
        "recomm_num":   "3",
    })
    return err
}
```

**Python**：
```python
from bytedance.fornax.integration.langchain import FornaxPromptHub

prompt = FornaxPromptHub.get_chat_prompt_messages('fornax.example.trip_assistant')
if len(prompt) > 0:
    # system prompt
    print('role:' + prompt[0][0])
    print('content:' + prompt[0][1])
```

### 2. 大模型调用（Prompt as a Service）

#### 执行模式说明
Fornax SDK支持两种执行模式：

1. **远端执行模式**：
   - 接口调用时不传入`WithChatModelConfig` Option配置
   - Prompt渲染、模型参数组装、大模型调用、Trace上报等逻辑在Fornax服务内完成
   - 使用平台发布Prompt版本对应的模型参数值

2. **本地执行模式**：
   - 接口调用时传入`WithChatModelConfig` Option配置
   - SDK从Fornax服务只获取Prompt模板，渲染、调用等逻辑在SDK内完成
   - 需要传入`WithTemperature`等Option配置来指定模型参数

#### 同步调用示例
**Golang - 使用平台公共模型账号**：
```go
result, err := fornaxClient.ExecutePromptLocal(ctx, &execution.ExecutePromptLocalParam{
    PromptKey: "fornax.example.trip_assistant",
    Version:   nil, // 不指定则调用最新版本
    Variables: map[string]any{
        "role":         "旅行",
        "holiday_name": "元旦",
        "recomm_num":   3,
    },
})
```

**Golang - 使用本地模型账号**：
```go
modelConfig := &chatmodel.Config{
    Provider: chatmodel._MaaS_,
    MassConfig: &chatmodel.MaasConfig{
        Model:  "your_model_name",
        APIKey: "your_ak",
    },
}

result, err := fornaxClient.ExecutePromptLocal(ctx, &execution.ExecutePromptLocalParam{
    PromptKey: "fornax.example.trip_assistant",
    Version:   nil,
    Variables: map[string]any{
        "role":         "旅行",
        "holiday_name": "元旦",
        "recomm_num":   "3",
    },
}, execution.WithChatModelConfig(modelConfig), execution.WithTemperature(0.7))
```

#### 流式调用示例
**Golang**：
```go
streamReader, err := fornaxClient.StreamExecutePromptLocal(ctx, &execution.ExecutePromptLocalParam{
    PromptKey: "fornax.example.trip_assistant",
    Version:   nil,
    Variables: map[string]any{
        "role":         "旅行",
        "holiday_name": "元旦",
        "recomm_num":   3,
    },
}))

for {
    resp, err := streamReader.Recv(context.Background())
    if errors.Is(err, io.EOF) {
        break
    }
    if err != nil {
        return err
    }
    fmt.Println(resp.Choices[0].Delta.Content)
}
```

### 3. 知识库检索

**Golang**：
```go
result, err := client.RetrieveKnowledge(ctx, &knowledge.RetrieveKnowledgeParams{
    KnowledgeKeys: []string{"fornax.demo.your_first_knowledge"},
    Query:         "your user query",
    Channels: []*knowledge.Channel{
        {
            Field:    knowledge._RetrieveSource_Text_Embedding_,
            TopK:     2,
            MinScore: 0.82,
        },
    },
    TopK: 3,
})
```

**Python**：
```python
from bytedance.fornax.infra import Channel, RetrieveSource

retrieve_result = FornaxClient.global_fornax_client.retrieve_knowledge(
    'fornax.demo.your_first_knowledge', 
    'fornax是什么', 
    channels=Channel(field=RetrieveSource.TextEmbedding)
)
```

### 4. 链路观测

#### 自定义Span上报
**Golang**：
```go
func CustomSpan(ctx context.Context, client *fornax_sdk.Client) error {
    span, ctx, err := client.StartSpan(ctx, "my_span_name", "MySpanType")
    if err != nil {
        return err
    }

    // 设置自定义tag
    span.SetTag(ctx, map[string]interface{}{
        "key1":  "val1",
        "input": "val2",
    })

    // 业务逻辑...

    span.SetTag(ctx, map[string]interface{}{
        "key3":   "val3",
        "output": `{"content": "content"}`,
    })

    span.Finish(ctx) // 必须调用finish，否则无法完成上报
    return nil
}
```

#### 本地单测上报注意事项
本地单测时，需要在服务退出前确保Trace都上报完成：

**Golang**：
```go
// 方式1：等待2秒
time.Sleep(2 * time.Second)

// 方式2：调用Close方法
fornax_sdk.Close()
```

**Python**：
```python
# 方式1：等待2秒
time.sleep(2)

# 方式2：调用flush_trace方法
FornaxClient.flush_trace()  # 线上不要使用，会阻塞线程执行
```

## 最佳实践

### 1. 初始化最佳实践
- **单例模式**：在整个应用中只初始化一个Fornax客户端实例
- **环境隔离**：根据运行环境（BOE/Online）配置对应的AK/SK
- **错误处理**：在初始化时添加适当的错误处理和日志记录

### 2. 调用最佳实践
- **版本控制**：在生产环境中指定具体的Prompt版本，避免使用最新版本
- **错误重试**：对大模型调用添加适当的重试机制
- **超时设置**：根据业务需求设置合理的超时时间

### 3. 观测最佳实践
- **Span命名规范**：使用有意义的Span名称，便于问题排查
- **Tag标准化**：遵循Fornax Trace上报规范设置Tag
- **异常处理**：在Span中记录异常信息，便于链路追踪

### 4. 性能优化
- **连接复用**：复用HTTP连接，减少连接建立开销
- **批量操作**：对于批量数据，考虑使用批量接口
- **缓存策略**：对于频繁访问的数据，添加适当的缓存

## 常见问题处理

### 1. 鉴权失败（600703002）
**问题表现**：`AuthenticateServiceAccount DoHTTPRequest return code err, code=600703002, msg: unauthorized`

**解决方案**：
1. 确认AK/SK复制粘贴正确
2. 检查控制面区域是否匹配（CN/I18N）
3. 设置环境变量`FORNAX_CUSTOM_REGION`指定区域

### 2. 本地调试Trace无法上报
**解决方案**：
1. 配置环境变量`RUNTIME_IDC_NAME=boe`（或`boei18n`）
2. 确保在服务退出前等待Trace上报完成
3. 检查是否有明显的错误日志

### 3. Prompt未发布错误
**问题表现**：`[PTaaSLLM] errCode: 600503316 errMsg:Prompt not published, please publish it first.`

**解决方案**：
1. 将Prompt发布到对应环境（BOE/Online）
2. 调用时指定Prompt版本号

## 调试与监控

### 1. 开启调试模式
设置环境变量`FORNAX_SDK_DEV=1`，SDK将输出详细的调试信息，包括模型调用的真实输入参数。

### 2. 查看Trace
在Fornax平台的观测模块中，可以查看：
- **链路列表**：所有Trace的执行记录
- **Trace详情**：单个Trace的完整执行链路
- **会话数据**：基于ThreadID的会话追踪

### 3. 性能监控
通过Fornax平台的观测能力，可以监控：
- **调用耗时**：各Span的执行时间
- **Token消耗**：模型调用的Token使用情况
- **错误率**：各接口的调用成功率

## 版本兼容性

### SDK版本要求
- **Golang**：建议使用v1.2.10及以上版本
- **Python**：建议使用v1.0.7及以上版本
- **Node.js**：建议使用@next-ai/fornax-sdk@2.3.3及以上版本

### 环境兼容性
- **办公网访问**：升级到支持`I18N-DEV`区域的SDK版本
- **机房支持**：升级到SDK 2.0及以上版本，不再受机房限制

## 安全注意事项

### 1. 密钥管理
- **AK/SK保护**：不要将AK/SK硬编码在代码中，使用环境变量或配置中心
- **访问控制**：根据最小权限原则配置空间访问权限

### 2. 数据安全
- **敏感信息**：避免在Prompt中硬编码敏感信息
- **访问日志**：定期审计Fornax平台的访问日志

### 3. 合规要求
- **模型使用**：确保使用的大模型符合公司合规要求
- **数据出境**：注意国际业务的数据出境合规要求

## 故障排除

### 1. 快速诊断步骤
1. 检查AK/SK是否正确配置
2. 确认环境变量设置正确
3. 查看SDK日志输出
4. 在Fornax平台查看Trace记录

### 2. 常见错误代码
- **600703002**：鉴权失败，检查AK/SK和区域配置
- **600503316**：Prompt未发布，发布Prompt或指定版本
- **600503317**：模型调用失败，检查模型配置和网络连接

### 3. 获取帮助
- **用户群**：加入Fornax用户群获取技术支持
- **文档**：参考Fornax官方文档和示例代码
- **工单**：通过公司内部工单系统提交问题

---

**注意**：本文档基于Fornax SDK最新版本编写，具体实现细节可能随版本更新而变化，请以实际使用的SDK版本为准。建议定期查看Fornax官方文档获取最新信息。
