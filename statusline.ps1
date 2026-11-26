# statusline.ps1 — Claude Code custom status line
# Claude Code pipes the session JSON to stdin.
# Reads statusline-config.json from the same directory as this script.

Set-StrictMode -Off

# Ensure stdin/stdout are UTF-8 so non-ASCII characters (progressbar, etc.) survive the pipe to Claude Code
# InputEncoding guards against corrupted stdin JSON when the host console runs on CP850/CP1252
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# Diagnostic mode: set CCSTATUSLINE_DIAG=1 to emit statusline-diag.log next to the script.
# Has zero impact on rendered output and no overhead when disabled.
$script:DiagMode = $env:CCSTATUSLINE_DIAG -eq '1'

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

# ─── Diagnostic Logging Helpers ───────────────────────────────────────────────
# All functions are no-ops unless $script:DiagMode is $true (CCSTATUSLINE_DIAG=1).

<#
.SYNOPSIS
    Returns the UTF-8 byte dump of a string as space-separated uppercase hex pairs.
.PARAMETER Text
    Input string to encode and dump.
.OUTPUTS
    String like "E2 96 93 20 E2 96 91"
#>
function Format-DiagHex {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
}

<#
.SYNOPSIS
    Returns a human-readable codepoint list for all non-ASCII characters in a string.
.PARAMETER Text
    Input string (ANSI sequences are stripped internally).
.OUTPUTS
    String like "U+2593 ▓  U+2591 ░" or "(ASCII only)"
#>
function Format-DiagCodepoints {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '(empty)' }
    $clean = $Text -replace "\x1b\[[0-9;]*m", ''
    $parts = [System.Collections.Generic.List[string]]::new()
    $i = 0
    while ($i -lt $clean.Length) {
        $ch = $clean[$i]
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $clean.Length -and [char]::IsLowSurrogate($clean[$i + 1])) {
            $cp    = [char]::ConvertToUtf32($ch, $clean[$i + 1])
            $glyph = "$ch$($clean[$i + 1])"
            $label = 'U+{0:X4} {1}' -f $cp, $glyph
            $parts.Add($label)
            $i += 2
        } else {
            if ([int][char]$ch -gt 0x7F) {
                $label = 'U+{0:X4} {1}' -f ([int][char]$ch), $ch
                $parts.Add($label)
            }
            $i++
        }
    }
    if ($parts.Count -eq 0) { return '(ASCII only)' }
    return $parts -join '  '
}

<#
.SYNOPSIS
    Collects environment and terminal information for a diagnostic snapshot.
.OUTPUTS
    Ordered hashtable of key=value pairs.
#>
function Get-DiagEnvInfo {
    $info = [ordered]@{}
    $info['PSVersion']    = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    $info['OS']           = if ($PSVersionTable.OS) { $PSVersionTable.OS } else { [System.Environment]::OSVersion.VersionString }
    $info['HostName']     = $Host.Name
    $info['HostVersion']  = $Host.Version
    # Console handle properties throw IOException when there is no real console (e.g. piped by Claude Code)
    $info['WindowWidth']  = try { [Console]::WindowWidth }             catch { '(no console)' }
    $info['BufferWidth']  = try { [Console]::BufferWidth }             catch { '(no console)' }
    $info['InputCP']      = try { [Console]::InputEncoding.CodePage }  catch { '(unavailable)' }
    $info['OutputCP']     = try { [Console]::OutputEncoding.CodePage } catch { '(unavailable)' }
    $info['OutputEncVar'] = try { $OutputEncoding.CodePage }           catch { '(unavailable)' }
    $info['WT_SESSION']   = if ($env:WT_SESSION)   { $env:WT_SESSION }   else { '(not set)' }
    $info['TERM_PROGRAM'] = if ($env:TERM_PROGRAM)  { $env:TERM_PROGRAM }  else { '(not set)' }
    $info['TERM']         = if ($env:TERM)          { $env:TERM }          else { '(not set)' }
    $info['ConEmuPID']    = if ($env:ConEmuPID)     { $env:ConEmuPID }     else { '(not set)' }
    $info['VSCODE_PID']   = if ($env:VSCODE_PID)    { $env:VSCODE_PID }    else { '(not set)' }
    # Windows Terminal font detection — read-only, silent on failure
    try {
        $wtPattern  = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json'
        $wtFile     = Get-Item -Path $wtPattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wtFile) {
            $wtJson = Get-Content -Path $wtFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
            $info['WT_DefaultFont'] = if ($wtJson.profiles.defaults.font.face) { $wtJson.profiles.defaults.font.face } else { '(not set)' }
        } else {
            $info['WT_DefaultFont'] = '(WT settings not found)'
        }
    } catch {
        $info['WT_DefaultFont'] = '(detection failed)'
    }
    return $info
}

<#
.SYNOPSIS
    Appends a labeled section with lines to statusline-diag.log. No-op when DiagMode is off.
.PARAMETER Section
    Section header label (e.g. 'Environment').
.PARAMETER Lines
    Array of content strings to write indented under the header.
#>
function Write-StatuslineDiag {
    param([string]$Section, [string[]]$Lines)
    if (-not $script:DiagMode) { return }
    try {
        $logPath = Join-Path $PSScriptRoot 'statusline-diag.log'
        $out = [System.Collections.Generic.List[string]]::new()
        $out.Add("  [$Section]")
        foreach ($l in $Lines) { $out.Add("    $l") }
        Add-Content -Path $logPath -Value $out -Encoding UTF8
    } catch { }
}

<#
.SYNOPSIS
    Writes the opening timestamp/marker block to statusline-diag.log. No-op when DiagMode is off.
#>
function Write-DiagHeader {
    if (-not $script:DiagMode) { return }
    try {
        $logPath = Join-Path $PSScriptRoot 'statusline-diag.log'
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sep = '═' * 60
        Add-Content -Path $logPath -Value @($sep, "DIAG $ts", $sep) -Encoding UTF8
    } catch { }
}

<#
.SYNOPSIS
    Writes the closing marker block to statusline-diag.log. No-op when DiagMode is off.
#>
function Write-DiagFooter {
    if (-not $script:DiagMode) { return }
    try {
        $logPath = Join-Path $PSScriptRoot 'statusline-diag.log'
        $sep = '═' * 60
        Add-Content -Path $logPath -Value @($sep, 'END DIAG', '') -Encoding UTF8
    } catch { }
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
        if ($null -ne $_.Value -and $_.Value.GetType().Name -eq 'PSCustomObject') {
            # Container object — recurse into children, do not add the parent key itself.
            # GetType().Name is used instead of -is [PSCustomObject] because Add-Member -Force
            # on native command output (e.g. git) wraps the value in a PSObject adapter that
            # falsely returns True for -is [PSCustomObject] even when the value is a String.
            $result += Get-AllKeys $_.Value $key
        } elseif ($null -ne $_.Value) {
            # Leaf value (string, number, bool, array) — add directly; skip null (container was absent)
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

$script:AnsiReset      = "$([char]27)[0m"

# Default progressbar threshold colors. New-RenderContext takes the active theme's
# thresholds instead when the theme defines any, and Format-Field takes a per-field
# theme's thresholds over both; Format-ProgressBar falls back to these.
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
    'worktree.original_cwd',
    'scratchpad_dir'
)

# Default labels for the 'ago' format of unix_timestamp fields.
# Overridable per field via formatOptions (see Get-FormatOption).
$script:AgoDefaults = @{
    pastPrefix   = 'vor '
    pastSuffix   = ''
    futurePrefix = 'in '
    futureSuffix = ''
    nowLabel     = 'gerade eben'
}

# Below this absolute delta the 'ago' format renders nowLabel instead of a duration.
# Fixed at 60s because Format-Duration has minute resolution — anything shorter
# would render as "vor 0h 0m" and look like a bug.
$script:AgoNowThresholdSeconds = 60

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
    'hours' → "75h 32m" | 'short' → "1d 4h 32m" | 'long' → "1d 4hr 32min" | 'days_hours' → "1d 23h" / "23h" | 'days_hours_pad' → "0d 23h"
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
    # Math::Truncate statt [long]-Cast, da PowerShell bei [long] kaufmännisch rundet
    # statt abzuschneiden (z.B. [long](145.73) ergibt 146 statt 145)
    $totalMinutes = [long][Math]::Truncate(($TotalSeconds / 60))
    $hours        = [long][Math]::Truncate(($totalMinutes / 60))
    $minutes      = $totalMinutes % 60
    $days         = [long][Math]::Truncate(($hours / 24))
    $remHours     = $hours % 24

    switch ($Format) {
        'hours' { return "${hours}h ${minutes}m" }
        'long'  {
            if ($days -gt 0) { return "${days}d ${remHours}hr ${minutes}min" }
            return "${hours}hr ${minutes}min"
        }
        'days_hours' {
            if ($days -gt 0) { return "${days}d ${remHours}h" }
            return "${hours}h"
        }
        'days_hours_pad' { return "${days}d ${remHours}h" }
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
    One of: string | currency | bool | number | unix_timestamp | duration_ms
.PARAMETER Format
    Format variant string matching the data type (e.g. 'k', 'short', 'checkmark').
    For unix_timestamp countdown formats: value is treated as future epoch; past timestamps display as '0h 0m'.
    For unix_timestamp local-time formats (local_time, local_datetime, local_short, custom): converts epoch
    to local timezone and formats it. 'custom' reads pattern from FormatOptions.customPattern.
    For unix_timestamp 'ago': reports the distance in both directions, see Format-Ago.
    A null unix_timestamp yields an empty string rather than epoch 0.
.PARAMETER FormatOptions
    PSCustomObject with extra options. Used for bool custom format: trueLabel, falseLabel.
    For unix_timestamp custom format: customPattern (.NET DateTime format string).
    For unix_timestamp 'ago' format: pastPrefix, pastSuffix, futurePrefix, futureSuffix, nowLabel.
.PARAMETER Now
    The instant that countdown and 'ago' formats measure against. Defaults to UtcNow;
    Format-Field passes the Render Context's Now so one render shares a single instant.
.OUTPUTS
    Formatted string ready for display.
#>
function Get-FormatOption {
    param(
        [object]$FormatOptions,
        [string]$Name,
        [string]$Default
    )
    # Property presence is checked explicitly so that a deliberately empty string
    # (e.g. an empty pastSuffix) is honored instead of falling back to the default.
    if ($null -ne $FormatOptions -and
        $FormatOptions.PSObject.Properties.Name -contains $Name -and
        $null -ne $FormatOptions.$Name) {
        return [string]$FormatOptions.$Name
    }
    return $Default
}

<#
.SYNOPSIS
    Renders a unix timestamp as an elapsed/upcoming duration with configurable labels.
.DESCRIPTION
    Unlike the countdown formats, which clamp past timestamps to '0h 0m', this format
    reports the distance in both directions:
      past   -> "{pastPrefix}1h 12m{pastSuffix}"     (default: "vor 1h 12m")
      future -> "{futurePrefix}1h 12m{futureSuffix}" (default: "in 1h 12m")
      < 60s  -> "{nowLabel}"                         (default: "gerade eben")
.PARAMETER UnixSeconds
    Epoch seconds of the event.
.PARAMETER FormatOptions
    Optional PSCustomObject with pastPrefix, pastSuffix, futurePrefix, futureSuffix, nowLabel.
.PARAMETER Now
    The instant the distance is measured from. Defaults to UtcNow.
.OUTPUTS
    Formatted string.
#>
function Format-Ago {
    param(
        [long]$UnixSeconds,
        [object]$FormatOptions,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    $deltaSeconds = [long]([DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds) - $Now).TotalSeconds

    if ([Math]::Abs($deltaSeconds) -lt $script:AgoNowThresholdSeconds) {
        return Get-FormatOption $FormatOptions 'nowLabel' $script:AgoDefaults.nowLabel
    }

    $magnitude = Format-Duration -TotalSeconds ([Math]::Abs($deltaSeconds)) -Format 'short'

    if ($deltaSeconds -lt 0) {
        $prefix = Get-FormatOption $FormatOptions 'pastPrefix' $script:AgoDefaults.pastPrefix
        $suffix = Get-FormatOption $FormatOptions 'pastSuffix' $script:AgoDefaults.pastSuffix
    } else {
        $prefix = Get-FormatOption $FormatOptions 'futurePrefix' $script:AgoDefaults.futurePrefix
        $suffix = Get-FormatOption $FormatOptions 'futureSuffix' $script:AgoDefaults.futureSuffix
    }
    return "${prefix}${magnitude}${suffix}"
}

function Format-FieldValue {
    param(
        [object]$Value,
        [string]$DataType,
        [string]$Format,
        [object]$FormatOptions,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    # A null timestamp means "the event never happened" (e.g. prompt_cache.last_miss_at
    # before the first cache miss). Rendering it as epoch 0 would show 01.01.1970, so
    # the field yields nothing instead and the caller's placeholder logic takes over.
    if ($null -eq $Value -and $DataType -eq 'unix_timestamp') { return '' }

    # Fallback for null values — use a sensible zero-value per data type
    if ($null -eq $Value) {
        switch ($DataType) {
            { $_ -in 'number','currency','duration_ms' } { $Value = 0 }
            'bool'           { $Value = $false }
            default          { $Value = '' }
        }
    }

    switch ($DataType) {
        'unix_timestamp' {
            if ($Format -eq 'ago') {
                return Format-Ago -UnixSeconds ([long]$Value) -FormatOptions $FormatOptions -Now $Now
            }
            if ($Format -in @('local_time', 'local_datetime', 'local_short', 'custom')) {
                $local = [DateTimeOffset]::FromUnixTimeSeconds([long]$Value).ToLocalTime().DateTime
                $pattern = switch ($Format) {
                    'local_time'     { 'HH:mm' }
                    'local_datetime' { 'dd.MM.yyyy HH:mm' }
                    'local_short'    { 'dd.MM. HH:mm' }
                    'custom'         {
                        if ($null -ne $FormatOptions -and $FormatOptions.customPattern) { $FormatOptions.customPattern }
                        else { '' }
                    }
                }
                if ([string]::IsNullOrEmpty($pattern)) { return "$Value" }
                # CurrentCulture ensures MMM/MMMM render in the user's language (e.g. "Jan"/"Januar" on de-DE)
                return $local.ToString($pattern, [System.Globalization.CultureInfo]::CurrentCulture)
            }
            if ($Format -eq 'raw') { return "$Value" }
            $remaining    = [DateTimeOffset]::FromUnixTimeSeconds([long]$Value) - $Now
            $totalSeconds = [long]$remaining.TotalSeconds
            return Format-Duration -TotalSeconds $totalSeconds -Format $Format
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
function Truncate-Text {
    param(
        [string]$Value,
        [int]$MaxLength
    )
    if ($MaxLength -le 0 -or $Value.Length -le $MaxLength) { return $Value }
    # Unicode code point instead of the literal char, so the script survives being
    # read without a UTF-8 BOM on the Windows ANSI code page.
    $ellipsis = [char]0x2026  # …
    if ($MaxLength -eq 1) { return "$ellipsis" }
    return $Value.Substring(0, $MaxLength - 1) + $ellipsis
}

<#
.SYNOPSIS
    Reads a field's raw value from the payload and applies key-specific normalization.
.DESCRIPTION
    Two payload keys do not mean literally what they contain:
    - workspace.added_dirs is an array; the status line shows its element count.
    - prompt_cache.hit_ratio is a 0..1 ratio; the status line shows it as a percentage
      so it shares formatting and progress-bar thresholds with the other percentages.
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.PARAMETER Key
    Dotted field key.
.OUTPUTS
    The normalized value, or $null when the key is absent.
#>
function Get-FieldRawValue {
    param(
        [PSCustomObject]$Data,
        [string]$Key
    )
    $value = Get-NestedValue $Data $Key

    switch ($Key) {
        'workspace.added_dirs' {
            # A missing key must count as 0. @($null).Count would be 1, so guard first;
            # the @() wrapper then keeps an empty array (unboxed by the pipeline) at 0.
            if ($null -eq $value) { return 0 }
            return @($value).Count
        }
        'prompt_cache.hit_ratio' {
            if ($null -eq $value) { return $null }
            return [Math]::Round([double]$value * 100, 1)
        }
        default { return $value }
    }
}

<#
.SYNOPSIS
    Renders one configured Field as an ANSI-colored string.
.DESCRIPTION
    Dispatches on Field.type (static, progressbar, effort, thinking_enabled,
    new_fields_indicator, plain field) and applies the color priority chain
    fgOverride > per-field theme > active theme > none.
.PARAMETER Field
    Field config object (type, key, dataType, format, colors, ...).
.PARAMETER Data
    Payload (PSCustomObject parsed from Claude Code's JSON input).
.PARAMETER Context
    Render Context from New-RenderContext (themes, thresholds, known keys, logging).
.OUTPUTS
    ANSI-formatted string, or '' when the Field renders nothing.
#>
function Format-Field {
    param(
        [PSCustomObject]$Field,
        [PSCustomObject]$Data,
        [hashtable]$Context
    )
    $ctx = Assert-RenderContext $Context

    # Priority chain: fgOverride flag > field-specific theme > global theme > none.
    # Missing fgOverride is treated as false so the theme color applies.
    $fieldTheme      = if ($Field.themeId -and $ctx.ThemesMap.ContainsKey($Field.themeId)) { $ctx.ThemesMap[$Field.themeId] } else { $null }
    $effectiveFgTheme = if ($fieldTheme) { $fieldTheme.fieldFg } else { $ctx.ThemeFg }
    $effectiveBgTheme = if ($fieldTheme) { $fieldTheme.fieldBg } else { $ctx.ThemeBg }
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
            $value = Get-FieldRawValue $Data $Field.key
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

            # Same chain as the other colors: an explicit fg replaces the threshold colors,
            # the field theme's thresholds replace the active theme's. A field theme without
            # thresholds yields $null, so Format-ProgressBar uses its defaults (as the preview does).
            $barFg         = if ($fgIsOverride) { $Field.fg } else { $null }
            $barThresholds = if ($fieldTheme) { $fieldTheme.progressThresholds } else { $ctx.PbThresholds }
            $bar = Format-ProgressBar -Value ([double]$value) -Style $effectiveStyle -Fg $barFg `
                                       -Brackets $effectiveBrackets -Charset $effectiveCharset `
                                       -Thresholds $barThresholds
            if ($Field.bg) { return "${bgAnsi}${bar}${script:AnsiReset}" }
            return $bar
        }
        'effort' {
            # Mapping tables use Unicode code points to avoid encoding issues
            # when the script is loaded without a UTF-8 BOM (Windows ANSI page).
            $symbolMap = @{
                low    = [char]0x25CB  # ○
                medium = [char]0x25D0  # ◐
                high   = [char]0x25CF  # ●
                xhigh  = [char]0x2B24  # ⬤
                max    = [char]0x25C9  # ◉
            }
            $shortMap = @{
                low    = 'L'
                medium = 'M'
                high   = 'H'
                xhigh  = 'XH'
                max    = 'X'
            }
            $raw = Get-NestedValue $Data 'effort.level'
            if ($null -eq $raw -or "$raw" -eq '') { return '' }
            $rawStr    = "$raw"
            $symbol    = if ($symbolMap.ContainsKey($rawStr)) { $symbolMap[$rawStr] } else { $rawStr[0] }
            $shortChar = if ($shortMap.ContainsKey($rawStr))  { $shortMap[$rawStr]  } else { $rawStr.ToUpper()[0] }
            $rendered  = switch ($Field.format) {
                'short'      { $shortChar }
                'symbol'     { "$symbol" }
                'icon+raw'   { "$symbol $rawStr" }
                'icon+short' { "$symbol $shortChar" }
                default      { $rawStr }  # 'raw' and unset both yield the plain string
            }
            return "${fgAnsi}${bgAnsi}${rendered}${resetAnsi}"
        }
        'effort_level' {
            # Deprecated: use field type 'effort' instead. Returns empty to avoid crashing old configs.
            if ($ctx.DeprecationWarned.Add('effort_level')) {
                try {
                    $logPath = Join-Path $PSScriptRoot 'statusline-error.log'
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Add-Content -Path $logPath -Value "[$ts] DEPRECATED: field type 'effort_level' found in config — rename to 'effort'" -Encoding UTF8
                } catch {}
            }
            return ''
        }
        'thinking_enabled' {
            $raw = Get-NestedValue $Data 'thinking.enabled'
            if ($null -eq $raw) { return '' }
            $isEnabled   = [bool]$raw
            $defaultTrue  = [char]::ConvertFromUtf32(0x1F4AD)  # 💭
            $defaultFalse = [char]0x25CB                       # ○
            $opts         = $Field.formatOptions
            $trueSym      = if ($opts -and $opts.trueSymbol)  { [string]$opts.trueSymbol }  else { $defaultTrue }
            $falseSym     = if ($opts -and $opts.falseSymbol) { [string]$opts.falseSymbol } else { $defaultFalse }
            $symbol    = if ($isEnabled) { $trueSym } else { $falseSym }
            $shortChar = if ($isEnabled) { 'T' } else { '-' }
            $rawStr    = if ($isEnabled) { 'true' } else { 'false' }
            $rendered  = switch ($Field.format) {
                'short'      { $shortChar }
                'symbol'     { "$symbol" }
                'icon+raw'   { "$symbol $rawStr" }
                'icon+short' { "$symbol $shortChar" }
                default      { $rawStr }  # 'raw' and unset both yield the plain string
            }
            return "${fgAnsi}${bgAnsi}${rendered}${resetAnsi}"
        }
        'new_fields_indicator' {
            if (-not $ctx.KnownKeys) { return '' }
            $allKeys = Get-AllKeys $Data ''
            $newKeys = $allKeys | Where-Object { $ctx.KnownKeys -notcontains $_ }
            $count   = ($newKeys | Measure-Object).Count
            if ($count -eq 0) { return '' }

            # Log unknown key names to file when logging is enabled
            if ($ctx.LogNewFields -and $ctx.NewFieldsLogPath) {
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $keyList   = $newKeys -join ', '
                try {
                    "[$timestamp] $keyList" | Add-Content -Path $ctx.NewFieldsLogPath -Encoding UTF8
                } catch {
                    # Silently ignore log write failure
                }
            }

            # Use Unicode code point instead of literal to avoid encoding issues when
            # PowerShell reads the script without a UTF-8 BOM (Windows default ANSI page).
            $bullet = [char]0x25CF
            return "${fgAnsi}${bgAnsi}${bullet} ${count} neue Felder${resetAnsi}"
        }
        default {
            # type = 'field'
            $value = Get-FieldRawValue $Data $Field.key

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
                    Format-FieldValue -Value $value -DataType $Field.dataType -Format $Field.format -FormatOptions $Field.formatOptions -Now $ctx.Now
                } catch {
                    # Misconfigured dataType for this field — return raw value rather than crashing
                    "$value"
                }
            } else {
                "$value"
            }
            # Path fields are shortened by segment count, every other field by character
            # count — one tool per field kind, never both on the same field.
            if ($script:PathKeys -contains $Field.key) {
                if ($Field.pathDepth) {
                    $formatted = Truncate-Path -Value $formatted -Depth $Field.pathDepth
                }
            } elseif ($Field.maxLength) {
                $formatted = Truncate-Text -Value $formatted -MaxLength ([int]$Field.maxLength)
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
    return ($Text -replace "\x1b\[[0-9;]*m", '').Length
}

<#
.SYNOPSIS
    Returns the Powerline separator glyph for the configured style.
.PARAMETER PowerlineConfig
    PSCustomObject from config.powerline (may be null — returns solid arrow as default).
.OUTPUTS
    String containing exactly the separator character(s).
#>
function Get-PowerlineSeparator {
    param([object]$PowerlineConfig)
    if (-not $PowerlineConfig -or -not $PowerlineConfig.separator) { return [char]0xE0B0 }
    switch ($PowerlineConfig.separator) {
        'solid'   { return [char]0xE0B0 }
        'thin'    { return [char]0xE0B1 }
        'slant'   { return [char]0xE0B8 }
        'rounded' { return [char]0xE0B4 }
        'custom'  {
            $c = "$($PowerlineConfig.separatorCustom)"
            if ([string]::IsNullOrEmpty($c)) { return [char]0xE0B0 }
            return $c
        }
        default   { return [char]0xE0B0 }
    }
}

<#
.SYNOPSIS
    Renders a single group of fields as a Powerline segment: body text + resolved segment bg.
.PARAMETER Group
    Array of field PSCustomObjects belonging to one mergeWithNext group.
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.PARAMETER DefaultBg
    Hex color used when no field in the group has an explicit bg override.
.PARAMETER Context
    Render Context from New-RenderContext.
.OUTPUTS
    PSCustomObject with properties: bg (hex string), body (ANSI string without separator).
#>
function Build-PowerlineSegment {
    param(
        [array]$Group,
        [PSCustomObject]$Data,
        [string]$DefaultBg,
        [hashtable]$Context
    )
    $ctx = Assert-RenderContext $Context

    # Segment bg = first field with an explicit bgOverride; fall back to defaultSegmentBg.
    $segBg = $null
    foreach ($f in $Group) {
        if ($f.bgOverride -and $f.bg -and "$($f.bg)" -ne '') { $segBg = $f.bg; break }
    }
    if (-not $segBg) { $segBg = $DefaultBg }

    $segBgAnsi = ConvertTo-AnsiBg $segBg
    # Fields without explicit bg inherit the segment bg via the theme path. The segment
    # gets its own copy of the Render Context so the caller's context stays untouched.
    $segCtx = $ctx.Clone()
    $segCtx.ThemeBg = $segBg

    $bodyParts = [System.Collections.Generic.List[string]]::new()
    foreach ($field in $Group) {
        $out = Format-Field $field $Data -Context $segCtx
        if ($out) {
            # Re-assert segment bg before each field to recover from prior field's reset.
            $bodyParts.Add($segBgAnsi + $out)
        }
    }

    return [PSCustomObject]@{ bg = $segBg; body = $bodyParts -join '' }
}

<#
.SYNOPSIS
    Renders a group of lines in Powerline style with inter-segment triangle separators.
.DESCRIPTION
    Mirrors Format-Line-Group but uses mergeWithNext groups as Powerline segments:
    each segment has a uniform bg, separated by a Nerd Font triangle glyph whose
    fg=prev.bg and bg=next.bg. The last segment ends with an end-cap triangle into
    terminal default. Cross-line column alignment is preserved via a two-pass width scan.
.PARAMETER Lines
    Array of line config objects in one alignment group.
.PARAMETER Data
    PSCustomObject parsed from Claude Code JSON input.
.PARAMETER Context
    Render Context from New-RenderContext.
.OUTPUTS
    Rendered string for all lines in this group, joined by newline.
#>
function Format-Line-Group-Powerline {
    param(
        [array]$Lines,
        [PSCustomObject]$Data,
        [hashtable]$Context
    )
    $ctx = Assert-RenderContext $Context

    $plConfig  = $ctx.PowerlineConfig
    $separator = Get-PowerlineSeparator $plConfig
    $defaultBg = if ($plConfig -and $plConfig.defaultSegmentBg) { "$($plConfig.defaultSegmentBg)" } else { '#444444' }

    # Pass 1: build segments per line
    $allLineSegments = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Lines) {
        if (-not $line.fields -or $line.fields.Count -eq 0) {
            $allLineSegments.Add([object[]]@())
            continue
        }
        $groups   = Build-Groups $line.fields
        $segments = [System.Collections.Generic.List[object]]::new()
        foreach ($group in $groups) {
            $seg = Build-PowerlineSegment $group $Data $defaultBg -Context $ctx
            # Only include segments with visible content (skip blank/empty groups)
            if ((Get-VisibleWidth $seg.body) -gt 0) { $segments.Add($seg) }
        }
        $allLineSegments.Add($segments.ToArray())
    }

    # Pass 2: measure max visible body width per segment position (alignment)
    $maxSegCount = 0
    foreach ($segs in $allLineSegments) {
        if ($segs -is [array] -and $segs.Count -gt $maxSegCount) { $maxSegCount = $segs.Count }
    }
    $maxWidths = [int[]]::new([math]::Max(1, $maxSegCount))
    for ($g = 0; $g -lt $maxSegCount; $g++) {
        foreach ($segs in $allLineSegments) {
            if ($segs -is [array] -and $g -lt $segs.Count) {
                $w = Get-VisibleWidth $segs[$g].body
                if ($w -gt $maxWidths[$g]) { $maxWidths[$g] = $w }
            }
        }
    }

    # Pass 3: assemble each line with padding inside segments + separator glyphs between them
    $outputLines = [System.Collections.Generic.List[string]]::new()
    foreach ($segs in $allLineSegments) {
        if (-not ($segs -is [array]) -or $segs.Count -eq 0) { continue }

        $sb = [System.Text.StringBuilder]::new()
        for ($i = 0; $i -lt $segs.Count; $i++) {
            $seg    = $segs[$i]
            $isLast = $i -eq $segs.Count - 1

            # Body
            [void]$sb.Append($seg.body)

            # Alignment padding rendered in segment bg so the background fills evenly
            $visW    = Get-VisibleWidth $seg.body
            $padding = if (-not $isLast) { $maxWidths[$i] - $visW } else { 0 }
            if ($padding -gt 0) {
                [void]$sb.Append((ConvertTo-AnsiBg $seg.bg) + (' ' * $padding))
            }

            # Separator glyph: fg=this.bg, bg=next.bg (or terminal default for end-cap)
            if (-not $isLast) {
                $nextBg = $segs[$i + 1].bg
                [void]$sb.Append("$($script:AnsiReset)$(ConvertTo-AnsiFg $seg.bg)$(ConvertTo-AnsiBg $nextBg)${separator}")
            } else {
                [void]$sb.Append("$($script:AnsiReset)$(ConvertTo-AnsiFg $seg.bg)${separator}$($script:AnsiReset)")
            }
        }

        $rendered = $sb.ToString()
        if ((Get-VisibleWidth $rendered) -gt 0) { $outputLines.Add($rendered) }
    }

    return $outputLines -join "`n"
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
    Groups line config objects into alignment groups based on mergeWithNext flags.
.DESCRIPTION
    Lines with mergeWithNext=true are chained with the following line into one group.
    Only lines in the same group share column alignment.
.PARAMETER Lines
    Array of line config PSCustomObjects.
.OUTPUTS
    Array of arrays — each inner array is one line group.
#>
function Build-LineGroups {
    param([array]$Lines)
    if (-not $Lines -or $Lines.Count -eq 0) { return , @() }
    $groups  = [System.Collections.Generic.List[object]]::new()
    $current = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Lines) {
        $current.Add($line)
        if (-not $line.mergeWithNext) {
            $groups.Add($current.ToArray())
            $current = [System.Collections.Generic.List[object]]::new()
        }
    }
    if ($current.Count -gt 0) { $groups.Add($current.ToArray()) }
    return , $groups.ToArray()
}

<#
.SYNOPSIS
    Renders a group of lines with two-pass column alignment.
.DESCRIPTION
    Contains the three-pass alignment logic (previously in Format-Lines-Aligned):
    Pass 1 renders field groups, Pass 2 measures max widths, Pass 3 pads and joins.
.PARAMETER Lines
    Array of line config objects in one alignment group.
.PARAMETER Data
    PSCustomObject parsed from Claude Code JSON input.
.PARAMETER Context
    Render Context from New-RenderContext.
.OUTPUTS
    Rendered string for all lines in this group, joined by newline.
#>
function Format-Line-Group {
    param(
        [array]$Lines,
        [PSCustomObject]$Data,
        [hashtable]$Context
    )
    $ctx = Assert-RenderContext $Context

    # Dispatch to Powerline renderer when renderStyle is set in the Render Context
    if ($ctx.RenderStyle -eq 'powerline') {
        return Format-Line-Group-Powerline $Lines $Data -Context $ctx
    }

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
            $rendered = ($group | ForEach-Object { Format-Field $_ $Data -Context $ctx }) -join ''
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
        if (($renderedGroups | Where-Object { (Get-VisibleWidth $_) -gt 0 } | Measure-Object).Count -eq 0) { continue }
        $lineParts = [System.Collections.Generic.List[string]]::new()
        for ($g = 0; $g -lt $renderedGroups.Count; $g++) {
            $text    = $renderedGroups[$g]
            $isLast  = $g -eq $renderedGroups.Count - 1
            $visW    = Get-VisibleWidth $text
            $padding = if (-not $isLast) { $maxWidths[$g] - $visW } else { 0 }
            $lineParts.Add($text + (' ' * [math]::Max(0, $padding)))
            if ($script:DiagMode) {
                $clean = $text -replace "\x1b\[[0-9;]*m", ''
                Write-StatuslineDiag 'Group-Trace' @(
                    "g=$g  visW=$visW  maxW=$($maxWidths[$g])  pad=$padding"
                    "strip: $clean"
                    "hex  : $(Format-DiagHex $clean)"
                    "cpnt : $(Format-DiagCodepoints $clean)"
                )
            }
        }
        $outputLines.Add($lineParts -join '')
    }

    return $outputLines -join "`n"
}

<#
.SYNOPSIS
    Renders all configured lines with column alignment via line groups.
.DESCRIPTION
    Groups lines by their mergeWithNext flags (Build-LineGroups), then runs
    two-pass alignment for each group independently (Format-Line-Group).
    Lines without mergeWithNext form single-line groups (no cross-line alignment).
.PARAMETER Lines
    Array of line config objects (each with a .fields array).
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.PARAMETER Context
    Render Context from New-RenderContext.
.OUTPUTS
    All non-empty rendered lines joined by newline.
#>
function Format-Lines-Aligned {
    param(
        [array]$Lines,
        [PSCustomObject]$Data,
        [hashtable]$Context
    )
    if (-not $Lines -or $Lines.Count -eq 0) { return '' }
    $ctx = Assert-RenderContext $Context

    $lineGroups = Build-LineGroups $Lines
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $lineGroups) {
        $result = Format-Line-Group $group $Data -Context $ctx
        if ($result) { $parts.Add($result) }
    }
    return $parts -join "`n"
}

<#
.SYNOPSIS
    Renders a full configured line (all its fields joined) as an ANSI string.
.PARAMETER Line
    PSCustomObject with a 'fields' array.
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input.
.PARAMETER Context
    Render Context from New-RenderContext.
.OUTPUTS
    ANSI-formatted string for one status bar line.
#>
function Format-Line {
    param(
        [PSCustomObject]$Line,
        [PSCustomObject]$Data,
        [hashtable]$Context
    )
    if (-not $Line.fields -or $Line.fields.Count -eq 0) { return '' }
    $ctx = Assert-RenderContext $Context

    return ($Line.fields | ForEach-Object { Format-Field $_ $Data -Context $ctx }) -join ''
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
    - context_window.cache_efficiency = prompt_cache.hit_ratio * 100, falling back to
      cache_read_input_tokens / total_input_tokens * 100 on payloads without prompt_cache
    - context_window.used_tokens      = context_window_size * used_percentage / 100
    - context_window.remain_tokens    = context_window_size * remaining_percentage / 100
    Guards prevent computation when required inputs are null or zero.
.PARAMETER Data
    PSCustomObject parsed from Claude Code's JSON input (already enriched).
#>
function Compute-DerivedFields {
    param([PSCustomObject]$Data)

    # cache_efficiency is the deprecated name of what Claude Code now reports natively as
    # prompt_cache.hit_ratio (a 0..1 ratio). The native value wins; the original
    # self-computed formula remains as a fallback for payloads without prompt_cache.
    $efficiency = $null
    $hitRatio   = Get-NestedValue $Data 'prompt_cache.hit_ratio'
    if ($null -ne $hitRatio) {
        $efficiency = [Math]::Round([double]$hitRatio * 100, 1)
    } else {
        $cacheRead  = Get-NestedValue $Data 'context_window.current_usage.cache_read_input_tokens'
        $totalInput = Get-NestedValue $Data 'context_window.total_input_tokens'
        if ($null -ne $cacheRead -and $null -ne $totalInput -and [double]$totalInput -gt 0) {
            $efficiency = [Math]::Round([double]$cacheRead / [double]$totalInput * 100, 1)
        }
    }
    if ($null -ne $efficiency -and $null -ne $Data.context_window) {
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
    Builds the Render Context: everything Format-Field derives from the config once per render.
.DESCRIPTION
    The Render Context replaces ambient script-scope state. It is built once by Invoke-Main
    before the first Field is rendered and passed explicitly down the rendering chain.
    Keys of the returned hashtable:
      ThemesMap         - hashtable theme.id -> theme object (per-field themeId lookup)
      ThemeFg / ThemeBg - fieldFg / fieldBg of the active theme, or $null
      PbThresholds      - progressThresholds of the active theme, or the script defaults
      KnownKeys         - config.knownKeys for new_fields_indicator, or $null
      LogNewFields      - [bool] config.logNewFields
      NewFieldsLogPath  - path of the new-fields log next to the script
      RenderStyle       - 'classic' or 'powerline'
      PowerlineConfig   - config.powerline, or $null
      DeprecationWarned - HashSet[string] of deprecation warnings already written this render
      Now               - [DateTimeOffset] instant that time-relative formats measure against
.PARAMETER Config
    Parsed statusline-config.json (PSCustomObject).
.PARAMETER Now
    The render's instant. Defaults to UtcNow; tests pass a fixed value for determinism.
.OUTPUTS
    Hashtable with the keys listed above.
#>
function New-RenderContext {
    param(
        [PSCustomObject]$Config,
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )

    $themesMap = @{}
    if ($Config.themes) {
        foreach ($t in $Config.themes) {
            $themesMap[$t.id] = $t
        }
    }

    $themeFg      = $null
    $themeBg      = $null
    $pbThresholds = $script:PbThresholds
    if ($Config.activeTheme -and $Config.themes) {
        $activeThemeObj = $Config.themes | Where-Object { $_.id -eq $Config.activeTheme } | Select-Object -First 1
        if ($activeThemeObj) {
            if ($activeThemeObj.progressThresholds) {
                $pbThresholds = $activeThemeObj.progressThresholds
            }
            # fieldFg/fieldBg apply to non-progressbar fields without an explicit override
            $themeFg = $activeThemeObj.fieldFg
            $themeBg = $activeThemeObj.fieldBg
        }
    }

    return @{
        ThemesMap         = $themesMap
        ThemeFg           = $themeFg
        ThemeBg           = $themeBg
        PbThresholds      = $pbThresholds
        KnownKeys         = if ($Config.knownKeys) { $Config.knownKeys } else { $null }
        LogNewFields      = [bool]($Config.logNewFields)
        NewFieldsLogPath  = Join-Path $PSScriptRoot 'statusline-new-fields.log'
        RenderStyle       = if ($Config.renderStyle) { "$($Config.renderStyle)" } else { 'classic' }
        PowerlineConfig   = $Config.powerline
        DeprecationWarned = [System.Collections.Generic.HashSet[string]]::new()
        Now               = $Now
    }
}

<#
.SYNOPSIS
    Guards the rendering chain against a missing Render Context.
.DESCRIPTION
    The rendering functions are plain (non-advanced) functions, so a forgotten -Context
    would silently bind nothing. Failing loudly here keeps the interface honest: there is
    no ambient fallback to script scope.
.PARAMETER Context
    Render Context from New-RenderContext.
.OUTPUTS
    The same hashtable, for assignment at the call site.
#>
function Assert-RenderContext {
    param(
        [hashtable]$Context
    )
    if (-not $Context) {
        throw 'Render Context is required — build it with New-RenderContext and pass -Context.'
    }
    return $Context
}

<#
.SYNOPSIS
    Entry point. Reads config file and input JSON, renders all lines to stdout.
    Also persists the received payload to last-payload.json (next to the config file)
    for field discovery, and builds the Render Context (New-RenderContext) so that
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

    # ─── Diagnostic: header + environment + config + input snapshot ───────────
    # Wrapped in try/catch: diagnostic failures must never abort the statusline render.
    if ($script:DiagMode) {
        try {
            Write-DiagHeader

            $envInfo  = Get-DiagEnvInfo
            $envLines = @($envInfo.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" })
            Write-StatuslineDiag 'Environment' $envLines

            $cfgHash = try {
                $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $ConfigPath -Raw -Encoding UTF8))
                )
                ($hashBytes | ForEach-Object { $_.ToString('X2') }) -join ''
            } catch { '(hash failed)' }
            Write-StatuslineDiag 'Config-Snapshot' @(
                "Path          = $ConfigPath"
                "SHA256        = $cfgHash"
                "barCharset    = $($config.barCharset)"
                "progressStyle = $($config.progressStyle)"
                "separator     = $($config.separator)"
                "colAlign      = $($config.columnAlignmentEnabled)"
                "activeTheme   = $($config.activeTheme)"
            )

            # Mask filesystem paths that could reveal the user's folder structure
            $maskedJson = $InputJson `
                -replace '"cwd"\s*:\s*"[^"]*"',             '"cwd": "(masked)"' `
                -replace '"transcript_path"\s*:\s*"[^"]*"', '"transcript_path": "(masked)"'
            Write-StatuslineDiag 'Input-JSON' @($maskedJson)
        } catch {
            Write-StatuslineDiag 'Diag-Failure' @("$_")
        }
    }
    # ─────────────────────────────────────────────────────────────────────────

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

    # Build the Render Context once (themes, thresholds, known keys, logging, render style);
    # the rendering chain receives it explicitly instead of reading script scope.
    $ctx = New-RenderContext -Config $config

    # Render each line — use two-pass column alignment unless explicitly disabled
    if ($config.columnAlignmentEnabled -ne $false) {
        return Format-Lines-Aligned $config.lines $data -Context $ctx
    } else {
        if ($ctx.RenderStyle -eq 'powerline') {
            $output = $config.lines | ForEach-Object { Format-Line-Group-Powerline @($_) $data -Context $ctx } | Where-Object { $_ -ne '' }
            return $output -join "`n"
        }
        $output = $config.lines | ForEach-Object { Format-Line $_ $data -Context $ctx } | Where-Object { $_ -ne '' }
        return $output -join "`n"
    }
}

# ─── Script entry point ───────────────────────────────────────────────────
# Only run when invoked directly (not when dot-sourced by tests)
if ($MyInvocation.InvocationName -ne '.') {
    $result = try {
        Invoke-Main
    } catch {
        Write-StatuslineError ("Unexpected error: {0} ({1}) at line {2}" -f $_.Exception.Message, $_.Exception.GetType().Name, $_.InvocationInfo.ScriptLineNumber)
    }
    if ($result) {
        if ($script:DiagMode) {
            $resultLines = $result -split "`n"
            $traceLines  = [System.Collections.Generic.List[string]]::new()
            for ($li = 0; $li -lt $resultLines.Count; $li++) {
                $raw   = $resultLines[$li]
                $clean = $raw -replace "\x1b\[[0-9;]*m", ''
                $traceLines.Add("line[$li]: rawLen=$($raw.Length)  visW=$($clean.Length)")
                $traceLines.Add("  hex: $(Format-DiagHex $clean)")
                $traceLines.Add("  cpt: $(Format-DiagCodepoints $clean)")
            }
            Write-StatuslineDiag 'Output-Trace' $traceLines.ToArray()
            Write-DiagFooter
        }
        Write-Output $result
    }
}
