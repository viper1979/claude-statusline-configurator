# statusline.ps1 — Claude Code custom status line
# Claude Code pipes the session JSON to stdin.
# Reads statusline-config.json from the same directory as this script.

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# Functions are added in Tasks 11-14

<#
.SYNOPSIS
    Recursively enumerates all dot-notation key paths in a PSCustomObject.
.PARAMETER Obj
    The object to enumerate (PSCustomObject from ConvertFrom-Json).
.PARAMETER Prefix
    Current path prefix (empty string for root call).
.OUTPUTS
    Array of dot-notation key strings.
#>
function Get-AllKeys {
    param([object]$Obj, [string]$Prefix = '')
    if ($null -eq $Obj) { return @() }
    $result = @()
    $Obj.PSObject.Properties | ForEach-Object {
        $key = if ($Prefix) { "$Prefix.$($_.Name)" } else { $_.Name }
        $result += $key
        if ($_.Value -is [PSCustomObject]) {
            $result += Get-AllKeys $_.Value $key
        }
    }
    return $result
}

<#
.SYNOPSIS
    Retrieves a value from a PSCustomObject by dot-notation path.
.PARAMETER Data
    The root object parsed from JSON.
.PARAMETER Path
    Dot-separated property path, e.g. 'context_window.used_percentage'.
.OUTPUTS
    The value at the path, or $null if not found.
#>
function Get-NestedValue {
    param(
        [object]$Data,
        [string]$Path
    )
    if ($null -eq $Data -or [string]::IsNullOrEmpty($Path)) { return $null }

    $current = $Data
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return $null }
        $current = $current.$segment
    }
    return $current
}

<#
.SYNOPSIS
    Converts a hex color string like '#4ade80' to an ANSI RGB foreground escape sequence.
.PARAMETER Hex
    6-character hex color with leading '#'.
.OUTPUTS
    ANSI escape string, e.g. ESC[38;2;74;222;128m
#>
function ConvertTo-AnsiFg {
    param([string]$Hex)
    $r = [Convert]::ToInt32($Hex.Substring(1,2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(3,2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(5,2), 16)
    return "$([char]27)[38;2;${r};${g};${b}m"
}

<#
.SYNOPSIS
    Converts a hex color string to an ANSI RGB background escape sequence.
.PARAMETER Hex
    6-character hex color with leading '#'.
.OUTPUTS
    ANSI escape string, e.g. ESC[48;2;R;G;Bm
#>
function ConvertTo-AnsiBg {
    param([string]$Hex)
    $r = [Convert]::ToInt32($Hex.Substring(1,2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(3,2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(5,2), 16)
    return "$([char]27)[48;2;${r};${g};${b}m"
}

$script:AnsiReset = "$([char]27)[0m"

# Default progressbar threshold colors (overridden by active theme at runtime)
$script:PbThresholds = @(
    [PSCustomObject]@{ upTo = 50;  fg = '#4ade80' },
    [PSCustomObject]@{ upTo = 80;  fg = '#facc15' },
    [PSCustomObject]@{ upTo = 100; fg = '#f87171' }
)

# Field keys that contain file-system paths (used by Truncate-Path in Format-Field)
$script:PathKeys = @('cwd', 'workspace.current_dir', 'workspace.project_dir')

<#
.SYNOPSIS
    Renders a percentage value as an ANSI-colored progress bar string.
.PARAMETER Value
    Numeric percentage (0–100). Values outside range are clamped.
.PARAMETER Style
    'normal' | 'color-coded'. Controls color behavior only.
.PARAMETER Fg
    Override foreground hex color (#rrggbb), or $null to use threshold color (color-coded only).
.PARAMETER Brackets
    Whether to wrap the bar in [ ]. Default: $true.
.PARAMETER Charset
    Character pair to use: 'block' (▓░) | 'solid' (█░) | 'circle' (●○) | 'square' (■□) | 'ascii' (#-).
.OUTPUTS
    ANSI-formatted string ready for stdout.
#>
function Format-ProgressBar {
    param(
        [double]$Value,
        [string]$Style,
        [string]$Fg,
        [bool]$Brackets = $true,
        [string]$Charset = 'block',
        [array]$Thresholds = $null    # optional array of {upTo, fg}; null = use script defaults
    )
    $pct    = [Math]::Min(100, [Math]::Max(0, $Value))
    $filled = [int][Math]::Round($pct / 10)
    $empty  = 10 - $filled

    # Character sets for filled/empty segments
    $charMap = @{
        'block'  = @('▓', '░')
        'solid'  = @('█', '░')
        'circle' = @('●', '○')
        'square' = @('■', '□')
        'ascii'  = @('#', '-')
    }
    $chars    = if ($charMap.ContainsKey($Charset)) { $charMap[$Charset] } else { $charMap['block'] }
    $fillStr  = $chars[0] * $filled
    $emptyStr = $chars[1] * $empty

    # Color: use Fg override if provided; otherwise apply threshold only for color-coded
    $color = if ($Fg) {
        $Fg
    } elseif ($Style -eq 'color-coded') {
        $activeThresholds = if ($null -ne $Thresholds) { $Thresholds } else { $script:PbThresholds }
        # Exclusive upper bound: pct=50 falls into the 50–79 range, not 0–49 (same semantics as JS renderFieldHtml)
        $matched = $activeThresholds | Where-Object { $pct -lt $_.upTo } | Select-Object -First 1
        if ($matched) { $matched.fg } else { ($activeThresholds | Select-Object -Last 1).fg }
    } else {
        $null
    }

    $inner = "${fillStr}${emptyStr}"
    $bar   = if ($Brackets) { "[${inner}] $([int]$pct)%" } else { "${inner} $([int]$pct)%" }

    if ($color) {
        return (ConvertTo-AnsiFg $color) + $bar + $script:AnsiReset
    }
    return $bar
}

<#
.SYNOPSIS
    Converts a total number of seconds into a human-readable duration string.
.PARAMETER TotalSeconds
    Non-negative integer number of seconds.
.PARAMETER Format
    'hours' → "75h 32m" | 'short' → "1d 4h 32m" | 'long' → "1d 4hr 32min"
.OUTPUTS
    Formatted duration string.
#>
function Format-Duration {
    param(
        [long]$TotalSeconds,
        [string]$Format
    )
    if ($TotalSeconds -lt 0) { $TotalSeconds = 0 }
    $totalMinutes = [long]($TotalSeconds / 60)
    $hours        = [long]($totalMinutes / 60)
    $minutes      = $totalMinutes % 60
    $days         = [long]($hours / 24)
    $remHours     = $hours % 24

    switch ($Format) {
        'hours' { return "${hours}h ${minutes}m" }
        'long'  {
            if ($days -gt 0) { return "${days}d ${remHours}hr ${minutes}min" }
            return "${hours}hr ${minutes}min"
        }
        default { # 'short'
            if ($days -gt 0) { return "${days}d ${remHours}h ${minutes}m" }
            return "${hours}h ${minutes}m"
        }
    }
}

<#
.SYNOPSIS
    Formats a raw field value according to its configured data type and format.
.PARAMETER Value
    The raw value retrieved from the JSON payload.
.PARAMETER DataType
    One of: string | currency | bool | number | unix_timestamp | duration
.PARAMETER Format
    Format variant string matching the data type (e.g. 'k', 'short', 'checkmark').
    For unix_timestamp: value is treated as future epoch; past timestamps display as '0h 0m'.
.PARAMETER FormatOptions
    PSCustomObject with extra options. Used for bool custom format: trueLabel, falseLabel.
.OUTPUTS
    Formatted string ready for display.
#>
function Format-FieldValue {
    param(
        [object]$Value,
        [string]$DataType,
        [string]$Format,
        [object]$FormatOptions
    )

    switch ($DataType) {
        'unix_timestamp' {
            if ($Format -eq 'raw') { return "$Value" }
            $remaining    = [DateTimeOffset]::FromUnixTimeSeconds([long]$Value) - [DateTimeOffset]::UtcNow
            $totalSeconds = [long]$remaining.TotalSeconds
            return Format-Duration -TotalSeconds $totalSeconds -Format $Format
        }
        'duration' {
            return Format-Duration -TotalSeconds ([long][double]$Value) -Format $Format
        }
        'number' {
            switch ($Format) {
                'k' { return "$([math]::Round([double]$Value / 1000))k" }
                'm' { return "$([math]::Round([double]$Value / 1000000))m" }
                default { return "$Value" }
            }
        }
        'currency' {
            $rounded = [math]::Round([double]$Value, 2)
            return $rounded.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        'bool' {
            $b = [bool]$Value
            switch ($Format) {
                'yes_no'    { if ($b) { return 'yes' }    else { return 'no' } }
                'checkmark' { if ($b) { return '✓' }      else { return '✗' } }
                'custom'    {
                    if ($null -eq $FormatOptions) { return "$Value" }
                    if ($b) { return $FormatOptions.trueLabel } else { return $FormatOptions.falseLabel }
                }
                default     { if ($b) { return 'true' }   else { return 'false' } }
            }
        }
        default { return "$Value" }
    }
}

<#
.SYNOPSIS
    Truncates a file system path to the last N segments, prepending "..." if segments
    were removed. Returns the original path unchanged if depth is null or the path
    has fewer or equal segments.
.PARAMETER Value
    The path string to truncate.
.PARAMETER Depth
    Number of trailing path segments to keep. Null or 0 returns the full path.
.OUTPUTS
    Truncated path string.
#>
function Truncate-Path {
    param(
        [string]$Value,
        [object]$Depth
    )
    if ($null -eq $Depth -or [int]$Depth -le 0) { return $Value }
    $n   = [int]$Depth
    $sep = if ($Value -match '\\') { '\' } else { '/' }
    $parts = $Value -split '[/\\]' | Where-Object { $_ -ne '' }
    if ($parts.Count -le $n) { return $Value }
    $trailing = ($parts | Select-Object -Last $n) -join $sep
    return '...' + $sep + $trailing
}

<#
.SYNOPSIS
    Renders a single field configuration object as an ANSI-formatted string.
.PARAMETER Field
    PSCustomObject with properties: type, key, text, fg, bg, progressStyle, dataType, format, formatOptions
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.OUTPUTS
    ANSI-formatted string, or empty string if the field value is not found.
#>
function Format-Field {
    param(
        [PSCustomObject]$Field,
        [PSCustomObject]$Data
    )

    $fgAnsi    = if ($Field.fg) { ConvertTo-AnsiFg $Field.fg } else { '' }
    $bgAnsi    = if ($Field.bg) { ConvertTo-AnsiBg $Field.bg } else { '' }
    $resetAnsi = if ($Field.fg -or $Field.bg) { $script:AnsiReset } else { '' }

    switch ($Field.type) {
        'static' {
            return "${fgAnsi}${bgAnsi}$($Field.text)${resetAnsi}"
        }
        'progressbar' {
            $value = Get-NestedValue $Data $Field.key
            if ($null -eq $value) { return '' }
            if ($Field.progressStyle -eq 'raw') {
                return "${fgAnsi}${bgAnsi}${value}${resetAnsi}"
            }

            # Resolve effective style, brackets and charset.
            # Supports old single-field schema ('block'/'slim') and new decomposed schema.
            $effectiveStyle    = 'color-coded'
            $effectiveBrackets = $true
            $effectiveCharset  = 'block'
            switch ($Field.progressStyle) {
                'block'  { $effectiveStyle = 'normal' }   # old value — brackets+block implied
                'slim'   { $effectiveStyle = 'normal'; $effectiveBrackets = $false; $effectiveCharset = 'solid' }
                'normal' { $effectiveStyle = 'normal' }
                default  { $effectiveStyle = 'color-coded' }
            }
            # New decomposed fields take precedence over style-derived defaults
            if ($null -ne $Field.barBrackets) { $effectiveBrackets = [bool]$Field.barBrackets }
            if ($Field.barCharset)            { $effectiveCharset  = $Field.barCharset }

            $bar = Format-ProgressBar -Value ([double]$value) -Style $effectiveStyle -Fg $Field.fg `
                                       -Brackets $effectiveBrackets -Charset $effectiveCharset `
                                       -Thresholds $script:PbThresholds
            if ($Field.bg) { return "${bgAnsi}${bar}${script:AnsiReset}" }
            return $bar
        }
        'new_fields_indicator' {
            if (-not $script:KnownKeys) { return '' }
            $allKeys = Get-AllKeys $Data ''
            $newKeys = $allKeys | Where-Object { $script:KnownKeys -notcontains $_ }
            $count   = ($newKeys | Measure-Object).Count
            if ($count -eq 0) { return '' }
            return "${fgAnsi}${bgAnsi}● ${count} neue Felder${resetAnsi}"
        }
        default {
            # type = 'field'
            $value = Get-NestedValue $Data $Field.key
            if ($null -eq $value -or "$value" -eq '') { return '' }
            $formatted = if ($Field.dataType) {
                Format-FieldValue -Value $value -DataType $Field.dataType -Format $Field.format -FormatOptions $Field.formatOptions
            } else {
                "$value"
            }
            # Apply path truncation for path-type fields when pathDepth is configured
            if ($Field.pathDepth -and $script:PathKeys -contains $Field.key) {
                $formatted = Truncate-Path -Value $formatted -Depth $Field.pathDepth
            }
            return "${fgAnsi}${bgAnsi}${formatted}${resetAnsi}"
        }
    }
}

<#
.SYNOPSIS
    Renders a full configured line (all its fields joined) as an ANSI string.
.PARAMETER Line
    PSCustomObject with a 'fields' array.
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.OUTPUTS
    ANSI-formatted string for one status bar line.
#>
function Format-Line {
    param(
        [PSCustomObject]$Line,
        [PSCustomObject]$Data
    )
    if (-not $Line.fields -or $Line.fields.Count -eq 0) { return '' }

    return ($Line.fields | ForEach-Object { Format-Field $_ $Data }) -join ''
}

<#
.SYNOPSIS
    Entry point. Reads config file and input JSON, renders all lines to stdout.
    Also persists the received payload to last-payload.json (next to the config file)
    for field discovery, and exposes config.knownKeys to $script:KnownKeys so that
    the new_fields_indicator field type can detect unknown keys within the same call.
.PARAMETER ConfigPath
    Full path to statusline-config.json. Defaults to the script's own directory.
.PARAMETER InputJson
    JSON string with Claude Code session data. Defaults to reading from stdin.
.OUTPUTS
    One rendered status line per configured line, written to stdout.
#>
function Invoke-Main {
    param(
        [string]$ConfigPath   = (Join-Path $PSScriptRoot 'statusline-config.json'),
        [string]$InputJson    = $null
    )

    # Read config
    if (-not (Test-Path $ConfigPath)) { return '' }
    $configJson = try { Get-Content -Path $ConfigPath -Raw -Encoding UTF8 } catch { return '' }
    $config     = try { $configJson | ConvertFrom-Json } catch { return '' }

    # Read input JSON (from parameter or stdin)
    if (-not $InputJson) {
        $InputJson = try { [Console]::In.ReadToEnd() } catch { '{}' }
    }
    $data = try { $InputJson | ConvertFrom-Json } catch { return '' }

    # Persist the received payload for field discovery (fail silently)
    try {
        $payloadPath = Join-Path (Split-Path $ConfigPath -Parent) 'last-payload.json'
        $InputJson | Set-Content -Path $payloadPath -Encoding UTF8
    } catch {
        # Silently ignore — writing the payload file is optional diagnostics only
    }

    # Expose knownKeys to script scope so Format-Field can access them for new_fields_indicator
    $script:KnownKeys = if ($config.knownKeys) { $config.knownKeys } else { $null }

    # Load active theme thresholds into script scope for Format-ProgressBar
    if ($config.activeTheme -and $config.themes) {
        $activeThemeObj = $config.themes | Where-Object { $_.id -eq $config.activeTheme } | Select-Object -First 1
        if ($activeThemeObj -and $activeThemeObj.progressThresholds) {
            $script:PbThresholds = $activeThemeObj.progressThresholds
        }
    }

    # Render each line
    $output = $config.lines | ForEach-Object { Format-Line $_ $data } | Where-Object { $_ -ne '' }
    return $output -join "`n"
}

# ─── Script entry point ───────────────────────────────────────────────────
# Only run when invoked directly (not when dot-sourced by tests)
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-Main
    if ($result) { Write-Output $result }
}
