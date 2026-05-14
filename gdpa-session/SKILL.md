---
name: gdpa-session
description: |
  Initialize GDPA CLI session before using any GDPA tools.
  This must be called before any gdpa-cli run command.
  Triggers when any GDPA skill needs to be used: argos-query, bam-api,
  bam-query, bits-cd, codebase, devflow, edit-idl, env, eventbus,
  lark-docs, meego-query, meego-manage, neptune, overpass, repotalk,
  scm, tcc-query, tce.
---

# GDPA Session Management

GDPA CLI requires an active session for all `gdpa-cli run` commands.

## When to Use

Before calling **any** GDPA skill or tool that uses `gdpa-cli run`, you must
first create a session. This includes all tools like argos-query, bam-api,
bits-cd, codebase, devflow, lark-docs, meego, neptune, etc.

## Steps

1. **Create a session**:
   ```bash
   gdpa-cli create-session
   ```
   This returns output containing a session ID like `sess_20260304_152045_ff0f8d5f`.

2. **Extract the session ID** from the output.

3. **Use the session ID** in all subsequent `gdpa-cli run` commands:
   ```bash
   gdpa-cli run <agent> --session-id <session_id> --input '<json>'
   ```

## Important Notes

- One session can be reused for all commands within the same conversation
- Sessions do not expire during a normal conversation lifetime
- If a session error occurs, create a new session
- The `--session-id` parameter is **mandatory** for all `gdpa-cli run` commands
