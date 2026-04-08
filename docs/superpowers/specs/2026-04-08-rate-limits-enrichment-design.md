# Design: Rate-Limits Enrichment

**Date:** 2026-04-08
**Branch:** feature/statusline-enhancements

---

## Overview

Rate-limit fields (`rate_limits.five_hour`, `rate_limits.seven_day`) are only present in the Claude Code stdin payload after the first API response in a session. This means the statusline shows 0% / empty on first start. This enhancement adds a fallback chain to populate rate-limit data from alternative sources when stdin lacks it.

---

## 1. Fallback Chain (Data-Enrichment Phase)

### Goal

When the stdin JSON does not contain `rate_limits`, attempt to source the data from progressively less-fresh alternatives before falling back to the current 0%/empty behavior.

### Fallback Order

1. **Stdin JSON** — current behavior, highest priority
2. **`last-payload.json`** — the previous invocation's full payload (already written by the script)
3. **`rate-limits-cache.json`** — dedicated cache written exclusively by the plugin
4. **`request-usage.ps1`** — optional plugin script, called synchronously
5. **No data** — 0% / empty (current fallback, unchanged)

The chain short-circuits: the first source that provides a non-null `rate_limits` object wins.

### New Function: `Get-RateLimitsData`

```powershell
function Get-RateLimitsData {
    param(
        [string]$ScriptDir,
        [string]$LastPayloadPath
    )
    # Step 1: last-payload.json
    # Step 2: rate-limits-cache.json (in $ScriptDir)
    # Step 3: request-usage.ps1 (in $ScriptDir), then re-read cache
    # Returns: rate_limits PSCustomObject or $null
}
```

### Placement in `Invoke-Main`

After the existing `last-payload.json` write (line ~549) and before rendering (line ~562):

```powershell
if (-not (Get-NestedValue $data 'rate_limits')) {
    $scriptDir = Split-Path $PSCommandPath -Parent
    $rateLimits = Get-RateLimitsData -ScriptDir $scriptDir -LastPayloadPath $payloadPath
    if ($rateLimits) {
        $data | Add-Member -NotePropertyName 'rate_limits' -NotePropertyValue $rateLimits -Force
    }
}
```

This follows the same pattern as the existing `worktree.branch` auto-detection enrichment (lines 529–537).

### Merge Logic

Only the `rate_limits` subtree is merged — no other fields from fallback sources are touched. The merge uses `Add-Member -Force` on `$data`, identical to the worktree enrichment pattern.

---

## 2. Plugin: `request-usage.ps1`

### Responsibility

The plugin is fully autonomous. It handles:
1. Reading credentials from the local Claude credentials file
2. Calling the Anthropic OAuth usage API
3. Writing the result to `rate-limits-cache.json`

The main script has zero knowledge of OAuth, HTTP, or credentials. It only knows: "call the script if it exists, then read the cache."

### API Endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Headers:
  Authorization: Bearer <accessToken>
  anthropic-beta: oauth-2025-04-20
  Content-Type: application/json
```

### Credentials Path

The plugin checks two locations (in order):
1. **Windows:** `$env:USERPROFILE\.claude\.credentials.json`
2. **Linux/WSL:** `~/.claude/.credentials.json`

The token is at JSON path `claudeAiOauth.accessToken`.

### Cache Format (`rate-limits-cache.json`)

Same structure as the Claude Code payload subtree, so the main script can merge without transformation:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42,
      "resets_at": 1744123456
    },
    "seven_day": {
      "used_percentage": 18,
      "resets_at": 1744567890
    }
  }
}
```

### Cache Location

Next to `statusline.ps1` (same directory as the main script).

### Error Handling

- Credentials file not found → exit silently (exit code 1), no cache written
- Token missing or empty → exit silently (exit code 1), no cache written
- API call fails (network error, 401, 500, etc.) → exit silently (exit code 1), existing cache preserved
- The main script does not check the plugin's exit code. It simply reads the cache afterward. If no cache exists, the next fallback (0%/empty) applies.

### API Response Mapping

The API returns a structure like `{ "five_hour": { "utilization": 0.42, "resets_at": "..." }, "seven_day": { ... } }`. The plugin transforms this into the cache format above — `utilization` (0.0–1.0) is converted to `used_percentage` (0–100) and `resets_at` is converted to a Unix timestamp. The main script never sees the raw API response.

### Invocation

- **When:** Only when stdin, last-payload.json, and cache all lack rate_limits data
- **How:** Synchronous call via `& "$ScriptDir/request-usage.ps1"` — blocks until complete
- **Expected latency:** ~200–500ms (one-time, only on first start without any prior data)

---

## 3. Tests

### `Get-RateLimitsData` (4 tests)

- Returns `$null` when no source has data (no last-payload, no cache, no plugin)
- Reads `rate_limits` from `last-payload.json` when present
- Reads `rate_limits` from `rate-limits-cache.json` when last-payload lacks them
- Calls plugin when no other source has data (plugin call mocked, verifies cache is read afterward)

### `request-usage.ps1` (3 tests)

- Writes cache file on successful API call (HTTP response mocked)
- Does not write cache when credentials file is missing
- Preserves existing cache when API call fails (does not overwrite)

### Integration in `Invoke-Main` (2 tests)

- `rate_limits` from stdin take priority (enrichment is skipped entirely)
- Enrichment activates when stdin has no `rate_limits`

---

## 4. Configurator

No changes to `statusline-configurator.html`. The enrichment is invisible to the configurator — it only affects runtime data resolution in `statusline.ps1`.

---

## 5. Files

| File | Action |
|---|---|
| `statusline.ps1` | Add `Get-RateLimitsData` function and enrichment call in `Invoke-Main` |
| `request-usage.ps1` | New file — plugin script (OAuth API + cache write) |
| `rate-limits-cache.json` | Written by plugin at runtime (gitignored) |
| `tests/statusline.Tests.ps1` | Add 6 tests for `Get-RateLimitsData` and `Invoke-Main` integration |
| `tests/request-usage.Tests.ps1` | New file — 3 tests for the plugin |
| `.gitignore` | Add `rate-limits-cache.json` |
