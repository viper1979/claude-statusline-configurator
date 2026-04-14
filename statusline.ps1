# statusline.ps1 — Claude Code custom status line
# Claude Code pipes the session JSON to stdin.
# Reads statusline-config.json from the same directory as this script.

Set-StrictMode -Off

# Ensure stdout is UTF-8 so non-ASCII characters (progressbar, etc.) survive the pipe to Claude Code
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

<#
.SYNOPSIS
    Writes a diagnostic message to statusline-error.log next to the script,
    and returns a short error string for display in the status bar.
.PARAMETER Message
    Human-readable description of what went wrong.
.OUTPUTS
    Short indicator string like "[❌ statusline] Config not found".
#>
function Write-StatuslineError {
    param([string]$Message)
    try {
        $logPath = Join-Path $PSScriptRoot 'statusline-error.log'
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding UTF8
    } catch {
        # Ignore log write failures
    }
    return "[❌ statusline] $Message"
}

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
        if ($_.Value -is [PSCustomObject]) {
            # Container object — recurse into children, do not add the parent key itself
            $result += Get-AllKeys $_.Value $key
        } else {
            # Leaf value (string, number, bool, array, null) — add directly
            $result += $key
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

# Path for new-fields log (set by Invoke-Main, overridable in tests via $script:NewFieldsLogPath)
$script:LogNewFields     = $false
$script:NewFieldsLogPath = $null

# Default progressbar threshold colors (overridden by active theme at runtime)
$script:PbThresholds = @(
    [PSCustomObject]@{ upTo = 50;  fg = '#4ade80' },
    [PSCustomObject]@{ upTo = 80;  fg = '#facc15' },
    [PSCustomObject]@{ upTo = 100; fg = '#f87171' }
)

# Field keys that contain file-system paths (used by Truncate-Path in Format-Field)
$script:PathKeys = @(
    'cwd',
    'transcript_path',
    'workspace.current_dir',
    'workspace.project_dir',
    'worktree.path',
    'worktree.original_cwd'
)

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
    Whether to wrap the bar in [ ]. Default: $true. Ignored for 'braille' charset (edge chars serve as visual frame).
.PARAMETER Charset
    Character pair to use: 'block' (▓░) | 'solid' (█░) | 'circle' (●○) | 'square' (■□) | 'ascii' (#-) | 'pipe' (▮▯) | 'braille' (⣿⣉, special edge chars).
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

    # Character sets for filled/empty segments.
    # Use Unicode code points instead of literals to avoid encoding issues when
    # PowerShell reads the script without a UTF-8 BOM (Windows default ANSI page).
    $charMap = @{
        'block'  = @([char]0x2593, [char]0x2591)   # ▓ / ░
        'solid'  = @([char]0x2588, [char]0x2591)   # █ / ░
        'circle' = @([char]0x25CF, [char]0x25CB)   # ● / ○
        'square' = @([char]0x25A0, [char]0x25A1)   # ■ / □
        'ascii'  = @('#', '-')
        'pipe'   = @([char]0x25AE, [char]0x25AF)   # ▮ / ▯
    }
    $chars    = if ($charMap.ContainsKey($Charset)) { $charMap[$Charset] } else { $charMap['block'] }
    $fillStr  = ([string]$chars[0]) * $filled
    $emptyStr = ([string]$chars[1]) * $empty

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

    # Braille charset — special edge characters at positions 0 and 9
    if ($Charset -eq 'braille') {
        $bEdgeL = [char]0x28CF   # ⣏ left edge when empty
        $bEdgeR = [char]0x28F9   # ⣹ right edge (always)
        $bFill  = [char]0x28FF   # ⣿ filled
        $bEmpty = [char]0x28C9   # ⣉ empty

        $inner = ''
        for ($i = 0; $i -lt 10; $i++) {
            if     ($i -lt $filled)     { $inner += $bFill  }
            elseif ($i -eq 9)           { $inner += $bEdgeR }
            elseif ($i -eq 0)           { $inner += $bEdgeL }
            else                        { $inner += $bEmpty }
        }
        # Brackets are ignored for braille — edge chars serve as the visual frame
        $bar = "$inner $([int]$pct)%"

        if ($color) {
            return (ConvertTo-AnsiFg $color) + $bar + $script:AnsiReset
        }
        return $bar
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
        [object]$TotalSeconds,   # object to prevent PowerShell binding error on non-numeric input
        [string]$Format
    )
    $TotalSeconds = try { [long][double]$TotalSeconds } catch { return '?' }
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
    One of: string | currency | bool | number | unix_timestamp | duration | duration_ms
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

    # Fallback for null values — use a sensible zero-value per data type
    if ($null -eq $Value) {
        switch ($DataType) {
            { $_ -in 'number','currency','duration','duration_ms' } { $Value = 0 }
            'unix_timestamp' { $Value = 0 }
            'bool'           { $Value = $false }
            default          { $Value = '' }
        }
    }

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
        'duration_ms' {
            # Value is in milliseconds (e.g. cost.total_duration_ms) — convert to seconds first
            return Format-Duration -TotalSeconds ([long]([double]$Value / 1000)) -Format $Format
        }
        'number' {
            # k, m, b are deprecated — fall back to auto
            $effectiveFormat = if ($Format -in @('k', 'm', 'b')) { 'auto' } else { $Format }
            switch ($effectiveFormat) {
                'auto' {
                    $n = [double]$Value
                    # [math]::Round uses MidpointRounding.ToEven (banker's rounding) — acceptable for display purposes
                    if ($n -ge 1000000000) { return "$([math]::Round($n / 1000000000))B" }
                    if ($n -ge 1000000)    { return "$([math]::Round($n / 1000000))M" }
                    if ($n -ge 1000)       { return "$([math]::Round($n / 1000))K" }
                    return "$([int]$n)"
                }
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

    # Priority chain: fgOverride flag > field-specific theme > global theme > none.
    # Missing fgOverride is treated as false so the theme color applies.
    $fieldTheme      = if ($Field.themeId -and $script:ThemesMap.ContainsKey($Field.themeId)) { $script:ThemesMap[$Field.themeId] } else { $null }
    $effectiveFgTheme = if ($fieldTheme) { $fieldTheme.fieldFg } else { $script:ThemeFg }
    $effectiveBgTheme = if ($fieldTheme) { $fieldTheme.fieldBg } else { $script:ThemeBg }
    $fgIsOverride = [bool]$Field.fgOverride
    $bgIsOverride = [bool]$Field.bgOverride
    $effectiveFg  = if ($fgIsOverride) { $Field.fg } elseif ($effectiveFgTheme) { $effectiveFgTheme } else { $null }
    $effectiveBg  = if ($bgIsOverride) { $Field.bg } elseif ($effectiveBgTheme) { $effectiveBgTheme } else { $null }

    $fgAnsi    = if ($effectiveFg) { ConvertTo-AnsiFg $effectiveFg } else { '' }
    $bgAnsi    = if ($effectiveBg) { ConvertTo-AnsiBg $effectiveBg } else { '' }
    $resetAnsi = if ($effectiveFg -or $effectiveBg) { $script:AnsiReset } else { '' }

    switch ($Field.type) {
        'static' {
            return "${fgAnsi}${bgAnsi}$($Field.text)${resetAnsi}"
        }
        'progressbar' {
            $value = Get-NestedValue $Data $Field.key
            # Default to 0 when value is missing so the bar renders at 0%
            if ($null -eq $value) { $value = 0 }
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

            # Log unknown key names to file when logging is enabled
            if ($script:LogNewFields -and $script:NewFieldsLogPath) {
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $keyList   = $newKeys -join ', '
                try {
                    "[$timestamp] $keyList" | Add-Content -Path $script:NewFieldsLogPath -Encoding UTF8
                } catch {
                    # Silently ignore log write failure
                }
            }

            return "${fgAnsi}${bgAnsi}● ${count} neue Felder${resetAnsi}"
        }
        default {
            # type = 'field'
            $value = Get-NestedValue $Data $Field.key

            # Special case: workspace.added_dirs is an array — display element count.
            # An empty array is unboxed to $null by the pipeline, so we apply @().Count
            # unconditionally to correctly yield 0 instead of an empty result.
            if ($Field.key -eq 'workspace.added_dirs') {
                $value = @($value).Count
            }

            if ($null -eq $value -or "$value" -eq '') {
                # Priority: field.placeholder > worktree.branch hardcoded > per-dataType default > hide
                if ($Field.PSObject.Properties.Name -contains 'placeholder' -and $null -ne $Field.placeholder) {
                    # Explicitly configured placeholder (null = not set; '' = hide field)
                    $ph = $Field.placeholder
                    if ($ph -eq '') { return '' }
                    return "${fgAnsi}${bgAnsi}${ph}${resetAnsi}"
                }
                if ($Field.key -eq 'worktree.branch') {
                    $value = 'none'
                } else {
                    $defaultPlaceholder = switch ($Field.dataType) {
                        'currency'       { '$0.00' }
                        'number'         { '0' }
                        'string'         { '--' }
                        'duration_ms'    { '--' }
                        'unix_timestamp' { '--' }
                        default          { $null }
                    }
                    if ($null -eq $defaultPlaceholder) { return '' }
                    return "${fgAnsi}${bgAnsi}${defaultPlaceholder}${resetAnsi}"
                }
            }
            $formatted = if ($Field.dataType) {
                try {
                    Format-FieldValue -Value $value -DataType $Field.dataType -Format $Field.format -FormatOptions $Field.formatOptions
                } catch {
                    # Misconfigured dataType for this field — return raw value rather than crashing
                    "$value"
                }
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
    Returns the visible character width of a string after stripping ANSI escape sequences.
.PARAMETER Text
    String possibly containing ANSI color codes (e.g. ESC[38;2;R;G;Bm).
.OUTPUTS
    Integer: number of visible characters.
#>
function Get-VisibleWidth {
    param([string]$Text)
    return ($Text -replace "`e\[[0-9;]*m", '').Length
}

<#
.SYNOPSIS
    Groups an array of field objects into column groups based on mergeWithNext flags.
.DESCRIPTION
    Walks fields left to right. A field with mergeWithNext=true is merged with the
    following field into the same group. Groups form the unit of column alignment.
.PARAMETER Fields
    Array of field PSCustomObjects from the config.
.OUTPUTS
    Array of arrays — each inner array is one group of fields.
#>
function Build-Groups {
    param([array]$Fields)
    if (-not $Fields -or $Fields.Count -eq 0) { return , @() }
    $groups  = [System.Collections.Generic.List[object]]::new()
    $current = [System.Collections.Generic.List[object]]::new()
    foreach ($field in $Fields) {
        $current.Add($field)
        if (-not $field.mergeWithNext) {
            $groups.Add($current.ToArray())
            $current = [System.Collections.Generic.List[object]]::new()
        }
    }
    # Safety: trailing mergeWithNext=true on last field
    if ($current.Count -gt 0) { $groups.Add($current.ToArray()) }
    return , $groups.ToArray()
}

<#
.SYNOPSIS
    Renders all configured lines with column alignment via two-pass rendering.
.DESCRIPTION
    Pass 1: Renders each group of fields per line and measures visible width.
    Pass 2: Pads each group to the maximum width of that group position across all lines.
    The last group in each line is never padded (no trailing whitespace).
.PARAMETER Lines
    Array of line config objects (each with a .fields array).
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.OUTPUTS
    All non-empty rendered lines joined by newline.
#>
function Format-Lines-Aligned {
    param(
        [array]$Lines,
        [PSCustomObject]$Data
    )

    # Pass 1: render all groups for all lines, measure visible widths
    $allLineGroups = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Lines) {
        if (-not $line.fields -or $line.fields.Count -eq 0) {
            $allLineGroups.Add(@())
            continue
        }
        $groups = Build-Groups $line.fields
        $renderedGroups = [System.Collections.Generic.List[string]]::new()
        foreach ($group in $groups) {
            $rendered = ($group | ForEach-Object { Format-Field $_ $Data }) -join ''
            $renderedGroups.Add($rendered)
        }
        $allLineGroups.Add($renderedGroups.ToArray())
    }

    # Pass 2: compute max visible width per group position
    $maxGroupCount = 0
    foreach ($rg in $allLineGroups) { if ($rg.Count -gt $maxGroupCount) { $maxGroupCount = $rg.Count } }
    $maxWidths = [int[]]::new([math]::Max(1, $maxGroupCount))
    for ($g = 0; $g -lt $maxGroupCount; $g++) {
        foreach ($renderedGroups in $allLineGroups) {
            if ($g -lt $renderedGroups.Count) {
                $w = Get-VisibleWidth $renderedGroups[$g]
                if ($w -gt $maxWidths[$g]) { $maxWidths[$g] = $w }
            }
        }
    }

    # Pass 3: apply padding and join
    $outputLines = [System.Collections.Generic.List[string]]::new()
    foreach ($renderedGroups in $allLineGroups) {
        if ($renderedGroups.Count -eq 0) { continue }
        # Skip line if all groups are empty strings (field returned nothing)
        if (($renderedGroups | Where-Object { (Get-VisibleWidth $_) -gt 0 } | Measure-Object).Count -eq 0) { continue }
        $lineParts = [System.Collections.Generic.List[string]]::new()
        for ($g = 0; $g -lt $renderedGroups.Count; $g++) {
            $text    = $renderedGroups[$g]
            $isLast  = $g -eq $renderedGroups.Count - 1
            $padding = if (-not $isLast) { $maxWidths[$g] - (Get-VisibleWidth $text) } else { 0 }
            $lineParts.Add($text + (' ' * [math]::Max(0, $padding)))
        }
        $outputLines.Add($lineParts -join '')
    }

    return $outputLines -join "`n"
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
        [string]$ScriptDir,        # Used to locate rate-limits-cache.json and the request-usage.ps1 plugin
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
}

<#
.SYNOPSIS
    Computes derived fields and injects them into $Data via Add-Member.
.DESCRIPTION
    General-purpose hook for all derived field computations. Computes:
    - context_window.cache_efficiency = cache_read_input_tokens / total_input_tokens * 100
    - context_window.used_tokens      = context_window_size * used_percentage / 100
    - context_window.remain_tokens    = context_window_size * remaining_percentage / 100
    Guards prevent computation when required inputs are null or zero.
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input (already enriched).
#>
function Compute-DerivedFields {
    param([PSCustomObject]$Data)

    # cache_efficiency = cache_read_input_tokens / total_input_tokens * 100
    $cacheRead  = Get-NestedValue $Data 'context_window.current_usage.cache_read_input_tokens'
    $totalInput = Get-NestedValue $Data 'context_window.total_input_tokens'
    if ($null -ne $cacheRead -and $null -ne $totalInput -and [double]$totalInput -gt 0) {
        $efficiency = [Math]::Round([double]$cacheRead / [double]$totalInput * 100, 1)
        $Data.context_window | Add-Member -NotePropertyName 'cache_efficiency' `
                                          -NotePropertyValue $efficiency -Force
    }

    # used_tokens = floor(context_window_size * used_percentage / 100)
    $ctxSize  = Get-NestedValue $Data 'context_window.context_window_size'
    $usedPct  = Get-NestedValue $Data 'context_window.used_percentage'
    if ($null -ne $ctxSize -and [double]$ctxSize -gt 0 -and $null -ne $usedPct) {
        $usedTokens = [math]::Floor([double]$ctxSize * [double]$usedPct / 100)
        $Data.context_window | Add-Member -NotePropertyName 'used_tokens' `
                                          -NotePropertyValue $usedTokens -Force
    }

    # remain_tokens = floor(context_window_size * remaining_percentage / 100)
    $remainPct = Get-NestedValue $Data 'context_window.remaining_percentage'
    if ($null -ne $ctxSize -and [double]$ctxSize -gt 0 -and $null -ne $remainPct) {
        $remainTokens = [math]::Floor([double]$ctxSize * [double]$remainPct / 100)
        $Data.context_window | Add-Member -NotePropertyName 'remain_tokens' `
                                          -NotePropertyValue $remainTokens -Force
    }
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
    if (-not (Test-Path $ConfigPath)) {
        return Write-StatuslineError "Config not found: $ConfigPath"
    }
    $configJson = try {
        Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    } catch {
        return Write-StatuslineError "Cannot read config: $_"
    }
    if ([string]::IsNullOrWhiteSpace($configJson)) {
        return Write-StatuslineError "Config file is empty: $ConfigPath"
    }
    $config = try {
        $configJson | ConvertFrom-Json
    } catch {
        return Write-StatuslineError "Config JSON invalid: $_"
    }

    # Read input JSON (from parameter or stdin)
    if (-not $InputJson) {
        $InputJson = try { [Console]::In.ReadToEnd() } catch { '{}' }
        if ([string]::IsNullOrWhiteSpace($InputJson)) { $InputJson = '{}' }
    }
    $data = try {
        $InputJson | ConvertFrom-Json
    } catch {
        return Write-StatuslineError "Input JSON invalid: $_"
    }

    # Auto-detect git branch via git command when not provided in JSON input.
    # Wrapped in try-catch because git might not be installed on this system.
    if (-not (Get-NestedValue $data 'worktree.branch')) {
        try {
            $detectedBranch = git rev-parse --abbrev-ref HEAD 2>$null
            if ($detectedBranch) {
                if (-not $data.worktree) {
                    $data | Add-Member -NotePropertyName 'worktree' -NotePropertyValue ([PSCustomObject]@{})
                }
                $data.worktree | Add-Member -NotePropertyName 'branch' -NotePropertyValue $detectedBranch -Force
            }
        } catch {
            # git not installed or not in a repo — silently ignore
        }
    }

    # Persist the received payload for field discovery (fail silently).
    # $payloadPath is computed before the write so the enrichment block below can use it.
    # The previous file at this path (from the last invocation) serves as a fallback
    # for rate_limits — it is read before we overwrite the file with the current stdin.
    $payloadPath = Join-Path (Split-Path $ConfigPath -Parent) 'last-payload.json'

    # Enrich rate_limits from fallback sources when stdin JSON lacks them.
    # Mirrors the worktree.branch auto-detection pattern above.
    # This runs before the payload write so that the previous last-payload.json
    # (which may contain rate_limits from an earlier full invocation) is still intact.
    if (-not (Get-NestedValue $data 'rate_limits')) {
        $scriptDir = $PSScriptRoot
        $rateLimits = Get-RateLimitsData -ScriptDir $scriptDir -LastPayloadPath $payloadPath
        if ($rateLimits) {
            $data | Add-Member -NotePropertyName 'rate_limits' -NotePropertyValue $rateLimits -Force
        }
    }

    # Compute derived fields (e.g., cache_efficiency) from enriched data
    Compute-DerivedFields -Data $data

    # Write enriched $data to last-payload.json so that rate_limits added from fallback
    # sources (cache, plugin) are preserved for the next invocation's source-1 lookup.
    try {
        $data | ConvertTo-Json -Depth 20 | Set-Content -Path $payloadPath -Encoding UTF8
    } catch {
        # Silently ignore — writing the payload file is optional diagnostics only
    }

    # Expose knownKeys to script scope so Format-Field can access them for new_fields_indicator
    $script:KnownKeys = if ($config.knownKeys) { $config.knownKeys } else { $null }

    # Configure new-fields logging from config
    $script:LogNewFields     = [bool]($config.logNewFields)
    $script:NewFieldsLogPath = Join-Path $PSScriptRoot 'statusline-new-fields.log'

    # Build a lookup map of all themes for per-field theme resolution
    $script:ThemesMap = @{}
    if ($config.themes) {
        foreach ($t in $config.themes) {
            $script:ThemesMap[$t.id] = $t
        }
    }

    # Load active theme colors and thresholds into script scope
    $script:ThemeFg = $null
    $script:ThemeBg = $null
    if ($config.activeTheme -and $config.themes) {
        $activeThemeObj = $config.themes | Where-Object { $_.id -eq $config.activeTheme } | Select-Object -First 1
        if ($activeThemeObj) {
            if ($activeThemeObj.progressThresholds) {
                $script:PbThresholds = $activeThemeObj.progressThresholds
            }
            # fieldFg/fieldBg apply to non-progressbar fields without an explicit override
            $script:ThemeFg = $activeThemeObj.fieldFg
            $script:ThemeBg = $activeThemeObj.fieldBg
        }
    }

    # Render each line — use two-pass column alignment unless explicitly disabled
    if ($config.columnAlignmentEnabled -ne $false) {
        return Format-Lines-Aligned $config.lines $data
    } else {
        $output = $config.lines | ForEach-Object { Format-Line $_ $data } | Where-Object { $_ -ne '' }
        return $output -join "`n"
    }
}

# ─── Script entry point ───────────────────────────────────────────────────
# Only run when invoked directly (not when dot-sourced by tests)
if ($MyInvocation.InvocationName -ne '.') {
    $result = try {
        Invoke-Main
    } catch {
        Write-StatuslineError "Unexpected error: $_"
    }
    if ($result) { Write-Output $result }
}
