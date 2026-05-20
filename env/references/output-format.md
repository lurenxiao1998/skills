# 输出格式

所有输出遵循统一结构：

```json
{
  "success": true,
  "action": "<action>",
  "data": { ... }
}
```

## dsl_deploy / dsl_create 输出

```json
{
  "success": true,
  "action": "dsl_deploy",
  "data": {
    "env": "ppe_my_env",
    "psm": "example.service.psm",
    "deployment_id": "1234567890",
    "status": "Pending",
    "message": ""
  }
}
```

## dsl_status 输出

```json
{
  "success": true,
  "action": "dsl_status",
  "data": {
    "deployment_id": "1234567890",
    "env": "ppe_my_env",
    "env_type": "ppe",
    "status": "success",
    "create_user": "user1",
    "create_at": "2026-01-01T00:00:00Z",
    "tickets": [
      {
        "action": "create_service",
        "type": "tce",
        "resource": "example.service.psm",
        "scope": "ppe",
        "status": "success",
        "steps": [
          {"name": "SCM compile", "status": "Jumped"},
          {"name": "Create tce service", "status": "Succeed"},
          {"name": "Create tce cluster", "status": "Succeed"}
        ]
      }
    ]
  }
}
```

## dsl_deploy vs dsl_create vs faas_deploy vs faas_create

| | dsl_deploy | dsl_create | faas_deploy | faas_create |
|---|---|---|---|---|
| API | DSLUpdate (PUT) | DSLCreate (POST) | DSLUpdate (PUT) | DSLCreate (POST) |
| 用途 | 操作**已有环境**中的 TCE/TCC 服务 | 创建**全新环境** + TCE/TCC 服务 | 操作**已有环境**中的 ByteFaaS 服务 | 创建**全新环境** + ByteFaaS 服务 |
| 支持操作 | create/upgrade/delete 服务 | 创建环境 + 创建服务 | create/upgrade ByteFaaS | 创建环境 + 创建 ByteFaaS |
| 环境必须存在 | 是 | 否（会创建新环境） | 是 | 否（会创建新环境） |
