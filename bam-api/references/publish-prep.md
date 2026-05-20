# Publish Preparation Workflow — bam-api

Decision table and step-by-step workflow for preparing a BAM version publish. This workflow is read-only until the user explicitly confirms the `create_service_version` call.

## Decision table

| Step | Action | Required parameters | Purpose |
| --- | --- | --- | --- |
| 1 | `get_api_service_versions` (unscoped) | psm | Get overall latest version across all branches |
| 2 | `get_api_service_versions` (branch-scoped) | psm, branch | Get latest version on the target branch |
| 3 | Compare versions | — | Determine proposed next version and detect divergence |
| 4 | Present confirmation summary | — | Show user: psm, branch, region, cluster, current latest, proposed next, safety note |
| 5 | `create_service_version` (only after user confirms) | psm, branch, version, note, cluster, region | Execute the write |

## Step-by-step workflow

### Step 1: Unscoped version query

```bash
gdpa-cli run bam-api --session-id "$SESSION_ID" \
  --input '{"action": "get_api_service_versions", "psm": "tiktok.user.service"}'
```

Record the latest version across all branches.

### Step 2: Branch-scoped version query

```bash
gdpa-cli run bam-api --session-id "$SESSION_ID" \
  --input '{"action": "get_api_service_versions", "psm": "tiktok.user.service", "branch": "master"}'
```

Record the latest version on the target branch.

### Step 3: Compare and determine next version

- If branch-scoped version > unscoped latest: the branch is ahead — use branch version + 1.
- If branch-scoped version < unscoped latest: divergence detected — flag in confirmation summary.
- If branch-scoped version == unscoped latest: normal — increment by 1.

If the branch has no version history (empty response), note this in the confirmation summary. Missing branch history is informational, not a blocker — the first version will be `1.0.0` or auto-incremented from the unscoped latest.

### Step 4: Present confirmation summary

```
⚠️ 写操作确认
PSM: tiktok.user.service
Branch: master
Region: cn
Cluster: default
Current latest version (all branches): 0.0.67
Current latest version (master): 0.0.67
Proposed next version: 0.0.68

Note: This will create version 0.0.68 on branch master for PSM tiktok.user.service.
确认创建？
```

### Step 5: Execute (only after user confirms)

```bash
gdpa-cli run bam-api --session-id "$SESSION_ID" \
  --input '{"action": "create_service_version", "psm": "tiktok.user.service", "branch": "master"}'
```

After execution, display the result: version number, status, and any commit info that was auto-attached.

## Anti-patterns to avoid

- Do not open `scm`, repo grep, branch-existence checks, or `AskUserQuestion` before completing Steps 1–2. The version queries are sufficient for publish preparation.
- Do not check local git remote for IDL source — BAM is the authoritative source.
- Do not summarize partial context and ask for confirmation before both version queries complete.
