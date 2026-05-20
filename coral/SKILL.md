---
name: coral
description: Query Coral table assets and field semantics for Hive and ClickHouse tables.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# Coral

Query Coral table metadata and field semantics for Hive and ClickHouse table assets.

## Usage

```bash
gdpa-cli run coral --input '{"action":"get_table_semantics","qualified_name":"HiveTable:///db/table@0"}'
gdpa-cli run coral --input '{"action":"get_fields","type_name":"HiveTable","db_name":"db","table_name":"table","cid":0}'
gdpa-cli run coral --input '{"action":"resolve_table","type_name":"ClickhouseTable","db_name":"db","table_name":"table","cluster":"default"}'
gdpa-cli run coral --input '{"action":"get_fields","qualified_name":"HiveTable:///db/table@1","vregion":"us"}'
gdpa-cli run coral --input '{"action":"get_fields","qualified_name":"ClickhouseTable:///db/table@0","source_qualified_name":"HiveTable:///source_db/source_table@0"}'
```

## Supported Actions

| Action | Description |
|--------|-------------|
| `get_table_semantics` | Return table metadata, repository metadata, fields, and semantic warnings. |
| `get_fields` | Return field metadata and warnings only. |
| `resolve_table` | Resolve table input into a Coral `qualified_name` without calling Coral. |

## Table Input

Prefer `qualified_name`:

- `HiveTable:///db/table@cid`
- `ClickhouseTable:///db/table@cid`

Split input is also supported:

- `type_name`: `HiveTable` or `ClickhouseTable`
- `db_name`
- `table_name`
- `cid`

If `cid` is omitted, the agent can infer it from `cluster`, `ddl_cluster`, `control_plane`, or `vgeo`. If inference is ambiguous or unsupported, pass `cid` or a full `qualified_name`.

For derived tables whose Coral column entities do not carry descriptions, pass `source_qualified_name` (or `semantic_source_qualified_name`) to enrich missing field descriptions from the source table's Coral comments. Existing target-table comments are kept; only empty comments are filled from the source table.

## Coral Request

The agent calls `GET /v2/data-stores` through the selected Coral gateway with header `domain: coral_openapi;v1`. It sends `ignoreRelationships=false`, `withSchema=true`, `fetchReferredEntities=true`, and `withPrivilegeStatus=true` so the response includes column entities when Coral returns schema details.

## CID Mapping

| Control Plane | CID | `ddl_cluster` | `cluster` |
| --- | --- | --- | --- |
| China-BOE | 7 | `boe` | `boe` |
| US-BOE | 8 | `boei18n` | `boei18n` |
| China-North | 0 | `default` | `default` |
| China-East | 43 | `ce` | `ce` |
| China-North6 | 50 | `cn6` | `cn6` |
| China-Pay | 35 | `zg` | `zg` |
| Global | 100 | `global` | `global` |
| Singapore-Central | 6 | `alisg` | `alisg` |
| US-East | 1 | `va` | `i18n` |
| MY-Compliance | 44 | `mypipo` | `mypipo` |
| ID-Compliance | 37 | `idpipo` | `idpipo` |
| US-West | 36 | `uswest` | `uswest` |
| Europe-Central | 42 | `fr1a` | `fr1a` |
| US-SouthWest | 40 | `phx` | `phx` |
| Asia-CIS | 41 | `pinnacle` | `pinnacle` |
| JP-LARK | 25 | `jp_lark` | `jplark` |
| SG-LARK | 10 | `sg_lark` | `larksgaws` |
| US-Compliance | 38 | `uspipo` | `uspipo` |
| US-EastBD | 46 | `usbd` | `usbd` |
| US-TTP-Lark | 48 | `uslark` | `uslark` |
| AsiaSinf-SouthEast | 11 | `mya` | `mya` |
| US-EastRed | 5 | `gcp` | `gcp` |
| EU-TTP | 47 | `iepipo` | `ie` |
| EU-TTP2 | 39 | `norway` | `norway` |
| EU-Compliance2 | 31 | `eupipo_adhoc` | `eudupipo` |
| US-TTP | 9 | `oci` | `texas` |

## Gateway Routing

Coral uses a client-local gateway mapping selected by `vregion` or inferred from CID/cluster. This mapping is owned by the Coral client and does not reuse or modify other clients' region mappings. CID mapping and HTTP gateway routing are separate.

| VRegion | Gateway |
| --- | --- |
| China-North | `https://bc-cn-gw.bytedance.net` |
| China-East | `https://paas-gw-cn-east.byted.org` |
| pddt | `https://paas-gw-pddt.byted.org` |
| tjdt | `https://paas-gw-tjdt.byted.org` |
| China-Pay | `https://paas-gw-cn-pay.byted.org` |
| US-East / maliva | `https://bc-maliva-gw.tiktok-row.net` |
| sgdt | `https://bc-sgdt-gw.tiktok-row.net` |
| useastdt | `https://bc-useastdt-gw.tiktok-row.net` |
| Singapore-Central / sg | `https://bc-sg-gw.tiktok-row.net` |
| ID-Compliance | `https://bc-idcompliance-gw.tiktok-row.net` |
| US-West | `https://bc-uswest-gw.tiktok-row.net` |
| Europe-Central / awsfr | `https://bc-awsfr-gw.tiktok-row.net` |
| US-SouthWest | `https://bc-ussouthwest-gw.tiktok-row.net` |
| US-Compliance | `https://bc-uscompliance-gw.byteintl.net` |
| SINFI18N | `https://paas-gw-i18n.sinf.net` |
| US-EastRed / gcp | `https://bc-gcp-gw.tiktok-eu.net` |
| iedt | `https://bc-iedt-gw.tiktok-eu.net` |
| useast2b | `https://bc-useast2b-gw.tiktok-eu.net` |
| EU-TTP2 / no1a | `https://bc-no1a-gw.tiktok-eu.net` |
| EU-Compliance2 | `https://paas-gw-ie2.tiktoke.org` |
| EU-TTP / ie | `https://bc-ie-gw.tiktok-eu.net` |
| US-TTP / US-TTP2 | `https://bc-usttp-gw.tiktok-us.net` |

For other CID/VRegion values, pass `base_uri` explicitly once the Coral gateway is known.

## Output

The response includes:

- `table`: table metadata including CID, cluster, engine, dataset type, owner, description, TTL, and latest partition when Coral returns them.
- `repository`: database/repository metadata when Coral returns it.
- `fields[]`: field name, type, `comment`, `comment_en`, description source, qualified name, GUID, type name, and field kind.
- `semantic_warnings[]`: missing table, missing fields, fields without comments, or missing semantic arrays from the official response.

Field semantics are based on official Coral `comment` / `commentEN` values, with Coral AI description fields (`aiComment`, `aiSimpleComment`, `nuwaAiComment`) used when standard comments are empty. Missing comments are reported as warnings and are not inferred unless an explicit source table is supplied.
