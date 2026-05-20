---
name: des-mq
description: Query DES-MQ channels and sync latency — search channels, get channel details with source/target MQ pipeline info, and check sync delay status for abnormal channels. Use when the user wants to look up DES-MQ channels, inspect cross-region data sync configurations, check MQ sync latency/delay, diagnose abnormal sync links, or mentions DES-MQ, data exchange channels, cross-vgeo sync, Texas data pipeline, or sync delay/lag. Also trigger when investigating data sync issues between regions.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# DES-MQ Agent

Query DES-MQ (Data Exchange System - Message Queue) channels and sync latency for cross-compliance-region data sync.

> **When to Use**: Search DES-MQ channels, inspect channel detail with MQ pipeline info, check sync latency/delay, or diagnose abnormal sync links.

## Quick Start

```bash
# Search channels by source db name
gdpa-cli run des-mq --input '{"action": "search_channels", "source": "ies_item"}'

# Get channel detail with source_mq, target_mq, transfer_cluster
gdpa-cli run des-mq --input '{"action": "channel_detail", "channel_id": "7012214765456179503"}'

# Check global sync status (all abnormal channels sorted by update time)
gdpa-cli run des-mq --input '{"action": "sync_status"}'

# Check sync status for a specific channel
gdpa-cli run des-mq --input '{"action": "sync_status", "channel_id": "7012214765456179503"}'

# Check sync status filtered by source db name
gdpa-cli run des-mq --input '{"action": "sync_status", "source": "ies_item"}'
```

## Input Parameters

### Common (all actions)

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `action` | string | Yes | - | `search_channels`, `channel_detail`, `channel_partitions`, `sync_status`, `config` |
| `vregion` | string | No | `US-East` | VRegion (currently: `US-East`) |

### search_channels — Search Channels

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `channel_id` | string | - | Filter by channel ID |
| `type` | string | - | Filter by type (`rocketmq`, `kafka`, `mysql`, `redis`, `abase`) |
| `source` | string | - | Filter by source db name (e.g. `ies_item`) |
| `target` | string | - | Filter by target db name |
| `owner` | string | - | Filter by owner |
| `priority` | string | - | Filter by priority (`P0`, `P1`, etc.) |
| `source_region` | string | - | Filter by source region |
| `target_region` | string | - | Filter by target region |
| `page` | int | `0` | Page number (0-based) |
| `page_size` | int | `10` | Page size |

### channel_detail — Get Channel Detail (with MQ info)

Returns full channel info including `source_mq`, `target_mq`, `transfer_cluster`, `handler_cluster`, monitor links, and tier.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `channel_id` | string | Yes | Channel ID |

### sync_status — Check Sync Latency / Abnormal Channels

Returns abnormal channels with `lag_seconds`, `lag_display`, `root_cause`, and `phases`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `channel_id` | string | - | Filter by specific channel ID |
| `source` | string | - | Filter results by source or target db name (client-side substring match) |
| `page` | int | `1` | Page number (1-based) |
| `page_size` | int | `20` | Page size |

### channel_partitions / config

Same as before — see previous version.

## Output Examples

### channel_detail — now includes MQ pipeline info

```json
{
  "action": "channel_detail",
  "data": {
    "found": true,
    "channel_id": "7012214765456179503",
    "type": "mysql",
    "source": "toutiao.mysql.ies_item",
    "target": "toutiao.mysql.ies_item",
    "src_vregion": "US-TTP",
    "dst_vregion": "MALIVA",
    "status": "STOPPED",
    "priority": "P0",
    "source_mq": "bmq_des_mq_dflow_default_oci:useast5_maliva_dflow_mysql_ies_item",
    "target_mq": "bmq_des_mq_dflow_default_va:useast5_maliva_dflow_mysql_ies_item",
    "transfer_cluster": "ttp_va_kafka_core_v2",
    "handler_cluster": "kafka_ttp_va_offline",
    "source_cluster": "bmq_des_mq_dflow_default_oci",
    "target_cluster": "bmq_des_mq_dflow_default_va",
    "qps": "10000",
    "tier": "BMQ_P0_Medial"
  }
}
```

### sync_status — latency and root cause

```json
{
  "action": "sync_status",
  "data": {
    "total": 47,
    "abnormal_channels": [
      {
        "channel_id": 7621008271331082552,
        "direction": "Singapore-Central->US-TTP",
        "source": "bytedance.abase2.item_stats_crdt",
        "target": "bytedance.abase2.item_stats_crdt",
        "status": "Abnormal",
        "lag_seconds": 36094,
        "lag_display": "10h1m",
        "lag_bucket": ">>6 hours",
        "root_cause": "DFlowNoSQLFullLinkLatencyInternalErrorFault",
        "phases": ["MQ->DB"],
        "priority": "P1",
        "transfer_cluster": "sg_ttp_kafka_core_v2"
      }
    ]
  }
}
```

## VRegion Mapping

| VRegion | Aliases | Domain |
|---------|---------|--------|
| `US-East` (default) | `us`, `va` | des-mq-va.byted.org |

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `action parameter is required` | Missing action | Add `action` |
| `channel_id is required` | Missing for detail/partitions | Add `channel_id` |
| `authentication failed` | JWT issue | Run `gdpa-cli login i18n` |

## Notes

- **Sync Status**: `sync_status` returns only abnormal channels (with lag > threshold). Normal channels won't appear.
- **MQ Info**: `channel_detail` now returns `source_mq` and `target_mq` in `cluster:topic` format, along with `transfer_cluster`, `handler_cluster`, etc.
- **Latency Fields**: `lag_seconds` is the raw delay in seconds; `lag_display` is human-readable (e.g. "10h1m", "50min"); `root_cause` explains the delay reason.
- **Read-Only**: This agent only queries data, no write operations.
