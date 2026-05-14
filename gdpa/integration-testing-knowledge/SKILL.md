---
name: integration-testing-knowledge
description: Guide for integration testing including PPE environment setup and API test construction. Use when constructing HTTP/RPC requests for PPE, configuring BAM MCP tools, searching test cases, obtaining test accounts, or retrieving test data.
user-invocable: false
---

# Integration Testing Guide

This skill guides constructing and executing API integration tests using the duck framework and BAM MCP tools.

## Prerequisites

**Environment variables:**
- `API_TEST_ROOT`: Root directory of the api_test repository (e.g., `/path/to/api_test`)

## Request Construction Workflow

> Not all steps are mandatory; just choose them as needed.

There are four available to skills construct and execute test requests: 

### 1: Search for Test Cases

Use `grep` to search for relevant test cases in the test codebase.

**Environment variable:**
- `API_TEST_ROOT`: Root directory of api_test repository

**Search by PSM:**
```bash
grep -r "tikcast.game.anchor" ${API_TEST_ROOT}/tests/ --include="*.py"
```

**Search by API method:**
```bash
grep -r "QueryPermission" ${API_TEST_ROOT}/tests/ --include="*.py" -A 5
```

**Search by test data key:**
```bash
grep -r "read_test_data" ${API_TEST_ROOT}/tests/ --include="*.py" | grep "data_query"
```

**Key patterns to look for:**
- `@apipath(psm="...", apipath="...")` - API endpoint metadata
- `read_test_data("data_key")` - Associated test data keys
- `def test_*` - Test method names

### 2: Obtain Test Account (user_id)

Run the `get_occupied_user.py` script from this file's directory to get available test accounts:

```bash
# Basic usage (default test_env=sg)
python3 scripts/get_occupied_user.py

# Specify test environment
python3 scripts/get_occupied_user.py --test_env sg
```

**Arguments:**
- `--test_env`: Test environment (sg, va, boe, etc.), default: sg

**Environment variables (optional):**
- `USER_TOKEN`: Authentication token (default: public token)
- `COLLECTION_ID`: Collection ID for test account

**Output format:**
```json
{
  "accounts": [{
    "uid": "123456",
    "sec_uid": "...",
    "device_id": "...",
    "session_key": "...",
    "token": "..."
  }],
  "count": 1
}
```

### 3: Retrieve Test Data

Run the `read_test_data.py` script from this file's directory with the namespace and data key from Step 1:

```bash
# Get test data by namespace and key
python3 scripts/read_test_data.py my_namespace data_test_query_permission

# Specify test environment
python3 scripts/read_test_data.py my_namespace data_test_query_permission --test_env sg
```

**Arguments:**
- `namespace`: Namespace name for test data (required)
- `data_key`: The test data key/name to retrieve (required)
- `--test_env`: Test environment (sg, va, gcp, my, ttp, etc.), default: sg.

**Environment variables (optional):**
- `USER_TOKEN`: Authentication token

**Output format:**
```json
{
  "data_key": "data_test_query_permission",
  "data": [
    {"userId": "123", "permissionType": "anchor", "expected": true}
  ]
}
```

### 4: Execute Request via bam_test_api

Use the `bam_api_test:rpc_request/http_request` MCP tool to send HTTP/RPC requests.
Refer the PPE Guidance section below for request routing headers and environment configuration.

---

# Product Preview Environment (PPE) Guidance

PPE services connect to the online environment for internal testing or limited external previews. PPE identifiers always use the `ppe_` prefix.

## Request Routing

### HTTP Protocol
Add the following headers to route requests to PPE:

```text
x-use-ppe: 1
x-tt-env: ppe_*
```

### RPC Protocol
Add `env=ppe_*` to the `Base.Extra.env` field in the request body.

**Example:**
```json
{
  "ReqFieldA": {},
  "Base": {
    "Extra": {
      "env": "ppe_gdpa_dryrun"
    }
  }
}
```

### BAM MCP Tools
1. Add HTTP headers or RPC env fields according to the protocol chosen above.
2. Set the `env` field in the BAM request to `ppe_*`.
3. Bam will use `explorer.api.executor` as caller, it cannot be changed.
4. Read the Request Construction Workflow above to learn how to construct request parameters.

## Observability

Consult the `md3c` skill for VDC details if unknown. If the VDC is undetermined, default to `Singapore-*`.
PPE don't have traffic by default unless you send requests.

### Query Metrics
PPE requires specific VRegions for metric queries. Map the deployment VDC to the correct PPE VRegion:

| VDC                | Online VRegion    | PPE VRegion   |
|--------------------|-------------------|---------------|
| sg1/my/my1/my2/my3 | Singapore-Central | Singapore-PPE |
| useast5            | US-TTP            | US-TTP-PPE    |
| useast8            | US-TTP2           | US-TTP2-PPE   |
| no1a               | EU-TTP2           | EU-TTP2-PPE   |

### Query Logs
PPE logs are merged into the related online storage.
*   **Action**: Set the region to the **Online VRegion** (e.g., `Singapore-Central` or `US-TTP2`) corresponding to your VDC. Do not use the PPE VRegion for logs.
