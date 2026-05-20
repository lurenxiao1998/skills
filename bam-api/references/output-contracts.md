# Output Contracts — bam-api

Per-action output templates that specify which fields the agent must preserve in its final answer. These contracts exist because prior iterations showed agents dropping version context, `endpoint_id`, `rpc_method`, `cluster`, and precise timestamps even after BAM returned the correct data.

## get_api_service_list

Required fields in the answer:

| Field | Notes |
| --- | --- |
| `version` | BAM version string (e.g. `0.0.67`) — do not omit |
| `region` | `cn` or `i18n` |
| Per-row `endpoint_id` | Unique endpoint identifier |
| Per-row `method` | RPC method name |
| Per-row `path` | HTTP path |
| Per-row `name` | Endpoint display name |

Example output structure:
```
PSM: tiktok.user.service
Version: 0.0.67
Region: cn

Endpoints:
1. endpoint_id=12345, method=GetUserInfo, path=/api/v1/user/info, name=GetUserInfo
2. endpoint_id=12346, method=UpdateUser, path=/api/v1/user/update, name=UpdateUser
```

## get_api_definition_info* (all definition variants)

Required fields in the answer:

| Field | Notes |
| --- | --- |
| `endpoint_id` | Unique endpoint identifier — do not omit |
| `version` | BAM version string |
| `region` | `cn` or `i18n` |
| `serializer` | Serialization format (e.g. `protobuf`, `thrift`) |
| `rpc_method` | RPC method name — do not omit |
| `idl_path` | IDL file path |
| Request schema | Outline of request struct with field names |
| Response schema | Outline of response struct with field names |

Example output structure:
```
Endpoint: GetUserInfo
endpoint_id: 12345
Version: 0.0.67
Region: cn
Serializer: protobuf
RPC Method: tiktok.user.service.GetUserInfo
IDL Path: api/user/user.proto

Request: GetUserInfoReq
  - user_id (int64)
  - fields (repeated string)

Response: GetUserInfoResp
  - user_info (UserInfo)
  - status_code (int32)
```

## get_api_service_versions

Required fields in the answer:

| Field | Notes |
| --- | --- |
| `version` | BAM version string |
| `cluster` | Cluster name (e.g. `default`, `staging`) — do not omit |
| `branch` | Branch name |
| `ctime` | Precise creation timestamp — do not round or omit |
| `note` | Version note text |

Example output structure:
```
PSM: tiktok.user.service
Versions:
1. version=0.0.67, cluster=default, branch=master, ctime=2026-04-12T08:30:00Z, note="add GetUserInfo v2"
2. version=0.0.66, cluster=default, branch=master, ctime=2026-04-10T14:00:00Z, note="fix UpdateUser field"
```

## create_service_version (pre-confirmation display)

Before executing `create_service_version`, display a confirmation summary with these fields:

| Field | Notes |
| --- | --- |
| `psm` | Target PSM |
| `branch` | Target branch |
| `region` | `cn` or `i18n` |
| `cluster` | Target cluster — do not omit |
| Current latest version | From `get_api_service_versions` |
| Proposed next version | Auto-incremented or user-specified |
| Safety note | Warn that this is a write operation |

Example confirmation display:
```
⚠️ 写操作确认
PSM: tiktok.user.service
Branch: master
Region: cn
Cluster: default
Current latest version: 0.0.67
Proposed next version: 0.0.68

确认创建版本 0.0.67 → 0.0.68？
```
