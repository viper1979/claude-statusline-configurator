# Statusline Anpassungen 001 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit-Dialog für platzierte Felder, Datentyp-System mit Formatierung, wiederverwendbare Custom-Felder in der Palette, und PS JSON-Persistenz mit Erkennungsfeld für neue Keys.

**Architecture:** Das bestehende Field-Schema wird um `dataType`, `format`, `formatOptions` erweitert (rückwärtskompatibel). Eine neue PS-Funktion `Format-FieldValue` kapselt alle Typ-Formatierungen. Der bestehende 🎨-Popup wird durch einen Modal-Dialog mit 3 Tabs ersetzt. Custom-Felder und `knownKeys` werden als neue Root-Properties in `statusline-config.json` gespeichert.

**Tech Stack:** PowerShell 7+, Pester 5.x, Vanilla JS/HTML (kein Framework), Sortable.js 1.15.6

---

## File Map

| Datei | Änderung |
|---|---|
| `statusline.ps1` | Neue Funktionen: `Format-Duration`, `Format-FieldValue`, `Get-AllKeys`. Erweitert: `Format-Field` (dataType-Routing, new_fields_indicator). Erweitert: `Invoke-Main` (JSON-Persistenz, knownKeys-Scope) |
| `tests/statusline.Tests.ps1` | Neue Describe-Blöcke: `Format-FieldValue`, `Get-AllKeys`, `new_fields_indicator in Format-Field`, `Invoke-Main JSON persistence` |
| `statusline-configurator.html` | Neues HTML: Edit-Dialog (nach Zeile 219). Geändert: `renderFieldChip` (✏️ statt 🎨), `buildExportJson`, `loadConfig`, `initSortable` (onAdd). Entfernt: `openStylePopup`, `closePopup`, `applyPopup`, `addStaticFieldToClipboard`, `_popupContext`. Neue Funktionen: Edit-Dialog, Custom-Felder-Palette, Diagnose-Gruppe |

---

## Task 1: PS — Format-Duration + Format-FieldValue

**Files:**
- Modify: `statusline.ps1` (nach `Format-ProgressBar`, vor `Format-Field`, ca. Zeile 118)
- Modify: `tests/statusline.Tests.ps1` (neuer Describe-Block)

- [ ] **Schritt 1: Tests schreiben (fehlschlagend)**

Füge am Ende von `tests/statusline.Tests.ps1` (nach dem letzten `}`) ein:

```powershell
Describe 'Format-FieldValue' {
    It 'returns raw string for string type' {
        Format-FieldValue -Value 'claude-opus-4-6' -DataType 'string' -Format $null -FormatOptions $null |
            Should -Be 'claude-opus-4-6'
    }

    It 'formats currency rounded to 2 decimal places' {
        Format-FieldValue -Value 0.01234 -DataType 'currency' -Format $null -FormatOptions $null |
            Should -Be '0.01'
    }

    It 'formats currency with exactly 2 decimal places even for whole number' {
        Format-FieldValue -Value 5 -DataType 'currency' -Format $null -FormatOptions $null |
            Should -Be '5.00'
    }

    It 'formats number with k suffix' {
        Format-FieldValue -Value 12345 -DataType 'number' -Format 'k' -FormatOptions $null |
            Should -Be '12k'
    }

    It 'formats number with m suffix' {
        Format-FieldValue -Value 12000000 -DataType 'number' -Format 'm' -FormatOptions $null |
            Should -Be '12m'
    }

    It 'formats number raw' {
        Format-FieldValue -Value 42 -DataType 'number' -Format 'raw' -FormatOptions $null |
            Should -Be '42'
    }

    It 'formats bool true as true_false' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'true_false' -FormatOptions $null |
            Should -Be 'true'
    }

    It 'formats bool false as true_false' {
        Format-FieldValue -Value $false -DataType 'bool' -Format 'true_false' -FormatOptions $null |
            Should -Be 'false'
    }

    It 'formats bool as yes_no' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'yes_no' -FormatOptions $null |
            Should -Be 'yes'
        Format-FieldValue -Value $false -DataType 'bool' -Format 'yes_no' -FormatOptions $null |
            Should -Be 'no'
    }

    It 'formats bool as checkmark' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'checkmark' -FormatOptions $null |
            Should -Be '✓'
        Format-FieldValue -Value $false -DataType 'bool' -Format 'checkmark' -FormatOptions $null |
            Should -Be '✗'
    }

    It 'formats bool with custom labels' {
        $opts = [PSCustomObject]@{ trueLabel = 'aktiv'; falseLabel = 'inaktiv' }
        Format-FieldValue -Value $true  -DataType 'bool' -Format 'custom' -FormatOptions $opts | Should -Be 'aktiv'
        Format-FieldValue -Value $false -DataType 'bool' -Format 'custom' -FormatOptions $opts | Should -Be 'inaktiv'
    }

    It 'formats duration 5000 seconds as hours format: 1h 23m' {
        Format-FieldValue -Value 5000 -DataType 'duration' -Format 'hours' -FormatOptions $null |
            Should -Be '1h 23m'
    }

    It 'formats duration 90061 seconds as short format with days: 1d 1h 1m' {
        Format-FieldValue -Value 90061 -DataType 'duration' -Format 'short' -FormatOptions $null |
            Should -Be '1d 1h 1m'
    }

    It 'formats duration 90061 seconds as long format with days: 1d 1hr 1min' {
        Format-FieldValue -Value 90061 -DataType 'duration' -Format 'long' -FormatOptions $null |
            Should -Be '1d 1hr 1min'
    }

    It 'formats duration under 1 day as short without day prefix' {
        # 3661 seconds = 1h 1m
        Format-FieldValue -Value 3661 -DataType 'duration' -Format 'short' -FormatOptions $null |
            Should -Be '1h 1m'
    }

    It 'formats unix_timestamp as raw string' {
        Format-FieldValue -Value 1738857600 -DataType 'unix_timestamp' -Format 'raw' -FormatOptions $null |
            Should -Be '1738857600'
    }

    It 'formats unix_timestamp hours format as a time string matching pattern' {
        # Use a timestamp 2 hours and 5 minutes in the future
        $futureTs = [DateTimeOffset]::UtcNow.AddHours(2).AddMinutes(5).ToUnixTimeSeconds()
        $result = Format-FieldValue -Value $futureTs -DataType 'unix_timestamp' -Format 'hours' -FormatOptions $null
        $result | Should -Match '^\d+h \d+m$'
    }

    It 'returns raw string for unknown data type' {
        Format-FieldValue -Value 'anything' -DataType 'unknown_type' -Format $null -FormatOptions $null |
            Should -Be 'anything'
    }
}
```

- [ ] **Schritt 2: Tests ausführen — müssen fehlschlagen**

```powershell
cd D:\Development\ccstatusline
Invoke-Pester tests/statusline.Tests.ps1 -Output Minimal
```

Erwartet: Fehler wie `CommandNotFoundException: Format-FieldValue`

- [ ] **Schritt 3: Format-Duration und Format-FieldValue implementieren**

Füge in `statusline.ps1` nach `Format-ProgressBar` (nach Zeile 117, vor dem `<#` Kommentar von `Format-Field`) ein:

```powershell
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
                'custom'    { if ($b) { return $FormatOptions.trueLabel } else { return $FormatOptions.falseLabel } }
                default     { if ($b) { return 'true' }   else { return 'false' } }
            }
        }
        default { return "$Value" }
    }
}
```

- [ ] **Schritt 4: Tests ausführen — müssen grün sein**

```powershell
Invoke-Pester tests/statusline.Tests.ps1 -Output Minimal
```

Erwartet: Alle bisherigen Tests bestehen, alle neuen `Format-FieldValue`-Tests bestehen.

- [ ] **Schritt 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): Format-Duration and Format-FieldValue with data type formatting"
```

---

## Task 2: PS — Get-AllKeys + Format-Field erweitern

**Files:**
- Modify: `statusline.ps1` — `Get-AllKeys` hinzufügen, `Format-Field` switch erweitern
- Modify: `tests/statusline.Tests.ps1` — neue Describe-Blöcke

- [ ] **Schritt 1: Tests schreiben**

Füge am Ende von `tests/statusline.Tests.ps1` ein:

```powershell
Describe 'Get-AllKeys' {
    It 'returns top-level keys' {
        $data = [PSCustomObject]@{ version = '1.0'; cwd = '/tmp' }
        $result = Get-AllKeys $data ''
        $result | Should -Contain 'version'
        $result | Should -Contain 'cwd'
    }

    It 'returns nested keys with dot notation' {
        $inner = [PSCustomObject]@{ display_name = 'Opus' }
        $data  = [PSCustomObject]@{ model = $inner }
        $result = Get-AllKeys $data ''
        $result | Should -Contain 'model'
        $result | Should -Contain 'model.display_name'
    }

    It 'returns empty array for null input' {
        $result = Get-AllKeys $null ''
        $result.Count | Should -Be 0
    }
}

Describe 'Format-Field with dataType' {
    BeforeAll {
        $data = [PSCustomObject]@{
            cost = [PSCustomObject]@{ total_cost_usd = 0.01234 }
            model = [PSCustomObject]@{ display_name = 'Opus' }
        }
    }

    It 'formats field value using dataType=currency' {
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_cost_usd'; dataType='currency'; format=$null; formatOptions=$null; fg=$null; bg=$null
        }
        Format-Field $field $data | Should -Be '0.01'
    }

    It 'falls back to raw value when dataType is not set' {
        $field = [PSCustomObject]@{
            type='field'; key='model.display_name'; dataType=$null; format=$null; formatOptions=$null; fg=$null; bg=$null
        }
        Format-Field $field $data | Should -Be 'Opus'
    }
}

Describe 'new_fields_indicator in Format-Field' {
    BeforeAll {
        $script:KnownKeys = @('model.display_name', 'version')
        $data = [PSCustomObject]@{
            model   = [PSCustomObject]@{ display_name = 'Opus' }
            version = '1.0'
            newKey  = 'surprise'
        }
    }

    AfterAll {
        $script:KnownKeys = $null
    }

    It 'returns indicator string when new keys are present' {
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null }
        $result = Format-Field $field $data
        $result | Should -Match '●'
        $result | Should -Match 'neue'
    }

    It 'returns empty string when all keys are known' {
        $script:KnownKeys = @('model', 'model.display_name', 'version', 'newKey')
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null }
        Format-Field $field $data | Should -BeNullOrEmpty
    }
}
```

- [ ] **Schritt 2: Tests ausführen — müssen fehlschlagen**

```powershell
Invoke-Pester tests/statusline.Tests.ps1 -Output Minimal
```

Erwartet: Fehler bei `Get-AllKeys`, `Format-Field with dataType`, `new_fields_indicator`

- [ ] **Schritt 3: Get-AllKeys implementieren**

Füge in `statusline.ps1` vor `Get-NestedValue` (vor Zeile 20) ein:

```powershell
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
    param([object]$Obj, [string]$Prefix)
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
```

- [ ] **Schritt 4: Format-Field erweitern**

Ersetze in `statusline.ps1` den `default`-Block in `Format-Field` (Zeile 150–155):

```powershell
        default {
            # type = 'field'
            $value = Get-NestedValue $Data $Field.key
            if ($null -eq $value -or "$value" -eq '') { return '' }
            return "${fgAnsi}${bgAnsi}${value}${resetAnsi}"
        }
```

mit:

```powershell
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
            return "${fgAnsi}${bgAnsi}${formatted}${resetAnsi}"
        }
```

Aktualisiere auch den Doc-Kommentar von `Format-Field` (Zeile 121–128):

```powershell
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
```

- [ ] **Schritt 5: Tests ausführen**

```powershell
Invoke-Pester tests/statusline.Tests.ps1 -Output Minimal
```

Erwartet: Alle Tests grün.

- [ ] **Schritt 6: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): Get-AllKeys, dataType routing in Format-Field, new_fields_indicator"
```

---

## Task 3: PS — Invoke-Main JSON-Persistenz

**Files:**
- Modify: `statusline.ps1` — `Invoke-Main` um try/catch Persistenz-Block erweitern, `$script:KnownKeys` setzen
- Modify: `tests/statusline.Tests.ps1` — neuer Describe-Block

- [ ] **Schritt 1: Tests schreiben**

Füge am Ende von `tests/statusline.Tests.ps1` ein:

```powershell
Describe 'Invoke-Main JSON persistence' {
    BeforeAll {
        $configPath = Join-Path $TestDrive 'statusline-config.json'
        $config = @{
            lines = @(@{ fields = @(@{ type='field'; key='version'; fg=$null; bg=$null }) })
            knownKeys = @('version')
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $config -Encoding UTF8
    }

    It 'writes last-payload.json next to the config file' {
        $payloadPath = Join-Path $TestDrive 'last-payload.json'
        Invoke-Main -ConfigPath $configPath -InputJson '{"version":"1.0"}'
        Test-Path $payloadPath | Should -Be $true
        Get-Content $payloadPath -Raw | Should -Match '"version"'
    }

    It 'does not crash when the target directory is read-only' {
        # Simulate a write failure by providing an invalid path via a config in a read-only location.
        # We test this by using a config that points the script to a location it cannot write to.
        # The simplest safe approach: pass a config from a path whose sibling directory doesn't exist.
        $roConfig = Join-Path $TestDrive 'subdir' 'statusline-config.json'
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'subdir') -Force | Out-Null
        Set-Content -Path $roConfig -Value $config -Encoding UTF8
        # Even if writing fails, the function must return without throwing
        { Invoke-Main -ConfigPath $roConfig -InputJson '{"version":"1.0"}' } | Should -Not -Throw
    }

    It 'sets script:KnownKeys from config so new_fields_indicator works in same call' {
        $cfgWithIndicator = @{
            lines = @(@{ fields = @(@{ type='new_fields_indicator'; fg=$null; bg=$null }) })
            knownKeys = @('version')
        } | ConvertTo-Json -Depth 10
        $indicatorConfig = Join-Path $TestDrive 'indicator-config.json'
        Set-Content -Path $indicatorConfig -Value $cfgWithIndicator -Encoding UTF8
        # Input has 'version' (known) + 'extra' (unknown) → indicator fires
        $result = Invoke-Main -ConfigPath $indicatorConfig -InputJson '{"version":"1.0","extra":"new"}'
        $result | Should -Match '●'
    }
}
```

- [ ] **Schritt 2: Tests ausführen — müssen fehlschlagen**

```powershell
Invoke-Pester tests/statusline.Tests.ps1 -Output Minimal
```

Erwartet: Tests für `Invoke-Main JSON persistence` schlagen fehl (kein `last-payload.json`, kein KnownKeys-Support).

- [ ] **Schritt 3: Invoke-Main erweitern**

Ersetze in `statusline.ps1` den `Invoke-Main`-Body (Zeilen 195–209) mit:

```powershell
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

    # Render each line
    $output = $config.lines | ForEach-Object { Format-Line $_ $data } | Where-Object { $_ -ne '' }
    return $output -join "`n"
```

- [ ] **Schritt 4: Tests ausführen**

```powershell
Invoke-Pester tests/statusline.Tests.ps1 -Output Minimal
```

Erwartet: Alle Tests grün.

- [ ] **Schritt 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): JSON persistence in Invoke-Main, knownKeys scope for new_fields_indicator"
```

---

## Task 4: JS — FIELD_TYPE_DEFAULTS, Schema-Erweiterung, loadConfig, buildExportJson

**Files:**
- Modify: `statusline-configurator.html`
  - Nach `PERCENTAGE_KEYS` (nach Zeile 276): `FIELD_TYPE_DEFAULTS` hinzufügen
  - `state`-Init (Zeile 357): `customFields` hinzufügen
  - `loadConfig` (Zeile 639): neue Properties lesen
  - `buildExportJson` (Zeile 570): neue Properties schreiben
  - `initSortable` onAdd (Zeile 512): FIELD_TYPE_DEFAULTS auto-apply

- [ ] **Schritt 1: FIELD_TYPE_DEFAULTS einfügen**

Füge in `statusline-configurator.html` nach Zeile 276 (nach der `PERCENTAGE_KEYS`-Definition, vor `// Sample data shown in preview`) ein:

```javascript
// Default data type for each known field key.
// When a field is dragged from the palette, this mapping is applied automatically.
// The user can override the dataType/format in the Edit Dialog.
const FIELD_TYPE_DEFAULTS = {
  // Model
  'model.display_name':                      { dataType: 'string' },
  'model.id':                                { dataType: 'string' },
  // Cost
  'cost.total_cost_usd':                     { dataType: 'currency' },
  'cost.total_duration_ms':                  { dataType: 'duration',       format: 'short' },
  'cost.total_lines_added':                  { dataType: 'number',         format: 'raw' },
  'cost.total_lines_removed':                { dataType: 'number',         format: 'raw' },
  // Context Window
  'context_window.used_percentage':          { dataType: 'number',         format: 'raw' },
  'context_window.remaining_percentage':     { dataType: 'number',         format: 'raw' },
  'context_window.total_input_tokens':       { dataType: 'number',         format: 'k' },
  'context_window.total_output_tokens':      { dataType: 'number',         format: 'k' },
  'context_window.context_window_size':      { dataType: 'number',         format: 'k' },
  // Rate Limits
  'rate_limits.five_hour.used_percentage':   { dataType: 'number',         format: 'raw' },
  'rate_limits.seven_day.used_percentage':   { dataType: 'number',         format: 'raw' },
  // Workspace / Session
  'workspace.current_dir':                   { dataType: 'string' },
  'workspace.project_dir':                   { dataType: 'string' },
  'cwd':                                     { dataType: 'string' },
  'version':                                 { dataType: 'string' },
  'session_id':                              { dataType: 'string' },
  'agent.name':                              { dataType: 'string' },
  'vim.mode':                                { dataType: 'string' },
  // Worktree
  'worktree.name':                           { dataType: 'string' },
  'worktree.branch':                         { dataType: 'string' },
  'worktree.original_branch':                { dataType: 'string' },
};
```

- [ ] **Schritt 2: State um customFields erweitern**

Ersetze Zeile 357:

```javascript
const state = { lines: [] };
```

mit:

```javascript
const state = { lines: [], customFields: [] };
```

- [ ] **Schritt 3: loadConfig erweitern**

Ersetze in `loadConfig` (Zeile 645–657) den Body:

```javascript
  state.lines = json.lines.map(line => ({
    id:     generateId(),
    fields: (line.fields || []).map(f => ({
      id:            generateId(),
      type:          f.type || 'field',
      key:           f.key  || null,
      text:          f.text || '',
      fg:            f.fg   || null,
      bg:            f.bg   || null,
      progressStyle: f.progressStyle || 'color-coded',
    })),
  }));
```

mit:

```javascript
  state.lines = json.lines.map(line => ({
    id:     generateId(),
    fields: (line.fields || []).map(f => ({
      id:            generateId(),
      type:          f.type          || 'field',
      key:           f.key           || null,
      text:          f.text          || '',
      fg:            f.fg            || null,
      bg:            f.bg            || null,
      progressStyle: f.progressStyle || 'color-coded',
      dataType:      f.dataType      || null,
      format:        f.format        || null,
      formatOptions: f.formatOptions || null,
    })),
  }));

  state.customFields = (json.customFields || []).map(cf => ({
    id:    cf.id    || generateId(),
    label: cf.label || '',
    text:  cf.text  || '',
    fg:    cf.fg    || null,
    bg:    cf.bg    || null,
  }));
```

- [ ] **Schritt 4: buildExportJson erweitern**

Ersetze `buildExportJson` (Zeilen 570–583) komplett:

```javascript
function buildExportJson() {
  const lines = state.lines.map(line => ({
    fields: line.fields.map(f => {
      const base = { type: f.type };
      if (f.key)           base.key = f.key;
      if (f.text != null)  base.text = f.text;
      if (f.fg)            base.fg = f.fg;
      if (f.bg)            base.bg = f.bg;
      if (f.progressStyle && f.type === 'progressbar') base.progressStyle = f.progressStyle;
      if (f.dataType)      base.dataType = f.dataType;
      if (f.format)        base.format = f.format;
      if (f.formatOptions) base.formatOptions = f.formatOptions;
      return base;
    }),
  }));

  const customFields = state.customFields.map(cf => ({
    id: cf.id, label: cf.label, text: cf.text,
    fg: cf.fg || null, bg: cf.bg || null,
  }));

  // All keys from AVAILABLE_FIELDS — used by PS for new_fields_indicator
  const knownKeys = AVAILABLE_FIELDS.flatMap(g => g.items.map(i => i.key));

  return JSON.stringify({ lines, customFields, knownKeys }, null, 2);
}
```

- [ ] **Schritt 5: FIELD_TYPE_DEFAULTS auto-apply beim Drag**

Ersetze in `initSortable` den gesamten `onAdd`-Handler (Zeilen 507–530). Der neue Handler vereint alle Drag-Quellen:

```javascript
      onAdd(evt) {
        const panelFieldType     = evt.item?.dataset?.fieldType;
        const panelCustomFieldId = evt.item?.dataset?.customFieldId;
        const panelFieldKey      = evt.item?.dataset?.fieldKey;
        evt.item.remove();
        let newField;
        if (panelFieldType === 'new_fields_indicator') {
          // Diagnose palette item
          newField = { id: generateId(), type: 'new_fields_indicator', fg: null, bg: null };
          _draggedField = null;
        } else if (panelCustomFieldId) {
          // Custom-field clone from "Eigene Felder" palette → independent static copy
          const cf = state.customFields.find(f => f.id === panelCustomFieldId);
          if (!cf) return;
          newField = { id: generateId(), type: 'static', text: cf.text, fg: cf.fg, bg: cf.bg };
          _draggedField = null;
        } else if (panelFieldKey) {
          // Left-panel known field clone → apply FIELD_TYPE_DEFAULTS automatically
          const isPercentage = PERCENTAGE_KEYS.has(panelFieldKey);
          const defaults = FIELD_TYPE_DEFAULTS[panelFieldKey] || {};
          newField = isPercentage
            ? { id: generateId(), type: 'progressbar', key: panelFieldKey, progressStyle: 'color-coded', fg: null, bg: null }
            : { id: generateId(), type: 'field', key: panelFieldKey, fg: null, bg: null, ...defaults };
          _draggedField = null;
        } else {
          // Zone-to-zone chip move → use the field buffered by onRemove
          newField = _draggedField;
          _draggedField = null;
          if (!newField) return;
        }
        const line = state.lines.find(l => l.id === lineId);
        if (!line) return;
        const safeIndex = Math.min(evt.newIndex, line.fields.length);
        line.fields.splice(safeIndex, 0, newField);
        render();
      },
```

- [ ] **Schritt 6: Manuell im Browser verifizieren**

1. `statusline-configurator.html` im Browser öffnen
2. Ein Feld (z.B. "Total Cost") in eine Zeile ziehen
3. Im Export-Bereich prüfen: JSON enthält `"dataType": "currency"`
4. Eine Config-JSON-Datei mit `dataType` und `customFields` importieren — nach dem Laden sind die Felder korrekt geladen
5. Im Export enthält der JSON-Output `customFields: []` und `knownKeys: [...]`

- [ ] **Schritt 7: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): FIELD_TYPE_DEFAULTS, schema extension in loadConfig/buildExportJson"
```

---

## Task 5: Edit-Dialog HTML + JS-Grundgerüst

**Files:**
- Modify: `statusline-configurator.html`
  - HTML: neues Dialog-Overlay nach Zeile 219 (nach `</div>` des `styling-popup`)
  - JS: `openEditDialog`, `closeEditDialog`, `switchEditTab`, Dialog-State-Variablen

- [ ] **Schritt 1: Dialog-HTML einfügen**

Füge in `statusline-configurator.html` nach Zeile 219 (nach der schließenden `</div>` des `styling-popup`) ein:

```html
  <!-- Edit Dialog -->
  <div id="edit-dialog-overlay"
       style="display:none;position:fixed;inset:0;background:rgba(0,0,0,0.55);z-index:200;"
       onclick="closeEditDialog()"></div>
  <div id="edit-dialog"
       style="display:none;position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);
              background:var(--color-surface);border:1px solid var(--color-border);
              border-radius:var(--radius);z-index:201;min-width:360px;max-width:440px;
              box-shadow:0 8px 32px rgba(0,0,0,0.4);">
    <div style="padding:14px 20px;border-bottom:1px solid var(--color-border);">
      <div id="edit-dialog-title" style="font-weight:600;font-size:13px;"></div>
    </div>
    <div id="edit-dialog-tabs" style="display:flex;border-bottom:1px solid var(--color-border);">
      <button class="edit-tab-btn" data-tab="general"
              style="flex:1;padding:9px 4px;font-size:12px;border:none;background:none;
                     cursor:pointer;color:var(--color-text);border-bottom:2px solid transparent;"
              onclick="switchEditTab('general')">Allgemein</button>
      <button class="edit-tab-btn" data-tab="datatype"
              style="flex:1;padding:9px 4px;font-size:12px;border:none;background:none;
                     cursor:pointer;color:var(--color-text);border-bottom:2px solid transparent;"
              onclick="switchEditTab('datatype')">Datentyp</button>
      <button class="edit-tab-btn" data-tab="colors"
              style="flex:1;padding:9px 4px;font-size:12px;border:none;background:none;
                     cursor:pointer;color:var(--color-text);border-bottom:2px solid transparent;"
              onclick="switchEditTab('colors')">Farben</button>
    </div>
    <div style="padding:16px 20px;min-height:120px;">
      <div class="edit-tab-content" data-tab="general"  id="edit-tab-general"></div>
      <div class="edit-tab-content" data-tab="datatype" id="edit-tab-datatype" style="display:none;"></div>
      <div class="edit-tab-content" data-tab="colors"   id="edit-tab-colors"   style="display:none;"></div>
    </div>
    <div style="padding:12px 20px;border-top:1px solid var(--color-border);
                display:flex;justify-content:flex-end;gap:8px;">
      <button class="btn" onclick="closeEditDialog()">Abbrechen</button>
      <button class="btn btn-primary" onclick="saveEditDialog()">Speichern</button>
    </div>
  </div>
```

- [ ] **Schritt 2: Dialog-State-Variablen und Grundfunktionen hinzufügen**

Füge in `statusline-configurator.html` in der `<script>`-Sektion nach `let _draggedField = null;` (Zeile 667) ein:

```javascript
// ─── Edit Dialog ─────────────────────────────────────────────────────────

let _editCtx = null;  // { source: 'line'|'palette'|'palette-new', lineId, fieldId }
let _editDraft = null; // deep copy of the field being edited

function openEditDialog(source, lineId, fieldId) {
  let field;
  if (source === 'line') {
    const line = state.lines.find(l => l.id === lineId);
    if (!line) return;
    field = line.fields.find(f => f.id === fieldId);
    if (!field) return;
  } else if (source === 'palette') {
    field = state.customFields.find(f => f.id === fieldId);
    if (!field) return;
  } else if (source === 'palette-new') {
    // Creating a new custom field — start with a blank template
    field = { id: generateId(), label: '', text: '', fg: null, bg: null };
  }

  _editCtx   = { source, lineId, fieldId: field.id };
  _editDraft = JSON.parse(JSON.stringify(field));

  const title = source === 'palette-new'
    ? 'Neues Feld'
    : source === 'palette'
      ? `Palette: ${field.label || field.text || '?'}`
      : `Feld: ${fieldLabel(field)}`;
  document.getElementById('edit-dialog-title').textContent = title;

  // Show/hide Datentyp tab — only for line fields of type 'field'
  const isDatatypeVisible = source === 'line' && field.type === 'field';
  document.querySelector('.edit-tab-btn[data-tab="datatype"]').style.display =
    isDatatypeVisible ? '' : 'none';

  switchEditTab('general');
  document.getElementById('edit-dialog-overlay').style.display = '';
  document.getElementById('edit-dialog').style.display = '';
}

function closeEditDialog() {
  document.getElementById('edit-dialog-overlay').style.display = 'none';
  document.getElementById('edit-dialog').style.display = 'none';
  _editCtx   = null;
  _editDraft = null;
}

function switchEditTab(tab) {
  document.querySelectorAll('.edit-tab-btn').forEach(btn => {
    const active = btn.dataset.tab === tab;
    btn.style.borderBottomColor = active ? 'var(--color-accent)' : 'transparent';
    btn.style.color = active ? 'var(--color-accent)' : 'var(--color-text)';
  });
  document.querySelectorAll('.edit-tab-content').forEach(content => {
    content.style.display = content.dataset.tab === tab ? '' : 'none';
  });

  // Render the tab content when switching
  if (tab === 'general')  renderEditTabGeneral();
  if (tab === 'datatype') renderEditTabDatatype();
  if (tab === 'colors')   renderEditTabColors();
}

// Stubs — filled in Tasks 6 and 7
function renderEditTabGeneral()  { document.getElementById('edit-tab-general').textContent  = 'Allgemein'; }
function renderEditTabDatatype() { document.getElementById('edit-tab-datatype').textContent = 'Datentyp'; }
function renderEditTabColors()   { document.getElementById('edit-tab-colors').textContent   = 'Farben'; }
function saveEditDialog()        { closeEditDialog(); }
```

- [ ] **Schritt 3: Manuell im Browser verifizieren**

1. Datei im Browser öffnen
2. In der Browser-Konsole eingeben:
   ```javascript
   openEditDialog('palette-new', null, null)
   ```
3. Prüfen: Modal erscheint, Titel "Neues Feld", 3 Tabs sichtbar
4. Tabs anklicken — wechseln korrekt (aktiver Tab in Akzentfarbe)
5. "Abbrechen" schließt Dialog
6. `openEditDialog` auf `'line'` mit ungültiger ID aufrufen — kein Crash

- [ ] **Schritt 4: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): edit dialog HTML structure and open/close/tab-switching"
```

---

## Task 6: Edit-Dialog — Allgemein + Datentyp + Farben Tabs

**Files:**
- Modify: `statusline-configurator.html` — `renderEditTabGeneral`, `renderEditTabDatatype`, `renderEditTabColors` und `saveEditDialog` implementieren

- [ ] **Schritt 1: renderEditTabGeneral implementieren**

Ersetze den Stub `function renderEditTabGeneral() { ... }` mit:

```javascript
function renderEditTabGeneral() {
  const el = document.getElementById('edit-tab-general');
  const f  = _editDraft;
  if (!f) return;

  if (f.type === 'static' || _editCtx.source === 'palette' || _editCtx.source === 'palette-new') {
    // Editable: label (for palette) + text
    const showLabel = _editCtx.source !== 'line';
    el.innerHTML = `
      ${showLabel ? `
      <div style="margin-bottom:10px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Name in der Palette</div>
        <input id="edit-label" type="text" value="${escapeHtml(f.label || '')}"
               style="width:100%;box-sizing:border-box;padding:6px 8px;border-radius:4px;
                      border:1px solid var(--color-border);background:var(--color-surface-2);
                      color:var(--color-text);font-size:12px;">
      </div>` : ''}
      <div>
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Text</div>
        <input id="edit-text" type="text" value="${escapeHtml(f.text || '')}"
               style="width:100%;box-sizing:border-box;padding:6px 8px;border-radius:4px;
                      border:1px solid var(--color-border);background:var(--color-surface-2);
                      color:var(--color-text);font-size:12px;">
      </div>
    `;
  } else if (f.type === 'progressbar') {
    const styles = [
      ['block',       '[▓▓▓▓░░░░] 23%',  'Block'],
      ['slim',        '████░░░░ 23%',    'Slim'],
      ['color-coded', '[▓▓▓░░░░░] 23%',  'Farbkodiert (grün/gelb/rot)'],
    ];
    el.innerHTML = `
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:8px;">Progress Bar Stil</div>
      ${styles.map(([val, ex, lbl]) => `
        <label style="display:flex;align-items:center;gap:8px;font-size:12px;margin-bottom:6px;cursor:pointer;">
          <input type="radio" name="edit-pb-style" value="${val}"
                 ${(f.progressStyle || 'color-coded') === val ? 'checked' : ''}>
          <code style="font-size:11px;color:var(--color-text-muted);">${ex}</code>
          <span>${lbl}</span>
        </label>
      `).join('')}
    `;
  } else if (f.type === 'new_fields_indicator') {
    el.innerHTML = `
      <p style="font-size:12px;color:var(--color-text-muted);line-height:1.5;">
        Zeigt an, ob der aktuelle JSON-Payload Keys enthält, die dem Konfigurator noch unbekannt sind.<br>
        Beispielausgabe: <code>● 3 neue Felder</code>
      </p>
    `;
  } else {
    // type === 'field' — key is read-only
    el.innerHTML = `
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Key</div>
      <div style="padding:6px 8px;border-radius:4px;border:1px solid var(--color-border);
                  background:var(--color-surface-2);font-size:12px;color:var(--color-text-muted);">
        ${escapeHtml(f.key || '')}
      </div>
    `;
  }
}
```

- [ ] **Schritt 2: renderEditTabDatatype implementieren**

Ersetze den Stub `function renderEditTabDatatype() { ... }` mit:

```javascript
// Format options per data type
const DATATYPE_FORMATS = {
  string:          [],
  currency:        [],
  bool:            [['true_false','true / false'],['yes_no','yes / no'],['checkmark','✓ / ✗'],['custom','Benutzerdefiniert']],
  number:          [['raw','Rohwert (12345678)'],['k','Tausend (12346k)'],['m','Millionen (12m)']],
  unix_timestamp:  [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)'],['raw','Rohwert']],
  duration:        [['hours','Stunden (75h 32m)'],['short','Kurz (1d 4h 32m)'],['long','Lang (1d 4hr 32min)']],
};

function renderEditTabDatatype() {
  const el = document.getElementById('edit-tab-datatype');
  const f  = _editDraft;
  if (!f) return;

  const currentType   = f.dataType || 'string';
  const currentFormat = f.format   || '';
  const formats       = DATATYPE_FORMATS[currentType] || [];

  el.innerHTML = `
    <div style="margin-bottom:12px;">
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:4px;">Datentyp</div>
      <select id="edit-datatype"
              style="width:100%;padding:6px 8px;border-radius:4px;border:1px solid var(--color-border);
                     background:var(--color-surface-2);color:var(--color-text);font-size:12px;">
        ${Object.keys(DATATYPE_FORMATS).map(t =>
          `<option value="${t}" ${t === currentType ? 'selected' : ''}>${t}</option>`
        ).join('')}
      </select>
    </div>
    <div id="edit-format-section">
      ${renderFormatOptions(formats, currentFormat, currentType)}
    </div>
  `;

  document.getElementById('edit-datatype').addEventListener('change', (e) => {
    const newType    = e.target.value;
    const newFormats = DATATYPE_FORMATS[newType] || [];
    document.getElementById('edit-format-section').innerHTML =
      renderFormatOptions(newFormats, '', newType);
    if (newType === 'bool') wireBoolCustomLabels();
  });

  if (currentType === 'bool') wireBoolCustomLabels();
}

function renderFormatOptions(formats, currentFormat, dataType) {
  if (formats.length === 0) {
    return '<div style="font-size:12px;color:var(--color-text-muted);">Keine Format-Optionen verfügbar.</div>';
  }
  const opts = formats.map(([val, lbl]) => `
    <label style="display:flex;align-items:center;gap:8px;font-size:12px;margin-bottom:5px;cursor:pointer;">
      <input type="radio" name="edit-format" value="${val}"
             ${(!currentFormat && formats[0][0] === val) || currentFormat === val ? 'checked' : ''}>
      <span>${lbl}</span>
    </label>
  `).join('');

  const customSection = dataType === 'bool' ? `
    <div id="edit-custom-labels" style="display:none;margin-top:8px;padding-left:20px;">
      <div style="margin-bottom:6px;">
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:3px;">True-Label</div>
        <input id="edit-true-label" type="text"
               style="width:100%;box-sizing:border-box;padding:5px 8px;border-radius:4px;
                      border:1px solid var(--color-border);background:var(--color-surface-2);
                      color:var(--color-text);font-size:12px;">
      </div>
      <div>
        <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:3px;">False-Label</div>
        <input id="edit-false-label" type="text"
               style="width:100%;box-sizing:border-box;padding:5px 8px;border-radius:4px;
                      border:1px solid var(--color-border);background:var(--color-surface-2);
                      color:var(--color-text);font-size:12px;">
      </div>
    </div>
  ` : '';

  return `
    <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Format</div>
    <div id="edit-format-radios">${opts}</div>
    ${customSection}
  `;
}

// Wires the show/hide logic for the bool custom-label inputs.
// Must be called AFTER innerHTML is set (script tags inside innerHTML don't execute).
function wireBoolCustomLabels() {
  function toggle() {
    const checked = document.querySelector('[name="edit-format"]:checked');
    const sec = document.getElementById('edit-custom-labels');
    if (sec) sec.style.display = checked?.value === 'custom' ? '' : 'none';
  }
  document.querySelectorAll('[name="edit-format"]').forEach(r => r.addEventListener('change', toggle));
  toggle();
}
```

- [ ] **Schritt 3: renderEditTabColors implementieren**

Ersetze den Stub `function renderEditTabColors() { ... }` mit:

```javascript
function renderEditTabColors() {
  const el = document.getElementById('edit-tab-colors');
  const f  = _editDraft;
  if (!f) return;

  const fg = f.fg || '';
  const bg = f.bg || '';

  el.innerHTML = `
    <div style="margin-bottom:12px;">
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Vordergrundfarbe</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <input type="color" id="edit-fg" value="${fg || '#e0e0e0'}" style="cursor:pointer;">
        <label style="font-size:12px;cursor:pointer;display:flex;align-items:center;gap:4px;">
          <input type="checkbox" id="edit-fg-none" ${!fg ? 'checked' : ''}> Keine Farbe
        </label>
      </div>
    </div>
    <div>
      <div style="font-size:11px;color:var(--color-text-muted);margin-bottom:6px;">Hintergrundfarbe</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <input type="color" id="edit-bg" value="${bg || '#333333'}" style="cursor:pointer;">
        <label style="font-size:12px;cursor:pointer;display:flex;align-items:center;gap:4px;">
          <input type="checkbox" id="edit-bg-none" ${!bg ? 'checked' : ''}> Keine Farbe
        </label>
      </div>
    </div>
  `;
}
```

- [ ] **Schritt 4: saveEditDialog implementieren**

Ersetze den Stub `function saveEditDialog() { closeEditDialog(); }` mit:

```javascript
function saveEditDialog() {
  if (!_editCtx || !_editDraft) return;
  const { source, lineId } = _editCtx;

  // Read Allgemein tab values into draft
  const labelEl  = document.getElementById('edit-label');
  const textEl   = document.getElementById('edit-text');
  const pbRadio  = document.querySelector('[name="edit-pb-style"]:checked');
  if (labelEl) _editDraft.label = labelEl.value;
  if (textEl)  _editDraft.text  = textEl.value;
  if (pbRadio) _editDraft.progressStyle = pbRadio.value;

  // Read Datentyp tab values into draft (only when tab is visible)
  const typeEl = document.getElementById('edit-datatype');
  if (typeEl) {
    _editDraft.dataType = typeEl.value;
    const fmtRadio = document.querySelector('[name="edit-format"]:checked');
    _editDraft.format = fmtRadio ? fmtRadio.value : null;
    if (_editDraft.dataType === 'bool' && _editDraft.format === 'custom') {
      _editDraft.formatOptions = {
        trueLabel:  document.getElementById('edit-true-label')?.value  || '',
        falseLabel: document.getElementById('edit-false-label')?.value || '',
      };
    } else {
      _editDraft.formatOptions = null;
    }
  }

  // Read Farben tab values into draft
  const fgNone = document.getElementById('edit-fg-none')?.checked;
  const bgNone = document.getElementById('edit-bg-none')?.checked;
  _editDraft.fg = fgNone ? null : (document.getElementById('edit-fg')?.value || null);
  _editDraft.bg = bgNone ? null : (document.getElementById('edit-bg')?.value || null);

  // Apply draft to actual state
  if (source === 'line') {
    const line = state.lines.find(l => l.id === lineId);
    if (!line) { closeEditDialog(); return; }
    const idx = line.fields.findIndex(f => f.id === _editDraft.id);
    if (idx !== -1) Object.assign(line.fields[idx], _editDraft);
  } else if (source === 'palette') {
    const idx = state.customFields.findIndex(f => f.id === _editDraft.id);
    if (idx !== -1) Object.assign(state.customFields[idx], _editDraft);
  } else if (source === 'palette-new') {
    state.customFields.push(_editDraft);
  }

  closeEditDialog();
  render();
}
```

- [ ] **Schritt 5: Manuell im Browser verifizieren**

1. Öffne `statusline-configurator.html`
2. In der Konsole: `openEditDialog('palette-new', null, null)` — Dialog öffnet sich, Allgemein-Tab zeigt Label + Text Inputs
3. Text eingeben, "Speichern" — Dialog schließt ohne Fehler
4. Ein Feld in eine Zeile ziehen, dann in Konsole: `openEditDialog('line', state.lines[0].id, state.lines[0].fields[0].id)`
5. Datentyp-Tab öffnen — Dropdown zeigt verfügbare Typen, Format-Radio-Buttons erscheinen
6. Typ "bool" wählen, Format "custom" — True/False Label-Inputs erscheinen
7. Farben-Tab öffnen — Color-Picker sichtbar
8. "Speichern" — State wird aktualisiert, Export-JSON zeigt neue Werte

- [ ] **Schritt 6: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): edit dialog tab content — Allgemein, Datentyp, Farben, Speichern"
```

---

## Task 7: Altes Popup entfernen, ✏️-Button verdrahten

**Files:**
- Modify: `statusline-configurator.html`
  - HTML: `popup-overlay` und `styling-popup` Divs entfernen (Zeilen 210–219)
  - JS: `openStylePopup`, `closePopup`, `applyPopup`, `addStaticFieldToClipboard`, `_popupContext` entfernen
  - JS: `renderFieldChip` — 🎨 → ✏️, Aufruf auf `openEditDialog`
  - JS: `fieldLabel` — `new_fields_indicator` hinzufügen

- [ ] **Schritt 1: Altes Popup-HTML entfernen**

Lösche aus `statusline-configurator.html` die Zeilen 210–219 (die beiden Divs `popup-overlay` und `styling-popup` samt Kommentaren):

```html
  <!-- Popup overlay -->
  <div id="popup-overlay"
       style="display:none;position:fixed;inset:0;background:rgba(0,0,0,0.55);z-index:100;"
       onclick="closePopup()"></div>
  <!-- Styling popup -->
  <div id="styling-popup"
       style="display:none;position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);
              background:var(--color-surface);border:1px solid var(--color-border);
              border-radius:var(--radius);padding:20px;z-index:101;min-width:290px;max-width:340px;">
  </div>
```

- [ ] **Schritt 2: Altes JS entfernen**

Entferne aus `statusline-configurator.html` die folgenden Elemente komplett:

1. `let _popupContext = null;` (Zeile 666)
2. `function openStylePopup(lineId, fieldId) { ... }` (Zeilen 669–751)
3. `function closePopup() { ... }` (Zeilen 753–757)
4. `function applyPopup() { ... }` (Zeilen 759–784)
5. `function addStaticFieldToClipboard() { ... }` (Zeilen 388–402)

- [ ] **Schritt 3: renderFieldChip aktualisieren**

Ersetze in `renderFieldChip` (Zeile 450) den 🎨-Button:

```javascript
      <button class="btn-icon" title="Styling" onclick="openStylePopup('${lineId}','${field.id}')">🎨</button>
```

mit:

```javascript
      <button class="btn-icon" title="Bearbeiten" onclick="openEditDialog('line','${lineId}','${field.id}')">✏️</button>
```

- [ ] **Schritt 4: fieldLabel für new_fields_indicator erweitern**

Ersetze in `fieldLabel` (Zeile 456–467):

```javascript
function fieldLabel(field) {
  if (field.type === 'static') return `"${escapeHtml(field.text)}"`;
  if (field.type === 'field' || field.type === 'progressbar') {
    // Find label in AVAILABLE_FIELDS
    for (const g of AVAILABLE_FIELDS) {
      const found = g.items.find(i => i.key === field.key);
      if (found) return found.label;
    }
    return field.key;
  }
  return '?';
}
```

mit:

```javascript
function fieldLabel(field) {
  if (field.type === 'static')              return `"${escapeHtml(field.text)}"`;
  if (field.type === 'new_fields_indicator') return '● Neue Felder';
  if (field.type === 'field' || field.type === 'progressbar') {
    for (const g of AVAILABLE_FIELDS) {
      const found = g.items.find(i => i.key === field.key);
      if (found) return found.label;
    }
    return field.key;
  }
  return '?';
}
```

- [ ] **Schritt 5: Schaltfläche "Statisches Feld hinzufügen" im HTML entfernen oder anpassen**

Suche im HTML nach dem Button, der `addStaticFieldToClipboard()` aufruft (sollte irgendwo in der Toolbar/Header sein), und entferne ihn. Statische Felder werden nun über Custom-Felder in der Palette erstellt (Task 8).

```bash
grep -n "addStaticFieldToClipboard" statusline-configurator.html
```

Den gefundenen Button-HTML-Block entfernen.

- [ ] **Schritt 6: Manuell im Browser verifizieren**

1. Seite neu laden — kein JS-Fehler in der Konsole
2. Ein Feld in eine Zeile ziehen — Chip hat ✏️-Button statt 🎨
3. ✏️ anklicken — Edit-Dialog öffnet sich korrekt für das Feld
4. Alle 3 Tabs testen, Speichern und Abbrechen prüfen
5. State wird korrekt aktualisiert (Export-JSON)

- [ ] **Schritt 7: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): replace styling popup with edit dialog, wire pencil button"
```

---

## Task 8: Custom-Felder Palette

**Files:**
- Modify: `statusline-configurator.html`
  - `renderFieldsPanel`: Custom-Felder-Gruppe hinzufügen
  - `render()`: `renderFieldsPanel()` nach Änderungen neu aufrufen
  - `initSortable`: custom field drag handling
  - `renderFieldHtml`: `new_fields_indicator` in Preview

- [ ] **Schritt 1: renderCustomFieldsGroup implementieren**

Füge in `statusline-configurator.html` nach `renderFieldsPanel()` (nach Zeile 353) ein:

```javascript
function renderCustomFieldsGroup() {
  const tree = document.getElementById('fields-tree');

  // Remove existing custom group if present
  const existing = document.getElementById('custom-fields-group');
  if (existing) existing.remove();
  const existingHdr = document.getElementById('custom-fields-group-header');
  if (existingHdr) existingHdr.remove();

  const wrapper = document.createElement('div');
  wrapper.id = 'custom-fields-group';

  // Group header
  const header = document.createElement('div');
  header.id = 'custom-fields-group-header';
  header.style.cssText = 'font-size:10px;text-transform:uppercase;letter-spacing:0.06em;color:var(--color-text-muted);padding:8px 4px 4px;cursor:pointer;user-select:none;display:flex;align-items:center;gap:4px;';
  header.innerHTML = '<span class="group-arrow" style="display:inline-block;transition:transform 0.15s;">▶</span> Eigene Felder';

  const itemList = document.createElement('div');
  itemList.className = 'field-group-list';
  itemList.id = 'custom-fields-list';
  itemList.style.cssText = 'display:none;';

  header.addEventListener('click', () => {
    const open = itemList.style.display !== 'none';
    itemList.style.display = open ? 'none' : 'block';
    header.querySelector('.group-arrow').style.transform = open ? '' : 'rotate(90deg)';
  });

  // Render each custom field as a draggable item
  for (const cf of state.customFields) {
    const item = document.createElement('div');
    item.className = 'field-source';
    item.dataset.customFieldId = cf.id;
    item.style.cssText = 'padding:5px 8px;border-radius:4px;font-size:12px;cursor:grab;display:flex;align-items:center;gap:6px;transition:background 0.1s;';
    item.innerHTML = `
      <span style="color:var(--color-text-muted);font-size:10px;">⠿</span>
      <span style="flex:1;">${escapeHtml(cf.label || cf.text || '?')}</span>
      <button class="btn-icon" title="Bearbeiten" style="font-size:11px;"
              onclick="event.stopPropagation();openEditDialog('palette',null,'${cf.id}')">✏️</button>
      <button class="btn-icon" title="Löschen" style="font-size:11px;"
              onclick="event.stopPropagation();deleteCustomField('${cf.id}')">🗑️</button>
    `;
    item.addEventListener('mouseenter', () => item.style.background = 'var(--color-surface-2)');
    item.addEventListener('mouseleave', () => item.style.background = '');
    itemList.appendChild(item);
  }

  // "+ Neues Feld" button
  const addBtn = document.createElement('button');
  addBtn.className = 'btn';
  addBtn.style.cssText = 'width:100%;margin-top:4px;font-size:11px;padding:4px 8px;';
  addBtn.textContent = '+ Neues Feld';
  addBtn.onclick = () => openEditDialog('palette-new', null, null);
  itemList.appendChild(addBtn);

  wrapper.appendChild(header);
  wrapper.appendChild(itemList);
  tree.appendChild(wrapper);
}

function deleteCustomField(cfId) {
  state.customFields = state.customFields.filter(f => f.id !== cfId);
  render();
}
```

- [ ] **Schritt 2: render() um renderCustomFieldsGroup erweitern**

Ersetze `render()` (Zeile 406–411):

```javascript
function render() {
  renderLines();
  renderPreview();
  updateExportTextarea();
  document.getElementById('btn-add-line').disabled = state.lines.length >= 10;
}
```

mit:

```javascript
function render() {
  renderLines();
  renderPreview();
  updateExportTextarea();
  document.getElementById('btn-add-line').disabled = state.lines.length >= 10;
  renderCustomFieldsGroup();
}
```

- [ ] **Schritt 3: initSortable — Custom Field Drag handling**

Der `onAdd`-Handler wurde bereits in Task 4 Schritt 5 vollständig ersetzt und unterstützt `panelCustomFieldId` bereits. Kein weiterer Code nötig — weiter mit Schritt 4.

- [ ] **Schritt 4: renderFieldHtml — new_fields_indicator in Preview**

Füge in `renderFieldHtml` (nach `if (field.type === 'static')`) einen neuen Block hinzu:

```javascript
  if (field.type === 'new_fields_indicator') {
    return `<span style="${style}">● Neue Felder (Indikator)</span>`;
  }
```

- [ ] **Schritt 5: Manuell im Browser verifizieren**

1. Seite öffnen — "Eigene Felder" Gruppe erscheint in der Palette unten
2. Gruppe aufklappen — zeigt "+ Neues Feld" Button
3. "+ Neues Feld" → Edit Dialog öffnet sich im Anlege-Modus (Titel "Neues Feld")
4. Label "Pipe" und Text " | " eingeben, Speichern → Eintrag erscheint in der Palette
5. Das neue Feld in eine Zeile ziehen → Chip erscheint als `" | "` (static)
6. ✏️ auf Palette-Eintrag → Edit Dialog im Palette-Modus (nur Allgemein + Farben)
7. 🗑️ → Eintrag entfernt (bestehende Chips in Zeilen bleiben)

- [ ] **Schritt 6: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): custom fields palette with add, edit, delete, and drag to line"
```

---

## Task 9: Diagnose-Gruppe + new_fields_indicator

**Files:**
- Modify: `statusline-configurator.html`
  - `renderFieldsPanel`: Diagnose-Gruppe hinzufügen
  - `initSortable` onAdd: `new_fields_indicator` dragging
  - `loadConfig`: `knownKeys` importieren

- [ ] **Schritt 1: Diagnose-Gruppe in renderFieldsPanel**

Füge am Ende der `for`-Schleife in `renderFieldsPanel()` (nach dem letzten `tree.appendChild(itemList)`, vor der schließenden `}` der Funktion) eine zweite Gruppe hinzu:

```javascript
  // Diagnose group — special virtual fields
  const diagHeader = document.createElement('div');
  diagHeader.style.cssText = 'font-size:10px;text-transform:uppercase;letter-spacing:0.06em;color:var(--color-text-muted);padding:8px 4px 4px;cursor:pointer;user-select:none;display:flex;align-items:center;gap:4px;';
  diagHeader.innerHTML = '<span class="group-arrow" style="display:inline-block;transition:transform 0.15s;">▶</span> Diagnose';

  const diagList = document.createElement('div');
  diagList.className = 'field-group-list';
  diagList.style.cssText = 'display:none;';

  diagHeader.addEventListener('click', () => {
    const open = diagList.style.display !== 'none';
    diagList.style.display = open ? 'none' : 'block';
    diagHeader.querySelector('.group-arrow').style.transform = open ? '' : 'rotate(90deg)';
  });

  const diagItem = document.createElement('div');
  diagItem.className = 'field-source';
  diagItem.dataset.fieldType = 'new_fields_indicator';
  diagItem.style.cssText = 'padding:5px 8px;border-radius:4px;font-size:12px;cursor:grab;display:flex;align-items:center;gap:6px;transition:background 0.1s;';
  diagItem.innerHTML = `
    <span style="color:var(--color-text-muted);font-size:10px;">⠿</span>
    <span>Neue Felder</span>
    <span style="font-size:9px;color:var(--color-accent);margin-left:auto;border:1px solid var(--color-accent);border-radius:3px;padding:1px 4px;">●</span>
  `;
  diagItem.addEventListener('mouseenter', () => diagItem.style.background = 'var(--color-surface-2)');
  diagItem.addEventListener('mouseleave', () => diagItem.style.background = '');
  diagList.appendChild(diagItem);

  tree.appendChild(diagHeader);
  tree.appendChild(diagList);
```

- [ ] **Schritt 2: new_fields_indicator drag in initSortable**

Der `onAdd`-Handler wurde in Task 4 Schritt 5 vollständig ersetzt und unterstützt `panelFieldType === 'new_fields_indicator'` bereits. Kein weiterer Code nötig — weiter mit Schritt 3.

- [ ] **Schritt 3: loadConfig — knownKeys importieren**

Füge am Ende von `loadConfig` (nach dem `state.customFields = ...`-Block) ein:

```javascript
  // knownKeys: stored in config but not actively used by the configurator at runtime
  // (they are only used by the PS script; the configurator rebuilds them on every export)
```

Kein Code nötig — `knownKeys` wird beim Export automatisch aus `AVAILABLE_FIELDS` neu berechnet und überschreibt den importierten Wert. Kein State-Speichern erforderlich.

- [ ] **Schritt 4: Edit Dialog für new_fields_indicator — Datentyp-Tab verstecken**

In `openEditDialog`, der Check für Tab-Sichtbarkeit muss auch `new_fields_indicator` ausschließen:

```javascript
  const isDatatypeVisible = source === 'line' && field.type === 'field';
```

Dies ist bereits korrekt (nur `type === 'field'` zeigt den Datentyp-Tab). Keine Änderung nötig.

- [ ] **Schritt 5: Manuell im Browser verifizieren**

1. Seite neu laden
2. "Diagnose" Gruppe in der Palette aufklappen — "Neue Felder" Eintrag sichtbar
3. "Neue Felder" in eine Zeile ziehen — Chip erscheint mit Label "● Neue Felder"
4. ✏️ auf dem Chip — Edit Dialog öffnet sich, nur Allgemein (Info-Text) + Farben (kein Datentyp-Tab)
5. Export-JSON prüfen: das Feld hat `"type": "new_fields_indicator"`; `knownKeys`-Array ist befüllt
6. Export-JSON in `statusline-config.json` speichern, PS-Script aufrufen — `last-payload.json` wird erzeugt

- [ ] **Schritt 6: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): Diagnose palette group with new_fields_indicator drag support"
```

---

## Self-Review Checkliste

Nach Abschluss aller Tasks prüfen:

- [ ] Alle Pester-Tests grün: `Invoke-Pester tests/statusline.Tests.ps1 -Output Detailed`
- [ ] Bestehende Config-JSONs ohne `dataType`/`customFields` laden korrekt (Rückwärtskompatibilität)
- [ ] Drag eines bekannten Feldes → Export hat `dataType` aus `FIELD_TYPE_DEFAULTS`
- [ ] Drag eines unbekannten Feldes (nach manueller Key-Eingabe) → Export hat kein `dataType` (kein Crash)
- [ ] Edit Dialog: alle 3 Tabs funktionieren für jeden Field-Typ
- [ ] `bool`/`custom` → True/False-Labels werden gespeichert und in PS korrekt angezeigt
- [ ] Custom-Feld anlegen → in Palette sichtbar → per Drag in Zeile → unabhängige Kopie
- [ ] `last-payload.json` wird nach PS-Aufruf erzeugt
- [ ] Wenn `knownKeys` in Config und unbekannte Keys im Payload → Indikator zeigt `● N neue Felder`
- [ ] Wenn alle Keys bekannt → Indikator gibt leeren String zurück
