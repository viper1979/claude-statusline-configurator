# Statusline Enhancements 004 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `auto` number format, fix false-positive "neue Felder" indicator, and add `pipe`/`braille` progressbar charsets to both the PowerShell script and the HTML configurator.

**Architecture:** Three independent enhancements. All PS logic lives in `statusline.ps1`; all UI in the single-file `statusline-configurator.html`. Tests are Pester 5.x in `tests/statusline.Tests.ps1`. Changes are TDD: failing test → implementation → passing test → commit.

**Tech Stack:** PowerShell 7 (pwsh), Pester 5.x, plain HTML/JS (no build step)

---

## Files

| File | Changes |
|---|---|
| `statusline.ps1` | Fix `Get-AllKeys` (leaf-only); add `auto` format + deprecation in `Format-FieldValue`; add `pipe` to `$charMap` and `braille` branch in `Format-ProgressBar` |
| `tests/statusline.Tests.ps1` | Add `Get-AllKeys` describe block; add `auto` number format tests; add `pipe`/`braille` charset tests |
| `statusline-config.json` | Add `workspace.added_dirs` to `knownKeys` |
| `statusline-configurator.html` | Update `DATATYPE_FORMATS.number`; migrate `FIELD_TYPE_DEFAULTS` k→auto; update `formatFieldValue` number case; add `pipe`/`braille` to `PB_CHARSETS` and charset UI array; update `makeProgressBar` for braille special logic |

---

## Task 1: Fix Get-AllKeys — leaf-only output

**Files:**
- Modify: `statusline.ps1:43-55`
- Modify: `tests/statusline.Tests.ps1` (append new Describe block)

### Background

`Get-AllKeys` currently adds both parent keys (e.g., `model`) and their children (e.g., `model.id`) to the result. Parent keys are never in `knownKeys`, so the `new_fields_indicator` falsely reports them as new fields. The fix: skip adding a key when its value is a `PSCustomObject` — recurse into it but don't add the key itself.

- [ ] **Step 1: Write failing tests for leaf-only behavior**

Append this new `Describe` block at the end of `tests/statusline.Tests.ps1`:

```powershell
Describe 'Get-AllKeys' {
    It 'returns leaf keys but not parent container objects' {
        $data = [PSCustomObject]@{
            model   = [PSCustomObject]@{ id = 'x'; display_name = 'Opus' }
            version = '1.0'
        }
        $keys = Get-AllKeys $data ''
        $keys | Should -Not -Contain 'model'
        $keys | Should -Contain 'model.id'
        $keys | Should -Contain 'model.display_name'
        $keys | Should -Contain 'version'
    }

    It 'returns nested leaf keys three levels deep' {
        $inner = [PSCustomObject]@{ used_percentage = 42 }
        $mid   = [PSCustomObject]@{ five_hour = $inner }
        $data  = [PSCustomObject]@{ rate_limits = $mid }
        $keys  = Get-AllKeys $data ''
        $keys | Should -Not -Contain 'rate_limits'
        $keys | Should -Not -Contain 'rate_limits.five_hour'
        $keys | Should -Contain 'rate_limits.five_hour.used_percentage'
    }

    It 'returns array and null values as leaf keys' {
        $data = [PSCustomObject]@{
            tags    = @('a', 'b')
            missing = $null
        }
        $keys = Get-AllKeys $data ''
        $keys | Should -Contain 'tags'
        $keys | Should -Contain 'missing'
    }

    It 'returns empty array for null input' {
        $keys = Get-AllKeys $null ''
        $keys | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run tests — verify the new tests FAIL**

```
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Expected: the three new `Get-AllKeys` tests fail because the current implementation includes parent keys.

- [ ] **Step 3: Fix Get-AllKeys in statusline.ps1**

Replace the body of `Get-AllKeys` (lines 43–55):

```powershell
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
```

- [ ] **Step 4: Run all tests — verify they all pass**

```
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Expected: all tests pass (was 26, now 30).

- [ ] **Step 5: Add workspace.added_dirs to knownKeys in statusline-config.json**

In `statusline-config.json`, find the `"knownKeys"` array (line 349). Add `"workspace.added_dirs"` after `"workspace.project_dir"`:

```json
"workspace.current_dir",
"workspace.project_dir",
"workspace.added_dirs",
"cwd",
```

- [ ] **Step 6: Commit**

```
git add statusline.ps1 tests/statusline.Tests.ps1 statusline-config.json
git commit -m "fix(statusline): Get-AllKeys returns leaf keys only, fix false new-fields indicator"
```

---

## Task 2: Number `auto` format in PowerShell

**Files:**
- Modify: `statusline.ps1:280-286` (`Format-FieldValue`, `'number'` branch)
- Modify: `tests/statusline.Tests.ps1` (append to `Describe 'Format-FieldValue'`)

### Background

Add `auto` format that selects k/m/b suffix by magnitude (rounding). Deprecate `k`, `m`, `b` as separate formats — they silently fall back to `auto` so existing configs keep working.

- [ ] **Step 1: Write failing tests**

Append these `It` blocks inside the existing `Describe 'Format-FieldValue'` block in `tests/statusline.Tests.ps1` (before the closing `}`):

```powershell
    It 'auto format returns raw integer below 1000' {
        Format-FieldValue -Value 456 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -Be '456'
    }

    It 'auto format rounds to k for thousands' {
        Format-FieldValue -Value 32768 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -Be '33k'
    }

    It 'auto format rounds to m for millions' {
        Format-FieldValue -Value 938723466 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -Be '939m'
    }

    It 'auto format rounds to b for billions' {
        Format-FieldValue -Value 12000000000 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -Be '12b'
    }

    It 'deprecated k format falls back to auto behavior' {
        Format-FieldValue -Value 5000 -DataType 'number' -Format 'k' -FormatOptions $null |
            Should -Be '5k'
    }

    It 'deprecated m format falls back to auto behavior' {
        Format-FieldValue -Value 5000000 -DataType 'number' -Format 'm' -FormatOptions $null |
            Should -Be '5m'
    }
```

- [ ] **Step 2: Run tests — verify the new tests FAIL**

```
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Expected: the 6 new `auto`/deprecated-fallback tests fail. Existing `k` and `m` tests still pass (they happen to produce the same output).

- [ ] **Step 3: Replace the 'number' branch in Format-FieldValue**

In `statusline.ps1`, replace the `'number'` switch arm (lines 281–286):

```powershell
        'number' {
            # k, m, b are deprecated — fall back to auto
            $effectiveFormat = if ($Format -in @('k', 'm', 'b')) { 'auto' } else { $Format }
            switch ($effectiveFormat) {
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

- [ ] **Step 4: Run all tests — verify they all pass**

```
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Expected: all tests pass (was 30, now 36).

- [ ] **Step 5: Commit**

```
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add auto number format with k/m/b suffix, deprecate fixed suffixes"
```

---

## Task 3: Number format in configurator HTML

**Files:**
- Modify: `statusline-configurator.html:1760` (`DATATYPE_FORMATS.number`)
- Modify: `statusline-configurator.html:416-418` (`FIELD_TYPE_DEFAULTS` — k entries)
- Modify: `statusline-configurator.html:2183-2188` (`formatFieldValue` number case)

### Background

The configurator's `DATATYPE_FORMATS` drives the format-selector UI. Replace k/m/b options with `auto`. Migrate `FIELD_TYPE_DEFAULTS` defaults from `k` to `auto`. Update `formatFieldValue` to handle `k`/`m`/`b` as deprecated fallbacks.

- [ ] **Step 1: Update DATATYPE_FORMATS.number**

In `statusline-configurator.html`, find line 1760:

```javascript
  number:         [['raw','Rohwert (12345678)'],['k','Tausend (12346k)'],['m','Millionen (12m)']],
```

Replace with:

```javascript
  number:         [['raw','Rohwert (12345678)'],['auto','Auto (456 / 33k / 939m / 12b)']],
```

- [ ] **Step 2: Migrate FIELD_TYPE_DEFAULTS k → auto**

In `statusline-configurator.html`, find lines 416–418:

```javascript
  'context_window.total_input_tokens':       { dataType: 'number',         format: 'k' },
  'context_window.total_output_tokens':      { dataType: 'number',         format: 'k' },
  'context_window.context_window_size':      { dataType: 'number',         format: 'k' },
```

Replace with:

```javascript
  'context_window.total_input_tokens':       { dataType: 'number',         format: 'auto' },
  'context_window.total_output_tokens':      { dataType: 'number',         format: 'auto' },
  'context_window.context_window_size':      { dataType: 'number',         format: 'auto' },
```

- [ ] **Step 3: Update formatFieldValue number case**

In `statusline-configurator.html`, find lines 2183–2188 (inside `formatFieldValue`):

```javascript
    case 'number': {
      const n = parseFloat(value);
      if (isNaN(n)) return String(value);
      if (format === 'k') return Math.round(n / 1000) + 'k';
      if (format === 'm') return Math.round(n / 1000000) + 'm';
```

Replace with:

```javascript
    case 'number': {
      const n = parseFloat(value);
      if (isNaN(n)) return String(value);
      // k, m, b are deprecated — fall back to auto
      const effectiveFormat = ['k', 'm', 'b'].includes(format) ? 'auto' : format;
      if (effectiveFormat === 'auto') {
        if (n >= 1_000_000_000) return Math.round(n / 1_000_000_000) + 'b';
        if (n >= 1_000_000)     return Math.round(n / 1_000_000) + 'm';
        if (n >= 1_000)         return Math.round(n / 1_000) + 'k';
        return String(Math.round(n));
      }
```

- [ ] **Step 4: Manual smoke test in browser**

Open `statusline-configurator.html` in a browser. Open a field with `dataType: number`. Verify:
- Format dropdown shows only "Rohwert" and "Auto"
- Selecting "Auto" and previewing shows compact notation (e.g., `33k` for token counts)
- Existing configs with `"format": "k"` load correctly and show the same output

- [ ] **Step 5: Commit**

```
git add statusline-configurator.html
git commit -m "feat(configurator): replace k/m/b number formats with auto, migrate defaults"
```

---

## Task 4: New charsets pipe and braille in PowerShell

**Files:**
- Modify: `statusline.ps1:165-174` (`Format-ProgressBar`, `$charMap` and charset resolution)
- Modify: `tests/statusline.Tests.ps1` (append to `Describe 'Format-ProgressBar'`)

### Background

`pipe` uses `▮`/`▯` and fits into the generic `$charMap`. `braille` requires special per-position logic (edge chars at positions 0 and 9) and must be handled before the generic charMap lookup. The `Brackets` parameter is ignored for `braille` — the edge chars ⣏/⣹ serve as the visual frame.

- [ ] **Step 1: Write failing tests**

Append these `It` blocks inside the existing `Describe 'Format-ProgressBar'` block:

```powershell
    It 'renders pipe charset with filled and empty characters' {
        $result = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'pipe'
        $result | Should -Match ([char]0x25AE)  # ▮ filled
        $result | Should -Match ([char]0x25AF)  # ▯ empty
    }

    It 'braille: left edge is edgeL char at 0 percent' {
        $result = Format-ProgressBar -Value 0 -Style 'normal' -Fg $null -Charset 'braille'
        $result[0] | Should -Be ([char]0x28CF)  # ⣏
    }

    It 'braille: left edge becomes fill char when first block is filled' {
        $result = Format-ProgressBar -Value 10 -Style 'normal' -Fg $null -Charset 'braille'
        $result[0] | Should -Be ([char]0x28FF)  # ⣿
    }

    It 'braille: right edge position is always edgeR char' {
        $result = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'braille'
        $result[9] | Should -Be ([char]0x28F9)  # ⣹
    }

    It 'braille: brackets parameter is ignored' {
        $withBrackets    = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'braille' -Brackets $true
        $withoutBrackets = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'braille' -Brackets $false
        $withBrackets | Should -Be $withoutBrackets
    }
```

- [ ] **Step 2: Run tests — verify the new tests FAIL**

```
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Expected: all 5 new charset tests fail. All existing tests still pass.

- [ ] **Step 3: Add pipe to $charMap and braille branch in Format-ProgressBar**

In `statusline.ps1`, inside `Format-ProgressBar`:

**3a — Add `pipe` to `$charMap`** (around line 171, after `'ascii'`):

```powershell
        'ascii'  = @('#', '-')
        'pipe'   = @([char]0x25AE, [char]0x25AF)   # ▮ / ▯
    }
```

**3b — Add braille branch** after the `$color = ...` block and before the `$inner = "${fillStr}${emptyStr}"` line. Insert this block:

```powershell
    # Braille charset — special edge characters at positions 0 and 9
    if ($Charset -eq 'braille') {
        $bEdgeL = [char]0x28CF   # ⣏ left edge when empty
        $bEdgeR = [char]0x28F9   # ⣹ right edge (always)
        $bFill  = [char]0x28FF   # ⣿ filled
        $bEmpty = [char]0x28C9   # ⣉ empty

        $inner = ''
        for ($i = 0; $i -lt 10; $i++) {
            if     ($i -eq 9)           { $inner += $bEdgeR }
            elseif ($i -lt $filled)     { $inner += $bFill  }
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
```

- [ ] **Step 4: Run all tests — verify they all pass**

```
pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Expected: all tests pass (was 36, now 41).

- [ ] **Step 5: Commit**

```
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add pipe and braille progressbar charsets"
```

---

## Task 5: New charsets in configurator HTML

**Files:**
- Modify: `statusline-configurator.html:2131-2137` (`PB_CHARSETS`)
- Modify: `statusline-configurator.html:1659-1664` (`charsets` UI array in `renderEditPanel`)
- Modify: `statusline-configurator.html:2147-2167` (`makeProgressBar`)

### Background

`pipe` just needs a new entry in `PB_CHARSETS` and in the UI charset array. `braille` needs the same UI entry, plus a special branch in `makeProgressBar` (mirrors the PS logic from Task 4). `makeProgressBar` for braille ignores `brackets` — it builds the bar character by character.

- [ ] **Step 1: Add pipe and braille to PB_CHARSETS**

In `statusline-configurator.html`, find lines 2131–2137:

```javascript
const PB_CHARSETS = {
  block:  ['▓', '░'],
  solid:  ['█', '░'],
  circle: ['●', '○'],
  square: ['■', '□'],
  ascii:  ['#', '-'],
};
```

Replace with:

```javascript
const PB_CHARSETS = {
  block:  ['▓', '░'],
  solid:  ['█', '░'],
  circle: ['●', '○'],
  square: ['■', '□'],
  ascii:  ['#', '-'],
  pipe:   ['▮', '▯'],
};
```

Note: `braille` is intentionally NOT in `PB_CHARSETS` — it is handled by a dedicated branch in `makeProgressBar`.

- [ ] **Step 2: Add pipe and braille to the charset UI array**

In `statusline-configurator.html`, find the `charsets` array (line ~1659):

```javascript
      const charsets = [
        ['block',  '▓░', 'Block'],
        ['solid',  '█░', 'Voll'],
```

Append `pipe` and `braille` before the closing `]`:

```javascript
      const charsets = [
        ['block',  '▓░', 'Block'],
        ['solid',  '█░', 'Voll'],
        ['circle', '●○', 'Kreis'],
        ['square', '■□', 'Quadrat'],
        ['ascii',  '#-', 'ASCII'],
        ['pipe',   '▮▯', 'Pipe'],
        ['braille', '⣿⣉', 'Braille'],
      ];
```

(Keep the existing entries between `solid` and `pipe` — only append the two new lines.)

- [ ] **Step 3: Add braille branch to makeProgressBar**

In `statusline-configurator.html`, inside `makeProgressBar` (line 2147), add a braille branch before the `const [fillCh, emptyCh]` line (line 2152):

```javascript
  // Braille charset — special edge characters at positions 0 and 9 (brackets ignored)
  if (charset === 'braille') {
    let inner = '';
    for (let i = 0; i < 10; i++) {
      if      (i === 9)      inner += '\u28F9';  // ⣹ right edge always
      else if (i < filled)   inner += '\u28FF';  // ⣿ filled
      else if (i === 0)      inner += '\u28CF';  // ⣏ left edge when empty
      else                   inner += '\u28C9';  // ⣉ empty
    }
    const bar = `${inner} ${Math.round(pct)}%`;
    return { bar, color };
  }

  const [fillCh, emptyCh] = PB_CHARSETS[charset] || PB_CHARSETS.block;
```

- [ ] **Step 4: Manual smoke test in browser**

Open `statusline-configurator.html`. Add or edit a progressbar field:
- Switch charset to "Pipe" → preview shows `▮▮▮▮▮▯▯▯▯▯ 50%`
- Switch charset to "Braille" → preview shows `⣿⣿⣿⣿⣿⣉⣉⣉⣉⣹ 50%`
- At 0%: braille shows `⣏⣉⣉⣉⣉⣉⣉⣉⣉⣹ 0%`
- Brackets checkbox has no effect on braille preview

- [ ] **Step 5: Commit**

```
git add statusline-configurator.html
git commit -m "feat(configurator): add pipe and braille progressbar charsets"
```
