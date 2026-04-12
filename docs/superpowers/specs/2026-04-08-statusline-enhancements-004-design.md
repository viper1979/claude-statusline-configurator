# Design: Statusline Enhancements 004

**Date:** 2026-04-08
**Branch:** feature/statusline-enhancements

---

## Overview

Three independent enhancements to `statusline.ps1` and `statusline-configurator.html`:

1. Number `auto` format — compact notation with k/m/b suffix
2. New Fields Indicator bug fix — parent container keys falsely reported as new
3. New progressbar charsets — `pipe` (▮▯) and `braille` (Braille patterns)

---

## 1. Number `auto` Format

### Goal

A new format variant for the `number` data type that automatically selects the right suffix based on magnitude. Always shows at most 3 significant digits.

### Behavior

| Value | Output |
|---|---|
| 456 | `456` |
| 32,768 | `33k` |
| 938,723,466 | `939m` |
| 12,000,000,000 | `12b` |

Logic: rounding (not truncation). Thresholds: `>= 1,000,000,000` → b, `>= 1,000,000` → m, `>= 1,000` → k, else raw integer.

### Deprecation of `k`, `m`, `b` fixed formats

The single-suffix formats `k`, `m`, `b` are deprecated. They are no longer exposed in the configurator UI. In `statusline.ps1` they silently fall back to `auto` behavior so existing configs continue to work. Configs are migrated naturally: the next time a field is saved in the configurator, `auto` is written.

### Changes

**`statusline.ps1` — `Format-FieldValue`, `'number'` branch:**

```powershell
'number' {
    switch ($Format) {
        { $_ -in 'k','m','b' } { $Format = 'auto'; continue }
        'auto' {
            $n = [double]$Value
            if ($n -ge 1000000000) { return "$([math]::Round($n / 1000000000))b" }
            if ($n -ge 1000000)    { return "$([math]::Round($n / 1000000))m" }
            if ($n -ge 1000)       { return "$([math]::Round($n / 1000))k" }
            return "$([int]$n)"
        }
        default { return "$Value" }
    }
}
```

**`statusline-configurator.html`:** Format dropdown for `number` data type shows only `auto` and raw (no format). Old values `k`/`m`/`b` are treated as `auto` on load and written as `auto` on save.

**Tests:** Add cases for `auto` format: below 1k, k-range, m-range, b-range.

---

## 2. New Fields Indicator Bug Fix

### Problem

`Get-AllKeys` returns both parent/container keys (e.g., `model`, `cost`, `rate_limits.five_hour`) and leaf keys. Since `knownKeys` only contains leaf-level keys, all container keys are falsely reported as new fields. With a typical Claude Code payload this produces "10 neue Felder" for 10 container objects.

The 10 false positives: `model`, `workspace`, `workspace.added_dirs`, `output_style`, `cost`, `context_window`, `context_window.current_usage`, `rate_limits`, `rate_limits.five_hour`, `rate_limits.seven_day`.

### Fix

**`Get-AllKeys`:** Only add a key to the result when its value is NOT a `PSCustomObject`. Container objects are recursed into but not added themselves.

```powershell
function Get-AllKeys {
    param([object]$Obj, [string]$Prefix = '')
    if ($null -eq $Obj) { return @() }
    $result = @()
    $Obj.PSObject.Properties | ForEach-Object {
        $key = if ($Prefix) { "$Prefix.$($_.Name)" } else { $_.Name }
        if ($_.Value -is [PSCustomObject]) {
            $result += Get-AllKeys $_.Value $key
        } else {
            $result += $key
        }
    }
    return $result
}
```

**`statusline-config.json`:** Add `workspace.added_dirs` to `knownKeys`.

### Behavior after fix

With a standard Claude Code payload: 0 neue Felder reported. The `new_fields_indicator` already returns `''` when count is 0 — no change needed there.

### Tests

Review existing `Get-AllKeys` tests — any test asserting that parent keys are returned needs to be updated to reflect leaf-only output.

---

## 3. New Progressbar Charsets

### `pipe` Charset (▮▯)

Straightforward addition to `$charMap` in `Format-ProgressBar`:

```powershell
'pipe' = @([char]0x25AE, [char]0x25AF)   # ▮ / ▯
```

Behaves identically to all other charsets. Supports `Brackets` and `Style` as usual.

### `braille` Charset

Uses four Braille Unicode characters. Positions 0 and 9 have special edge characters; positions 1–8 use standard fill/empty chars.

| Position | Empty | Filled |
|---|---|---|
| 0 (left edge) | `⣏` U+28CF | `⣿` U+28FF |
| 1–8 (inner) | `⣉` U+28C9 | `⣿` U+28FF |
| 9 (right edge) | `⣹` U+28F9 (always) | `⣹` U+28F9 (always) |

The right edge (position 9) is always `⣹` regardless of fill state. The left edge (position 0) shows `⣏` when empty and transitions to the regular fill char `⣿` once filled (Variant A).

Since this charset cannot use the generic `$charMap` pair approach, it is handled via a dedicated branch in `Format-ProgressBar` before the generic `$charMap` lookup.

The `Brackets` parameter is ignored for `braille` — the edge characters ⣏/⣹ already serve as visual frame. `Style` (normal/color-coded) and `Fg` work as usual.

**Visual reference:**

```
   0%  ⣏⣉⣉⣉⣉⣉⣉⣉⣉⣹
  30%  ⣿⣿⣿⣉⣉⣉⣉⣉⣉⣹
  70%  ⣿⣿⣿⣿⣿⣿⣿⣉⣉⣹
 100%  ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣹
```

### Changes

**`statusline.ps1` — `Format-ProgressBar`:** Add `pipe` to `$charMap`; add `braille` branch before `$charMap` lookup.

**`statusline-configurator.html`:** Add `pipe` and `braille` to the progressbar charset dropdown.

**Tests:** One test each for `pipe` and `braille` charset rendering.
