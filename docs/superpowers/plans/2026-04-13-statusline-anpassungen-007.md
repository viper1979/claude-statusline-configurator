# Statusline Anpassungen 007 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drei neue Claude Code Payload-Felder integrieren, Cache-Effizienz als berechnetes Feld hinzufügen, New-Fields-Logging konfigurierbar machen, und Null/Leer-Defaults per dataType implementieren.

**Architecture:** Vier unabhängige Bereiche: (1) PS `Format-Field` erhält special-case für `workspace.added_dirs` + placeholder-Logik, (2) neue `Compute-DerivedFields`-Funktion in Enrichment-Phase, (3) `new_fields_indicator` schreibt Logdatei wenn `$script:LogNewFields = $true`, (4) Konfigurator bekommt neue Felder in AVAILABLE_FIELDS + logNewFields-Toggle + placeholder-Input im Edit-Dialog.

**Tech Stack:** PowerShell 7 (Pester 5.x für Tests), Single-file HTML/JS Konfigurator (`statusline-configurator.html`). Alle Tests laufen mit `pwsh -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"`.

---

## File Map

| Datei | Änderungen |
|---|---|
| `statusline.ps1` | `Format-Field` (added_dirs special case, placeholder-Logik, Logging), `Compute-DerivedFields` (neu), `Invoke-Main` (LogNewFields-Scope, DerivedFields-Call) |
| `tests/statusline.Tests.ps1` | Neue Tests: added_dirs Count, Logging, Compute-DerivedFields, Placeholder |
| `statusline-configurator.html` | AVAILABLE_FIELDS (4 neue), FIELD_TYPE_DEFAULTS, SAMPLE_DATA, logNewFields-Toggle UI, placeholder-Input im Edit-Dialog, `buildExportJson`, `loadConfig` |
| `.gitignore` | `statusline-new-fields.log` hinzufügen |

---

## Task 1: PS — `workspace.added_dirs` Count-Handling

**Files:**
- Modify: `statusline.ps1` — `Format-Field` default case
- Modify: `tests/statusline.Tests.ps1` — neue `Describe 'Format-Field added_dirs'`

- [ ] **Schritt 1: Failing Test schreiben**

Am Ende von `tests/statusline.Tests.ps1`, vor der letzten schließenden Klammer, folgenden Block hinzufügen:

```powershell
Describe 'Format-Field added_dirs' {
    It 'returns count when added_dirs is a populated array' {
        $data  = [PSCustomObject]@{
            workspace = [PSCustomObject]@{ added_dirs = @('/path/a', '/path/b') }
        }
        $field = [PSCustomObject]@{
            type='field'; key='workspace.added_dirs'; fg=$null; bg=$null
            dataType='number'; format='raw'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()
        Format-Field $field $data | Should -Match '2'
    }

    It 'returns 0 when added_dirs is an empty array' {
        $data  = [PSCustomObject]@{
            workspace = [PSCustomObject]@{ added_dirs = @() }
        }
        $field = [PSCustomObject]@{
            type='field'; key='workspace.added_dirs'; fg=$null; bg=$null
            dataType='number'; format='raw'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()
        Format-Field $field $data | Should -Match '0'
    }
}
```

- [ ] **Schritt 2: Test fehlschlagen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Die 2 neuen Tests FAIL (Array wird nicht als Zahl gerendert).

- [ ] **Schritt 3: Implementierung in `statusline.ps1`**

In `Format-Field` den `default`-Case suchen (ca. Zeile 439). Direkt **nach** `$value = Get-NestedValue $Data $Field.key` und **vor** dem bestehenden Null-Check einfügen:

```powershell
# Special case: workspace.added_dirs is an array — display element count
if ($Field.key -eq 'workspace.added_dirs' -and $null -ne $value) {
    $value = @($value).Count
}
```

Der vollständige `default`-Block sieht danach so aus:

```powershell
default {
    # type = 'field'
    $value = Get-NestedValue $Data $Field.key

    # Special case: workspace.added_dirs is an array — display element count
    if ($Field.key -eq 'workspace.added_dirs' -and $null -ne $value) {
        $value = @($value).Count
    }

    if ($null -eq $value -or "$value" -eq '') {
        # Show 'none' for git branch when value is missing
        if ($Field.key -eq 'worktree.branch') {
            $value = 'none'
        } else {
            return ''
        }
    }
    # ... (Rest unverändert)
```

- [ ] **Schritt 4: Tests laufen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Alle Tests PASS (inkl. 2 neue).

- [ ] **Schritt 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): handle workspace.added_dirs array as element count"
```

---

## Task 2: PS — Null/Leer-Defaults mit Placeholder-Logik

**Files:**
- Modify: `statusline.ps1` — `Format-Field` default case, Null-Check-Block
- Modify: `tests/statusline.Tests.ps1` — neue `Describe 'Format-Field placeholder'`

- [ ] **Schritt 1: Failing Tests schreiben**

An `tests/statusline.Tests.ps1` anhängen:

```powershell
Describe 'Format-Field placeholder' {
    BeforeAll {
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()
    }

    It 'returns per-dataType default -- for string when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='agent.name'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '--'
    }

    It 'returns per-dataType default 0 for number when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_lines_added'; fg=$null; bg=$null
            dataType='number'; format='raw'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '0'
    }

    It 'returns per-dataType default $0.00 for currency when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_cost_usd'; fg=$null; bg=$null
            dataType='currency'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '$0.00'
    }

    It 'returns per-dataType default -- for duration_ms when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_duration_ms'; fg=$null; bg=$null
            dataType='duration_ms'; format='short'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '--'
    }

    It 'returns per-dataType default -- for unix_timestamp when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='rate_limits.five_hour.resets_at'; fg=$null; bg=$null
            dataType='unix_timestamp'; format='hours'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '--'
    }

    It 'uses explicit placeholder over dataType default' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='agent.name'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null; placeholder='(kein Agent)'
        }
        Format-Field $field $data | Should -Be '(kein Agent)'
    }

    It 'returns empty string when placeholder is explicitly empty string' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='agent.name'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null; placeholder=''
        }
        Format-Field $field $data | Should -BeNullOrEmpty
    }

    It 'retains none for worktree.branch when no placeholder is set' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='worktree.branch'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be 'none'
    }

    It 'respects placeholder for worktree.branch when explicitly set' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='worktree.branch'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null; placeholder='main'
        }
        Format-Field $field $data | Should -Be 'main'
    }
}
```

- [ ] **Schritt 2: Tests fehlschlagen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Die 8 neuen Tests FAIL (aktueller Code gibt '' zurück statt Defaults).

- [ ] **Schritt 3: Implementierung — Null-Check-Block ersetzen**

In `Format-Field` den `default`-Case suchen. Den bestehenden Null-Check-Block ersetzen:

**ALT (ab ca. Zeile 442):**
```powershell
if ($null -eq $value -or "$value" -eq '') {
    # Show 'none' for git branch when value is missing
    if ($Field.key -eq 'worktree.branch') {
        $value = 'none'
    } else {
        return ''
    }
}
```

**NEU:**
```powershell
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
```

- [ ] **Schritt 4: Tests laufen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Alle Tests PASS. Prüfe insbesondere, dass der bestehende Test `'returns empty string for unknown field path'` noch PASS ist — er hat keinen `dataType`, daher greift `default { $null }` im switch → `return ''`.

- [ ] **Schritt 5: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add per-dataType null defaults and per-field placeholder"
```

---

## Task 3: PS — `Compute-DerivedFields` (Cache-Effizienz)

**Files:**
- Modify: `statusline.ps1` — neue Funktion `Compute-DerivedFields` + Aufruf in `Invoke-Main`
- Modify: `tests/statusline.Tests.ps1` — neue `Describe 'Compute-DerivedFields'`

- [ ] **Schritt 1: Failing Tests schreiben**

An `tests/statusline.Tests.ps1` anhängen:

```powershell
Describe 'Compute-DerivedFields' {
    It 'sets cache_efficiency correctly for normal values' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                total_input_tokens = 10000
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 7340
                }
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.cache_efficiency | Should -Be 73.4
    }

    It 'rounds cache_efficiency to 1 decimal place' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                total_input_tokens = 3
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 1
                }
            }
        }
        Compute-DerivedFields -Data $data
        # 1/3 * 100 = 33.333... → rounded to 33.3
        $data.context_window.cache_efficiency | Should -Be 33.3
    }

    It 'does not set cache_efficiency when total_input_tokens is 0' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                total_input_tokens = 0
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 0
                }
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.PSObject.Properties['cache_efficiency'] | Should -BeNullOrEmpty
    }

    It 'does not set cache_efficiency when total_input_tokens is null' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 500
                }
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.PSObject.Properties['cache_efficiency'] | Should -BeNullOrEmpty
    }
}
```

- [ ] **Schritt 2: Tests fehlschlagen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: 4 neue Tests FAIL mit "Compute-DerivedFields not recognized".

- [ ] **Schritt 3: Funktion in `statusline.ps1` einfügen**

Direkt **vor** der Funktion `Invoke-Main` (ca. Zeile 570) einfügen:

```powershell
<#
.SYNOPSIS
    Computes derived fields and injects them into $Data via Add-Member.
.DESCRIPTION
    Computes context_window.cache_efficiency = cache_read_input_tokens / total_input_tokens * 100.
    Only sets the field when total_input_tokens > 0 to avoid division by zero.
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
}
```

- [ ] **Schritt 4: Aufruf in `Invoke-Main` einbauen**

In `Invoke-Main` nach dem `rate_limits`-Enrichment-Block (nach der schließenden `}` des `if (-not (Get-NestedValue $data 'rate_limits'))` Blocks) und **vor** dem `last-payload.json`-Write einfügen:

```powershell
# Compute derived fields (e.g., cache_efficiency) from enriched data
Compute-DerivedFields -Data $data
```

- [ ] **Schritt 5: Tests laufen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Alle Tests PASS.

- [ ] **Schritt 6: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1
git commit -m "feat(statusline): add Compute-DerivedFields for cache_efficiency"
```

---

## Task 4: PS — New-Fields-Logging

**Files:**
- Modify: `statusline.ps1` — `new_fields_indicator` case + `Invoke-Main`
- Modify: `tests/statusline.Tests.ps1` — neue `Describe 'new_fields_indicator logging'`
- Modify: `.gitignore` — `statusline-new-fields.log` hinzufügen

- [ ] **Schritt 1: Failing Tests schreiben**

An `tests/statusline.Tests.ps1` anhängen:

```powershell
Describe 'new_fields_indicator logging' {
    BeforeAll {
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:KnownKeys = @('version')
        $logPath = Join-Path $TestDrive 'statusline-new-fields.log'
        $script:NewFieldsLogPath = $logPath
    }

    AfterEach {
        if (Test-Path $script:NewFieldsLogPath) { Remove-Item $script:NewFieldsLogPath -Force }
    }

    It 'writes unknown key names to log file when LogNewFields is true' {
        $script:LogNewFields = $true
        $data  = [PSCustomObject]@{ version = '1.0'; unknownKey = 'value' }
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null; fgOverride=$false; bgOverride=$false }
        Format-Field $field $data | Out-Null
        Test-Path $script:NewFieldsLogPath | Should -BeTrue
        $logContent = Get-Content $script:NewFieldsLogPath -Raw
        $logContent | Should -Match 'unknownKey'
    }

    It 'does not write log when LogNewFields is false' {
        $script:LogNewFields = $false
        $data  = [PSCustomObject]@{ version = '1.0'; unknownKey = 'value' }
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null; fgOverride=$false; bgOverride=$false }
        Format-Field $field $data | Out-Null
        Test-Path $script:NewFieldsLogPath | Should -BeFalse
    }

    It 'does not write log when no unknown keys exist' {
        $script:LogNewFields = $true
        $data  = [PSCustomObject]@{ version = '1.0' }
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null; fgOverride=$false; bgOverride=$false }
        Format-Field $field $data | Out-Null
        Test-Path $script:NewFieldsLogPath | Should -BeFalse
    }
}
```

- [ ] **Schritt 2: Tests fehlschlagen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: 3 neue Tests FAIL.

- [ ] **Schritt 3: Logging-Variablen in `statusline.ps1` deklarieren**

Am Anfang der Script-Scope-Variablen (nach `$script:AnsiReset`), folgende Zeilen einfügen:

```powershell
# Path for new-fields log (set by Invoke-Main, overridable in tests)
$script:LogNewFields    = $false
$script:NewFieldsLogPath = $null
```

- [ ] **Schritt 4: `new_fields_indicator`-Case aktualisieren**

Den bestehenden `'new_fields_indicator'`-Case in `Format-Field` ersetzen:

```powershell
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
```

- [ ] **Schritt 5: `Invoke-Main` aktualisieren**

In `Invoke-Main`, nach dem Setzen von `$script:KnownKeys` (nach Zeile `$script:KnownKeys = if ($config.knownKeys) ...`) hinzufügen:

```powershell
# Configure new-fields logging from config
$script:LogNewFields     = [bool]($config.logNewFields)
$script:NewFieldsLogPath = Join-Path $PSScriptRoot 'statusline-new-fields.log'
```

- [ ] **Schritt 6: `.gitignore` ergänzen**

In `.gitignore` folgende Zeile hinzufügen:

```
statusline-new-fields.log
```

- [ ] **Schritt 7: Tests laufen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Alle Tests PASS.

- [ ] **Schritt 8: Commit**

```bash
git add statusline.ps1 tests/statusline.Tests.ps1 .gitignore
git commit -m "feat(statusline): add configurable new-fields logging to log file"
```

---

## Task 5: Konfigurator — Neue Felder + Cache-Effizienz in AVAILABLE_FIELDS

**Files:**
- Modify: `statusline-configurator.html` — `AVAILABLE_FIELDS`, `FIELD_TYPE_DEFAULTS`, `SAMPLE_DATA`

- [ ] **Schritt 1: Drei neue Felder in `AVAILABLE_FIELDS` eintragen**

In `statusline-configurator.html` die `AVAILABLE_FIELDS`-Definition suchen.

**Workspace-Gruppe** — nach dem Eintrag `{ key: 'workspace.project_dir', label: 'Project Dir' }` zwei neue Einträge hinzufügen:

```javascript
{ key: 'workspace.added_dirs',   label: 'Added Dirs Count' },
{ key: 'workspace.git_worktree', label: 'Git Worktree'      },
```

**Session-Gruppe** — als ersten Eintrag (vor `{ key: 'version', ... }`) hinzufügen:

```javascript
{ key: 'session_name', label: 'Session Name' },
```

**Context Window-Gruppe** — nach `{ key: 'exceeds_200k_tokens', label: 'Exceeds 200k Tokens' }` einfügen:

```javascript
{ key: 'context_window.cache_efficiency', label: 'Cache Efficiency (%)' },
```

- [ ] **Schritt 2: Einträge in `FIELD_TYPE_DEFAULTS` ergänzen**

In `FIELD_TYPE_DEFAULTS` nach dem letzten bestehenden Eintrag der Workspace-Gruppe folgendes einfügen:

```javascript
'workspace.added_dirs':              { dataType: 'number',  format: 'raw' },
'workspace.git_worktree':            { dataType: 'string' },
// Session
'session_name':                      { dataType: 'string' },
// Context Window — derived
'context_window.cache_efficiency':   { dataType: 'number',  format: 'raw' },
```

- [ ] **Schritt 3: `SAMPLE_DATA` erweitern**

In `SAMPLE_DATA` das `workspace`-Objekt ergänzen:

```javascript
workspace: {
    current_dir: '/home/user/myproject',
    project_dir: '/home/user/myproject',
    added_dirs: ['/home/user/extra'],
    git_worktree: 'my-feature'
},
```

`session_name` auf Top-Level hinzufügen (z.B. nach `session_id`):

```javascript
session_name: 'my-session',
```

Im `context_window`-Objekt `cache_efficiency` ergänzen:

```javascript
context_window: {
    total_input_tokens: 15234, total_output_tokens: 4521, context_window_size: 200000,
    used_percentage: 16, remaining_percentage: 84,
    cache_efficiency: 73.4,
    current_usage: { input_tokens: 8500, output_tokens: 1200, cache_creation_input_tokens: 5000, cache_read_input_tokens: 2000 },
},
```

- [ ] **Schritt 4: Manuell im Browser testen**

1. `statusline-configurator.html` im Browser öffnen
2. Im linken Panel prüfen: Gruppe "Workspace" zeigt "Added Dirs Count" und "Git Worktree"
3. Gruppe "Session" zeigt "Session Name" als erstes Feld
4. Gruppe "Context Window" zeigt "Cache Efficiency (%)"
5. "Added Dirs Count" in eine Linie ziehen → Preview zeigt `1` (von SAMPLE_DATA)
6. "Cache Efficiency (%)" in eine Linie ziehen → Preview zeigt `73.4`

- [ ] **Schritt 5: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add workspace.added_dirs, git_worktree, session_name, cache_efficiency to field palette"
```

---

## Task 6: Konfigurator — `logNewFields`-Toggle

**Files:**
- Modify: `statusline-configurator.html` — globale Einstellungssektion, `buildExportJson`, `loadConfig`, `state`

- [ ] **Schritt 1: State-Property hinzufügen**

Im `state`-Objekt (suche `const state = {` oder äquivalent) die Property `logNewFields` hinzufügen:

```javascript
logNewFields: false,
```

- [ ] **Schritt 2: UI-Toggle in globaler Einstellungssektion einbauen**

Den bestehenden Bereich für globale Einstellungen suchen (z.B. unter dem Theme-Tab oder als eigenem Bereich). Falls noch kein dedizierter Bereich existiert, direkt **über** dem Preview-Bereich einen `<div>` mit dem Toggle einfügen:

```html
<div class="global-settings-section">
  <label class="setting-row">
    <input type="checkbox" id="logNewFieldsToggle"
           onchange="state.logNewFields = this.checked"
           title="Unbekannte Payload-Keys in statusline-new-fields.log schreiben">
    <span>Neue Felder protokollieren</span>
  </label>
</div>
```

**Hinweis:** Den Toggle so platzieren, dass er zur bestehenden UI passt — z.B. im Settings-Tab falls vorhanden, sonst als `<fieldset>` über den Linien-Bereich.

- [ ] **Schritt 3: `buildExportJson` erweitern**

In `buildExportJson` (suche `function buildExportJson`) vor dem Return-Statement `logNewFields` hinzufügen:

```javascript
if (state.logNewFields) {
    config.logNewFields = true;
}
```

- [ ] **Schritt 4: `loadConfig` erweitern**

In `loadConfig` (suche `function loadConfig`) nach dem Laden der lines/themes folgende Zeile hinzufügen:

```javascript
state.logNewFields = !!(imported.logNewFields);
const toggle = document.getElementById('logNewFieldsToggle');
if (toggle) toggle.checked = state.logNewFields;
```

- [ ] **Schritt 5: Manuell im Browser testen**

1. Toggle aktivieren → `Exportieren` → JSON enthält `"logNewFields": true`
2. Toggle deaktivieren → `Exportieren` → JSON enthält kein `logNewFields`
3. JSON mit `"logNewFields": true` importieren → Toggle ist aktiviert

- [ ] **Schritt 6: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add logNewFields toggle to global settings"
```

---

## Task 7: Konfigurator — Placeholder-Input im Edit-Dialog

**Files:**
- Modify: `statusline-configurator.html` — Edit-Dialog HTML, `_editDraft`, `saveEditDialog`, `buildExportJson` (field-level), `loadConfig`

- [ ] **Schritt 1: Edit-Dialog HTML erweitern**

Im Edit-Dialog (suche `id="editDialog"` oder den Dialog-Render-Code) das Placeholder-Textfeld zum Tab "Allgemein" (oder direkt ins Hauptformular) hinzufügen. Suche nach dem Bereich wo `dataType` oder `format` gerendert wird und danach einfügen:

```html
<div class="form-row">
  <label for="editPlaceholder">Platzhalter (wenn leer)</label>
  <input type="text" id="editPlaceholder"
         placeholder="Leer = Standardwert je Datentyp"
         oninput="_editDraft.placeholder = this.value === '' ? undefined : this.value">
  <small>Leer lassen: Standardwert je Datentyp. Leerzeichen eingeben: Feld unsichtbar.</small>
</div>
```

- [ ] **Schritt 2: `_editDraft` in `openEditDialog` initialisieren**

In `openEditDialog` (suche `function openEditDialog` oder `_editDraft = `), sicherstellen dass `placeholder` aus dem Feld geladen wird:

```javascript
_editDraft.placeholder = field.placeholder;  // undefined wenn nicht gesetzt
```

Und das Input-Feld befüllen:

```javascript
const phInput = document.getElementById('editPlaceholder');
if (phInput) phInput.value = _editDraft.placeholder ?? '';
```

- [ ] **Schritt 3: `saveEditDialog` — placeholder speichern**

In `saveEditDialog` (suche `function saveEditDialog`), `placeholder` in das Feld-Objekt schreiben:

```javascript
// placeholder: undefined means "use dataType default", '' means "hide"
field.placeholder = _editDraft.placeholder;
```

- [ ] **Schritt 4: `buildExportJson` — placeholder exportieren**

In `buildExportJson` beim Aufbau jedes Feld-Objekts (suche wo `base.fgOverride` gesetzt wird) folgendes hinzufügen:

```javascript
if (f.placeholder !== undefined && f.placeholder !== null) {
    base.placeholder = f.placeholder;
}
```

- [ ] **Schritt 5: `loadConfig` — placeholder importieren**

Beim Laden von Feldern aus dem importierten JSON sicherstellen, dass `placeholder` übernommen wird:

```javascript
field.placeholder = imported_field.placeholder;  // undefined wenn fehlt
```

- [ ] **Schritt 6: Manuell im Browser testen**

1. Ein Feld bearbeiten → Placeholder-Input ist leer → Exportieren → kein `placeholder` im JSON
2. Placeholder "n/a" eingeben → Exportieren → `"placeholder": "n/a"` im JSON
3. JSON mit `"placeholder": "n/a"` importieren → Edit-Dialog zeigt "n/a" im Placeholder-Feld
4. Leeres Feld (per Leerzeichen als Placeholder) → unsichtbar wenn Wert fehlt

- [ ] **Schritt 7: Commit**

```bash
git add statusline-configurator.html
git commit -m "feat(configurator): add placeholder input to field edit dialog"
```

---

## Abschluss

- [ ] **Alle Tests laufen lassen**

```bash
pwsh -NonInteractive -NoProfile -Command "Invoke-Pester tests/statusline.Tests.ps1 -Output Normal"
```

Erwartetes Ergebnis: Alle Tests PASS (ursprünglich 26 + ca. 17 neue = ~43 Tests).

- [ ] **Branch-Status prüfen**

```bash
git log --oneline feature/statusline-007-new-fields-defaults
```

Erwartetes Ergebnis: 7 neue Commits auf dem Feature-Branch.
