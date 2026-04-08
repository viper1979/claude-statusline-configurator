# Rate-Limits Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When stdin JSON lacks `rate_limits`, populate them from cached/plugin sources so the statusline shows real data on first start.

**Architecture:** A new `Get-RateLimitsData` function in `statusline.ps1` implements a 3-source fallback chain (last-payload → cache file → plugin script). A new standalone `request-usage.ps1` handles OAuth API calls and writes the cache. The main script's rendering pipeline is unchanged.

**Tech Stack:** PowerShell 7, Pester 5.x, Anthropic OAuth API

**Spec:** `docs/superpowers/specs/2026-04-08-rate-limits-enrichment-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `statusline.ps1` | Modify | Add `Get-RateLimitsData` function + enrichment call in `Invoke-Main` |
| `request-usage.ps1` | Create | Standalone plugin — reads credentials, calls API, writes cache |
| `.gitignore` | Modify | Add `rate-limits-cache.json` |
| `tests/statusline.Tests.ps1` | Modify | Add tests for `Get-RateLimitsData` + `Invoke-Main` enrichment integration |
| `tests/request-usage.Tests.ps1` | Create | Tests for the plugin script |

---

### Task 1: `Get-RateLimitsData` — Fallback from `last-payload.json`

**Files:**
- Modify: `statusline.ps1` (insert new function before `Invoke-Main`, ~line 479)
- Modify: `tests/statusline.Tests.ps1` (add new Describe block)

- [ ] **Step 1: Write failing tests**

Add a new `Describe 'Get-RateLimitsData'` block at the end of `tests/statusline.Tests.ps1`:

```powershell
Describe 'Get-RateLimitsData' {
    BeforeAll {
        $testDir = Join-Path $TestDrive 'ratelimits'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    It 'returns $null when no source has data' {
        $emptyDir = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $result = Get-RateLimitsData -ScriptDir $emptyDir -LastPayloadPath (Join-Path $emptyDir 'nonexistent.json')
        $result | Should -BeNullOrEmpty
    }

    It 'reads rate_limits from last-payload.json when present' {
        $payloadPath = Join-Path $testDir 'last-payload.json'
        @{
            version = '1.0'
            rate_limits = @{
                five_hour = @{ used_percentage = 42; resets_at = 1744123456 }
                seven_day = @{ used_percentage = 18; resets_at = 1744567890 }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $payloadPath -Encoding UTF8
        $result = Get-RateLimitsData -ScriptDir $testDir -LastPayloadPath $payloadPath
        $result.five_hour.used_percentage | Should -Be 42
        $result.seven_day.used_percentage | Should -Be 18
    }

    It 'returns $null from last-payload.json when it has no rate_limits' {
        $payloadNoRL = Join-Path $testDir 'payload-no-rl.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $payloadNoRL -Encoding UTF8
        $noCacheDir = Join-Path $TestDrive 'nocache'
        New-Item -ItemType Directory -Path $noCacheDir -Force | Out-Null
        $result = Get-RateLimitsData -ScriptDir $noCacheDir -LastPayloadPath $payloadNoRL
        $result | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*Get-RateLimitsData*'} -Output Detailed"`
Expected: FAIL — `Get-RateLimitsData` is not defined

- [ ] **Step 3: Implement `Get-RateLimitsData` with last-payload fallback**

Add this function in `statusline.ps1` before `Invoke-Main` (before the `<# .SYNOPSIS Orchestrates...` doc comment at ~line 479):

```powershell
<#
.SYNOPSIS
    Resolves rate_limits data from fallback sources when stdin JSON lacks it.
.DESCRIPTION
    Fallback chain: last-payload.json → rate-limits-cache.json → request-usage.ps1 plugin.
    Returns the first non-null rate_limits object found, or $null if no source has data.
.PARAMETER ScriptDir
    Directory where statusline.ps1 resides (used to locate cache and plugin).
.PARAMETER LastPayloadPath
    Full path to last-payload.json (already computed by Invoke-Main).
.OUTPUTS
    PSCustomObject with rate_limits subtree, or $null.
#>
function Get-RateLimitsData {
    param(
        [string]$ScriptDir,
        [string]$LastPayloadPath
    )

    # Source 1: last-payload.json (previous invocation's full payload)
    if ($LastPayloadPath -and (Test-Path $LastPayloadPath)) {
        try {
            $lastPayload = Get-Content -Path $LastPayloadPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($lastPayload.rate_limits) {
                return $lastPayload.rate_limits
            }
        } catch {
            # Corrupted file — fall through to next source
        }
    }

    return $null
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*Get-RateLimitsData*'} -Output Detailed"`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add Get-RateLimitsData with last-payload fallback"
```

---

### Task 2: `Get-RateLimitsData` — Cache file fallback

**Files:**
- Modify: `statusline.ps1` — extend `Get-RateLimitsData`
- Modify: `tests/statusline.Tests.ps1` — add cache test
- Modify: `.gitignore` — add `rate-limits-cache.json`

- [ ] **Step 1: Write failing test**

Add inside the existing `Describe 'Get-RateLimitsData'` block:

```powershell
    It 'reads rate_limits from rate-limits-cache.json when last-payload lacks them' {
        # last-payload without rate_limits
        $payloadNoRL = Join-Path $testDir 'payload-cache-test.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $payloadNoRL -Encoding UTF8
        # Cache file with rate_limits
        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        @{
            rate_limits = @{
                five_hour = @{ used_percentage = 55; resets_at = 1744200000 }
                seven_day = @{ used_percentage = 30; resets_at = 1744600000 }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $cachePath -Encoding UTF8
        $result = Get-RateLimitsData -ScriptDir $testDir -LastPayloadPath $payloadNoRL
        $result.five_hour.used_percentage | Should -Be 55
        $result.seven_day.used_percentage | Should -Be 30
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*reads rate_limits from rate-limits-cache*'} -Output Detailed"`
Expected: FAIL — function returns `$null` because cache logic not implemented yet

- [ ] **Step 3: Add cache fallback to `Get-RateLimitsData`**

In `statusline.ps1`, in `Get-RateLimitsData`, replace the final `return $null` with:

```powershell
    # Source 2: rate-limits-cache.json (written by request-usage.ps1 plugin)
    $cachePath = Join-Path $ScriptDir 'rate-limits-cache.json'
    if (Test-Path $cachePath) {
        try {
            $cacheData = Get-Content -Path $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cacheData.rate_limits) {
                return $cacheData.rate_limits
            }
        } catch {
            # Corrupted cache — fall through to next source
        }
    }

    return $null
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*Get-RateLimitsData*'} -Output Detailed"`
Expected: 4 tests PASS

- [ ] **Step 5: Add `rate-limits-cache.json` to `.gitignore`**

Append to `.gitignore`:
```
rate-limits-cache.json
```

- [ ] **Step 6: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1 .gitignore
git commit -m "feat(statusline): add cache file fallback to Get-RateLimitsData"
```

---

### Task 3: `Get-RateLimitsData` — Plugin invocation

**Files:**
- Modify: `statusline.ps1` — extend `Get-RateLimitsData`
- Modify: `tests/statusline.Tests.ps1` — add plugin test

- [ ] **Step 1: Write failing test**

Add inside the existing `Describe 'Get-RateLimitsData'` block:

```powershell
    It 'calls request-usage.ps1 plugin when no other source has data and reads cache afterward' {
        $pluginDir = Join-Path $TestDrive 'plugin-test'
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        # No last-payload, no cache — plugin should be called
        # Create a fake plugin that writes a cache file
        $pluginPath = Join-Path $pluginDir 'request-usage.ps1'
        $cacheDest  = Join-Path $pluginDir 'rate-limits-cache.json'
        @"
`@{
    rate_limits = @{
        five_hour = @{ used_percentage = 77; resets_at = 1744300000 }
        seven_day = @{ used_percentage = 25; resets_at = 1744700000 }
    }
} | ConvertTo-Json -Depth 5 | Set-Content -Path '$($cacheDest -replace "'","''")' -Encoding UTF8
"@ | Set-Content -Path $pluginPath -Encoding UTF8

        $emptyPayload = Join-Path $pluginDir 'last-payload.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $emptyPayload -Encoding UTF8

        $result = Get-RateLimitsData -ScriptDir $pluginDir -LastPayloadPath $emptyPayload
        $result.five_hour.used_percentage | Should -Be 77
        $result.seven_day.used_percentage | Should -Be 25
    }

    It 'returns $null when plugin does not exist and no other source has data' {
        $noPluginDir = Join-Path $TestDrive 'no-plugin'
        New-Item -ItemType Directory -Path $noPluginDir -Force | Out-Null
        $emptyPayload = Join-Path $noPluginDir 'last-payload.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $emptyPayload -Encoding UTF8
        $result = Get-RateLimitsData -ScriptDir $noPluginDir -LastPayloadPath $emptyPayload
        $result | Should -BeNullOrEmpty
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*plugin*'} -Output Detailed"`
Expected: FAIL — plugin invocation not implemented

- [ ] **Step 3: Add plugin invocation to `Get-RateLimitsData`**

In `statusline.ps1`, in `Get-RateLimitsData`, replace the final `return $null` with:

```powershell
    # Source 3: request-usage.ps1 plugin (calls OAuth API, writes cache)
    $pluginPath = Join-Path $ScriptDir 'request-usage.ps1'
    if (Test-Path $pluginPath) {
        try {
            & $pluginPath
        } catch {
            # Plugin failed — fall through
        }
        # Re-read cache (plugin writes rate-limits-cache.json on success)
        if (Test-Path $cachePath) {
            try {
                $cacheData = Get-Content -Path $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cacheData.rate_limits) {
                    return $cacheData.rate_limits
                }
            } catch {
                # Corrupted cache after plugin run — give up
            }
        }
    }

    return $null
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*Get-RateLimitsData*'} -Output Detailed"`
Expected: 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add plugin invocation fallback to Get-RateLimitsData"
```

---

### Task 4: Wire enrichment into `Invoke-Main`

**Files:**
- Modify: `statusline.ps1:549` — add enrichment call after last-payload write
- Modify: `tests/statusline.Tests.ps1` — add integration tests

- [ ] **Step 1: Write failing tests**

Add a new `Describe 'Invoke-Main rate-limits enrichment'` block:

```powershell
Describe 'Invoke-Main rate-limits enrichment' {
    BeforeAll {
        $enrichDir = Join-Path $TestDrive 'enrich'
        New-Item -ItemType Directory -Path $enrichDir -Force | Out-Null
        $enrichConfig = Join-Path $enrichDir 'statusline-config.json'
        @{
            lines = @(@{
                fields = @(@{
                    type = 'progressbar'
                    key  = 'rate_limits.five_hour.used_percentage'
                    fg   = $null
                    bg   = $null
                    progressStyle = 'color-coded'
                })
            })
            knownKeys = @('rate_limits.five_hour.used_percentage')
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $enrichConfig -Encoding UTF8
    }

    It 'uses rate_limits from stdin when present (no enrichment)' {
        $inputWithRL = @{
            rate_limits = @{
                five_hour = @{ used_percentage = 60 }
            }
        } | ConvertTo-Json -Depth 5
        $result = Invoke-Main -ConfigPath $enrichConfig -InputJson $inputWithRL
        # 60% should be in the output
        $result | Should -Match '60%'
    }

    It 'enriches from last-payload.json when stdin lacks rate_limits' {
        # Write a last-payload with rate_limits
        $payloadPath = Join-Path $enrichDir 'last-payload.json'
        @{
            rate_limits = @{
                five_hour = @{ used_percentage = 35 }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $payloadPath -Encoding UTF8

        # Stdin without rate_limits — enrichment should kick in
        $result = Invoke-Main -ConfigPath $enrichConfig -InputJson '{"version":"1.0"}'
        $result | Should -Match '35%'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Filter @{FullName='*rate-limits enrichment*'} -Output Detailed"`
Expected: First test passes (stdin path works already), second test FAILS (enrichment not wired)

- [ ] **Step 3: Wire enrichment into `Invoke-Main`**

In `statusline.ps1`, after the `last-payload.json` write block (after line ~549, before `# Expose knownKeys`), add:

```powershell
    # Enrich rate_limits from fallback sources when stdin JSON lacks them
    if (-not (Get-NestedValue $data 'rate_limits')) {
        $scriptDir = Split-Path $PSCommandPath -Parent
        $rateLimits = Get-RateLimitsData -ScriptDir $scriptDir -LastPayloadPath $payloadPath
        if ($rateLimits) {
            $data | Add-Member -NotePropertyName 'rate_limits' -NotePropertyValue $rateLimits -Force
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester ./tests/statusline.Tests.ps1 -Output Detailed"`
Expected: ALL tests PASS (existing + new)

- [ ] **Step 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): wire rate-limits enrichment into Invoke-Main"
```

---

### Task 5: `request-usage.ps1` plugin

**Files:**
- Create: `request-usage.ps1`
- Create: `tests/request-usage.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `tests/request-usage.Tests.ps1`:

```powershell
BeforeAll {
    $script:PluginPath = Join-Path $PSScriptRoot '../request-usage.ps1'
}

Describe 'request-usage.ps1' {
    BeforeEach {
        $testDir = Join-Path $TestDrive "run-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    It 'writes rate-limits-cache.json on successful API response' {
        # Create fake credentials
        $credsDir = Join-Path $testDir '.claude'
        New-Item -ItemType Directory -Path $credsDir -Force | Out-Null
        $credsPath = Join-Path $credsDir '.credentials.json'
        @{ claudeAiOauth = @{ accessToken = 'fake-token' } } | ConvertTo-Json -Depth 3 |
            Set-Content -Path $credsPath -Encoding UTF8

        # Mock Invoke-RestMethod to return a fake API response
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                five_hour = [PSCustomObject]@{ utilization = 0.42; resets_at = '2026-04-08T15:00:00Z' }
                seven_day = [PSCustomObject]@{ utilization = 0.18; resets_at = '2026-04-10T00:00:00Z' }
            }
        }

        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        & $script:PluginPath -CredentialsPath $credsPath -CachePath $cachePath

        Test-Path $cachePath | Should -Be $true
        $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
        $cache.rate_limits.five_hour.used_percentage | Should -Be 42
        $cache.rate_limits.seven_day.used_percentage | Should -Be 18
    }

    It 'does not write cache when credentials file is missing' {
        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        $nonExistent = Join-Path $testDir 'no-creds.json'
        & $script:PluginPath -CredentialsPath $nonExistent -CachePath $cachePath
        Test-Path $cachePath | Should -Be $false
    }

    It 'preserves existing cache when API call fails' {
        # Create fake credentials
        $credsDir = Join-Path $testDir '.claude'
        New-Item -ItemType Directory -Path $credsDir -Force | Out-Null
        $credsPath = Join-Path $credsDir '.credentials.json'
        @{ claudeAiOauth = @{ accessToken = 'fake-token' } } | ConvertTo-Json -Depth 3 |
            Set-Content -Path $credsPath -Encoding UTF8

        # Pre-existing cache
        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        @{ rate_limits = @{ five_hour = @{ used_percentage = 99 } } } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $cachePath -Encoding UTF8

        # Mock Invoke-RestMethod to throw
        Mock Invoke-RestMethod { throw 'Network error' }

        & $script:PluginPath -CredentialsPath $credsPath -CachePath $cachePath

        # Cache should still have the old value
        $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
        $cache.rate_limits.five_hour.used_percentage | Should -Be 99
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester ./tests/request-usage.Tests.ps1 -Output Detailed"`
Expected: FAIL — `request-usage.ps1` does not exist

- [ ] **Step 3: Create `request-usage.ps1`**

Create `request-usage.ps1` in the project root:

```powershell
# request-usage.ps1 — Plugin for statusline.ps1
# Fetches rate-limit usage from the Anthropic OAuth API and writes rate-limits-cache.json.
# Called by Get-RateLimitsData in statusline.ps1 when no other source has rate_limits data.
# This script is fully autonomous: it handles credentials, HTTP, and caching.

param(
    [string]$CredentialsPath = $null,
    [string]$CachePath       = $null
)

# Resolve default credentials path (Windows first, then Linux/WSL)
if (-not $CredentialsPath) {
    $windowsPath = Join-Path $env:USERPROFILE '.claude\.credentials.json'
    $linuxPath   = Join-Path $HOME '.claude/.credentials.json'
    if (Test-Path $windowsPath)    { $CredentialsPath = $windowsPath }
    elseif (Test-Path $linuxPath)  { $CredentialsPath = $linuxPath }
    else { exit 1 }
}

# Resolve default cache path (next to this script)
if (-not $CachePath) {
    $CachePath = Join-Path (Split-Path $PSCommandPath -Parent) 'rate-limits-cache.json'
}

# Read credentials
if (-not (Test-Path $CredentialsPath)) { exit 1 }
try {
    $creds = Get-Content -Path $CredentialsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $token = $creds.claudeAiOauth.accessToken
    if (-not $token) { exit 1 }
} catch {
    exit 1
}

# Call Anthropic OAuth usage API
try {
    $headers = @{
        'Authorization'  = "Bearer $token"
        'anthropic-beta' = 'oauth-2025-04-20'
        'Content-Type'   = 'application/json'
    }
    $response = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $headers -Method Get
} catch {
    # API call failed — do not overwrite existing cache
    exit 1
}

# Transform API response to cache format
# API returns utilization as 0.0–1.0, we store as 0–100 (used_percentage)
# API returns resets_at as ISO 8601 string, we convert to Unix timestamp
$fiveHour = $response.five_hour
$sevenDay = $response.seven_day

# Helper: convert ISO 8601 string to Unix timestamp
function ConvertTo-UnixTimestamp([string]$IsoDate) {
    if (-not $IsoDate) { return 0 }
    try {
        $dt = [DateTimeOffset]::Parse($IsoDate)
        return [int]$dt.ToUnixTimeSeconds()
    } catch {
        return 0
    }
}

$cache = @{
    rate_limits = @{
        five_hour = @{
            used_percentage = [int][math]::Round(($fiveHour.utilization) * 100)
            resets_at       = ConvertTo-UnixTimestamp $fiveHour.resets_at
        }
        seven_day = @{
            used_percentage = [int][math]::Round(($sevenDay.utilization) * 100)
            resets_at       = ConvertTo-UnixTimestamp $sevenDay.resets_at
        }
    }
}

$cache | ConvertTo-Json -Depth 5 | Set-Content -Path $CachePath -Encoding UTF8
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester ./tests/request-usage.Tests.ps1 -Output Detailed"`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add request-usage.ps1 tests/request-usage.Tests.ps1
git commit -m "feat(statusline): add request-usage.ps1 plugin for OAuth rate-limit fetching"
```

---

### Task 6: `.gitignore` update + full test run

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Verify `.gitignore` has `rate-limits-cache.json`**

If not already added in Task 2, append to `.gitignore`:
```
rate-limits-cache.json
```

- [ ] **Step 2: Run full test suite**

Run: `pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"`
Expected: ALL tests PASS (existing 106 + 9 new = 115 total)

- [ ] **Step 3: Commit if `.gitignore` changed**

```bash
git add .gitignore
git commit -m "chore: add rate-limits-cache.json to gitignore"
```

---

## Verification

1. **Unit tests:** `pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"` — all pass
2. **Manual test without rate_limits:** `echo '{"version":"1.0"}' | pwsh -File statusline.ps1` — should show 0% bars (no cache, no plugin)
3. **Manual test with cached data:** Create `rate-limits-cache.json` manually with test data, run without rate_limits in stdin — should show cached percentages
4. **Manual test with real plugin:** If credentials exist at `~/.claude/.credentials.json`, remove cache, run without rate_limits — plugin should fetch and populate
