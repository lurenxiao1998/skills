# Fornax OpenAPI 接口说明

本文档详细说明 Fornax 平台的 OpenAPI 认证方式和接口使用指南，为服务端应用提供与 Fornax 平台集成的标准化接口。

## 认证方式

Fornax OpenAPI 使用基于空间 AKSK 签发的 JWT-Token 进行认证，整体流程如下：

1. **获取 AKSK**：在有管理员权限的 Fornax 空间下获取 Access Key 和 Secret Key
2. **签发 JWT-Token**：使用 AKSK + Payload 签发 Fornax-Auth Token，调用 authenticate 接口获取 JWT-Token
3. **调用接口**：将获取到的 JWT-Token 放入 `Authorization: Bearer xxx` Header 中调用 Fornax 平台的 OpenAPI 接口

### 域名说明

不同环境的域名选择与控制面保持一致，不区分 BOE 环境：

- **CN 环境**：`https://fornax.bytedance.net`
- **I18N-ROWTT（SG）生产网**：`https://fornax.byteintl.net`
- **I18N-ROWTT（SG）办公网**：`https://fornax-i18n.byteintl.net`
- **I18N（VA）环境**：`https://fornax-va.byteintl.net`
- **I18N - nontt BD 环境**：`https://fornax-i18nbd.byteintl.net`

### SDK 签发方式

对于支持 SDK 的语言，建议直接使用 SDK 内置的认证机制：

**Golang SDK**（要求版本大于 v1.1.33）：
```go
import (
    "code.byted.org/flowdevops/fornax_sdk"
    "code.byted.org/flowdevops/fornax_sdk/domain"
)

func TestGetJWTToken(t *testing.T) {
    c, err := fornax_sdk.NewClient(&domain.Config{
        Identity: &domain.Identity{
            AK: "xxx",
            SK: "xxx",
        },
    })
    if err != nil {
        t.Fatal(err)
    }
    res, err := c.GetJWTToken(context.Background())
    if err != nil {
        t.Fatal(err)
    }
    t.Log(res.JWTToken)
}
```

**Python SDK**（要求版本 >= 1.0.5）：
```python
from bytedance.fornax.infra import initialize, FornaxClient

ak = "-" # 填写你的空间AK
sk = "-" # 填写你的空间SK

# 必须初始化
initialize(ak, sk)

# 获取jwt_token
print(FornaxClient.get_jwt_token())
```

**Node SDK**（仅支持 Node 环境，不支持 Web 环境）：
```javascript
import { fornaxHttp } from '@next-ai/fornax-sdk/services';

const http = fornaxHttp({
  ak: 'fornax_ak',
  sk: 'fornax_sk',
  region: 'CN',
});

const resp = http.post('/open-apis/prompt/v1/prompt/list', {
  /** data */
});

// 如果一定要获取 token
const accessToken = await http.getAccessToken();
```

### 签名接口说明

对于不支持 SDK 的语言，需要手动实现签名逻辑：

**请求参数**：
- **Header**：`Fornax-Auth: xxxx`（参考下一步【Fornax-Auth 的生成代码】）
- **Body**：需要将本 Body 内容作为 payload 生成签名到 Fornax-Auth，请保证请求和签名使用同一个 Body 字符串，空格和换行都会导致验签失败

**Payload 示例**：
```json
{
    "psm": "p.s.m",           // 必填，PSM词条
    "isBOE": true,            // 必填，是否是BOE环境
    "env": "prod",            // 选填，影响PromptKey获取发布的泳道
    "cluster": "default",     // 选填，PSM部署的集群
    "isTCE": true,            // 选填，是否在TCE部署
    "ztiToken": ""            // 选填，开启DLP的L4 Prompt需传递
}
```

**签名生成代码（Python 示例）**：
```python
import hmac
import hashlib
import time
import json

def _sha256_hmac(key, data):
    return hmac.new(key, data, hashlib.sha256).hexdigest()

def _gen_signature(ak, sk, payload):
    ts = int(time.time())
    sign_key_info = f"auth-v1/{ak}/{ts}/3600"
    sign_key = _sha256_hmac(sk.encode(), sign_key_info.encode())
    sign_result = _sha256_hmac(sign_key.encode(), payload)
    return f"{sign_key_info}/{sign_result}"

# 使用示例
body = {
    "psm": "p.s.m",
    "isBOE": True,
    "env": "prod",
    "cluster": "default",
    "isTCE": True
}
body_string = json.dumps(body, separators=(",", ":")).encode()
signature = _gen_signature("your_ak", "your_sk", body_string)
```

## 支持的 OpenAPI

### Prompt Hub 接口

**批量获取 Prompt 详情**：
- **接口**：`/open-apis/prompt/v1/prompt/list`
- **方法**：POST
- **说明**：最大单次建议 50 个以内，超过需分批拉取

### PTaaS 接口

**同步执行：execute**：
- **接口**：`/api/devops/prompt_platform/v1/prompt/execute`
- **方法**：POST
- **说明**：使用已发布版本进行执行，在调用接口前，请务必在 Fornax 平台完成发布操作

**请求示例**：
```json
{
    "prompt_key": "dsf.test.7",
    "message": {
        "message_type": 2,
        "content": "给我推荐下泰国旅游攻略"
    },
    "account_mode": 1
}
```

**流式执行：streaming_execute**：
- **接口**：`/api/devops/prompt_platform/v1/prompt/streaming_execute`
- **方法**：POST
- **说明**：支持流式返回结果，适用于长文本生成场景

### 数据集相关接口

Fornax 数据集提供了丰富的 OpenAPI 接口，包括：

**数据集管理**：
- **创建数据集**：`/open-api/ml_flow/v2/datasets`（POST）
- **搜索数据集**：`/open-api/ml_flow/v2/datasets/search`（POST）
- **获取数据集版本列表**：`/open-api/ml_flow/v2/datasets/:datasetID/versions`（GET）

**数据行操作**：
- **批量新增数据行**：`/open-api/ml_flow/v2/datasets/:datasetID/items/batch`（POST）
- **更新单条数据内容**：`/open-api/ml_flow/v2/datasets/:datasetID/items/:itemID`（PATCH）
- **批量获取数据行**：`/open-api/ml_flow/v2/datasets/:datasetID/items/batch_get`（POST）

**标注任务相关**：
- **获取数据集标注任务列表**：`/open-api/ml_flow/v2/datasets/:datasetID/annotation_jobs`（GET）
- **运行标注任务**：`/open-api/ml_flow/v2/datasets/:datasetID/annotation_jobs/:jobID/run`（POST）
- **获取标注任务实例状态**：`/open-api/ml_flow/v2/datasets/:datasetID/annotation_jobs/:jobID/instances`（GET）

**训练集相关**：
- **创建训练集**：`/open-api/ml_flow/v2/training_datasets`（POST）
- **支持的应用场景**：`text_generation_sft`、`text_generation_dpo_or_simpo`、`text_generation_kto`、`text_generation_continue_pretrain`、`text_generation_rft`

## 常见错误码

- **601100201**：用户传入的参数非法，如 dataset_id 和 space_id 对应不上等
- **601100202**：用户传入的参数格式不符合要求
- **601103006**：访问频率超过 quota
- **601103010**：空间未在灰度中，需要联系管理员

## 注意事项

1. **签名一致性**：生成 Fornax-Auth 签名使用的 payload 必须与请求 body 的内容字符完全一致，包括空格和换行
2. **Token 有效期**：JWT Token 有效期为 3 小时，需要定期刷新
3. **空间隔离**：AKSK 签发的 JWT Token 只可以访问该空间的资源，不可以跨空间访问
4. **本地调试**：本地环境需要设置 `isBOE: true` 以确保能正确获取 PromptKey 发布的环境
5. **Prompt 调用限制**：Prompt 调用不支持配置 durationDay 长效 Token，请勿传递该参数

## 最佳实践

1. **使用 SDK**：对于支持的语言，优先使用官方 SDK 进行认证和接口调用
2. **缓存 Token**：JWT Token 有缓存和刷新机制，可以在每次请求时多次调用 GetJWTToken，无需重复创建 Client
3. **错误处理**：实现完善的错误处理机制，特别是对于签名失败和 Token 过期的情况
4. **环境配置**：根据部署环境正确配置域名和认证参数
5. **批量操作**：对于数据行操作，建议使用批量接口以提高效率

