# CLI Recipes — bam-api

First-choice action selection and canonical CLI patterns for common lookup types.

## First-choice lookup guide

| Lookup type | First-choice action | When to use alternatives |
| --- | --- | --- |
| Schema by method name | `get_api_definition_info` (psm + method) | Use `get_api_definition_info_with_endpoint_id` when endpointId is known |
| Schema by path | `get_api_definition_info_through_path` (psm + path) | Use `get_api_definition_info_without_psm` when PSM is unknown |
| Schema by endpointId | `get_api_definition_info_with_endpoint_id` (endpointId) | Preferred when endpointId is available — most precise |
| All endpoints for a PSM | `get_api_service_list` (psm) | Add `version` or `branch` to scope to a specific version |
| Version list for a PSM | `get_api_service_versions` (psm) | Add `branch` to see branch-scoped versions |
| Publish preparation | `get_api_service_versions` (psm + branch) first, then confirm | See `references/publish-prep.md` for the full workflow |

## Malformed vs correct command

**Malformed** — guessing a shell binary that does not exist:
```bash
# WRONG: bam-api is not a standalone CLI binary
bam-api --psm tiktok.user.service --method GetUserInfo
```

**Correct** — canonical gdpa-cli invocation:
```bash
# CORRECT: always use gdpa-cli run bam-api
gdpa-cli run bam-api --session-id "$SESSION_ID" --input '{"action": "get_api_definition_info", "psm": "tiktok.user.service", "method": "GetUserInfo"}'
```

## On-axis recovery after wrapper failure

When `Skill(bam-api)` returns an `Execute skill:*` error, retry with the canonical CLI path before any off-axis fallback:

```bash
# Step 1: create a session if one does not exist
SESSION_ID=$(gdpa-cli create-session | sed -n '1p')

# Step 2: retry via gdpa-cli
gdpa-cli run bam-api --session-id "$SESSION_ID" --input '{"action": "get_api_service_list", "psm": "tiktok.user.service"}'
```

Only if the canonical retry also fails should you consider alternative approaches, and even then prefer re-reading SKILL.md for parameter corrections over repo search or sibling skills.
