# Action 参数详情

## 查询类参数

| 参数 | 类型 | 描述 |
|------|------|------|
| scope | string | 环境范围：`boe` 或 `ppe` |
| env | string | 具体的环境名称（用于 cluster_info、check_permission、create_suggest、scm_dependencies；也可作为 dsl_status/dsl_retry 跟进命令里的上下文信息） |
| env_name | string | 环境名称（用于 fallback_conf） |
| type | string | 环境类型，可从 name 前缀自动推断 |
| env_type | string | 环境类型：`boe_feature`、`boe_base`、`ppe` |
| search | string | 搜索关键字（用于 instance_meta 过滤） |
| service_types | string | 服务类型过滤（用于 instance_meta），如 `tce` |
| services | string | 服务 PSM 过滤（用于 instance_meta），如 `my.service.psm` |
| detail_limit | int | 服务详情返回数量上限（用于 service_info），默认 100 |
| service_type | string | 服务类型（用于 create_suggest），默认 `tce` |

## create_suggest 参数

`create_suggest` 用于获取服务在某个环境下的部署建议（推荐 cpu/mem/count/zone/idc/cluster 等）。
默认 `env_type=ppe`（未传时自动补默认值，否则 BITS API 返回基本为空）。
默认 `SpecifyDcs` 来自 `vregion → DefaultVDC`，但只要用户显式传 `idc/zone/cluster`，就会原样透传给 BITS API，不再受 vregion 默认 VDC 限制。

| 参数 | 类型 | 描述 |
|------|------|------|
| psm | string | 必填，服务 PSM |
| service_type | string | 服务类型，默认 `tce`（可选 `tcc`） |
| env | string | 环境名（可选；用于查同名环境下的建议） |
| env_type | string | `ppe` / `boe_feature` / `boe_base`，未传默认 `ppe` |
| vregion | string | 目标 VRegion，例如 `Singapore-Central`、`MYCOMPLIANCE`；未显式给 idc 时用作默认 VDC |
| idc | string | 想看哪些 IDC 的建议，逗号分隔（如 `my,my2`），等价于 `idcs`/`vdc`/`vdcs` |
| zone | string | 想看哪些 zone 的建议，逗号分隔（如 `tiktok-row-default`） |
| cluster | string | 想看哪些虚拟集群的建议，逗号分隔 |

返回字段除了原有的 `quota.cpu_suggest / mem_suggest / count_suggest / idc_suggest` 外，
还包含 `quota.zones`：完整的 `zone → virtual_clusters → idc_list` 树（每个 IDC 标注 vregion / cpu / mem / resource_pool / resource_group_id），便于人工或后续 `dsl_deploy` 选择放置。

## 部署类参数（dsl_deploy）

`dsl_deploy` 操作已有环境中的服务，使用 `DSLUpdate` API。支持三种模式：

- **升级（upgrade）**：已有集群 + 提供 version/branch → 自动检测为 upgrade
- **新建服务（create）**：无集群 → 自动检测为 create，从 `create_suggest` 补全参数
- **删除服务（delete）**：设置 `deploy_action=delete`

| 参数 | 类型 | 描述 | 自动补全 |
|------|------|------|----------|
| version | string | SCM 版本号（如 `1.0.0.213`），与 `branch` 二选一 | — |
| branch | string | Git 分支名，与 `version` 二选一 | — |
| deploy_action | string | 部署动作：`create`、`upgrade`、`delete`。不传时自动推断 | — |
| service_type | string | 服务类型，默认 `tce`（可选：`tcc`） | — |
| scope | string | 集群查询范围：`boe` 或 `ppe` | ✅ 从 env_type / vregion / env name 推断 |
| env_type | string | 环境类型：`ppe`、`boe_feature`、`boe_base` | ✅ 从 env name / scope / vregion 推断 |
| clusters | array/string | 升级目标集群 ID 列表 | — |
| scm_name | string | SCM 仓库名称 | ✅ 从 `scm_dependencies` 主仓库获取 |
| region | string | 部署区域（TCC 服务必填，如 `EU-TTP,US-EastRed`） | — |
| service_id | string | TCC 服务 ID | ✅ 自动通过 `SearchTccService` 获取 |
| cluster_name | string | 集群名称，默认 `default`（仅新建时使用） | — |
| zone | string | TCE zone（仅新建时使用） | ✅ 从 `create_suggest` 获取 |
| idc | string | IDC 名称（仅新建时使用，支持逗号分隔多个 IDC） | ✅ 从 `create_suggest` 获取 |
| virtual_cluster | string | 虚拟集群名称（仅新建时使用） | ✅ 从 `create_suggest` 获取 |
| cpu | float | CPU 配额（仅新建时使用） | ✅ 从 `create_suggest` 获取 |
| mem | float | 内存配额（仅新建时使用） | ✅ 从 `create_suggest` 获取 |
| count | int | 实例数量（仅新建时使用；多 IDC 时会对每个 IDC 生效） | ✅ 从 `create_suggest` 获取 |
| sync | bool | 是否同步等待部署完成，默认 `false` | — |
| failed_strategy | string | 失败策略，默认 `WaitBrothers` | — |

> **自动补全说明**：
> - 所有自动补全的参数均可被用户显式传入的值覆盖
> - `scm_dependencies` → 自动获取主仓库 `name` 和 `remote_id`
> - `cluster_info` → 获取已有集群 ID 列表（用于判断 create/upgrade）
> - 显式 `clusters` → upgrade 时优先使用用户指定的集群 ID
> - `create_suggest` → 新建时自动获取 zone、cpu、mem、ports、sidecar 等参数
> - `SearchTccService` → TCC 服务自动获取 service_id
>
> **SCM 类型自动设置**：
> - 传 `version` → `ScmRepo.Type="scm"`（SCM 版本号部署）
> - 传 `branch` → `ScmRepo.Type="git"`（Git 分支部署）
>
> **TCC 注意事项**：
> - TCC 部署必须提供 `region` 参数（如 `EU-TTP`、`US-EastRed`、`CN`），否则会报错
> - `service_id` 可自动获取，也可手动指定

## 部署类参数（faas_deploy）

`faas_deploy` 用于在**已有 PPE 环境**中部署 ByteFaaS 服务。它和 `dsl_deploy` 一样属于"已有环境内的部署"，但面向 ByteFaaS 场景。

支持两种模式：

- **`create`**（默认）：为目标服务创建/选择 ByteFaaS 集群并发版
- **`upgrade`**：仅对已有 ByteFaaS 集群发版，**必须显式传 `cluster`**

执行前会做必要的一致性校验；如果代码版本与 SCM 依赖信息不匹配，或预检查发现阻断项，agent 会直接失败并把原因返回给用户。

| 参数 | 类型 | 描述 |
|------|------|------|
| name | string | 环境名称（必填） |
| psm | string | 服务 PSM（必填） |
| deploy_action | string | `create`（默认）：建集群并发版；`upgrade`：仅发版（须传 `cluster`） |
| env_type | string | 环境类型，默认 `ppe` |
| region | string | FaaS region 的 `name`（如 `cn-north`）；不传则按 `vregion`、`lane_zone` 推断 |
| lane_zone | string | 指定 lane_zone（如 `CN`），用于在没有显式 `region` 时挑选 region |
| cluster | string | base cluster 名；与 `base_cluster` 等价 |
| base_cluster | string | 同 `cluster`，二选一 |
| base_cluster_name | string | DSL `meta.clusters[].base_cluster_name`，默认与 cluster 相同 |
| code_version | string | 选用 `get_code_version` 中 `number` 或 `source` 匹配的一项；不传则取列表第一个 |
| code_revision_id | string | `faas_release[].code_revision_id` |
| use_latest_code_revision | bool | 默认 `true` |
| scm_source | string | 覆盖 `scm_version.source`（可选） |
| scm_source_type | string | 覆盖 `source_type`（可选） |
| scm_deploy_method | string | 覆盖 `deploy_method`（可选） |
| pre_check | bool | 是否 DSL 预检查，默认 `false` |
| expire_time | int | `run_option.expire_time`，默认 `10` |
| recycle_type | string | 默认 `short` |
| recycle_due_time | string | PPE `short` 回收截止时间（RFC3339）；不传时 agent 对 `ppe` 默认约为 14 天后 |
| debug | bool | `meta.debug`，默认 `false` |
| sync / failed_strategy | bool / string | 与 `dsl_deploy` 相同 |

> 注意：
> - `faas_deploy` 面向 **PPE ByteFaaS**
> - 如果只是给已有集群发版，优先使用 `deploy_action=upgrade`
> - `upgrade` 场景下必须提供 `cluster`
> - `pre_check=true` 时，若存在阻断项会直接中止，不会继续部署

## 部署类参数（faas_create）

`faas_create` 用于创建**全新 PPE 环境**并部署 ByteFaaS 服务，使用 `DSLCreate` API。仅当环境不存在时使用。与 `faas_deploy` 的区别在于：`faas_deploy` 操作已有环境（DSLUpdate），`faas_create` 创建新环境（DSLCreate）。

| 参数 | 类型 | 描述 |
|------|------|------|
| name | string | 新环境名称（必填） |
| psm | string | 服务 PSM（必填） |
| env_type | string | 环境类型，默认 `ppe` |
| region | string | FaaS region 的 `name`；不传则按 `vregion`、`lane_zone` 推断 |
| lane_zone | string | 指定 lane_zone |
| cluster | string | base cluster 名 |
| base_cluster | string | 同 `cluster`，二选一 |
| base_cluster_name | string | DSL `meta.clusters[].base_cluster_name`，默认与 cluster 相同 |
| code_version | string | 选用 `get_code_version` 匹配项 |
| code_revision_id | string | `faas_release[].code_revision_id` |
| use_latest_code_revision | bool | 默认 `true` |
| scm_source | string | 覆盖 `scm_version.source`（可选） |
| scm_source_type | string | 覆盖 `source_type`（可选） |
| scm_deploy_method | string | 覆盖 `deploy_method`（可选） |
| pre_check | bool | 是否 DSL 预检查，默认 `false` |
| expire_time | int | `run_option.expire_time`，默认 `10` |
| recycle_type | string | 默认 `short` |
| recycle_due_time | string | PPE 回收截止时间（RFC3339） |
| debug | bool | `meta.debug`，默认 `false` |
| sync / failed_strategy | bool / string | 与 `dsl_deploy` 相同 |

## 部署类参数（dsl_create）

`dsl_create` 用于创建**全新环境**并部署服务，使用 `DSLCreate` API。仅当环境不存在时使用。

| 参数 | 类型 | 描述 | 自动补全 |
|------|------|------|----------|
| name | string | 新环境名称（必填） | — |
| psm | string | 服务 PSM（必填） | — |
| version | string | SCM 版本号，与 `branch` 二选一 | — |
| branch | string | Git 分支名，与 `version` 二选一 | — |
| service_type | string | 服务类型，默认 `tce` | — |
| zone | string | TCE zone | ✅ 从 `create_suggest` 获取 |
| idc | string | IDC 名称（支持逗号分隔多个 IDC） | ✅ 从 `create_suggest` 获取 |
| virtual_cluster | string | 虚拟集群名称 | ✅ 从 `create_suggest` 获取 |
| cpu | float | CPU 配额 | ✅ 从 `create_suggest` 获取 |
| mem | float | 内存配额 | ✅ 从 `create_suggest` 获取 |
| count | int | 实例数量 | ✅ 从 `create_suggest` 获取 |
| cluster_name | string | 集群名称，默认 `default` | — |
| sync | bool | 是否同步等待，默认 `false` | — |
| failed_strategy | string | 失败策略，默认 `WaitBrothers` | — |
