# Fornax 观测能力集成指南

Fornax 观测模块基于 OpenTelemetry 标准，提供 AI Agent 执行全链路的追踪能力，帮助开发者监控和分析 AI 应用的执行情况。

## 核心概念

### Trace（链路）
Trace 指的是一次对话中从接收输入到产生输出结果的整个过程的链路执行情况。Trace 记录了请求根节点、模型调用、工具调用、知识库检索等关键节点的 Input、Output、状态及其耗时等信息。

### Span（节点）
Trace 由一个个节点串联而成，其中节点称之为 Span，代表链路执行过程中原子的一环。常见的 Span 类型包括：
- **Root Span**：根节点，通常是整个 Trace 的开始，包含丰富的 Trace 信息
- **LLM Call**：大模型调用节点，对整个链路有着举足轻重的作用

## SDK 集成方式

### 自动上报
Fornax SDK 中各 AI 能力组件 & 出口均已接入 Trace 上报，可实现无感上报。SDK 会基于 OpenTelemetry 采集标准化的 Trace 数据，并上报到 Fornax 平台-观测模块进行消费。

### 自定义上报
开发者可以在任何地方自由进行自定义上报，所有上报的 Span 将按调用链路自动串联。SDK 提供了灵活的 API 支持手动创建和关联 Span。

## 数据上报机制

### 异步上报
Trace 上报是**异步**的，SDK 侧会定时（1s）、定量（100 spans）触发异步请求上报 Trace。

### 上报限制
在不同的场景下上报存在一些限制：
- 如业务调用结束后 Node 进程关闭（命令行、执行文件），此时上报的异步尚未执行，对应的 Trace 无法上报到 Fornax
- 在服务类应用（如 GuluX）中，因为进程没有被杀死，所以异步上报得以正常执行

### 强制刷新
SDK 提供了 flush 方法，用于上报当前所有 Span：
```typescript
await fornaxTracer.forceFlush();
```
这在需要确保数据上报的场景下特别有用，比如在进程退出前调用。

## 观测平台功能

### Trace 列表查询
Fornax 观测平台提供 Trace 列表查询功能，支持以下筛选维度：
- **Span 维度**：支持根据 Root Span、All Span、LLM Call 等类型筛选
- **时间筛选**：根据 Span 的上报时间进行筛选，目前支持 7 天内数据的查询
- **Span 筛选**：支持根据 LogId 和 TraceId 进行快捷筛选，也支持根据 Span 的各个属性全方位筛选
- **过滤列**：支持个性化展示字段，包括 Bot 信息、Trace 基础信息、开发信息等

### Trace 详情查看
Trace 详情页面提供以下信息：
- **调用树**：展示 Trace 的完整执行链路
- **节点详情**：显示每个 Span 的详细信息
- **错误消息展示**：当执行出错时显示错误信息
- **RawData/UI 展示选择**：Model 等 Span 提供原始数据或 UI 界面的展示选择

### 性能指标
观测平台支持以下关键指标监控：
- **Tokens 消耗**：监控每次调用的 Token 使用情况
- **Latency**：记录各节点的执行耗时
- **QPS**：统计服务的请求处理能力

## 会话管理
观测平台支持会话功能，可以还原用户对话过程，并关联 Tracing 进行排障。

## 最佳实践

### 服务端应用
在服务端应用中，由于进程持续运行，异步上报机制可以正常工作。建议在关键业务逻辑处添加自定义 Span，以便更精细地监控执行情况。

### 命令行工具
对于命令行工具或一次性执行脚本，建议在程序退出前调用 `forceFlush()` 方法，确保所有 Trace 数据都能上报到平台。

### 环境配置
确保正确配置环境变量，特别是对于 Golang SDK v1.0+：
```bash
export RUNTIME_IDC_NAME=boe  # 指定运行环境
export TCE_PSM=<your-psm>    # 设置服务标识
```

### 错误处理
在自定义上报时，建议添加适当的错误处理逻辑，避免因 Trace 上报失败影响主业务流程。

## 故障排查

### Trace 未上报
如果发现 Trace 数据未上报到平台，可以检查：
1. SDK 初始化是否正确
2. 网络连接是否正常
3. 异步上报是否被进程提前终止
4. 环境变量配置是否正确

### 数据延迟
由于采用异步上报机制，Trace 数据可能会有 1-2 秒的延迟。如果对实时性要求较高，可以考虑在关键节点后调用 `forceFlush()`。

### Span 关联错误
如果发现 Span 关联不正确，检查 Span 的创建和结束时机，确保父子关系正确建立。

## 集成示例

### Node.js 示例
```javascript
const { fornaxTracer } = require('@next-ai/fornax-sdk');

// 自动上报示例
async function processRequest() {
  // SDK 会自动上报 LLM 调用等 Span
  const result = await llmCall(prompt);
  
  // 自定义 Span
  const span = fornaxTracer.startSpan('custom-operation');
  try {
    // 业务逻辑
    await someOperation();
    span.setStatus({ code: 0 });
  } catch (error) {
    span.setStatus({ code: 1, message: error.message });
    throw error;
  } finally {
    span.end();
  }
  
  // 确保数据上报
  await fornaxTracer.forceFlush();
  return result;
}
```

### Python 示例
```python
from bytedance.fornax.observability import tracer

def process_request():
    # 自动上报
    result = llm_call(prompt)
    
    # 自定义 Span
    with tracer.start_as_current_span("custom-operation") as span:
        try:
            some_operation()
            span.set_status(StatusCode.OK)
        except Exception as e:
            span.set_status(StatusCode.ERROR, str(e))
            raise
    
    # 强制刷新
    tracer.force_flush()
    return result
```

通过以上集成方式，开发者可以充分利用 Fornax 观测能力，实现对 AI 应用的全面监控和性能分析。
