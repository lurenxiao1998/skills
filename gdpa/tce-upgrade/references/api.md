# TCE Upgrade OpenAPI Reference (for tce-upgrade)

本文件为 `tce-upgrade` 场景的补充参考，主要用于：
- 对照抓包确认 URL/Query/Header/Body 是否一致
- 调试 `CreateUpgradeTicket` payload

如果只是执行升级流程，优先看 `../SKILL.md`。

## Base URL

- BOE: `https://cloud-boe.bytedance.net/api/v1/tce/open-apis`
- CN: `https://cloud.bytedance.net/api/v1/tce/open-apis`
- I18N-TT: `https://bc-sg-gw.tiktok-row.net/api/v1/tce/open-apis`

## Headers

所有请求建议包含：
- `x-bcgw-tenant-id: bytedance`
- `accept-language: zh`
- `x-jwt-token: <jwt>`

`CreateUpgradeTicket` 还需要：
- `content-type: application/json`

> 说明：`byte-cli` 会尝试通过 cookies 自动注入 `x-jwt-token`；如果没有有效 cookies/JWT，需要先登录对应控制面：
> - BOE: `byte-cli login --control-plane boe`
> - CN: `byte-cli login --control-plane cn`
> - I18N-TT: `byte-cli login --control-plane i18n-tt`

## Endpoints（升级相关）

### 1) GetService

- Method: `GET`
- Path: `/v1/services/{service_id}/`

对应命令：

```bash
byte-cli --config "$CONFIG" TCE BOE GetService --service-id 200882194
```

### 2) ListClusters (upgrade page default params)

- Method: `GET`
- Path: `/v1/services/{service_id}/clusters/`
- Query (upgrade 页面默认)：
  - `include_upstream=true`
  - `no_dp_metrics=true`
  - `no_pagination=true`

对应命令：

```bash
byte-cli --config "$CONFIG" TCE BOE ListClusters --service-id 200882194
```

### 3) GetRepoInfoList

- Method: `GET`
- Path: `/v1/services/{service_id}/repo_info_list/`

对应命令：

```bash
byte-cli --config "$CONFIG" TCE BOE GetRepoInfoList --service-id 200882194
```

### 4) CreateUpgradeTicket

- Method: `POST`
- Path: `/v1/deployment/cluster/upgrade/`

抓包示例（见 `plugins/tce/tce_upgrade_requests.md`）的 body 关键结构：

```json
{
  "cluster_info": {
    "runtime": {
      "repo_info": [
        {
          "name": "code_forge/pipeline/api",
          "version": "1.0.0.676",
          "description": "...",
          "scm_repo_id": "452040"
        }
      ]
    }
  },
  "cluster_list": [
    {"id": 201473163, "rollout_strategy": "eager"}
  ],
  "pipeline_template": 1,
  "service": 200882194,
  "step_built_in": false
}
```

byte-cli 的参数映射：
- `--service` → `service`
- `--pipeline-template` → `pipeline_template`
- `--cluster-list` → `cluster_list`（JSON array 字符串）
- `--cluster-info` → `cluster_info`（JSON object 字符串）
- `--step-built-in/--no-step-built-in` → `step_built_in`（boolean flag）

命令示例：

```bash
byte-cli --config "$CONFIG" TCE BOE CreateUpgradeTicket \
  --service 200882194 \
  --pipeline-template 1 \
  --cluster-list '[{"id":201473163,"rollout_strategy":"eager"}]' \
  --cluster-info '{"runtime":{"repo_info":[{"name":"code_forge/pipeline/api","version":"1.0.0.676","description":"...","scm_repo_id":"452040"}]}}'
```

### 5) GetDeploymentTicket

- Method: `GET`
- Path: `/v2/deployment/{ticket_id}/`
- Query：
  - `steps=`（可为空字符串）
  - `use_pods_list=true`

对应命令：

```bash
byte-cli --config "$CONFIG" TCE BOE GetDeploymentTicket --ticket-id 222941109
```

## 抓包对照

如果你发现线上页面新增字段（例如 pipeline template / 蓝绿 / smooth 等模式），优先以抓包文件为准：
- `plugins/tce/tce_upgrade_requests.md`
