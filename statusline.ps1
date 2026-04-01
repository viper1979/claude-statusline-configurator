# statusline.ps1 — Claude Code custom status line
# Claude Code pipes the session JSON to stdin.
# Reads statusline-config.json from the same directory as this script.

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

# Functions are added in Tasks 11-14

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

# Threshold colors (matches configurator JS constants)
$script:PbColorLow  = '#4ade80'   # green  — 0–49%
$script:PbColorMid  = '#facc15'   # yellow — 50–79%
$script:PbColorHigh = '#f87171'   # red    — 80–100%

<#
.SYNOPSIS
    Renders a percentage value as an ANSI-colored progress bar string.
.PARAMETER Value
    Numeric percentage (0–100). Values outside range are clamped.
.PARAMETER Style
    'block' | 'slim' | 'color-coded'
.PARAMETER Fg
    Override foreground hex color (#rrggbb), or $null to use threshold color (color-coded only).
.OUTPUTS
    ANSI-formatted string ready for stdout.
#>
function Format-ProgressBar {
    param(
        [double]$Value,
        [string]$Style,
        [string]$Fg
    )
    $pct    = [Math]::Min(100, [Math]::Max(0, $Value))
    $filled = [int][Math]::Round($pct / 10)
    $empty  = 10 - $filled

    # Color: use Fg override if provided; otherwise apply threshold only for color-coded
    $color = if ($Fg) {
        $Fg
    } elseif ($Style -eq 'color-coded') {
        if ($pct -lt 50) { $script:PbColorLow }
        elseif ($pct -lt 80) { $script:PbColorMid }
        else { $script:PbColorHigh }
    } else {
        $null
    }

    $bar = if ($Style -eq 'slim') {
        ('█' * $filled) + ('░' * $empty) + ' ' + [int]$pct + '%'
    } else {
        '[' + ('▓' * $filled) + ('░' * $empty) + '] ' + [int]$pct + '%'
    }

    if ($color) {
        return (ConvertTo-AnsiFg $color) + $bar + $script:AnsiReset
    }
    return $bar
}

<#
.SYNOPSIS
    Renders a single field configuration object as an ANSI-formatted string.
.PARAMETER Field
    PSCustomObject with properties: type, key, text, fg, bg, progressStyle
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
            $bar = Format-ProgressBar -Value ([double]$value) -Style ($Field.progressStyle ?? 'color-coded') -Fg $Field.fg
            if ($Field.bg) { return "${bgAnsi}${bar}${script:AnsiReset}" }
            return $bar
        }
        default {
            # type = 'field'
            $value = Get-NestedValue $Data $Field.key
            if ($null -eq $value -or "$value" -eq '') { return '' }
            return "${fgAnsi}${bgAnsi}${value}${resetAnsi}"
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
