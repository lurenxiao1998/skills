# 完整示例

## 查询类

```bash
# 查询 PPE 环境详情（EUTTP）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "detail", "name": "ppe_my_env", "vregion": "EU-TTP"}'

# 查询 BOE 环境详情（国内）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "detail", "name": "boe_my_feature", "vregion": "China-BOE"}'

# 查询环境的服务列表
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "service_info", "name": "ppe_my_env", "vregion": "EU-TTP"}'

# 查询 PSM 在 PPE 中的集群信息
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "cluster_info", "psm": "tiktok.example.service", "scope": "ppe", "vregion": "EU-TTP"}'

# 检查用户对服务的操作权限
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "check_permission", "psm": "tiktok.example.service", "scope": "ppe", "env": "ppe_my_env", "vregion": "EU-TTP"}'

# 查询环境的 Fallback 配置
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "fallback_conf", "env_name": "ppe_my_env", "env_type": "ppe", "vregion": "EU-TTP"}'

# 查询环境实例元信息
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "instance_meta", "name": "ppe_my_env", "service_types": "tce", "vregion": "EU-TTP"}'

# 查询环境中指定服务的实例详情
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "instance_meta", "name": "ppe_my_env", "service_types": "tce", "services": "my.service.psm", "vregion": "Singapore-Central"}'

# 获取服务部署建议（默认按 vregion 推断 IDC）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "create_suggest", "psm": "tiktok.example.service", "env": "ppe_my_env", "env_type": "ppe", "vregion": "EU-TTP"}'

# 显式指定多个 IDC 查看资源建议
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "create_suggest", "psm": "tiktok.example.service", "vregion": "MYCOMPLIANCE", "idc": "my,my2"}'

# 获取 SCM 代码依赖
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "scm_dependencies", "psm": "tiktok.example.service", "env": "ppe_my_env", "env_type": "ppe", "vregion": "EU-TTP"}'
```

## 部署类

```bash
# 升级 TCE 服务版本（自动检测已有集群，使用 upgrade 模式）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_deploy", "name": "ppe_my_env", "psm": "tiktok.example.service", "version": "1.0.0.213", "vregion": "EU-TTP"}'

# 使用 Git 分支部署
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_deploy", "name": "ppe_my_env", "psm": "tiktok.example.service", "branch": "feature/my-branch", "vregion": "EU-TTP"}'

# 在已有环境中新建 TCE 服务（PSM 无集群时自动补全参数）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_deploy", "name": "ppe_my_env", "psm": "tiktok.new.service", "version": "1.0.0.1", "vregion": "EU-TTP"}'

# 删除环境中的服务
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_deploy", "name": "ppe_my_env", "psm": "tiktok.example.service", "deploy_action": "delete", "vregion": "EU-TTP"}'

# 部署 TCC 服务（region 必填，service_id 自动获取）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_deploy", "name": "ppe_my_env", "psm": "tiktok.example.tcc", "service_type": "tcc", "version": "1.0.0.1", "region": "EU-TTP,US-EastRed", "vregion": "EU-TTP"}'

# 部署 ByteFaaS 服务（PPE）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "faas_deploy", "name": "ppe_my_env", "psm": "tiktok.example.faas", "vregion": "EU-TTP"}'

# 指定 region/base_cluster/code revision 并开启 pre-check
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "faas_deploy", "name": "ppe_my_env", "psm": "tiktok.example.faas", "region": "eu-ttp", "base_cluster": "default", "code_revision_id": "123456", "pre_check": true, "vregion": "EU-TTP"}'

# 集群已就绪后仅发版（对齐 faas_ppe_publish.har）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "faas_deploy", "deploy_action": "upgrade", "name": "ppe_my_env", "psm": "tiktok.example.faas", "cluster": "faas-cn-north", "vregion": "China-North"}'

# 创建全新 PPE 环境并部署 ByteFaaS 服务
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "faas_create", "name": "ppe_new_env", "psm": "tiktok.example.faas", "vregion": "EU-TTP"}'

# 创建全新 PPE 环境并部署 ByteFaaS 服务（指定 region 和 base_cluster）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "faas_create", "name": "ppe_new_env", "psm": "tiktok.example.faas", "region": "eu-ttp", "base_cluster": "faas-eu-ttp", "vregion": "EU-TTP"}'

# 创建全新环境并部署服务
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_create", "name": "ppe_new_env", "psm": "tiktok.example.service", "version": "1.0.0.1", "vregion": "EU-TTP"}'

# 删除整个环境（包含其中所有服务）
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "delete_env", "name": "ppe_my_env", "vregion": "EU-TTP"}'

# 查询部署状态
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_status", "deployment_id": "1234567890", "env": "ppe_my_env", "vregion": "EU-TTP"}'

# 重试失败的部署
gdpa-cli run env --session-id "$SESSION_ID" --input '{"action": "dsl_retry", "deployment_id": "1234567890", "env": "ppe_my_env", "vregion": "EU-TTP"}'
```

## 典型部署流程

```
1. 查询环境服务：service_info → 了解当前环境中有哪些服务
2. 部署/升级服务：dsl_deploy → 获取 deployment_id
   - 升级版本：只需 name + psm + version
   - 新建服务：只需 name + psm + version（自动补全集群参数）
   - 删除服务：name + psm + deploy_action=delete
3. 查询状态：dsl_status → 轮询直到 status 为 success 或 failure（至少带 deployment_id + vregion；可直接复用上一步返回的 env）
4.（失败时）重试：dsl_retry
```
