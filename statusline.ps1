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
