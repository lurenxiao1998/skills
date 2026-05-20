---
name: starling
description: Use whenever the user works with Bytedance Starling i18n translations — looking up a key's translations across locales, reverse-searching a Chinese source string to find its key, pulling/pushing translation files (xlsx/json), or machine-translating md/docx/xlsx to multiple locales. Wraps local `@ies/starling-cli`. Trigger even when the user doesn't say "starling" explicitly: i18n key, 国际化, 文案反查, 翻译查询, 机器翻译, i18nops.
---

> **session_id 传递**：若本次任务需要在多次 `gdpa-cli run` 之间串联 workflow 状态、日志或上下文，请复用同一个 `session_id`。如果当前 skill / Agent 已经提供了 `session_id`，**请直接复用，不要新建**。
>
> - **已有时优先复用**：不要重复执行 `create-session`。
> - **没有时再创建**：执行 `gdpa-cli create-session`。
> - **后续调用**：可以显式传 `--session-id <session_id>`，例如 `gdpa-cli run <agent> --session-id <session_id> --input '{...}'`。
> - **适用场景**：Base Workflow、BITS Dev Workflow、post-coding-verify 及其他依赖 Session 工作目录的场景需要持续复用；普通单次查询通常可以不传。

# Starling Agent

Query / sync Starling i18n translations via the local `starling` CLI.

## Prerequisites

- `starling` (≥ 3.7.53) on PATH: `npm install -g @ies/starling-cli --registry=http://bnpm.byted.org`
- **Authentication**: run `starling login` in your terminal — opens browser SSO, persists in `~/.config/configstore/@ies/starling-cli.json`. One time per machine.
- Bytedance intranet access (Starling platform is internal)

> The wrapper does not manage credentials. Auth lives entirely in starling's own configstore (populated by `starling login`); no AK/SK ever touches the wrapper, the rendered config.js, or env vars.
>
> The agent **pre-flights `exec.LookPath`** on every command. If the `starling` binary is missing it returns `IO-001` with the npm-install command spelled out — relay it verbatim to the user.

## Commands

| `command` | Purpose |
|---|---|
| `whoami` | Show current Starling SSO login identity (from `starling login`) |
| `download` | Pull translations to disk; returns file list + key counts |
| `upload` | Push xlsx (with `include_target=true`) or json (source-only) to Starling |
| `search_by_source` | Reverse-lookup: given a source string, find existing keys + their translations |
| `translate` | Machine-translate a file to N locales using Starling's translation backend |

## Session ID (recommended)

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{...}'
```

- **`search_by_source` with `scope=namespace`**: when `--session-id` is provided, the full namespace download lands under `.gdpa/{sid}/starling/namespaces/<project>/<ns>/<mode>__<locales>/` and is reused across calls within the same session. Subsequent reverse-lookups against the same namespace skip the download entirely (`from_cache: true` in the response).
- **Other commands** (`whoami` / `download` / `upload` / `translate` / `search_by_source` with `scope=project`): `--session-id` is optional and has no behavioral effect — pass it for consistency with other skills, but everything works without it.
- **No `--session-id`**: the namespace mode of `search_by_source` falls back to a per-call tempdir, so every call re-downloads the entire namespace. Tolerable for one-off queries, but pass `--session-id` if you plan to do multiple lookups.

## Authentication errors → recommend `starling login`

When the underlying starling CLI returns a "not logged in" / authentication error (surfaced as `AGT-001`), instruct the user:

```text
You haven't authenticated with Starling yet. In your terminal, run:

    starling login

That opens browser SSO; the credential persists in
~/.config/configstore/@ies/starling-cli.json so you only need to do it
once. Then retry the original command.
```

The agent does NOT collect AK/SK itself — that is starling's job via `starling login`. This keeps the credential store consistent and avoids duplicating the SSO flow.

## search_by_source

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{
  "command": "search_by_source",
  "text": "我是一个段落",
  "scope": "project",
  "project_id": "7031",
  "namespace": ["common"],
  "locales": ["zh", "en", "ja"],
  "match": "normalized"
}'
```

Two scopes:

| Scope | Data source | Coverage | When to use |
|---|---|---|---|
| `project` (default) | `starling scan --fallback` in cwd | Keys already i18n'd in this codebase | "Did anyone in this repo already key this?" |
| `namespace` | `starling download` of full namespace (snapshot under `.gdpa/{sid}/starling/namespaces/` when `--session-id` is set; per-call tempdir otherwise) | All keys in the namespace | "Did anyone anywhere key this?" |

`match`:
- `exact` — literal string equality
- `normalized` (default) — placeholders collapsed to `{}`, whitespace folded. `你好{{name}}` matches `你好{{user}}`.

`placeholder_matchers` (optional, array of regex strings) — **appended to** the default `{{var}}` matcher (not a replacement). For example, passing `["\\{[^{}]+\\}"]` makes `{foo}` normalize alongside `{{foo}}`. **Go RE2 syntax only**: no lookbehind (`(?<=`/`(?<!`); use capture groups instead.

When `--session-id` is supplied, namespace snapshots persist at `.gdpa/{sid}/starling/namespaces/<project>/<ns>/<mode>__<locales>/` and are reused across calls in the same session until session GC sweeps them (~30 days). Set `refresh: true` to force re-download even on a cache hit.

## download

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{
  "command": "download",
  "project_id": "7031",
  "namespace": ["common"],
  "locales": ["zh", "en"],
  "mode": "normal"
}'
```

`mode`: `normal` (default) / `gray` / `test` / `offline`. Output dropped under `$TMPDIR/starling-dl-*/`.

### Look up specific keys' translations

Pass `keys` to filter — works for "show me the translations of these N keys" without downloading the whole namespace. When `keys` is non-empty the result includes a `translations` map: `key → locale → text`.

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{
  "command": "download",
  "project_id": "278",
  "namespace": ["Test"],
  "locales": ["zh", "en", "ja"],
  "keys": ["downloadAssets_landingPage_progressCaption", "pm_mt_sub_emotes"]
}'
# →
# "translations": {
#   "downloadAssets_landingPage_progressCaption": {
#     "zh": "...",
#     "en": "..."
#   },
#   "pm_mt_sub_emotes": {...}
# }
```

Requires starling-cli ≥ 3.3.20 (the wrapper sets `download.keysToDownload` in config).

## upload

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{
  "command": "upload",
  "project_id": "7031",
  "namespace": ["common"],
  "file_path": "./translations.xlsx",
  "include_target": true
}'
```

`include_target=true` requires `.xlsx` (json upload can only carry source text per Starling docs).

## whoami

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{"command":"whoami"}'
```

Returns `{ email, accessKey }` from starling's own configstore (populated by `starling login`). If the user hasn't run `starling login`, starling itself errors — the wrapper passes that through.

## translate

```bash
gdpa-cli run starling --session-id "$SESSION_ID" --input '{
  "command": "translate",
  "entry": "./i18n/source.xlsx",
  "locales": ["ja", "ko", "zh-Hant", "vi", "th"]
}'
```

Wraps `starling translate <type> <entry> [dist] -l <locale> -t` and loops once per locale. The wrapper auto-infers `type` from the entry extension:

| Extension | `type` |
|---|---|
| `.xlsx` | `xs` |
| `.md` / `.markdown` | `md` |
| `.docx` | `dc` |

| Field | Required | Notes |
|---|---|---|
| `entry` | Yes | File or directory path on local disk |
| `locales` | Yes | Target locales; one CLI invocation per locale |
| `type` | No | Pass explicitly to override inference |
| `dist` | No | Output directory; default writes next to `entry` |
| `depth` | No | When `entry` is a directory, recursion depth (`*` unlimited) |

**Output naming** follows Starling's default: `<basename>-<locale>.<ext>`. Per-locale failures are tolerated; **all** locales failing returns `AGT-001`.

**Typical workflow** (tmates → Bitable → cherry-pick → branch → translate):

```bash
# 1. CI on PPE branch has the polished English source from upstream steps.
# 2. Fan out to 5 locales:
gdpa-cli run starling --session-id "$SESSION_ID" --input '{
  "command": "translate",
  "entry": "./i18n/source.xlsx",
  "locales": ["zh", "ja", "ko", "vi", "th"]
}'
# 3. Commit the locale files back to the branch.
```

## Errors

| Code | Meaning | Fix |
|---|---|---|
| `INPUT-001` | Required field missing | Check input JSON |
| `INPUT-002` | Bad input | Read error message |
| `IO-001` | Upload file not found, OR `starling` binary missing | Relay the install command from the error verbatim |
| `AGT-001` | starling CLI exited non-zero (incl. not-logged-in, all-locales-failed for translate) | Inspect per-locale errors / stderr; if it looks like an auth error, ask the user to run `starling login` |
| `NET-001` | CLI timed out | Network slow / Starling slow; retry |

## Notes

- Browser is always disabled (`--disable-browser`). Pipeline / preview UI is out of scope.
- No AK/SK ever written to disk by this wrapper. starling's own configstore (managed by `starling login`) is the single source of truth for SSO state.
- Placeholder matchers must be Go RE2-compatible: no lookbehind. Use capture groups instead.
