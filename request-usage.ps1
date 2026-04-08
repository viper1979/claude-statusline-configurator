# request-usage.ps1 — Plugin for statusline.ps1
# Fetches rate-limit usage from the Anthropic OAuth API and writes rate-limits-cache.json.
# Called by Get-RateLimitsData in statusline.ps1 when no other source has rate_limits data.
# Fully autonomous: handles credentials, HTTP, transformation, and caching.

param(
    [string]$CredentialsPath = $null,
    [string]$CachePath       = $null
)

# Resolve default credentials path: Windows first, then Linux/WSL
if (-not $CredentialsPath) {
    $windowsPath = Join-Path $env:USERPROFILE '.claude\.credentials.json'
    $linuxPath   = Join-Path $HOME '.claude/.credentials.json'
    if     (Test-Path $windowsPath) { $CredentialsPath = $windowsPath }
    elseif (Test-Path $linuxPath)   { $CredentialsPath = $linuxPath }
    else                            { exit 1 }
}

# Resolve default cache path: next to this script
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

# Convert ISO 8601 resets_at string to Unix timestamp (seconds since epoch)
function ConvertTo-UnixTimestamp {
    <#
    .SYNOPSIS
        Converts an ISO 8601 date string to a Unix timestamp (seconds since epoch).
    .PARAMETER IsoDate
        The ISO 8601 date string to convert (e.g. "2026-04-08T15:00:00Z").
    .OUTPUTS
        [int] Unix timestamp in seconds, or 0 if the input is null/empty or cannot be parsed.
    #>
    param([string]$IsoDate)
    if (-not $IsoDate) { return 0 }
    try {
        return [int][DateTimeOffset]::Parse($IsoDate).ToUnixTimeSeconds()
    } catch {
        return 0
    }
}

# Transform API response: utilization (0.0–1.0) → used_percentage (0–100, rounded)
$cache = @{
    rate_limits = @{
        five_hour = @{
            used_percentage = [int][math]::Round($response.five_hour.utilization * 100)
            resets_at       = ConvertTo-UnixTimestamp $response.five_hour.resets_at
        }
        seven_day = @{
            used_percentage = [int][math]::Round($response.seven_day.utilization * 100)
            resets_at       = ConvertTo-UnixTimestamp $response.seven_day.resets_at
        }
    }
}

$cache | ConvertTo-Json -Depth 5 | Set-Content -Path $CachePath -Encoding UTF8
